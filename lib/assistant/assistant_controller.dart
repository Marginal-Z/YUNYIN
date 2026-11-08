import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../core/lyrics_overlay.dart';
import '../core/settings.dart';
import '../core/theme/palette.dart';
import '../data/downloads.dart';
import '../data/listen_stats.dart';
import '../data/models.dart';
import '../data/sources/music_source.dart';
import '../data/sources/source_manager.dart';
import '../pet/pet_rig.dart';
import '../player/player_controller.dart';
import '../voice/prosody.dart';
import '../voice/speech_output.dart';
import '../voice/voice_library.dart';
import 'assistant_settings.dart';
import 'intents.dart';
import 'llm_client.dart';
import 'voice_engine.dart';
import 'voice_models.dart';
import 'wake_word.dart';

/// 对话中的一条消息。
class AssistantMessage {
  AssistantMessage(this.fromUser, this.text, {this.songs = const []});

  final bool fromUser;

  /// 文字（大模型边生成边显示时逐步增加）。
  String text;

  /// 助手为这条回答播放 / 推荐的歌曲（界面上显示为可点按的列表）。
  List<Song> songs;

  /// 大模型还在生成这条回答。
  bool streaming = false;
}

enum AssistantStatus { idle, listening, thinking }

/// 云音助手：语音唤醒（离线）、语音 / 文字指令、调用大模型（用户自己的接口）完成点歌、推荐与问答。
///
/// 常用指令（播放控制、点歌、音量、定时、音效）在本机解析，不需要大模型也能用；
/// 其余的话交给大模型，大模型通过函数调用操作播放器（见 [_tools]）。
class AssistantController extends ChangeNotifier {
  AssistantController({required this.settings, required this.app, required this.player, required this.sources, required this.stats, LlmClient? llm, this.speech, this.downloads}) {
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

  /// 语音输出（音色系统）；为 null 时不朗读（测试）。
  final SpeechOutput? speech;

  /// 下载管理（“下载这首歌”）；为 null 时不支持（测试）。
  final DownloadManager? downloads;
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

  /// 请界面打开某个页面（页面名称，附带的搜索关键词），见 [AppAction.open]。
  final StreamController<(String, String?)> _openEvents = StreamController.broadcast();
  Stream<(String, String?)> get openRequests => _openEvents.stream;

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
  /// 当前识别引擎使用的模型与唤醒词：变化时重启。
  String? _workerKey;
  String get _wantedKey => '${settings.asrModel.name}|${settings.wakeWordTokens.join(';')}';

  Future<void> _syncVoice() async {
    if (_worker != null && _workerKey != _wantedKey && status != AssistantStatus.listening) {
      await _stopVoice();
    }
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
      if (!await VoiceModelStore.ready(settings.asrModel)) {
        downloadProgress = 0;
        notifyListeners();
        await VoiceModelStore.download(
          settings.asrModel,
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
      final worker = await VoiceWorker.start(await VoiceModelStore.paths(settings.asrModel), wake: settings.voiceWake, wakeWords: settings.wakeWordTokens);
      _worker = worker;
      _workerKey = _wantedKey;
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
    debugPrint('assistant: $message');
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
    _worker?.setMonitor(false);
    unawaited(player.duck(true));
    unawaited(_stopSpeaking());
    notifyListeners();
  }

  void _onVoice(VoiceEvent e) {
    switch (e) {
      case VoiceWake():
        _beginListening();
        _wakeEvents.add(null);
      case VoiceBargeIn():
        // 助手说话时用户开口：立即停止朗读，开始听。
        unawaited(speech?.stop());
        _beginListening();
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

  /// 处理一句话（打字或语音）。[spoken] 为 true 时按设置朗读回答：大模型边生成边显示、边朗读；
  /// 朗读时可以开口打断；打开“连续对话”时，说完自动继续听下一句。
  Future<void> submit(String text, {bool spoken = false}) async {
    text = text.trim();
    if (text.isEmpty) return;
    messages.add(AssistantMessage(true, text));
    status = AssistantStatus.thinking;
    notifyListeners();
    final out = spoken && settings.speakReplies ? speech : null;
    SpeechTurn? turn;
    AssistantMessage? reply;
    var failed = false;
    try {
      final intent = parseIntent(text);
      if (intent != null) {
        reply = await _runLocal(intent);
      } else if (settings.llmConfigured) {
        reply = AssistantMessage(false, '')..streaming = true;
        messages.add(reply);
        turn = out?.begin();
        if (turn != null) _monitor(true);
        await _askLlm(text, reply, turn);
      } else {
        reply = AssistantMessage(false, '这句话需要大模型来理解。请在“设置 → 云音助手”中填写大模型接口与密钥；播放控制、点歌、音量与定时等常用指令不用设置也能直接说。');
      }
    } catch (e) {
      failed = true;
      final message = '出错了：${'$e'.replaceFirst('Exception: ', '')}';
      if (reply != null && reply.streaming) {
        // 已经说了一半：停下，改说出错的原因。
        await out?.stop();
        turn = null;
        reply.text = reply.text.isEmpty ? message : '${reply.text}\n$message';
      } else {
        reply = AssistantMessage(false, message);
      }
    }
    reply.streaming = false;
    if (!messages.contains(reply)) messages.add(reply);
    if (messages.length > 60) messages.removeRange(0, messages.length - 60);
    if (status == AssistantStatus.thinking) status = AssistantStatus.idle;
    notifyListeners();
    if (out != null) {
      if (turn == null) {
        turn = out.begin();
        turn.add(failed ? reply.text.split('\n').last : reply.text);
        _monitor(true);
      }
      // 等说完（被打断时立即返回）。
      await turn.end();
      _monitor(false);
    }
    if (!spoken) return;
    // 连续对话：说完后接着听（这期间用户已经开口打断、或者又点了麦克风时，已经在听了）。
    if (settings.continuous && !failed && status == AssistantStatus.idle && _worker != null) {
      _worker!.listen();
      _beginListening();
    } else if (!settings.voiceWake && status != AssistantStatus.listening) {
      unawaited(_stopVoice());
    }
  }

  /// 朗读期间检测用户开口（打断）。
  void _monitor(bool on) {
    if (settings.bargeIn || !on) _worker?.setMonitor(on);
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
        return AssistantMessage(false, await _runApp(const AppIntent(AppAction.open, 'lyrics')));
      case AppIntent():
        return AssistantMessage(false, await _runApp(intent));
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
你是“云音助手”，云音音乐播放器里的语音助手，用简体中文回答。当前平台：${_source.name}（只能播放这个平台的歌）。现在是 ${now.year} 年 ${now.month} 月 ${now.day} 日 ${now.hour} 点。
${song == null ? '现在没有在播放歌曲。' : '正在播放《${song.name}》- ${song.artistText}。'}
规则：
- 用户想听歌、要推荐或按心情 / 场景要歌单时，调用 play_songs，给出真实存在的歌曲（“歌名 歌手”），一般 8–15 首，风格贴合需求；只想听某位歌手时调用 play_artist。
- 播放控制、音量、定时关闭、音效等直接调用对应函数。
- 问到正在播放的歌、歌词含义、创作背景时，先调用 get_now_playing 或 get_lyrics 获取信息再回答；不确定的事实要说明不确定，不要编造。
- 这是语音对话：像朋友聊天一样自然、口语化，一般 1–3 句（不超过 80 字），不要列清单；用户要求详细解读时可以写长一些。不要使用 Markdown 标题和表格。
- 每次回答开头加一个情绪标记，从 [开心] [兴奋] [温柔] [平静] [难过] [认真] 中选一个最贴切的，例如“[开心] 好呀，这就放！”。标记只用来调整语气，不会显示也不会读出来。''';
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
    tool(
      'control_app',
      '控制云音本身：切换平台模式、深浅色、主题色、播放页样式，开关桌面歌词 / 状态栏歌词 / 歌词翻译 / 液态玻璃，'
          '显示或隐藏桌宠、换助手音色，下载正在播放的歌，播放每日推荐 / 我喜欢的音乐 / 最近播放，打开页面或搜索。',
      {
        'action': {
          'type': 'string',
          'enum': [for (final a in AppAction.values) a.name],
          'description':
              'platform（value：网易云 / QQ 音乐 / 酷狗 / 洛雪）；themeMode（light / dark / system）；accent（朱红 / 蓝 / 青绿 / 橙 / 石墨）；'
              'playerStyle（封面 / 黑胶 / 光盘 / 沉浸 / 卡片流 / 3D 封面流 / 照片墙 / 极简）；desktopLyrics、statusLyrics、translation、glass（on / off）；'
              'pet（团团 / 星月 / 阿曜 / off）；voice（云汐 / 小柚 / 晚星 / 清川 / 暮言）；download；playCollection（daily / liked / recent）；'
              'open（settings / downloads / stats / voice / pet / player / lyrics / library / search，search 时把关键词放在 query）',
        },
        'value': {'type': 'string'},
        'query': {'type': 'string'},
      },
      required: ['action'],
    ),
    tool('get_now_playing', '获取正在播放的歌曲信息、播放进度与当前歌词', {}),
    tool('get_lyrics', '获取正在播放歌曲的完整歌词', {}),
    tool('get_queue', '获取播放队列中接下来的歌曲', {}),
    tool('get_listening_stats', '获取用户的听歌统计（常听的歌曲与歌手、累计时长）', {}),
  ];

  /// 问大模型（流式）：文字边生成边写进 [reply]，有 [turn] 时边生成边朗读；函数调用最多 5 轮。
  Future<void> _askLlm(String text, AssistantMessage reply, SpeechTurn? turn) async {
    _history.add({'role': 'user', 'content': text});
    final played = <Song>[];
    final raw = StringBuffer();
    for (var round = 0; round < 5; round++) {
      final m = await _llm.stream(
        [
          {'role': 'system', 'content': _system},
          ..._history,
        ],
        tools: _tools,
        onText: (delta) {
          raw.write(delta);
          reply.text = ProsodyPlanner.displayText(raw.toString()).trimLeft();
          // 开始回答：不再是“思考中”。
          if (status == AssistantStatus.thinking) status = AssistantStatus.idle;
          turn?.add(delta);
          notifyListeners();
        },
      );
      final calls = (m['tool_calls'] as List?)?.cast<Map>() ?? const [];
      _history.add({
        'role': 'assistant',
        'content': m['content'] ?? '',
        if (calls.isNotEmpty) 'tool_calls': calls,
      });
      if (calls.isEmpty) break;
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
      reply.songs = List.of(played);
      notifyListeners();
      // 下一轮的文字接在后面，换一行。
      if (raw.isNotEmpty && !raw.toString().endsWith('\n')) {
        raw.write('\n');
        turn?.add('\n');
      }
    }
    _trimHistory();
    reply.songs = played;
    if (reply.text.trim().isEmpty) {
      reply.text = '好的';
      turn?.add('好的');
    }
  }

  /// 执行控制云音本身的指令，返回给用户的说明。
  Future<String> _runApp(AppIntent i) async {
    final v = (i.value ?? '').trim();
    bool on() => v != 'off';
    Future<bool> canDraw() async => !_android || await LyricsOverlay.canDraw();
    switch (i.action) {
      case AppAction.platform:
        final key = v.toLowerCase().replaceAll('音乐', '').replaceAll('网易云', '网易');
        final source = sources.selectable.where((s) => s.name.toLowerCase().contains(key)).firstOrNull;
        if (source == null) return '没有“$v”这个平台模式';
        await sources.select(source.id);
        return '已切换到${source.name}模式';
      case AppAction.themeMode:
        final mode = switch (v) {
          'dark' => ThemeMode.dark,
          'light' => ThemeMode.light,
          _ => ThemeMode.system,
        };
        app.setThemeMode(mode);
        return switch (mode) {
          ThemeMode.dark => '已切换到深色模式',
          ThemeMode.light => '已切换到浅色模式',
          _ => '外观已改为跟随系统',
        };
      case AppAction.accent:
        final accent = switch (v.replaceAll('色', '')) {
          '红' || '朱红' => AccentColor.red,
          '蓝' => AccentColor.blue,
          '绿' || '青绿' => AccentColor.teal,
          '橙' => AccentColor.orange,
          '灰' || '石墨' => AccentColor.graphite,
          _ => null,
        };
        if (accent == null) return '主题色只有朱红、蓝、青绿、橙和石墨';
        app.setAccent(accent);
        return '主题色已换成${accent.label}';
      case AppAction.playerStyle:
        final key = v.replaceAll(' ', '');
        final style = PlayerStyle.values.where((s) => s.label.replaceAll(' ', '') == key).firstOrNull ?? PlayerStyle.values.where((s) => s.label.replaceAll(' ', '').contains(key)).firstOrNull;
        if (style == null) return '没有“$v”这种播放页样式';
        app.setPlayerStyle(style);
        return '播放页已换成${style.label}样式';
      case AppAction.desktopLyrics || AppAction.statusLyrics:
        final desktop = i.action == AppAction.desktopLyrics;
        if (on() && !await canDraw()) return '需要先允许云音“显示在其他应用上层”：设置 → 桌面与状态栏歌词';
        app.setFlag(desktop ? 'desktopLyrics' : 'statusBarLyrics', on());
        return '${on() ? '已打开' : '已关闭'}${desktop ? '桌面歌词' : '状态栏歌词'}';
      case AppAction.translation:
        app.setFlag('showTranslation', on());
        return on() ? '已显示歌词翻译' : '已隐藏歌词翻译';
      case AppAction.glass:
        app.setFlag('glass', on());
        return on() ? '已打开液态玻璃效果' : '已关闭液态玻璃效果';
      case AppAction.pet:
        if (v == 'off') {
          settings.setPet('');
          return '桌宠已收起';
        }
        final kind = PetKind.values.where((k) => k.label == v).firstOrNull ?? PetKind.byName(settings.pet) ?? PetKind.tuantuan;
        if (!await canDraw()) return '需要先允许云音“显示在其他应用上层”：设置 → 云音助手 → 桌宠';
        settings.setPet(kind.name);
        speech?.settings.setVoice(kind.voiceId);
        return '${kind.label}来啦，${_android ? '回到桌面就能看到它' : '在桌面上陪你'}';
      case AppAction.voice:
        final voice = VoicePresets.all.where((p) => p.name == v).firstOrNull;
        if (voice == null || speech == null) return '没有“$v”这个音色';
        speech!.settings.setVoice(voice.id);
        return '好的，换成${voice.name}的声音了';
      case AppAction.download:
        final song = player.current;
        if (song == null) return '现在没有在播放歌曲';
        if (downloads == null) return '这里不能下载歌曲';
        final ok = await downloads!.download(song);
        return ok ? '开始下载《${song.name}》' : '《${song.name}》已经下载过了或者不能下载';
      case AppAction.playCollection:
        final (title, songs) = switch (v) {
          'liked' => ('我喜欢的音乐', await _likedSongs()),
          'recent' => ('最近播放', await _source.recentSongs()),
          _ => ('每日推荐', (await _source.homeFeed()).daily),
        };
        final playable = songs.where((s) => s.playable).toList();
        if (playable.isEmpty) return '$title里没有可以播放的歌曲';
        await player.playSongs(playable, title: title);
        return '为你播放$title，共 ${playable.length} 首';
      case AppAction.open:
        const names = {
          'settings': '设置',
          'downloads': '下载与缓存',
          'stats': '听歌统计',
          'voice': '音色中心',
          'pet': '桌宠设置',
          'player': '播放页',
          'lyrics': '歌词',
          'library': '乐库',
          'search': '搜索结果',
        };
        final page = names.containsKey(v) ? v : 'settings';
        if ((page == 'player' || page == 'lyrics') && player.current == null) return '现在没有在播放歌曲';
        _openEvents.add((page, i.query));
        return page == 'search' ? '为你搜索“${i.query ?? ''}”' : '已打开${names[page]}';
    }
  }

  /// “我喜欢的音乐”：用户歌单中名称带“喜欢”的那个（网易云、QQ 音乐、酷狗都是第一个）。
  Future<List<Song>> _likedSongs() async {
    final lists = await _source.userPlaylists();
    final liked = lists.where((p) => p.name.contains('喜欢')).firstOrNull ?? lists.firstOrNull;
    if (liked == null) return const [];
    return (await _source.playlist(liked.id)).tracks ?? const [];
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
      case 'control_app':
        final action = AppAction.values.asNameMap()['${a['action']}'];
        if (action == null) return jsonEncode({'error': '未知动作 ${a['action']}'});
        return jsonEncode({'result': await _runApp(AppIntent(action, a['value'] as String?, a['query'] as String?))});
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

  Future<void> _stopSpeaking() async => speech?.stop();

  /// 设置自定义唤醒词（空字符串恢复默认）。返回错误原因，成功时为 null。
  Future<String?> setWakeWord(String word) async {
    if (word.trim().isEmpty) {
      settings.setWakeWord('', '');
      return null;
    }
    // 读音校验需要唤醒模型的标记表：模型还没下载时先下载。
    if (!await VoiceModelStore.ready(settings.asrModel)) {
      downloadProgress = 0;
      notifyListeners();
      try {
        await VoiceModelStore.download(settings.asrModel, onProgress: (p) {
          downloadProgress = p;
          notifyListeners();
        });
      } catch (e) {
        return '$e'.replaceFirst('Exception: ', '');
      } finally {
        downloadProgress = null;
        notifyListeners();
      }
    }
    final (line, error) = await WakeWords.toTokens(word, (await VoiceModelStore.paths(settings.asrModel)).kwsTokens);
    if (line == null) return error;
    settings.setWakeWord(word.trim(), line);
    return null;
  }

  /// 测试大模型连接。
  Future<String> testLlm() => _llm.ping();

  @override
  void dispose() {
    settings.removeListener(_syncVoice);
    unawaited(_stopVoice());
    _recorder?.dispose();
    _wakeEvents.close();
    _openEvents.close();
    super.dispose();
  }
}

