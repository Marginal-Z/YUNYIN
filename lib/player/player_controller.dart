import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/settings.dart';
import '../data/cover_resolver.dart';
import '../data/models.dart';
import '../data/sources/music_source.dart';
import '../data/sources/source_manager.dart';
import '../data/sources/source_policy.dart';
import 'mpv_property.dart' if (dart.library.js_interop) 'mpv_property_web.dart';

enum PlayMode { sequence, shuffle, repeatOne }

/// 播放器提示（由界面以轻提示 / 弹窗展示）。
class PlayerNotice {
  const PlayerNotice(this.title, {this.message, this.blocking = false, this.actionUrl});

  final String title;
  final String? message;
  final Uri? actionUrl;

  /// 需要用户确认的提示（例如“暂无播放版权”）。
  final bool blocking;
}

/// 播放队列与播放状态。音频由 media_kit（libmpv / HTML5 audio）驱动。
class PlayerController extends ChangeNotifier {
  PlayerController(this.sources, this.settings, {Player? engine}) : _player = engine;

  final SourceManager sources;
  final AppSettings settings;

  Player? _player;
  bool _disposed = false;
  int _likesToken = 0;
  final List<StreamSubscription<Object?>> _subs = [];

  List<Song> _queue = [];
  int _index = -1;
  List<int> _order = [];
  PlayMode mode = PlayMode.sequence;
  bool playing = false;
  bool buffering = false;
  String? queueTitle;

