import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'engines/cloud_engines.dart';
import 'engines/local_engine.dart';
import 'engines/system_engine.dart';
import 'prosody.dart';
import 'tts_types.dart';
import 'voice_library.dart';
import 'voice_settings.dart';
import 'wav.dart';

/// 播放合成好的音频文件（默认使用单独的 media_kit 播放器，与音乐播放器互不干扰）。
abstract class SpeechSink {
  /// 播放一个文件，播放完（或被 [stop]）后结束。
  Future<void> play(String path);
  Future<void> stop();
  void dispose() {}
}

class MediaKitSpeechSink extends SpeechSink {
  Player? _player;
  Completer<void>? _done;
  StreamSubscription<bool>? _sub;

  Player get _p {
    final p = _player ??= Player(configuration: const PlayerConfiguration(title: '云音助手', logLevel: MPVLogLevel.error));
    _sub ??= p.stream.completed.listen((c) {
      if (c && !(_done?.isCompleted ?? true)) _done!.complete();
    });
    return p;
  }

  @override
  Future<void> play(String path) async {
    final done = _done = Completer<void>();
    await _p.open(Media(path));
    // 播放出错（文件损坏等）时不能一直等。
    await done.future.timeout(const Duration(seconds: 60), onTimeout: () {});
  }

  @override
  Future<void> stop() async {
    if (!(_done?.isCompleted ?? true)) _done!.complete();
    await _player?.stop();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _player?.dispose();
  }
}

/// 引擎注册表与选择：按“用户指定的引擎 → 已配置的云端引擎 → 本地离线（模型已下载）→ 系统朗读”的顺序降级。
class VoiceEngines {
  VoiceEngines(this.settings, {List<TtsEngine>? engines})
    : all = engines ?? [CosyVoiceEngine(settings), ElevenLabsEngine(settings), FishAudioEngine(settings), LocalTtsEngine(), SystemTtsEngine()];

  final VoiceSettings settings;
  final List<TtsEngine> all;

  TtsEngine? byId(String id) => all.where((e) => e.id == id).firstOrNull;

  /// 引擎最近失败后的冷却截止时间（期间跳过它，直接用下一个）。
  final Map<String, DateTime> _cooldown = {};

  void reportFailure(String engine, TtsException e) {
    _cooldown[engine] = DateTime.now().add(e.retryable ? const Duration(minutes: 1) : const Duration(minutes: 10));
  }

  void reportSuccess(String engine) => _cooldown.remove(engine);

  /// 带用户覆盖的声音 ID 的绑定。
  EngineVoice bindingFor(VoiceProfile voice, TtsEngine engine) {
    final base = voice.binding(engine.id) ?? EngineVoice(engine.id, const {});
    var b = base;
    for (final lang in VoiceLanguage.values) {
      final o = settings.override(voice.id, engine.id, lang);
      if (o != null) b = b.withVoice(lang, o);
    }
    return b;
  }

  /// 这个音色在这种语言上可用的引擎，按优先顺序。
  Future<List<(TtsEngine, EngineVoice)>> chain(VoiceProfile voice, VoiceLanguage lang, {bool ignoreCooldown = false}) async {
    final now = DateTime.now();
    final ordered = <TtsEngine>[
      ?byId(settings.preferredEngine),
      ...all.where((e) => !e.offline && e.id != settings.preferredEngine),
      ...all.where((e) => e.offline && e.id != settings.preferredEngine),
    ];
    final out = <(TtsEngine, EngineVoice)>[];
    for (final e in ordered) {
      if (!e.configured || !e.languages.contains(lang)) continue;
      if (!ignoreCooldown && (_cooldown[e.id]?.isAfter(now) ?? false)) continue;
      final b = bindingFor(voice, e);
      if (e.id != 'system' && !await e.ready(b, lang)) continue;
      out.add((e, b));
    }
    return out;
  }
}

/// 一句待朗读的话。
class _Utterance {
  _Utterance(this.text, this.prosody, this.voice, this.language);

  final String text;
  final Prosody prosody;
  final VoiceProfile voice;
  final VoiceLanguage language;
  final Completer<List<String>> files = Completer();
}

/// 语音输出：句子队列 → 合成（提前合成下一句）→ 依次播放。可以随时打断（清空队列、停止播放、取消合成），
/// 播放期间压低音乐（音频焦点），说完恢复。合成失败自动换下一个引擎，全部失败时跳过这一句。
class SpeechOutput extends ChangeNotifier {
  SpeechOutput(this.settings, {VoiceEngines? engines, SpeechSink? sink, this.onDuck})
    : engines = engines ?? VoiceEngines(settings),
      _sink = sink ?? MediaKitSpeechSink();

