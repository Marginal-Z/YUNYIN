import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/music_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/player/player_controller.dart';

/// 在 CI 上无声卡的桌面环境可传 --dart-define=AO=null，只验证解码与音频滤镜链。
const _ao = String.fromEnvironment('AO');

/// 返回本地测试音频的播放源，并带上与网易云相同形式的响度增益。
class _ToneSource extends MusicSource {
  _ToneSource(this.path);

  final String path;

  @override
  String get id => 'tone';

  @override
  String get name => '测试音源';

  @override
  String get description => '';

  @override
  Set<SourceFeature> get features => const {};

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async => StreamInfo(url: path, gainDb: -11.2);
}

/// 生成 6 秒正弦波 WAV（44.1kHz / 16bit / 单声道，默认 440Hz）。
Future<String> _writeTone({int freq = 440}) async {
  const rate = 44100, seconds = 6;
  final samples = rate * seconds;
  final data = ByteData(44 + samples * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, rate, Endian.little);
  data.setUint32(28, rate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(44 + i * 2, (math.sin(2 * math.pi * freq * i / rate) * 12000).round(), Endian.little);
  }
  Directory dir;
  try {
    dir = await getTemporaryDirectory();
  } catch (_) {
    dir = Directory.systemTemp; // 在主机上以普通测试方式运行时没有 path_provider 插件。
  }
  await dir.create(recursive: true);
  final f = File('${dir.path}/yunyin_tone_$freq.wav');
  await f.writeAsBytes(data.buffer.asUint8List());
  return f.path;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('应用播放器能真正输出音频（默认开启音量均衡与淡入淡出）', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final path = await _writeTone();
    final settings = AppSettings();
    await settings.init();
    expect(settings.normalize, isTrue);
    expect(settings.crossfade, isTrue);

    final sources = SourceManager([_ToneSource(path)]);
    await sources.init();
    final player = PlayerController(sources, settings);
    await player.init();
    expect(player.engineError, isNull, reason: '播放引擎初始化失败');

    final native = player.engine!.platform as NativePlayer;
    if (_ao.isNotEmpty) await native.setProperty('ao', _ao);

    await player.playSongs([const Song(id: '1', sourceId: 'tone', name: '测试音', duration: Duration(seconds: 6))]);
    final sw = Stopwatch()..start();
    while (player.position.value < const Duration(milliseconds: 1500) && sw.elapsed < const Duration(seconds: 25)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final ao = await native.getProperty('current-ao');
    final rate = await native.getProperty('audio-params/samplerate');
    final volume = double.tryParse(await native.getProperty('volume')) ?? 0;
    final af = await native.getProperty('af');
    // ignore: avoid_print
    print('position=${player.position.value} current-ao=$ao samplerate=$rate volume=$volume af=$af');

    expect(player.position.value, greaterThanOrEqualTo(const Duration(milliseconds: 1500)), reason: '播放进度没有推进');
    expect(ao, isNotEmpty, reason: '没有可用的音频输出（音频链初始化失败）');
    expect(int.tryParse(rate) ?? 0, greaterThan(0), reason: '没有解码出音频');
    expect(volume, greaterThan(0), reason: '音量为 0');
    expect(af.contains('loudnorm'), isFalse, reason: '精简版 libmpv 不支持 loudnorm，不能使用');
    if (Platform.isAndroid) {
      // 平板兼容：16 位立体声输出（见 PlayerController._configureAndroidAudio）。
      expect(await native.getProperty('audiotrack-pcm-float'), 'no');
      expect(await native.getProperty('audio-channels'), 'stereo');
    }
    player.dispose();
  });

  testWidgets('均衡器滤镜在各平台的播放引擎中可用，打开后仍正常输出音频', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final path = await _writeTone();
    final settings = AppSettings();
    await settings.init();
    settings.setFlag('eqEnabled', true);
    settings.setEqPreset(EqPreset.rock);

    final sources = SourceManager([_ToneSource(path)]);
    await sources.init();
    final player = PlayerController(sources, settings);
    await player.init();
    final native = player.engine!.platform as NativePlayer;
    if (_ao.isNotEmpty) await native.setProperty('ao', _ao);

    await player.playSongs([const Song(id: '2', sourceId: 'tone', name: '测试音', duration: Duration(seconds: 6))]);
    final sw = Stopwatch()..start();
    while (player.position.value < const Duration(milliseconds: 2000) && sw.elapsed < const Duration(seconds: 25)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final af = await native.getProperty('af');
    final rate = await native.getProperty('audio-params/samplerate');
    // ignore: avoid_print
    print('eq position=${player.position.value} samplerate=$rate af=$af unsupported=${player.eqUnsupported}');
    // 各平台的播放引擎都带有 equalizer 滤镜（CI 探测结果）；即使个别设备不支持，也会自动关闭均衡器继续播放。
    expect(player.eqUnsupported, isFalse, reason: '均衡器滤镜创建失败');
    expect(af, contains('equalizer'));
    expect(player.position.value, greaterThanOrEqualTo(const Duration(milliseconds: 2000)), reason: '打开均衡器后播放进度没有推进');
    expect(int.tryParse(rate) ?? 0, greaterThan(0), reason: '打开均衡器后没有解码出音频');

    // 关闭后滤镜被移除。
    settings.setFlag('eqEnabled', false);
    await tester.pump(const Duration(milliseconds: 600));
    expect(await native.getProperty('af'), isNot(contains('equalizer')));
    player.dispose();
  });

  testWidgets('音量增强经过限幅器：打开 +6 dB 后仍正常输出音频，不靠提升播放器音量', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final path = await _writeTone();
    final settings = AppSettings();
    await settings.init();
    expect(settings.hifiEngine, isTrue);
    settings.setVolumeBoost(6);

    final sources = SourceManager([_ToneSource(path)]);
    await sources.init();
    final player = PlayerController(sources, settings);
    await player.init();
    final native = player.engine!.platform as NativePlayer;
    if (_ao.isNotEmpty) await native.setProperty('ao', _ao);

    await player.playSongs([const Song(id: '3', sourceId: 'tone', name: '测试音', duration: Duration(seconds: 6))]);
    final sw = Stopwatch()..start();
    while (player.position.value < const Duration(milliseconds: 2500) && sw.elapsed < const Duration(seconds: 30)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final af = await native.getProperty('af');
    final volume = double.tryParse(await native.getProperty('volume')) ?? 0;
    final rate = await native.getProperty('audio-params/samplerate');
    final filterSize = await native.getProperty('audio-resample-filter-size');
    final session = Platform.isAndroid ? await native.getProperty('audiotrack-session-id') : '';
    // ignore: avoid_print
    print('boost position=${player.position.value} samplerate=$rate volume=$volume af=$af limiterUnsupported=${player.limiterUnsupported} session=$session filterSize=$filterSize smartBoost=${player.smartBoost}');

    expect(player.position.value, greaterThanOrEqualTo(const Duration(milliseconds: 2500)), reason: '打开音量增强后播放进度没有推进');
    expect(int.tryParse(rate) ?? 0, greaterThan(0), reason: '打开音量增强后没有解码出音频');
    expect(filterSize, '32', reason: '高保真引擎使用 32 抽头重采样滤镜');
    if (Platform.isAndroid) {
      // 增强交给系统音效链（DynamicsProcessing / LoudnessEnhancer），播放器挂在单独申请的音频会话上。
      expect(int.tryParse(session) ?? 0, greaterThan(0), reason: '没有使用独立的音频会话');
      expect(af, isNot(contains('alimiter')));
    } else if (player.limiterUnsupported) {
      // 精简版引擎没有限幅滤镜：自动去掉限幅器继续播放，改为按峰值智能提升（测试音源没有峰值信息，不提升）。
      expect(af, isNot(contains('alimiter')));
      expect(player.smartBoost, isTrue);
      expect(volume, lessThanOrEqualTo(100), reason: '没有峰值信息时不提升播放器音量');
    } else {
      expect(af, contains('alimiter'));
      expect(af, contains('volume=6dB'));
      expect(player.smartBoost, isFalse);
      // 增益在滤镜中完成，播放器音量不再额外提升（音量均衡与峰值余量只会让它低于 100）。
      expect(volume, lessThanOrEqualTo(100));
    }
    player.dispose();
  });
  testWidgets('音效真正改变输出：低频增强把 62Hz 测试音提升，空间音效提升 8kHz（录下播放器输出比较电平）', (tester) async {
    /// 用 ao=pcm 把播放器的实际输出写入 WAV，返回跳过开头淡入后的均方根电平（dBFS）。
    Future<double> render(int freq, {double bass = 0, double spatial = 0}) async {
      SharedPreferences.setMockInitialValues({});
      final path = await _writeTone(freq: freq);
      final settings = AppSettings();
      await settings.init();
      settings.setBassEnhance(bass);
      settings.setSpatial(spatial);
      // ao=pcm 不按实时速度输出：淡入（420 ms）期间整首测试音就已经写完，录到的全是静音。
      settings.setFlag('crossfade', false);
      final sources = SourceManager([_ToneSource(path)]);
      await sources.init();
      final player = PlayerController(sources, settings);
      await player.init();
      final native = player.engine!.platform as NativePlayer;
      final out = '${File(path).parent.path}/yunyin_out_${freq}_${bass}_$spatial.wav';
      if (File(out).existsSync()) File(out).deleteSync();
      await native.setProperty('ao-pcm-file', out);
      await native.setProperty('ao-pcm-waveheader', 'yes');
      await native.setProperty('ao', 'pcm');
      await player.playSongs([Song(id: 'fx$freq$bass$spatial', sourceId: 'tone', name: '测试音', duration: const Duration(seconds: 6))]);
      final sw = Stopwatch()..start();
      while (player.position.value < const Duration(milliseconds: 4500) && sw.elapsed < const Duration(seconds: 30)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      final af = await native.getProperty('af');
      player.dispose();
      await tester.pump(const Duration(milliseconds: 800));
      final level = _rmsDb(File(out).readAsBytesSync(), skipSeconds: 1.5);
      // ignore: avoid_print
      print('fx freq=$freq bass=$bass spatial=$spatial level=${level.toStringAsFixed(2)} dB af=$af');
      return level;
    }

    final bassOff = await render(62);
    final bassOn = await render(62, bass: 1);
    expect(bassOn - bassOff, greaterThan(2.0), reason: '低频增强没有提升低频电平');
    final airOff = await render(8000);
    final airOn = await render(8000, spatial: 1);
    expect(airOn - airOff, greaterThan(1.0), reason: '空间音效的声场曲线没有生效');
  });
}

/// 解析 WAV（16 / 32 位整数或 32 位浮点），返回跳过开头 [skipSeconds] 秒后的均方根电平（dBFS）。
double _rmsDb(Uint8List bytes, {double skipSeconds = 0}) {
  final d = ByteData.sublistView(bytes);
  var pos = 12, format = 1, channels = 2, rate = 44100, bits = 16, dataStart = -1;
  while (pos + 8 <= bytes.length) {
    final id = String.fromCharCodes(bytes.sublist(pos, pos + 4));
    final size = d.getUint32(pos + 4, Endian.little);
    if (id == 'fmt ') {
      format = d.getUint16(pos + 8, Endian.little);
      channels = d.getUint16(pos + 10, Endian.little);
      rate = d.getUint32(pos + 12, Endian.little);
      bits = d.getUint16(pos + 22, Endian.little);
      if (format == 0xFFFE) format = d.getUint16(pos + 32, Endian.little);
    } else if (id == 'data') {
      dataStart = pos + 8;
      break;
    }
    pos += 8 + size + (size & 1);
  }
  expect(dataStart, greaterThan(0), reason: '没有录到播放器输出');
  final width = bits ~/ 8;
  final frame = width * channels;
  final start = dataStart + (skipSeconds * rate).round() * frame;
  var sum = 0.0;
  var n = 0;
  for (var o = start; o + width <= bytes.length; o += width) {
    final double v = switch ((format, bits)) {
      (3, 32) => d.getFloat32(o, Endian.little),
      (_, 16) => d.getInt16(o, Endian.little) / 32768,
      (_, 32) => d.getInt32(o, Endian.little) / 2147483648,
      _ => 0,
    };
    sum += v * v;
    n++;
  }
  expect(n, greaterThan(rate), reason: '录到的音频太短');
  return 10 * math.log(sum / n + 1e-12) / math.ln10;
}