  /// 播放进度单独通知，避免整页重建。
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);
  Duration duration = Duration.zero;

  Lyrics lyrics = Lyrics.empty;
  final Set<String> _liked = {};
  final List<Song> history = [];

  final StreamController<PlayerNotice> _notices = StreamController.broadcast();
  Stream<PlayerNotice> get notices => _notices.stream;

  /// 查找已下载的本地副本（由下载管理器提供）。
  Song? Function(Song song)? localLookup;

  Timer? _sleepTimer;
  DateTime? sleepAt;
  int _loadToken = 0;
  bool _playRequested = false;
  double _fade = 1;

  List<Song> get queue => List.unmodifiable(_queue);
  int get index => _index;
  Song? get current => _index >= 0 && _index < _queue.length ? _queue[_index] : null;
  double get volume => settings.volume;

  /// 接下来要播放的歌曲（不含当前）。
  List<Song> get upNext {
    if (_index < 0) return const [];
    final pos = _order.indexOf(_index);
    return [for (final i in _order.skip(pos + 1)) _queue[i]];
  }

  bool isLiked(Song s) => _liked.contains(s.key);

  /// 播放引擎初始化失败的原因（例如 Linux 上缺少 libmpv）。为 null 表示正常。
  String? engineError;

  Future<void> init() async {
    try {
      await _initEngine();
    } catch (e) {
      engineError = e.toString();
      debugPrint('player engine unavailable: $e');
    }
    settings.addListener(_applyVolume);
    settings.addListener(_applyOutput);
    settings.addListener(_scheduleEq);
    settings.addListener(_scheduleFx);
    sources.addListener(_refreshLikes);
    sources.addListener(_onPlatformChanged);
    _platform = sources.current.id;
    await _restore();
    _scheduleEq();
    _refreshLikes();
  }

  /// Linux 便携包（tar.gz / AppImage）把 libmpv 及其依赖放在可执行文件旁的 lib/mpv 中，优先使用它；
  /// 否则使用系统安装的 libmpv（deb 包通过依赖自动安装）。
  static String? bundledLibmpv() {
    if (kIsWeb || !Platform.isLinux) return null;
    final dir = File(Platform.resolvedExecutable).parent.path;
    for (final name in ['libmpv.so.2', 'libmpv.so.1', 'libmpv.so']) {
      final f = File('$dir/lib/mpv/$name');
      if (f.existsSync()) return f.path;
    }
    return null;
  }

  Future<void> _initEngine() async {
    if (_player == null && !kIsWeb) MediaKit.ensureInitialized(libmpv: bundledLibmpv());
    final p =
        _player ??
        Player(
          configuration: const PlayerConfiguration(title: '云音', logLevel: MPVLogLevel.error),
        );
    _player = p;
    _subs.addAll([
      // 只在状态真正变化时通知：播放引擎会重复报告相同的状态，每次通知都会让监听播放器的页面整页重建。
      p.stream.playing.listen((v) {
        if (v == playing) return;
        playing = v;
        notifyListeners();
      }),
      p.stream.position.listen((v) {
        // 正在打开新歌时上一首仍在报告进度，不能覆盖新歌的进度（界面与系统媒体控制会先跳到上一首的位置）。
        if (_opening) return;
        // 界面上的进度每 250ms 刷新一次即可，避免每帧重绘（玻璃模糊开销很大）。
        if ((v - position.value).abs() >= const Duration(milliseconds: 250) || v < position.value) position.value = v;
      }),
      p.stream.duration.listen((v) {
        if (_opening || v == Duration.zero || v == duration) return;
        duration = v;
        notifyListeners();
      }),
      p.stream.buffering.listen((v) {
        if (v == buffering) return;
        buffering = v;
        notifyListeners();
      }),
      p.stream.completed.listen((done) {
        if (done) _onCompleted();
      }),
      p.stream.error.listen((e) {
        if (current != null && e.isNotEmpty) debugPrint('player error: $e');
        // 播放地址打不开（失效、404、网络错误）：结束加载并给出原因，而不是一直显示加载中。
        if (e.contains('Failed to open') && current != null) _onOpenFailed();
        // 音频滤镜（均衡器）创建失败：关闭均衡器并在原位置重新播放，避免一直没有声音。
        if (e.contains('Audio filter') && _eqApplied.isNotEmpty) {
          unawaited(_onEqFailed().then((_) => current != null ? _load(autoplay: true, keepPosition: true) : null));
        }
      }),
      p.stream.log.listen((l) {
        if (l.text.contains('Could not open/initialize audio device')) _onAudioDeviceFailed();
        // 音频滤镜（均衡器）在个别设备上创建失败时关闭它，避免没有声音。
        if (_eqApplied.isNotEmpty &&
            (l.text.contains('Disabling filter') ||
                l.text.contains('failed to configure the filter graph') ||
                l.text.contains('Could not create') ||
                l.text.contains('Error parsing'))) {
          _onEqFailed();
        }
      }),
    ]);
    if (!kIsWeb && Platform.isAndroid) await _configureAndroidAudio(p);
    await _configureOutput(p);
    await _applyEq();
    await _applyVolume();
  }

  /// Android 音频输出的兼容设置。
  ///
  /// mpv 默认把浮点 PCM、按音源声道数交给 AudioTrack。部分平板（多扬声器、部分联发科芯片等）
  /// 的音频 HAL 接受浮点格式却输出静音，或者无法按多声道布局打开设备。音乐本身都是立体声，
  /// 这里统一以 16 位立体声交给系统混音，这是所有 Android 设备都支持的格式，手机上听感相同。
  Future<void> _configureAndroidAudio(Player p) async {
    if (!await setMpvProperty(p, 'audio-channels', 'stereo')) return;
    // 播放器使用单独申请的音频会话，系统音效链（音量增强与限幅、空间音效、低频增强）挂在这个会话上。
    try {
      final session = await _fxChannel.invokeMethod<int>('session');
      if (session != null && session > 0 && await setMpvProperty(p, 'audiotrack-session-id', '$session')) _fxSession = session;
    } catch (e) {
      debugPrint('audio fx session: $e');
    }
    await _applyFx();
    // “高解析输出”打开时以 32 位浮点交给系统，保留解码后的完整动态范围。
    await setMpvProperty(p, 'audiotrack-pcm-float', settings.hiResOutput ? 'yes' : 'no');
    if (settings.openSles) await setMpvProperty(p, 'ao', 'opensles');
    _openSles = settings.openSles;
    _hiRes = settings.hiResOutput;
  }

  /// 各平台通用的输出设置：
  /// - 软件音量上限提高到 200%，用于“音量增强”；
  /// - 本地文件带 ReplayGain 标签时按标签均衡音量（与“音量均衡”开关一致）；
  /// - Windows / macOS 可独占音频设备（WASAPI / Core Audio 独占模式），绕过系统混音与重采样。
  Future<void> _configureOutput(Player p) async {
    if (!await setMpvProperty(p, 'volume-max', '200')) return;
    await _applyHifi(p);
    await setMpvProperty(p, 'replaygain', settings.normalize ? 'track' : 'no');
    // 按标签提升音量时自动降低增益，避免削波破音。
    await setMpvProperty(p, 'replaygain-clip', 'yes');
    if (_exclusiveSupported) await setMpvProperty(p, 'audio-exclusive', settings.exclusiveAudio ? 'yes' : 'no');
    _exclusive = settings.exclusiveAudio;
    _normalize = settings.normalize;
  }

  static bool get _exclusiveSupported => !kIsWeb && (Platform.isWindows || Platform.isMacOS);

  bool _openSles = false;
  bool _hiRes = false;
  bool _exclusive = false;
  bool _normalize = true;
  bool? _hifi;

  /// 高保真引擎：重采样使用更长的 sinc 滤镜（32 抽头、12 位相位精度，默认 16 / 10），
  /// 转换为整数采样时使用三角高通抖动，降低量化噪声。关闭时恢复 mpv 默认值。
  Future<void> _applyHifi(Player p) async {
    if (_hifi == settings.hifiEngine) return;
    _hifi = settings.hifiEngine;
    final on = settings.hifiEngine;
    await setMpvProperty(p, 'audio-resample-filter-size', on ? '32' : '16');
    await setMpvProperty(p, 'audio-resample-phase-shift', on ? '12' : '10');
    await setMpvProperty(p, 'audio-swresample-o', on ? 'dither_method=triangular_hp' : '');
  }

  /// 设置中切换输出相关选项（兼容输出、高解析输出、独占输出、音量均衡）：更新 mpv 属性，
  /// 需要重新打开音频设备的选项在原位置重新加载当前歌曲。
  Future<void> _applyOutput() async {
    final p = _player;
    if (kIsWeb || p == null) return;
    var reload = false;
    if (settings.normalize != _normalize) {
      _normalize = settings.normalize;
      await setMpvProperty(p, 'replaygain', _normalize ? 'track' : 'no');
    }
    if (settings.hifiEngine != _hifi) await _applyHifi(p);
    if (Platform.isAndroid && settings.openSles != _openSles) {
      _openSles = settings.openSles;
      reload = await setMpvProperty(p, 'ao', _openSles ? 'opensles' : 'audiotrack,opensles');
    }
    if (Platform.isAndroid && settings.hiResOutput != _hiRes) {
      _hiRes = settings.hiResOutput;
      reload = await setMpvProperty(p, 'audiotrack-pcm-float', _hiRes ? 'yes' : 'no') || reload;
    }
    if (_exclusiveSupported && settings.exclusiveAudio != _exclusive) {
      _exclusive = settings.exclusiveAudio;
      reload = await setMpvProperty(p, 'audio-exclusive', _exclusive ? 'yes' : 'no') || reload;
    }
    if (reload && current != null) await _load(autoplay: playing, keepPosition: true);
  }

  /// 重新获取当前歌曲的播放地址并播放（例如完成平台的官方验证后）。
  Future<void> retryCurrent() async {
    if (current != null) await _load(autoplay: true, keepPosition: true);
  }

  /// 已经尝试过的音频输出兜底次数。
  int _audioFallback = 0;

  /// mpv 无法打开音频设备（静音播放）：Android 上依次改用 48kHz 采样率与 OpenSL ES 输出并重新加载；
  /// 仍然失败时提示，而不是一直无声播放。
  Future<void> _onAudioDeviceFailed() async {
    final p = _player;
    if (!kIsWeb && Platform.isAndroid && p != null && _audioFallback < 2) {
      _audioFallback++;
      debugPrint('audio device failed, fallback $_audioFallback');
      if (_audioFallback == 1) {
        await setMpvProperty(p, 'audio-samplerate', '48000');
        // 个别设备不接受单独申请的音频会话：改用系统默认会话（系统音效链随之停用，增强改回软件音量）。
        if (_fxSession != 0 && await setMpvProperty(p, 'audiotrack-session-id', '0')) {
          _fxSession = 0;
          _nativeBoost = false;
          await _applyVolume();
        }
      } else {
        await setMpvProperty(p, 'ao', 'opensles');
      }
      if (current != null) await _load(autoplay: playing, keepPosition: true);
      return;
    }
    if (_audioFallback == 99) return;
    _audioFallback = 99;
    _notices.add(const PlayerNotice('无法打开音频设备', message: '系统没有可用的音频输出，请检查音量、蓝牙耳机或其他占用音频的应用后重新播放。'));
  }

  /// 测试用：直接设置播放队列与当前歌曲（不加载音频）。
  @visibleForTesting
  void debugSetQueue(List<Song> songs, int index) {
    _queue = List.of(songs);
    _index = index;
    _rebuildOrder();
    notifyListeners();
  }

  /// 底层播放器，供集成测试检查音频输出状态。
  @visibleForTesting
  Player? get engine => _player;

  PlayerNotice get _engineNotice => PlayerNotice(
    '缺少播放组件',
    message: !kIsWeb && Platform.isLinux ? '没有找到 libmpv。请在终端运行 sudo apt install libmpv2 后重新打开云音。' : '播放引擎初始化失败：$engineError',
    blocking: true,
  );

  /// 当前歌曲的音量均衡系数。
  ///
  /// 不使用 mpv 的 loudnorm 滤镜：Android / Windows / macOS 使用的精简版 libmpv 没有这个滤镜，
  /// 设置后音频链初始化失败会导致完全无声。改为按平台提供的响度增益调整音量：
  /// 比参考响度（-8 dB）更响的歌曲按差值衰减，较轻的歌曲保持原音量，避免削波。
  double _gain = 1;

  static double gainFactor(double? gainDb) {
    if (gainDb == null || gainDb == 0) return 1;
    // 最多衰减 6 dB：响度很高的歌曲也不会比其他歌曲明显偏小。
    return math.pow(10, (gainDb + 8) / 20).toDouble().clamp(0.5, 1.0);
  }

  /// 手机与平板没有应用内音量条，音量完全由系统音量键控制，应用内始终满音量输出；
  /// 桌面端使用播放条上的音量。
  static bool get _systemVolumeOnly => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// 峰值余量（-1.5 dB）：响度很高的母带解码后真峰值会超过满刻度（实测热门歌曲约 +0.3 dBTP），
  /// 手机上以 16 位交给系统、或者重采样到 48kHz 时被削波，听起来就是破音。
  /// QQ 音乐、酷狗与洛雪音源不提供响度信息，网易云关闭音量均衡时也不衰减，所以至少保留这一余量。
  static const peakHeadroom = 0.8414;

  /// 应用到播放器的音量系数（1 为原始电平）：音量均衡的衰减与峰值余量取较小者。
  @visibleForTesting
  static double levelFactor({required double gain, required bool normalize, required double strength}) {
    final norm = normalize ? math.pow(gain, strength).toDouble() : 1.0;
    return math.min(norm, peakHeadroom);
  }

  double get _effectiveVolume {
    final base = _systemVolumeOnly ? 1.0 : settings.volume;
    // 音量均衡强度：按比例应用响度增益（强度 0.5 时衰减量减半）。
    final level = levelFactor(gain: _gain, normalize: settings.normalize, strength: settings.normalizeStrength);
    final boost = softwareBoost(
      boostDb: _boostHandled ? 0 : settings.volumeBoost,
      peak: _peak,
      level: math.pow(base, 3) * level * _eqHeadroom,
      eqPeakDb: _eqApplied.isEmpty ? 0 : _filterGains.fold<double>(0, math.max),
    );
    return mpvVolume(base: base * _fade, gain: _duck * level * boost * _eqHeadroom);
  }

  /// 换算为 mpv 的音量。mpv 的音量是三次方曲线：音量 v 对应的振幅是 (v / 100)³。
  /// [base] 是音量滑块与淡入淡出（按听感变化，直接使用）；[gain] 是线性的振幅系数（音量均衡、峰值余量、
  /// 均衡器余量、音量增强与语音助手压低），需要先开三次方根。此前直接相乘，所有衰减在分贝上都被放大到三倍：
  /// 例如均衡器有 +4 dB 提升时整体本应只压低 2.4 dB，实际压低了 7 dB 多，均衡器的提升几乎被抵消，听不出变化。
  @visibleForTesting
  static double mpvVolume({required double base, required double gain}) =>
      (base * math.pow(math.max(gain, 0), 1 / 3) * 100).clamp(0, 200).toDouble();

  /// 语音助手听指令时压低音乐的系数。
  double _duck = 1;

  /// 语音助手听指令时把音乐压低到 25%（识别更准），说完后恢复。
  Future<void> duck(bool on) async {
    final v = on ? 0.25 : 1.0;
    if (v == _duck) return;
    _duck = v;
    await _applyVolume();
  }

  /// 当前歌曲的峰值（平台提供；不知道时为 null）。
  double? _peak;

  /// 没有限幅器时的音量增强（Windows / macOS 的精简版播放引擎、Android 系统音效不可用时）：
  /// 按平台给出的峰值计算最多能提升多少而不超过满刻度（-0.26 dBFS），取它与设定的增强量中较小的一个。
  /// 平台没有给出峰值的歌曲不提升（无法保证不削波）。[level] 为提升之前的电平系数，[eqPeakDb] 为均衡器最大提升。
  @visibleForTesting
  static double softwareBoost({required int boostDb, required double? peak, required double level, double eqPeakDb = 0}) {
    if (boostDb <= 0 || peak == null || peak <= 0 || level <= 0) return 1;
    final want = math.pow(10, boostDb / 20).toDouble();
    final effectivePeak = peak * math.pow(10, math.max(0, eqPeakDb) / 20).toDouble() * level;
    return math.min(want, math.max(1.0, 0.97 / effectivePeak));
  }

  // ── 均衡器 ──────────────────────────────────────────

  /// 当前生效的 mpv 音频滤镜（空字符串表示没有）。
  String _eqApplied = '';
  Timer? _eqTimer;

  /// 均衡器在当前设备上不可用（滤镜创建失败）。
  bool eqUnsupported = false;

  /// 低频增强（强度 1 时）在各频段的提升：集中在 30–120 Hz 的鼓点与贝斯，250 Hz 以上不变，人声不会发闷。
  static const bassCurve = [4.5, 5.0, 3.5, 1.5, 0, 0, 0, 0, 0, 0];

  /// 空间音效（强度 1 时）的声场曲线：略微降低 500 Hz–1 kHz 的中频“箱体感”，提升 4 kHz 以上的空气感与细节，
  /// 听感更开阔。系统的虚拟环绕在部分设备（尤其外放）上不生效，这条曲线保证所有设备都能听出变化。
  static const spatialCurve = [0.0, 0, 0, 0, -1.5, -1.0, 0, 1.0, 2.0, 2.5];

  /// 播放器均衡器的各频段增益：用户均衡器（打开时）+ 低频增强 + 空间音效，每个频段限制在 ±12 dB。
  @visibleForTesting
  static List<double> effectGains({required List<double> eq, double bass = 0, double spatial = 0}) => [
    for (var i = 0; i < kEqBands.length; i++)
      ((i < eq.length ? eq[i] : 0) + bassCurve[i] * bass + spatialCurve[i] * spatial).clamp(-12.0, 12.0),
  ];

  /// 当前设置下播放器均衡器的各频段增益（均衡器滤镜不可用时为空）。
  List<double> get _filterGains => eqUnsupported
      ? const []
      : effectGains(eq: settings.eqEnabled ? settings.eqGains : const [], bass: settings.bassEnhance, spatial: settings.spatial);

  /// 由 10 个频段的增益生成 mpv 的音频滤镜：每个频段一个倍频程宽的峰值均衡器。
  ///
  /// Android / Windows / macOS 的精简版 FFmpeg 只带有 equalizer（没有 volume、bass、aresample 等）。
  /// equalizer 只接受平面格式的采样，FFmpeg 平时会自动插入 aresample 转换格式，精简版里没有它，
  /// 滤镜图就无法配置；所以先用 mpv 自带的 format 滤镜转成平面浮点（floatp），FFmpeg 无需再转换。
  /// 所有频段为 0 时返回空字符串（不加滤镜）。
  static String eqFilter(List<double> gains) => audioFilter(gains: gains);

  /// 完整的音频滤镜：均衡器各频段，以及（[boostDb] 大于 0 时）增益与限幅器。
  /// 限幅器（alimiter，-0.5 dBFS，1 ms 起始、80 ms 释放，不做自动电平）放在最后，增益与均衡器提升都不会削波。
  static String audioFilter({List<double> gains = const [], int boostDb = 0}) {
    final parts = <String>[
      for (var i = 0; i < gains.length && i < kEqBands.length; i++)
        if (gains[i].abs() >= 0.05) 'equalizer=f=${kEqBands[i]}:width_type=o:width=1:g=${gains[i].toStringAsFixed(1)}',
      if (boostDb > 0) ...['volume=${boostDb}dB', 'alimiter=limit=0.944:attack=1:release=80:level=0'],
    ];
    if (parts.isEmpty) return '';
    return 'format=format=floatp,lavfi=[${parts.join(',')}]';
  }

  // ── 系统音效链与限幅 ──────────────────────────────────

  static const _fxChannel = MethodChannel('yunyin/audio_fx');

  /// Android 播放器使用的音频会话（0 表示系统默认会话，没有系统音效链）。
  int _fxSession = 0;

  /// Android 系统音效链负责音量增强（DynamicsProcessing / LoudnessEnhancer）。
  bool _nativeBoost = false;

  /// 桌面端的播放引擎没有限幅滤镜（精简版 FFmpeg）。
  bool limiterUnsupported = false;

  /// Android 设备不支持空间音效 / 低频增强（音效页显示“当前设备不支持”）。
  bool spatialUnsupported = false;
  bool bassUnsupported = false;

  /// 音量增强由带限幅的音效链完成，而不是提升播放器音量。
  bool get _boostHandled => settings.volumeBoost == 0 || _nativeBoost || _limiterBoost;

  /// 桌面端在滤镜中完成音量增强（增益 + 限幅）。
  bool get _limiterBoost => !_isAndroid && !limiterUnsupported && settings.volumeBoost > 0;

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// 音量增强改为按峰值智能提升（没有可用的限幅器）：不会削波，但已经很响的歌曲提升不多。
  bool get smartBoost => settings.volumeBoost > 0 && !_boostHandled;

  Timer? _fxTimer;
  String _fxApplied = '';

  void _scheduleFx() {
    if (!_isAndroid || _fxSession == 0) return;
    if (_fxKey == _fxApplied) return;
    _fxTimer?.cancel();
    _fxTimer = Timer(const Duration(milliseconds: 150), _applyFx);
  }

  String get _fxKey =>
      '${settings.volumeBoost}|${settings.spatial.toStringAsFixed(2)}|${settings.bassEnhance.toStringAsFixed(2)}|${settings.eqEnabled}|${_filterGains.any((g) => g > 0)}|$eqUnsupported';

  Future<void> _applyFx() async {
    if (!_isAndroid || _fxSession == 0) return;
    _fxApplied = _fxKey;
    try {
      final r = await _fxChannel.invokeMapMethod<String, Object?>('configure', {
        'boostDb': settings.volumeBoost.toDouble(),
        // 均衡器有提升或者开了音量增强时保留限幅器，其余时候不改变原始声音。
        'limiter': settings.volumeBoost > 0 || _filterGains.any((g) => g > 0),
        'spatial': settings.spatial,
        // 低频增强在播放器的均衡器中完成（所有设备都有效）；只有均衡器滤镜不可用时才交给系统的 BassBoost。
        'bass': eqUnsupported ? settings.bassEnhance : 0.0,
      });
      _nativeBoost = settings.volumeBoost > 0 && r?['limiter'] == true;
      spatialUnsupported = settings.spatial > 0 && r?['spatial'] == false;
      bassUnsupported = eqUnsupported && settings.bassEnhance > 0 && r?['bass'] == false;
    } catch (e) {
      debugPrint('audio fx: $e');
      _nativeBoost = false;
    }
    await _applyVolume();
    notifyListeners();
  }

  /// 均衡器有提升时整体降低一部分电平（通过播放器音量，而不是 volume 滤镜），减少削波。
  double get _eqHeadroom {
    if (_eqApplied.isEmpty || eqUnsupported) return 1;
    // 后面有限幅器时不需要预先压低电平。Android 的系统限幅器在 mpv 之后：只有以浮点格式交给系统时
    // （高解析输出），超过满刻度的采样才能完整到达限幅器，否则在转换为 16 位时已经削波。
    if (_eqApplied.contains('alimiter') || (_isAndroid && _fxSession != 0 && settings.hiResOutput)) return 1;
    final peak = _filterGains.fold<double>(0, math.max);
    return peak > 0 ? math.pow(10, -peak * 0.6 / 20).toDouble() : 1;
  }

  /// 拖动滑块时连续变化：合并为每 120ms 最多更新一次滤镜。
  /// 当前设置对应的滤镜：均衡器（打开且设备支持时），以及桌面端的音量增强与限幅。
  String get _wantedFilter => audioFilter(
    gains: _filterGains,
    boostDb: _limiterBoost ? settings.volumeBoost : 0,
  );

  void _scheduleEq() {
    final want = _wantedFilter;
    if (want == _eqApplied) return;
    _eqTimer?.cancel();
    _eqTimer = Timer(const Duration(milliseconds: 120), _applyEq);
  }

  Future<void> _applyEq() async {
    final p = _player;
    if (p == null || kIsWeb) return;
    final want = _wantedFilter;
    if (want == _eqApplied) return;
    if (await setMpvProperty(p, 'af', want)) _eqApplied = want;
    await _applyVolume();
  }

  /// 记一次滤镜失败（每次启动最多记一次）。
  final Set<String> _failedThisRun = {};
  Future<void> _countFailure(String key) async {
    if (!_failedThisRun.add(key)) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt(key, (p.getInt(key) ?? 0) + 1);
  }

  Future<void> _onEqFailed() async {
    // 滤镜链中有限幅器且还没确认过：先认为是限幅器不可用（精简版播放引擎没有 alimiter），去掉它再试，
    // 不连带关闭均衡器。
    if (_eqApplied.contains('alimiter') && !limiterUnsupported) {
      limiterUnsupported = true;
      unawaited(_countFailure('limiterFailures.v2'));
      final p = _player;
      final want = _wantedFilter;
      if (p != null && await setMpvProperty(p, 'af', want)) _eqApplied = want;
      await _applyVolume();
      notifyListeners();
      return;
    }
    if (eqUnsupported) return;
    eqUnsupported = true;
    unawaited(_countFailure('eqFailures.v2'));
    // 低频增强改由系统的 BassBoost 完成。
    _scheduleFx();
    final p = _player;
    if (p != null) await setMpvProperty(p, 'af', '');
    _eqApplied = '';
    notifyListeners();
    _notices.add(const PlayerNotice('均衡器不可用', message: '当前设备的播放引擎不支持均衡器，已自动关闭。'));
  }

  Future<void> _applyVolume() async {
    await _player?.setVolume(_effectiveVolume);
  }

  Future<void> _refreshLikes() async {
    final token = ++_likesToken;
    final ids = <String>{};
    for (final s in sources.sources) {
      try {
        for (final id in await s.likedSongIds()) {
          ids.add('${s.id}:$id');
        }
      } catch (_) {}
    }
    if (_disposed || token != _likesToken) return;
    _liked
      ..clear()
      ..addAll(ids)
      ..addAll(_localLikes.keys);
    notifyListeners();
  }

  // ── 队列 ──────────────────────────────────────────

  void _rebuildOrder({bool keepCurrentFirst = true}) {
    final n = _queue.length;
    _order = List.generate(n, (i) => i);
    if (mode == PlayMode.shuffle && n > 1) {
      _order.shuffle(math.Random());
      if (keepCurrentFirst && _index >= 0) {
        _order.remove(_index);
        _order.insert(0, _index);
      }
    }
  }

  Future<void> playSongs(List<Song> songs, {int start = 0, bool shuffle = false, String? title}) async {
    if (songs.isEmpty) return;
    // 歌单、榜单里偶尔有重复的歌曲：队列中每首只保留一次，否则按歌曲查找位置（切歌、移除）会落到另一处。
    final want = songs[start.clamp(0, songs.length - 1)];
    final seen = <String>{};
    songs = [
      for (final s in songs)
        if (seen.add(s.key)) s,
    ];
    start = songs.indexOf(want);
    _queue = List.of(songs);
    queueTitle = title;
    if (shuffle) {
      mode = PlayMode.shuffle;
      start = math.Random().nextInt(songs.length);
    }
    _index = start.clamp(0, songs.length - 1);
    _rebuildOrder();
    _saveQueue();
    await _load(autoplay: true);
  }

  /// 插到当前歌曲之后并立即播放。
  Future<void> playSong(Song song, {List<Song>? context, String? title}) async {
    if (context != null) {
      final i = context.indexOf(song);
      return playSongs(context, start: i < 0 ? 0 : i, title: title);
    }
    final existing = _queue.indexOf(song);
    if (existing >= 0) {
      _index = existing;
    } else {
      _queue.insert(_index + 1, song);
      _index = _index + 1;
      _rebuildOrder();
    }
    _saveQueue();
    await _load(autoplay: true);
  }

  void playNext(Song song) {
    if (current == null) {
      playSongs([song]);
      return;
    }
    final existing = _queue.indexOf(song);
    if (existing == _index) return;
    if (existing >= 0) {
      _queue.removeAt(existing);
      if (existing < _index) _index--;
    }
    _queue.insert(_index + 1, song);
    _rebuildOrder();
    if (mode == PlayMode.shuffle) {
      _order.remove(_index + 1);
      _order.insert(_order.indexOf(_index) + 1, _index + 1);
    }
    _saveQueue();
    notifyListeners();
  }

  void addToQueue(List<Song> songs) {
    if (current == null) {
      playSongs(songs);
      return;
    }
    for (final s in songs) {
      if (!_queue.contains(s)) _queue.add(s);
    }
    _rebuildOrder();
    _saveQueue();
    notifyListeners();
  }

  void removeSong(Song song) {
    final i = _queue.indexOf(song);
    if (i < 0 || i == _index) return;
    _queue.removeAt(i);
    if (i < _index) _index--;
    _rebuildOrder();
    _saveQueue();
    notifyListeners();
  }

  /// 在“接下来播放”列表中拖动排序。
  void moveUpNext(int from, int to) {
    final upcoming = upNext;
    if (from < 0 || from >= upcoming.length) return;
    final song = upcoming.removeAt(from);
    upcoming.insert(to.clamp(0, upcoming.length), song);
    final cur = current!;
    final before = [for (final i in _order.take(_order.indexOf(_index))) _queue[i]];
    _queue = [...before, cur, ...upcoming];
    _index = before.length;
    _order = List.generate(_queue.length, (i) => i);
    _saveQueue();
    notifyListeners();
  }

  /// 清空队列（保留当前播放）。
  void clearUpcoming() {
    final cur = current;
    if (cur == null) return;
    _queue = [cur];
    _index = 0;
    _rebuildOrder();
    _saveQueue();
    notifyListeners();
  }

  void setMode(PlayMode m) {
    if (mode == m) return;
    mode = m;
    _rebuildOrder();
    SharedPreferences.getInstance().then((prefs) => prefs.setString('player.mode', mode.name));
    notifyListeners();
  }

  void cycleMode() => setMode(PlayMode.values[(mode.index + 1) % PlayMode.values.length]);

  // ── 控制 ──────────────────────────────────────────

  Future<void> toggle() => (_opening ? _playRequested : playing) ? pause() : play();

  Future<void> play() async {
    if (_disposed) return;
    if (current == null) return;
    _playRequested = true;
    if (_opening) return;
    if (_player?.state.playlist.medias.isEmpty ?? true) {
      await _load(autoplay: true, keepPosition: true);
      return;
    }
    if (settings.crossfade) {
      final token = _loadToken;
      await _setFade(0);
      if (_disposed || token != _loadToken || !_playRequested) return;
      await _player?.play();
      await _rampFade(1, 380);
    } else {
      // 切歌时会先静音上一首；以暂停状态载入的歌曲按播放时要恢复音量，否则没有声音。
      await _setFade(1);
      await _player?.play();
    }
  }

  Future<void> pause() async {
    if (_disposed) return;
    _playRequested = false;
    if (settings.crossfade && playing) {
      final token = _loadToken;
      await _rampFade(0, 320);
      if (_disposed || token != _loadToken || _playRequested) return;
      await _player?.pause();
      await _setFade(1);
    } else {
      await _player?.pause();
    }
  }

  Future<void> next({bool auto = false}) async {
    if (_queue.isEmpty) return;
    final pos = _order.indexOf(_index);
    if (pos + 1 >= _order.length) {
      if (auto && mode == PlayMode.sequence) {
        // 列表循环。
      }
      _index = _order.first;
    } else {
      _index = _order[pos + 1];
    }
    await _load(autoplay: true);
  }

  Future<void> previous() async {
    if (_queue.isEmpty) return;
    if (position.value > const Duration(seconds: 4)) {
      await seek(Duration.zero);
      return;
    }
    final pos = _order.indexOf(_index);
    _index = pos <= 0 ? _order.last : _order[pos - 1];
    await _load(autoplay: true);
  }

  Future<void> jumpTo(Song song) async {
    final i = _queue.indexOf(song);
    if (i < 0) return;
    await jumpToIndex(i);
  }

  /// 切到队列中第 [i] 首（卡片流、照片墙按位置切歌）。
  Future<void> jumpToIndex(int i) async {
    if (i < 0 || i >= _queue.length || (i == _index && _player?.state.playlist.medias.isNotEmpty == true)) return;
    _index = i;
    await _load(autoplay: true);
  }

  Future<void> seek(Duration d) async {
    if (d < Duration.zero) d = Duration.zero;
    if (duration > Duration.zero && d > duration) d = duration;
    position.value = d;
    await _player?.seek(d);
  }

  Future<void> seekFraction(double f) {
    if (!f.isFinite) return Future.value();
    final total = duration.inMilliseconds;
    return seek(Duration(milliseconds: (total * f.clamp(0, 1)).round()));
  }

  Future<void> setVolume(double v) async {
    settings.setVolume(v.clamp(0, 1));
    await _applyVolume();
    notifyListeners();
  }

  Future<void> _setFade(double f) async {
    _fade = f;
    await _applyVolume();
  }

  Future<void> _rampFade(double to, int ms) async {
    const steps = 12;
    final from = _fade;
    final token = _loadToken;
    for (var i = 1; i <= steps; i++) {
      await Future<void>.delayed(Duration(milliseconds: ms ~/ steps));
      if (_disposed || token != _loadToken) return;
      await _setFade(from + (to - from) * i / steps);
    }
  }

  void _onOpenFailed() {
    final song = current;
    if (song == null) return;
    if (_retryFresh()) return;
    _opening = false;
    buffering = false;
    notifyListeners();
    final lx = song.sourceId == 'lx';
    _notices.add(PlayerNotice('无法打开这首歌', message: lx ? '洛雪音源返回的播放地址已失效，请在“设置 → 洛雪音源”中更换或调整音源顺序' : '播放地址已失效或网络不可用，请稍后重试'));
  }

  /// 正在打开新歌曲（从开始加载到播放器打开媒体）：这期间上一首的“播放结束”事件不能触发切歌。
  bool _opening = false;

  /// 正在获取或打开新歌曲（播放按钮显示加载中）。
  bool get loading => _opening;

  /// 最近一次打开媒体的时间。
  DateTime _openedAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _onCompleted() {
    if (_opening || !_playRequested) return;
    // 刚打开就“播放结束”且几乎没有播放：多半是地址失效或网络错误，提示一次后再切到下一首，而不是连续跳过好几首。
    if (DateTime.now().difference(_openedAt) < const Duration(seconds: 2) && position.value < const Duration(seconds: 1)) {
      if (_retryFresh()) return;
      final token = _loadToken;
      _notices.add(const PlayerNotice('这首歌无法播放', message: '播放地址暂时不可用，已切到下一首。'));
      Future<void>.delayed(const Duration(milliseconds: 800), () {
        if (token == _loadToken && _queue.length > 1) next(auto: true);
      });
      return;
    }
    if (mode == PlayMode.repeatOne) {
      seek(Duration.zero).then((_) => _player?.play());
    } else if (settings.autoNext) {
      next(auto: true);
    } else {
      // 关闭了自动切歌：重新载入这首歌并停在开头，等用户手动播放
      // （对已经播放结束的媒体直接跳转会一直停在缓冲状态）。
      _load(autoplay: false);
    }
  }

  /// 预先取好的下一首播放地址：当前歌曲开始播放 10 秒后（快速连续切歌时不取）向平台取下一首的地址，
  /// 切到下一首时直接交给播放器，省去取地址的等待（洛雪音源要等好几秒）。地址只在 8 分钟内使用，避免过期。
  ({Song song, AudioQuality quality, StreamInfo info, DateTime at})? _prefetched;
  Timer? _prefetchTimer;

  /// 当前歌曲使用的是预先取好的地址（打不开时重新取一次，而不是提示失败）。
  bool _usedPrefetch = false;

  StreamInfo? _takePrefetched(Song song) {
    final p = _prefetched;
    if (p == null || p.song != song) return null;
    _prefetched = null;
    if (p.quality != settings.quality || DateTime.now().difference(p.at) > const Duration(minutes: 8)) return null;
    return p.info;
  }

  void _schedulePrefetch(int token) {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(const Duration(seconds: 10), () => _prefetchNext(token));
  }

  Future<void> _prefetchNext(int token) async {
    if (_disposed || token != _loadToken || _queue.length < 2) return;
    final pos = _order.indexOf(_index);
    if (pos < 0) return;
    final song = _queue[_order[(pos + 1) % _order.length]];
    if (song.localPath != null || localLookup?.call(song)?.localPath != null) return;
    final quality = settings.quality;
    try {
      final info = await resolveStream(sources.byId(song.sourceId), song, quality);
      if (_disposed || token != _loadToken) return;
      _prefetched = (song: song, quality: quality, info: info, at: DateTime.now());
    } catch (e) {
      debugPrint('prefetch ${song.name}: $e');
    }
  }

  /// 预先取好的地址打不开（已过期）：重新向平台取地址再播放一次。
  bool _retryFresh() {
    if (!_usedPrefetch) return false;
    _usedPrefetch = false;
    _load(autoplay: _playRequested);
    return true;
  }

  Future<void> _load({required bool autoplay, bool keepPosition = false}) async {
    if (_disposed) return;
    final song = current;
    if (song == null) return;
    _playRequested = autoplay;
    final token = ++_loadToken;
    _opening = true;
    final resume = keepPosition ? position.value : Duration.zero;
    if (!keepPosition) position.value = Duration.zero;
    duration = song.duration;
    lyrics = Lyrics.empty;
    buffering = true;
    _addHistory(song);
    _restoringQueue = false;
    _saveQueue();
    notifyListeners();

    // 切歌后上一首立即静音：取新歌地址可能要等洛雪音源十几秒，期间不应继续听到上一首（淡入淡出时由下方渐隐处理）。
    StreamInfo info;
    try {
      if (!keepPosition && !settings.crossfade) await _setFade(0);
      final source = sources.byId(song.sourceId);
      _loadLyrics(source, song, token);
      final local = song.localPath ?? localLookup?.call(song)?.localPath;
      final early = local == null ? _takePrefetched(song) : null;
      _usedPrefetch = early != null;
      if (local != null) {
        info = StreamInfo(url: local);
      } else {
        info = early ?? await resolveStream(source, song, settings.quality);
      }
    } catch (e) {
      if (token != _loadToken) return;
      _opening = false;
      buffering = false;
      // 新歌取不到地址时停止上一首，否则界面显示的是新歌，听到的却还是上一首。
      await _player?.stop();
      if (_disposed || token != _loadToken) return;
      notifyListeners();
      _notices.add(
        PlayerNotice(
          e is SourceVerificationRequired ? '需要完成官方验证' : '播放失败',
          message: e.toString().replaceFirst('Exception: ', ''),
          blocking: e is SourceVerificationRequired,
          actionUrl: e is SourceVerificationRequired ? e.url : null,
        ),
      );
      return;
    }
    if (token != _loadToken) return;
    _fillCover(song, info.cover);

    if (_player == null || info.url == null) _opening = false;
    if (_player == null) {
      buffering = false;
      notifyListeners();
      _notices.add(_engineNotice);
      return;
    }
    if (info.url == null) {
      buffering = false;
      await _player?.stop();
      if (_disposed || token != _loadToken) return;
      notifyListeners();
      _notices.add(const PlayerNotice('暂无播放版权', message: '该歌曲暂时无法播放，已为你切到下一首。', blocking: true));
      if (_queue.length > 1) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        if (token == _loadToken) await next(auto: true);
      }
      return;
    }
    if (info.trial) _notices.add(PlayerNotice('当前为试听片段', message: info.note));
    final p = _player!;
    // 每次等待之后都检查是否已经切到别的歌：快速连续切歌时，较早的请求不能在之后打开自己的地址，
    // 否则界面显示的是新歌，实际播放的却是上一首。
    try {
      if (settings.crossfade && playing) await _rampFade(0, 260);
      if (token != _loadToken) return;
      _gain = gainFactor(info.gainDb);
      _peak = info.peak != null && info.peak! > 0 ? info.peak : null;
      _opening = true;
      await p.open(Media(info.url!, httpHeaders: info.headers), play: false);
      _openedAt = DateTime.now();
      if (token != _loadToken) return;
      _opening = false;
      if (p.state.duration > Duration.zero) duration = p.state.duration;
      buffering = p.state.buffering;
      notifyListeners();
      if (resume > Duration.zero) await p.seek(resume);
      if (token != _loadToken) return;
      if (_playRequested) {
        if (settings.crossfade) {
          await _setFade(0);
          if (token != _loadToken || !_playRequested) return;
          await p.play();
          if (token != _loadToken || !_playRequested) return;
          await _rampFade(1, 420);
        } else {
          await _setFade(1);
          if (token != _loadToken || !_playRequested) return;
          await p.play();
        }
        if (token != _loadToken) return;
        if (_eqApplied.isNotEmpty) _watchEq(token, resume);
        _schedulePrefetch(token);
      }
    } catch (error) {
      if (token != _loadToken) return;
      _opening = false;
      buffering = false;
      playing = false;
      notifyListeners();
      _notices.add(PlayerNotice('播放失败', message: error.toString().replaceFirst('Exception: ', '')));
    }
  }

  /// 当前歌曲没有封面：用取地址时平台给出的封面，或者向平台查询一次，查到后替换队列中的这首歌
  /// （播放页、通知栏、桌面小部件都显示新封面）。
  void _fillCover(Song song, String? cover) {
    if (song.coverUrl != null) return;
    CoverResolver.instance.remember(song, cover);
    CoverResolver.instance.resolve(sources, song).then((url) {
      if (_disposed || url == null) return;
      final i = _queue.indexOf(song);
      if (i < 0 || _queue[i].coverUrl != null) return;
      _queue[i] = _queue[i].copyWith(cover: url);
      _saveQueue();
      notifyListeners();
    });
  }

  /// 均衡器滤镜在个别播放引擎中无法创建时，mpv 不报错而是一直停在开头：
  /// 打开均衡器的歌曲 4 秒后仍没有开始播放，就关闭均衡器、记住当前设备不支持，并在原位置重新播放。
  void _watchEq(int token, Duration start) {
    Timer(const Duration(seconds: 4), () async {
      if (token != _loadToken || _eqApplied.isEmpty || !playing || buffering) return;
      if (position.value > start + const Duration(milliseconds: 300)) return;
      await _onEqFailed();
      if (token == _loadToken) await _load(autoplay: true, keepPosition: true);
    });
  }

  Future<void> _loadLyrics(MusicSource source, Song song, int token) async {
    try {
      final l = await source.lyrics(song);
      if (token != _loadToken) return;
      lyrics = l;
      notifyListeners();
    } catch (_) {}
  }

  /// 没有账号“喜欢”功能的平台（QQ 音乐、酷狗等）：喜欢的歌曲保存在本机。
  final Map<String, Song> _localLikes = {};

  /// 某个平台保存在本机的“我喜欢的音乐”（最近喜欢的在前）。
  List<Song> localLikedSongs(String sourceId) => [
    for (final s in _localLikes.values.toList().reversed)
      if (s.sourceId == sourceId) s,
  ];

  void _saveLocalLikes() {
    SharedPreferences.getInstance().then((p) => p.setString('player.localLikes', jsonEncode([for (final s in _localLikes.values) s.toJson()])));
  }

  Future<void> toggleLike(Song song) async {
    final liked = isLiked(song);
    final src = sources.byId(song.sourceId);
    if (!src.supports(SourceFeature.likeSong)) {
      if (liked) {
        _localLikes.remove(song.key);
        _liked.remove(song.key);
      } else {
        _localLikes[song.key] = song;
        _liked.add(song.key);
      }
      _saveLocalLikes();
      notifyListeners();
      _notices.add(PlayerNotice(liked ? '已取消喜欢' : '已添加到「我喜欢的音乐」'));
      return;
    }
    try {
      await src.likeSong(song, !liked);
      liked ? _liked.remove(song.key) : _liked.add(song.key);
      notifyListeners();
      _notices.add(PlayerNotice(liked ? '已取消喜欢' : '已添加到「我喜欢的音乐」'));
    } catch (e) {
      _notices.add(PlayerNotice(e.toString()));
    }
  }

  // ── 睡眠定时 ──────────────────────────────────────

  void setSleepTimer(Duration? d) {
    _sleepTimer?.cancel();
    sleepAt = d == null ? null : DateTime.now().add(d);
    if (d != null) {
      _sleepTimer = Timer(d, () {
        pause();
        sleepAt = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  // ── 持久化 ────────────────────────────────────────

  void _addHistory(Song s) {
    history.remove(s);
    history.insert(0, s);
    if (history.length > 200) history.removeLast();
    SharedPreferences.getInstance().then((p) => p.setString('player.history', jsonEncode([for (final h in history.take(200)) h.toJson()])));
  }

  /// 当前平台模式：网易云、QQ 音乐、酷狗与洛雪曲库各自有独立的播放队列，互不干扰。
  String _platform = '';
  bool _restoringQueue = false;

  String _qKey(String platform) => 'player.queue.$platform';

  void _saveQueue() {
    if (_restoringQueue) return;
    final platform = _platform;
    final queue = [for (final s in _queue) s.toJson()];
    final index = _index;
    final title = queueTitle ?? '';
    SharedPreferences.getInstance().then((p) {
      p.setString(_qKey(platform), jsonEncode(queue));
      p.setInt('${_qKey(platform)}.index', index);
      p.setString('${_qKey(platform)}.title', title);
    });
  }

  /// 切换平台模式：停止当前播放，保存这个平台的队列，换成新平台上次的队列（不自动播放）。
  Future<void> _onPlatformChanged() async {
    final next = sources.current.id;
    if (next == _platform) return;
    _saveQueue();
    _restoringQueue = true;
    final token = ++_loadToken;
    _opening = false;
    _playRequested = false;
    _platform = next;
    _queue = [];
    _index = -1;
    _order = [];
    queueTitle = null;
    duration = Duration.zero;
    buffering = false;
    playing = false;
    position.value = Duration.zero;
    lyrics = Lyrics.empty;
    notifyListeners();
    await _player?.stop();
    if (token != _loadToken) return;
    final p = await SharedPreferences.getInstance();
    if (token != _loadToken) return;
    _restoringQueue = false;
    _loadQueue(p);
    position.value = Duration.zero;
    lyrics = Lyrics.empty;
    notifyListeners();
    if (current != null) _loadLyrics(sources.byId(current!.sourceId), current!, _loadToken);
  }

  void _loadQueue(SharedPreferences p) {
    _queue = [];
    _index = -1;
    queueTitle = null;
    try {
      final q = p.getString(_qKey(_platform));
      _queue = [for (final j in jsonDecode(q ?? '[]') as List) Song.fromJson(Map<String, dynamic>.from(j as Map))];
      _index = (p.getInt('${_qKey(_platform)}.index') ?? 0).clamp(-1, _queue.length - 1);
      queueTitle = p.getString('${_qKey(_platform)}.title');
      if (queueTitle?.isEmpty ?? false) queueTitle = null;
    } catch (_) {
      _queue = [];
      _index = -1;
    }
    _rebuildOrder();
    duration = current?.duration ?? Duration.zero;
  }

  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    mode = PlayMode.values.asNameMap()[p.getString('player.mode')] ?? PlayMode.sequence;
    try {
      for (final j in jsonDecode(p.getString('player.localLikes') ?? '[]') as List) {
        final song = Song.fromJson(Map<String, dynamic>.from(j as Map));
        _localLikes[song.key] = song;
        _liked.add(song.key);
      }
    } catch (_) {}
    // 两次启动中都失败才认为不支持（偶尔一次失败，例如切换音频设备时，不应永久关闭均衡器）。
    // 旧版本一次失败就永久记下的标记不再沿用。
    eqUnsupported = (p.getInt('eqFailures.v2') ?? 0) >= 2;
    limiterUnsupported = (p.getInt('limiterFailures.v2') ?? 0) >= 2;
    try {
      final h = p.getString('player.history');
      if (h != null) {
        history.addAll([for (final j in jsonDecode(h) as List) Song.fromJson(Map<String, dynamic>.from(j as Map))]);
      }
      // 旧版本只有一个共用的队列：迁移给它当前歌曲所属的平台。
      final legacy = p.getString('player.queue');
      if (legacy != null) {
        final songs = [for (final j in jsonDecode(legacy) as List) Song.fromJson(Map<String, dynamic>.from(j as Map))];
        final i = (p.getInt('player.index') ?? 0).clamp(-1, songs.length - 1);
        final owner = i >= 0 && const {'netease', 'qq', 'kugou'}.contains(songs[i].sourceId) ? songs[i].sourceId : _platform;
        if (p.getString(_qKey(owner)) == null) {
          await p.setString(_qKey(owner), legacy);
          await p.setInt('${_qKey(owner)}.index', i);
          await p.setString('${_qKey(owner)}.title', p.getString('player.title') ?? '');
        }
        await p.remove('player.queue');
        await p.remove('player.index');
        await p.remove('player.title');
      }
      _loadQueue(p);
      if (current != null) _loadLyrics(sources.byId(current!.sourceId), current!, _loadToken);
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _loadToken++;
    _prefetchTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    settings.removeListener(_applyVolume);
    settings.removeListener(_applyOutput);
    settings.removeListener(_scheduleEq);
    settings.removeListener(_scheduleFx);
    _fxTimer?.cancel();
    sources.removeListener(_refreshLikes);
    sources.removeListener(_onPlatformChanged);
    _sleepTimer?.cancel();
    _eqTimer?.cancel();
    position.dispose();
    _player?.dispose();
    _notices.close();
    super.dispose();
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}