  final VoiceSettings settings;
  final VoiceEngines engines;
  final SpeechSink _sink;

  /// 开始 / 结束说话时调用（压低 / 恢复音乐）。
  final Future<void> Function(bool duck)? onDuck;

  final Queue<_Utterance> _queue = Queue();
  CancelToken _cancel = CancelToken();
  int _generation = 0;
  bool _playing = false;
  Future<void> _synthTail = Future.value();

  /// 正在说话（队列中还有句子或正在播放）。
  bool get speaking => _playing || _queue.isNotEmpty;

  /// 正在发出声音（不包括等待第一句合成的时间）：打断检测只在这时打开。
  bool get audible => _audible;
  bool _audible = false;

  void _setAudible(bool v) {
    if (v == _audible) return;
    _audible = v;
    notifyListeners();
  }

  /// 最近一次使用的引擎（音色中心显示“正在使用”）。
  String? lastEngine;

  /// 最近一次全部引擎都失败的原因。
  String? lastError;

  VoiceProfile get voice => VoicePresets.byId(settings.voiceId);

  /// 朗读一段完整的文字。
  Future<void> say(String text, {VoiceProfile? voice, Emotion? emotion}) async {
    final turn = begin(voice: voice);
    turn.add(text, emotion: emotion);
    await turn.end();
  }

  /// 开始一轮流式朗读：大模型边输出，边按句子合成与播放。
  SpeechTurn begin({VoiceProfile? voice}) => SpeechTurn._(this, voice ?? this.voice, _generation);

  void _enqueue(_Utterance u, int generation) {
    if (generation != _generation) return;
    _queue.add(u);
    // 逐句合成（与播放并行，最多领先若干句）：引擎失败时下一句立即换引擎，也不会同时向云端发出大量请求。
    _synthTail = _synthTail.then((_) => _synthesize(u, generation));
    notifyListeners();
    if (!_playing) _playLoop(generation);
  }

  /// 打断：清空队列、停止播放与合成。
  Future<void> stop() async {
    _generation++;
    _cancel.cancel();
    _cancel = CancelToken();
    for (final u in _queue) {
      if (!u.files.isCompleted) u.files.complete(const []);
    }
    _queue.clear();
    _synthTail = Future.value();
    await _sink.stop();
    _audible = false;
    if (_playing) {
      _playing = false;
      await onDuck?.call(false);
    }
    notifyListeners();
  }

  Future<void> _playLoop(int generation) async {
    _playing = true;
    await onDuck?.call(true);
    notifyListeners();
    while (_queue.isNotEmpty && generation == _generation) {
      final u = _queue.first;
      final files = await u.files.future;
      if (generation != _generation) return;
      for (final f in files) {
        if (generation != _generation) return;
        _setAudible(true);
        await _sink.play(f);
      }
      if (_queue.isNotEmpty && identical(_queue.first, u)) _queue.removeFirst();
    }
    if (generation != _generation) return;
    _playing = false;
    _audible = false;
    await onDuck?.call(false);
    notifyListeners();
  }

  /// 合成一句：按引擎链依次尝试，成功的引擎输出的每一段写成一个文件。
  Future<void> _synthesize(_Utterance u, int generation) async {
    final cancel = _cancel;
    final files = <String>[];
    if (generation != _generation) {
      if (!u.files.isCompleted) u.files.complete(files);
      return;
    }
    try {
      final cached = await _cached(u);
      if (cached != null) {
        files.add(cached);
      } else {
        final chain = await engines.chain(u.voice, u.language);
        for (final (engine, binding) in chain) {
          try {
            final parts = <TtsAudio>[];
            await for (final a in engine.synthesize(binding, TtsRequest(u.text, language: u.language, prosody: u.prosody), cancel: cancel)) {
              if (generation != _generation) return;
              parts.add(a);
            }
            if (parts.isEmpty) throw TtsException('没有生成音频', engine: engine.name);
            files.addAll(await _write(u, engine, parts));
            engines.reportSuccess(engine.id);
            lastEngine = engine.name;
            lastError = null;
            break;
          } on TtsException catch (e) {
            if (cancel.isCancelled) return;
            debugPrint('tts ${engine.id}: $e');
            engines.reportFailure(engine.id, e);
            lastError = e.toString();
          } catch (e) {
            if (cancel.isCancelled) return;
            debugPrint('tts ${engine.id}: $e');
            engines.reportFailure(engine.id, TtsException('$e', engine: engine.name));
            lastError = '${engine.name}：$e';
          }
        }
      }
    } finally {
      if (!u.files.isCompleted) u.files.complete(files);
    }
  }

