import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../core/settings.dart';
import '../data/listen_stats.dart';
import '../data/models.dart';
import '../data/sources/music_source.dart';
import '../data/sources/source_manager.dart';
import '../player/player_controller.dart';
import 'assistant_settings.dart';
import 'intents.dart';
import 'llm_client.dart';
import 'voice_engine.dart';
import 'voice_models.dart';

/// 对话中的一条消息。
class AssistantMessage {
  AssistantMessage(this.fromUser, this.text, {this.songs = const []});

  final bool fromUser;
  final String text;

  /// 助手为这条回答播放 / 推荐的歌曲（界面上显示为可点按的列表）。
  final List<Song> songs;
}

enum AssistantStatus { idle, listening, thinking }

/// AI 助手：语音唤醒（离线）、语音 / 文字指令、调用大模型（用户自己的接口）完成点歌、推荐与问答。
///
/// 常用指令（播放控制、点歌、音量、定时、音效）在本机解析，不需要大模型也能用；
/// 其余的话交给大模型，大模型通过函数调用操作播放器（见 [_tools]）。
class AssistantController extends ChangeNotifier {
  AssistantController({required this.settings, required this.app, required this.player, required this.sources, required this.stats, LlmClient? llm}) {
    _llm = llm ?? LlmClient(settings);
    _channel.setMethodCallHandler((call) async {
      // Android 常驻通知上点了“关闭”。
      if (call.method == 'stopRequested') settings.setVoiceWake(false);
    });
    settings.addListener(_syncVoice);
  }

  final AssistantSettings settings;
  final AppSettings app;
  final PlayerController player;
  final SourceManager sources;
  final ListenStats stats;
  late final LlmClient _llm;

  static const _channel = MethodChannel('yunyin/voice');
  static bool get _android => !kIsWeb && Platform.isAndroid;

  final List<AssistantMessage> messages = [];

  /// 发给大模型的对话记录（保留最近几轮，带工具调用）。
  final List<Map<String, dynamic>> _history = [];

  AssistantStatus status = AssistantStatus.idle;

  /// 正在说的话（识别中间结果）。
  String partial = '';

  /// 语音模型下载进度（0..1；为 null 表示没有在下载）。
  double? downloadProgress;

  /// 最近一次语音功能的错误（麦克风权限、模型下载失败等）。
  String? voiceError;

  /// 语音唤醒后请界面打开助手面板（应用在前台时）。
  final StreamController<void> _wakeEvents = StreamController.broadcast();
  Stream<void> get wakeEvents => _wakeEvents.stream;

  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _mic;
  VoiceWorker? _worker;
  StreamSubscription<VoiceEvent>? _voiceSub;
  bool _starting = false;

  /// 麦克风是否在工作（语音唤醒或正在听一句话）。
  bool get micActive => _worker != null;

  Future<void> init() async {
    await _syncVoice();
  }

  // ── 语音 ──────────────────────────────────────────

  /// 打开 / 关闭语音唤醒时启动或停止麦克风。
  Future<void> _syncVoice() async {
    if (settings.voiceWake && _worker == null) {
      await _startVoice();
    } else if (!settings.voiceWake && _worker != null && status != AssistantStatus.listening) {
      await _stopVoice();
    } else {
      _worker?.setWake(settings.voiceWake);
    }
  }

