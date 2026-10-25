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

/// 生成 6 秒 440Hz 正弦波 WAV（44.1kHz / 16bit / 单声道）。
Future<String> _writeTone() async {
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
    data.setInt16(44 + i * 2, (math.sin(2 * math.pi * 440 * i / rate) * 12000).round(), Endian.little);
  }
  Directory dir;
  try {
    dir = await getTemporaryDirectory();
  } catch (_) {
    dir = Directory.systemTemp; // 在主机上以普通测试方式运行时没有 path_provider 插件。
  }
  await dir.create(recursive: true);
  final f = File('${dir.path}/yunyin_tone.wav');
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

    expect(player.position.value, greaterThan(const Duration(milliseconds: 1500)), reason: '播放进度没有推进');
    expect(ao, isNotEmpty, reason: '没有可用的音频输出（音频链初始化失败）');
    expect(int.tryParse(rate) ?? 0, greaterThan(0), reason: '没有解码出音频');
    expect(volume, greaterThan(0), reason: '音量为 0');
    expect(af.contains('loudnorm'), isFalse, reason: '精简版 libmpv 不支持 loudnorm，不能使用');
    player.dispose();
  });
}