  // ── 缓存 ──────────────────────────────────────────

  Directory? _dir;

  Future<Directory> _cacheDir() async {
    final d = _dir ??= Directory('${(await getTemporaryDirectory()).path}/yunyin_voice');
    if (!d.existsSync()) d.createSync(recursive: true);
    return d;
  }

  /// 缓存键：音色、语言、文字与韵律相同的句子（试听、常用回答）直接复用。
  /// 系统朗读的结果不进缓存（见 [_write]）：下载离线声音或配置云端引擎后，同一句话要换成真正的音色。
  String _key(_Utterance u) => sha1
      .convert(utf8.encode('v2|${u.voice.id}|${settings.preferredEngine}|${u.language.name}|${u.text}|${u.prosody.rate.toStringAsFixed(2)}|${u.prosody.emotion.name}'))
      .toString();

  Future<String?> _cached(_Utterance u) async {
    final d = await _cacheDir();
    for (final ext in const ['wav', 'mp3']) {
      final f = File('${d.path}/${_key(u)}.$ext');
      if (f.existsSync()) {
        f.setLastModifiedSync(DateTime.now());
        return f.path;
      }
    }
    return null;
  }

  Future<List<String>> _write(_Utterance u, TtsEngine engine, List<TtsAudio> parts) async {
    final d = await _cacheDir();
    final key = engine.id == 'system' ? 'tmp-${DateTime.now().microsecondsSinceEpoch}' : _key(u);
    final out = <String>[];
    // 短句整句缓存（试听与常用回答）；分段的流式音频逐段写临时文件。
    if (parts.length == 1 || parts.every((p) => p.format == 'pcm16')) {
      final Uint8List bytes;
      final String ext;
      if (parts.first.format == 'pcm16') {
        final all = BytesBuilder(copy: false);
        for (final p in parts) {
          all.add(p.bytes);
        }
        bytes = pcm16ToWav(all.takeBytes(), parts.first.sampleRate);
        ext = 'wav';
      } else {
        bytes = parts.first.bytes;
        ext = parts.first.format;
      }
      final f = File('${d.path}/$key.$ext');
      await f.writeAsBytes(bytes);
      out.add(f.path);
    } else {
      for (var i = 0; i < parts.length; i++) {
        final p = parts[i];
        final f = File('${d.path}/$key-$i.${p.format == 'pcm16' ? 'wav' : p.format}');
        await f.writeAsBytes(p.format == 'pcm16' ? pcm16ToWav(p.bytes, p.sampleRate) : p.bytes);
        out.add(f.path);
      }
    }
    unawaited(_trim(d));
    return out;
  }

  /// 缓存超过 60 MB 时删除最久没用的文件。
  static Future<void> _trim(Directory d) async {
    try {
      final files = d.listSync().whereType<File>().toList()..sort((a, b) => a.lastModifiedSync().compareTo(b.lastModifiedSync()));
      var total = files.fold<int>(0, (s, f) => s + f.lengthSync());
      for (final f in files) {
        if (total <= 60 << 20) break;
        total -= f.lengthSync();
        f.deleteSync();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _cancel.cancel();
    _sink.dispose();
    super.dispose();
  }
}

/// 一轮朗读：加入文字（可以分多次，流式），结束后等待说完。
class SpeechTurn {
  SpeechTurn._(this._out, this.voice, this._generation);

  final SpeechOutput _out;
  final VoiceProfile voice;
  final int _generation;
  final SentenceSplitter _splitter = SentenceSplitter();
  Emotion? _tagged;
  Emotion? _last;
  bool _first = true;

  void add(String delta, {Emotion? emotion}) {
    if (_first) {
      // 开头的情绪标记（大模型给出）。
      final (text, tag) = ProsodyPlanner.stripTag(delta);
      if (tag != null) {
        _tagged = tag;
        delta = text;
      }
      _first = delta.trim().isEmpty;
    }
    _tagged ??= emotion;
    for (final s in _splitter.add(delta)) {
      _speak(s);
    }
  }

  void _speak(String sentence) {
    final p = ProsodyPlanner.plan(sentence, base: _out.settings.rate, tagged: _tagged, carry: _last, expressive: _out.settings.expressive);
    _last = p.emotion;
    _out._enqueue(_Utterance(sentence, p, voice, VoiceLanguage.detect(sentence)), _generation);
  }

  /// 结束本轮并等待说完（被打断时立即返回）。
  Future<void> end() async {
    for (final s in _splitter.close()) {
      _speak(s);
    }
    while (_out.speaking && _out._generation == _generation) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }
}