  /// 下载模型（需要时）、申请麦克风权限并开始监听。返回是否成功。
  Future<bool> _startVoice() async {
    if (_starting || _worker != null) return _worker != null;
    _starting = true;
    voiceError = null;
    try {
      if (!await VoiceModelStore.ready()) {
        downloadProgress = 0;
        notifyListeners();
        await VoiceModelStore.download(
          onProgress: (p) {
            downloadProgress = p;
            notifyListeners();
          },
        );
        downloadProgress = null;
      }
      final recorder = _recorder ??= AudioRecorder();
      if (!await recorder.hasPermission()) {
        throw Exception('没有麦克风权限：请在系统设置中允许云音使用麦克风');
      }
      final worker = await VoiceWorker.start(await VoiceModelStore.paths(), wake: settings.voiceWake);
      _worker = worker;
      _voiceSub = worker.events.listen(_onVoice);
      final stream = await recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: VoiceRecognizer.sampleRate,
          numChannels: 1,
          echoCancel: true,
          noiseSuppress: true,
          // 不抢占音频焦点（否则一开麦克风音乐就暂停）；不切换蓝牙耳机到通话模式。
          audioInterruption: AudioInterruptionMode.none,
          androidConfig: AndroidRecordConfig(audioSource: AndroidAudioSource.voiceRecognition, manageBluetooth: false),
        ),
      );
      _mic = stream.listen(worker.feed, onError: (Object e) => _fail('麦克风出错：$e'));
      if (_android && settings.voiceWake) await _channel.invokeMethod<bool>('startService');
      return true;
    } catch (e) {
      downloadProgress = null;
      var message = '$e'.replaceFirst('Exception: ', '');
      // Linux 通过 PulseAudio 的 parecord 录音。
      if (!kIsWeb && Platform.isLinux && message.contains('parecord')) message = '录音需要 parecord：请运行 sudo apt install pulseaudio-utils 后重试';
      _fail(message);
      await _stopVoice();
      if (settings.voiceWake) settings.setVoiceWake(false);
      return false;
    } finally {
      _starting = false;
      notifyListeners();
    }
  }

  Future<void> _stopVoice() async {
    await _mic?.cancel();
    _mic = null;
    try {
      await _recorder?.stop();
    } catch (_) {}
    await _voiceSub?.cancel();
    _voiceSub = null;
    _worker?.stop();
    _worker = null;
    if (_android) {
      try {
        await _channel.invokeMethod('stopService');
      } catch (_) {}
    }
    if (status == AssistantStatus.listening) status = AssistantStatus.idle;
    await player.duck(false);
    notifyListeners();
  }

  void _fail(String message) {
    voiceError = message;
    notifyListeners();
  }

  /// 点按麦克风按钮：开始听一句话（没开语音唤醒时临时打开麦克风，说完后关闭）。
  Future<void> startListening() async {
    if (status == AssistantStatus.listening) {
      await stopListening();
      return;
    }
    if (_worker == null && !await _startVoice()) return;
    _worker!.listen();
    _beginListening();
  }

  Future<void> stopListening() async {
    _worker?.cancel();
    status = AssistantStatus.idle;
    partial = '';
    await player.duck(false);
    if (!settings.voiceWake) await _stopVoice();
    notifyListeners();
  }

  void _beginListening() {
    status = AssistantStatus.listening;
    partial = '';
    unawaited(player.duck(true));
    unawaited(_stopSpeaking());
    notifyListeners();
  }

  void _onVoice(VoiceEvent e) {
    switch (e) {
      case VoiceWake():
        _beginListening();
        _wakeEvents.add(null);
      case VoicePartial(:final text):
        partial = text;
        notifyListeners();
      case VoiceFinal(:final text):
        partial = '';
        status = AssistantStatus.idle;
        unawaited(player.duck(false));
        notifyListeners();
        if (text.isNotEmpty) {
          unawaited(submit(text, spoken: true));
        } else if (!settings.voiceWake) {
          unawaited(_stopVoice());
        }
      case VoiceError(:final message):
        _fail('语音识别出错：$message');
    }
  }

  // ── 对话 ──────────────────────────────────────────

  /// 处理一句话（打字或语音）。[spoken] 为 true 时按设置朗读回答。
  Future<void> submit(String text, {bool spoken = false}) async {
    text = text.trim();
    if (text.isEmpty) return;
    messages.add(AssistantMessage(true, text));
    status = AssistantStatus.thinking;
    notifyListeners();
    AssistantMessage reply;
    try {
      final intent = parseIntent(text);
      if (intent != null) {
        reply = await _runLocal(intent);
      } else if (settings.llmConfigured) {
        reply = await _askLlm(text);
      } else {
        reply = AssistantMessage(false, '这句话需要大模型来理解。请在“设置 → AI 助手”中填写大模型接口与密钥；播放控制、点歌、音量与定时等常用指令不用设置也能直接说。');
      }
    } catch (e) {
      reply = AssistantMessage(false, '出错了：${'$e'.replaceFirst('Exception: ', '')}');
    }
    messages.add(reply);
    if (messages.length > 60) messages.removeRange(0, messages.length - 60);
    status = AssistantStatus.idle;
    notifyListeners();
    if (spoken && settings.speakReplies) unawaited(_speak(reply.text));
    if (spoken && !settings.voiceWake) unawaited(_stopVoice());
  }

  void clear() {
    messages.clear();
    _history.clear();
    notifyListeners();
  }

  MusicSource get _source => sources.current;

  Future<AssistantMessage> _runLocal(AssistantIntent intent) async {
    switch (intent) {
      case PlaybackIntent(:final action):
        switch (action) {
          case PlaybackAction.play:
            await player.play();
            return AssistantMessage(false, '继续播放');
          case PlaybackAction.pause:
            await player.pause();
            return AssistantMessage(false, '已暂停');
          case PlaybackAction.next:
            await player.next();
            return AssistantMessage(false, '下一首');
          case PlaybackAction.previous:
            await player.previous();
            return AssistantMessage(false, '上一首');
        }
      case PlayQueryIntent(:final query, :final artist):
        final songs = artist ? await _artistSongs(query) : (await _source.search(query)).songs.where((s) => s.playable).take(20).toList();
        if (songs.isEmpty) return AssistantMessage(false, '在${_source.name}没有找到“$query”');
        await player.playSongs(songs, title: artist ? '$query的歌' : query);
        return AssistantMessage(false, '为你播放${songs.first.name}（${songs.first.artistText}）', songs: songs.take(5).toList());
      case VolumeIntent(:final delta, :final level):
        final v = await _setVolume(level: level, delta: delta);
        return AssistantMessage(false, '音量 ${(v * 100).round()}%');
      case ModeIntent(:final mode):
        player.setMode(PlayMode.values[mode.index]);
        return AssistantMessage(false, switch (mode) {
          ModeChoice.sequence => '已切换为顺序播放',
          ModeChoice.shuffle => '已切换为随机播放',
          ModeChoice.repeatOne => '已切换为单曲循环',
        });
      case LikeIntent(:final like):
        final song = player.current;
        if (song == null) return AssistantMessage(false, '现在没有在播放歌曲');
        if (player.isLiked(song) != like) await player.toggleLike(song);
        return AssistantMessage(false, like ? '已收藏《${song.name}》' : '已取消收藏《${song.name}》');
      case SleepIntent(:final minutes):
        player.setSleepTimer(minutes == 0 ? null : Duration(minutes: minutes));
        return AssistantMessage(false, minutes == 0 ? '已取消定时关闭' : '$minutes 分钟后停止播放');
      case NowPlayingIntent():
        final song = player.current;
        if (song == null) return AssistantMessage(false, '现在没有在播放歌曲');
        return AssistantMessage(false, '正在播放《${song.name}》，${song.artistText}${song.album == null ? '' : '，专辑《${song.album!.name}》'}');
      case OpenLyricsIntent():
        return AssistantMessage(false, '在播放页点按“歌词”即可查看完整歌词');
      case EqIntent(:final preset):
        if (preset == null) {
          app.setFlag('eqEnabled', false);
          return AssistantMessage(false, '已关闭均衡器');
        }
        final p = EqPreset.values.firstWhere((e) => e.label.contains(preset) || preset.contains(e.label), orElse: () => EqPreset.flat);
        app.setEqPreset(p);
        app.setFlag('eqEnabled', true);
        return AssistantMessage(false, '已切换到${p.label}音效');
      case EffectIntent(:final bass, :final on):
        if (bass) {
          app.setBassEnhance(on ? 0.7 : 0);
        } else {
          app.setSpatial(on ? 0.7 : 0);
        }
        return AssistantMessage(false, '${on ? '已打开' : '已关闭'}${bass ? '低频增强' : '空间音效'}');
    }
  }

  Future<List<Song>> _artistSongs(String name) async {
    final r = await _source.search(name);
    final artist = r.artists.firstOrNull;
    if (artist != null && _source.supports(SourceFeature.artist)) {
      try {
        final songs = (await _source.artist(artist.id)).hotSongs;
        if (songs.isNotEmpty) return songs.where((s) => s.playable).toList();
      } catch (e) {
        debugPrint('assistant artist: $e');
      }
    }
    return r.songs.where((s) => s.playable && s.artistText.contains(name)).toList();
  }

  Future<double> _setVolume({double? level, double? delta}) async {
    if (_android) {
      return (await _channel.invokeMethod<double>('volume', {'level': level, 'delta': delta})) ?? 0;
    }
    final v = (level ?? app.volume + (delta ?? 0)).clamp(0.0, 1.0);
    await player.setVolume(v);
    return v;
  }

  // ── 大模型 ──────────────────────────────────────────

  String get _system {
    final song = player.current;
    final now = DateTime.now();
    return '''
你是“云音”音乐播放器里的 AI 助手，用简体中文回答。当前平台：${_source.name}（只能播放这个平台的歌）。现在是 ${now.year} 年 ${now.month} 月 ${now.day} 日 ${now.hour} 点。
${song == null ? '现在没有在播放歌曲。' : '正在播放《${song.name}》- ${song.artistText}。'}
规则：
- 用户想听歌、要推荐或按心情 / 场景要歌单时，调用 play_songs，给出真实存在的歌曲（“歌名 歌手”），一般 8–15 首，风格贴合需求；只想听某位歌手时调用 play_artist。
- 播放控制、音量、定时关闭、音效等直接调用对应函数。
- 问到正在播放的歌、歌词含义、创作背景时，先调用 get_now_playing 或 get_lyrics 获取信息再回答；不确定的事实要说明不确定，不要编造。
- 回答简短自然，适合语音播报（一般不超过 80 字）；用户要求详细解读时可以写长一些。不要使用 Markdown 标题和表格。''';
  }

  List<Map<String, dynamic>> get _tools => [
    tool(
      'play_songs',
      '搜索并播放一组歌曲（替换当前播放队列）。用于点歌、推荐、按心情或场景生成歌单。',
      {
        'songs': {
          'type': 'array',
          'items': {'type': 'string'},
          'description': '歌曲列表，每项为“歌名 歌手”',
        },
        'title': {'type': 'string', 'description': '这组歌的标题，例如“跑步歌单”'},
      },
      required: ['songs'],
    ),
    tool('play_artist', '播放某位歌手的热门歌曲', {
      'artist': {'type': 'string'},
    }, required: ['artist']),
    tool('add_to_queue', '把歌曲加到播放队列末尾（不打断当前歌曲）', {
      'songs': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '每项为“歌名 歌手”',
      },
    }, required: ['songs']),
    tool('control_playback', '播放控制', {
      'action': {
        'type': 'string',
        'enum': ['play', 'pause', 'next', 'previous'],
      },
    }, required: ['action']),
    tool('set_volume', '设置音量（0–100）', {
      'level': {'type': 'number'},
    }, required: ['level']),
    tool('set_sleep_timer', '定时停止播放；minutes 为 0 表示取消', {
      'minutes': {'type': 'integer'},
    }, required: ['minutes']),
    tool('set_sound', '调整音效：均衡器预设、低频增强与空间音效强度（0–100）', {
      'eq_preset': {
        'type': 'string',
        'enum': [for (final p in EqPreset.ordered) p.label, '关闭'],
      },
      'bass': {'type': 'number'},
      'spatial': {'type': 'number'},
    }),
    tool('like_current_song', '收藏正在播放的歌曲', {}),
    tool('get_now_playing', '获取正在播放的歌曲信息、播放进度与当前歌词', {}),
    tool('get_lyrics', '获取正在播放歌曲的完整歌词', {}),
    tool('get_queue', '获取播放队列中接下来的歌曲', {}),
    tool('get_listening_stats', '获取用户的听歌统计（常听的歌曲与歌手、累计时长）', {}),
  ];

  Future<AssistantMessage> _askLlm(String text) async {
    _history.add({'role': 'user', 'content': text});
    final played = <Song>[];
    for (var round = 0; round < 5; round++) {
      final reply = await _llm.complete([
        {'role': 'system', 'content': _system},
        ..._history,
      ], tools: _tools);
      final calls = (reply['tool_calls'] as List?)?.cast<Map>() ?? const [];
      _history.add({
        'role': 'assistant',
        'content': reply['content'] ?? '',
        if (calls.isNotEmpty) 'tool_calls': calls,
      });
      if (calls.isEmpty) {
        _trimHistory();
        return AssistantMessage(false, '${reply['content'] ?? ''}'.trim().ifEmpty('好的'), songs: played);
      }
      for (final c in calls) {
        final f = c['function'] as Map? ?? const {};
        Map<String, dynamic> args;
        try {
          args = (jsonDecode('${f['arguments'] ?? '{}'}') as Map).cast<String, dynamic>();
        } catch (_) {
          args = const {};
        }
        String result;
        try {
          result = await _runTool('${f['name']}', args, played);
        } catch (e) {
          result = jsonEncode({'error': '$e'});
        }
        _history.add({'role': 'tool', 'tool_call_id': c['id'], 'content': result});
      }
    }
    _trimHistory();
    return AssistantMessage(false, '好的', songs: played);
  }

  /// 只保留最近 16 条（从一条用户消息开始，避免留下没有对应调用的工具结果）。
  void _trimHistory() {
    if (_history.length <= 16) return;
    var start = _history.length - 16;
    while (start < _history.length && _history[start]['role'] != 'user') {
      start++;
    }
    _history.removeRange(0, start);
  }

  /// 按“歌名 歌手”逐个搜索，取最匹配的一首。
  Future<List<Song>> _findSongs(List<String> queries) async {
    final results = await Future.wait([
      for (final q in queries.take(20))
        _source.search(q).then((r) => r.songs.where((s) => s.playable).firstOrNull).catchError((Object _) => null),
    ]);
    final seen = <String>{};
    return [
      for (final s in results.nonNulls)
        if (seen.add(s.key)) s,
    ];
  }

  Future<String> _runTool(String name, Map<String, dynamic> a, List<Song> played) async {
    String ok([Map<String, Object?> extra = const {}]) => jsonEncode({'ok': true, ...extra});
    switch (name) {
      case 'play_songs':
        final songs = await _findSongs([for (final s in (a['songs'] as List? ?? const [])) '$s']);
        if (songs.isEmpty) return jsonEncode({'ok': false, 'error': '在${_source.name}一首都没有找到'});
        await player.playSongs(songs, title: '${a['title'] ?? 'AI 推荐'}');
        played
          ..clear()
          ..addAll(songs);
        return ok({
          'found': [for (final s in songs) '${s.name} - ${s.artistText}'],
        });
      case 'play_artist':
        final songs = await _artistSongs('${a['artist']}');
        if (songs.isEmpty) return jsonEncode({'ok': false, 'error': '没有找到这位歌手'});
        await player.playSongs(songs, title: '${a['artist']}的歌');
        played
          ..clear()
          ..addAll(songs.take(10));
        return ok({'count': songs.length});
      case 'add_to_queue':
        final songs = await _findSongs([for (final s in (a['songs'] as List? ?? const [])) '$s']);
        player.addToQueue(songs);
        played.addAll(songs);
        return ok({
          'added': [for (final s in songs) '${s.name} - ${s.artistText}'],
        });
      case 'control_playback':
        await _runLocal(PlaybackIntent(PlaybackAction.values.byName('${a['action']}')));
        return ok();
      case 'set_volume':
        final v = await _setVolume(level: ((a['level'] as num?) ?? 50).clamp(0, 100) / 100);
        return ok({'volume': (v * 100).round()});
      case 'set_sleep_timer':
        final m = (a['minutes'] as num?)?.round() ?? 0;
        player.setSleepTimer(m <= 0 ? null : Duration(minutes: m));
        return ok();
      case 'set_sound':
        final preset = a['eq_preset'] as String?;
        if (preset != null) await _runLocal(EqIntent(preset == '关闭' ? null : preset));
        if (a['bass'] is num) app.setBassEnhance(((a['bass'] as num) / 100).clamp(0, 1).toDouble());
        if (a['spatial'] is num) app.setSpatial(((a['spatial'] as num) / 100).clamp(0, 1).toDouble());
        return ok();
      case 'like_current_song':
        await _runLocal(const LikeIntent());
        return ok();
      case 'get_now_playing':
        final song = player.current;
        if (song == null) return jsonEncode({'playing': false});
        final lines = player.lyrics.lines;
        final i = player.lyrics.indexAt(player.position.value);
        return jsonEncode({
          'title': song.name,
          'artists': song.artistText,
          'album': song.album?.name,
          'platform': _source.name,
          'position_seconds': player.position.value.inSeconds,
          'duration_seconds': player.duration.inSeconds,
          'playing': player.playing,
          'current_lyric': i >= 0 && i < lines.length ? lines[i].text : null,
          'next_lyric': i + 1 >= 0 && i + 1 < lines.length ? lines[i + 1].text : null,
        });
      case 'get_lyrics':
        final text = player.lyrics.lines.map((l) => l.text).where((t) => t.trim().isNotEmpty).join('\n');
        return jsonEncode({'lyrics': text.isEmpty ? '这首歌没有歌词' : (text.length > 4000 ? text.substring(0, 4000) : text)});
      case 'get_queue':
        final q = player.queue;
        final i = player.current == null ? -1 : q.indexOf(player.current!);
        return jsonEncode({
          'upcoming': [for (final s in q.skip(i + 1).take(10)) '${s.name} - ${s.artistText}'],
        });
      case 'get_listening_stats':
        return jsonEncode({
          'total_minutes': stats.total.inMinutes,
          'this_week_minutes': stats.thisWeek.inMinutes,
          'top_songs': [for (final s in stats.topSongs(10)) '${s.song.name} - ${s.song.artistText}（${s.plays} 次）'],
          'top_artists': [for (final a in stats.topArtists(8)) a.$1],
        });
    }
    return jsonEncode({'error': '未知函数 $name'});
  }

  // ── 朗读 ──────────────────────────────────────────

  Process? _say;

  Future<void> _speak(String text) async {
    // 朗读时去掉 Markdown 符号，太长的回答只读前面一段。
    final t = text.replaceAll(RegExp(r'[*#`>|_~]'), '').trim();
    if (t.isEmpty) return;
    final short = t.length > 160 ? '${t.substring(0, 160)}……' : t;
    try {
      if (_android) {
        await _channel.invokeMethod('speak', {'text': short});
      } else if (Platform.isMacOS) {
        _say = await Process.start('say', [short]);
      } else if (Platform.isWindows) {
        final escaped = short.replaceAll("'", "''");
        _say = await Process.start('powershell', [
          '-NoProfile',
          '-Command',
          "Add-Type -AssemblyName System.Speech; (New-Object System.Speech.Synthesis.SpeechSynthesizer).Speak('$escaped')",
        ]);
      } else if (Platform.isLinux) {
        _say = await Process.start('spd-say', ['-l', 'zh', short]);
      }
    } catch (e) {
      debugPrint('assistant speak: $e');
    }
  }

  Future<void> _stopSpeaking() async {
    _say?.kill();
    _say = null;
    if (_android) {
      try {
        await _channel.invokeMethod('stopSpeaking');
      } catch (_) {}
    }
  }

  /// 测试大模型连接。
  Future<String> testLlm() => _llm.ping();

  @override
  void dispose() {
    settings.removeListener(_syncVoice);
    unawaited(_stopVoice());
    _recorder?.dispose();
    _wakeEvents.close();
    super.dispose();
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}
