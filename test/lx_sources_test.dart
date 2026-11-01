import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/lx/lx_sources.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/source_policy.dart';

/// 按真实洛雪音源的写法：读取 lx.version / env / currentScriptInfo，用 setTimeout 做请求超时，
/// 以表单提交、返回 JSON（自动解析），推送更新提示，并为三个平台声明不同的音质。
String _working(int port) =>
    '''
/*!
 * @name 本地测试音源
 * @description 端到端测试
 * @version 2.1.0
 * @author yunyin
 */
const { EVENT_NAMES, request, on, send, version, env, currentScriptInfo } = globalThis.lx
const httpFetch = (url, options) => new Promise((resolve, reject) => {
  let done = false
  const timer = setTimeout(() => { if (!done) { done = true; reject(new Error('请求超时')) } }, 8000)
  request(url, options, (err, resp) => {
    if (done) return
    done = true
    clearTimeout(timer)
    err ? reject(err) : resolve(resp)
  })
})
const sources = {
  wy: { name: '网易云', type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k', 'flac'] },
  tx: { name: 'QQ 音乐', type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k'] },
  kg: { name: '酷狗', type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k', 'flac', 'flac24bit'] },
}
on(EVENT_NAMES.request, async ({ source, action, info }) => {
  if (action !== 'musicUrl') throw new Error('action not support')
  const id = info.musicInfo.hash || info.musicInfo.songmid
  const resp = await httpFetch('http://127.0.0.1:$port/api', {
    method: 'POST',
    timeout: 8000,
    form: { source, id, quality: info.type, v: version, env, script: currentScriptInfo.name },
  })
  if (resp.body.code !== 0) throw new Error(resp.body.msg || 'failed')
  return resp.body.url
})
send(EVENT_NAMES.inited, { status: true, openDevTools: false, sources })
send(EVENT_NAMES.updateAlert, { log: '有新版本', updateUrl: 'http://127.0.0.1:$port/script.js' })
''';

/// 排在前面但已经失效的音源：每次请求都报错。
const _broken = '''
/*!
 * @name 失效音源
 * @version 1.0.0
 */
const { EVENT_NAMES, on, send } = globalThis.lx
on(EVENT_NAMES.request, () => Promise.reject(new Error('接口已失效')))
send(EVENT_NAMES.inited, { status: true, sources: { kg: { name: '酷狗', type: 'music', actions: ['musicUrl'], qualitys: ['128k'] } } })
''';

final _skip = (Platform.environment['LIBQUICKJSC_TEST_PATH'] ?? '').isEmpty ? '需要 LIBQUICKJSC_TEST_PATH 指向 libquickjs_c_bridge_plugin.so' : null;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 测试绑定默认把 HTTP 请求全部替换成 400；这里要访问本机的测试服务，恢复真实的 HttpClient。
  setUp(() => HttpOverrides.global = null);

  test('洛雪音源：从链接导入、失效音源自动跳过、为未登录的酷狗歌曲取得可播放的地址', () async {
    final tmp = await Directory.systemTemp.createTemp('yunyin-lx');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );
    SharedPreferences.setMockInitialValues({});

    // 本地服务：提供音源脚本、取地址接口与音频文件。
    final audio = List<int>.generate(4096, (i) => i & 0xff);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    final forms = <Map<String, String>>[];
    server.listen((req) async {
      final res = req.response;
      switch (req.uri.path) {
        case '/script.js':
          res.write(_working(port));
        case '/api':
          final form = Uri.splitQueryString(await const SystemEncoding().decoder.bind(req).join());
          forms.add(form);
          res.headers.contentType = ContentType.json;
          res.write('{"code":0,"url":"http://127.0.0.1:$port/audio/${form['id']}_${form['quality']}.mp3"}');
        case final p when p.startsWith('/audio/'):
          res.headers.contentType = ContentType('audio', 'mpeg');
          res.add(audio);
        default:
          res.statusCode = 404;
      }
      await res.close();
    });

    final lx = LxSources();
    await lx.init();
    final broken = await lx.importText(_broken);
    final working = await lx.importUrl('http://127.0.0.1:$port/script.js');
    expect(working.name, '本地测试音源');
    expect(working.version, '2.1.0');
    expect(lx.enabled.map((s) => s.id), [broken.id, working.id]);

    // 酷狗未登录时自己的接口取不到地址：由洛雪音源兜底，失效的音源被跳过。
    SourcePolicy.custom = lx.resolve;
    final song = Song(
      id: 'a1b2c3d4e5f60718293a4b5c6d7e8f90:123456:7890',
      sourceId: KugouSource.sourceId,
      name: '晴天',
      artists: const [ArtistRef('kugou:周杰伦', '周杰伦')],
      duration: const Duration(minutes: 4, seconds: 29),
    );
    final info = await resolveStream(_RefusingKugou(), song, AudioQuality.lossless);
    expect(info.url, 'http://127.0.0.1:$port/audio/a1b2c3d4e5f60718293a4b5c6d7e8f90_flac.mp3');
    expect(info.quality, AudioQuality.lossless);
    expect(forms.last, containsPair('source', 'kg'));
    expect(forms.last, containsPair('v', '2.0.0'));
    expect(forms.last, containsPair('script', '本地测试音源'));

    // 返回的地址真的能下载到音频。
    final client = HttpClient();
    final res = await (await client.getUrl(Uri.parse(info.url!))).close();
    expect(res.statusCode, 200);
    expect(res.headers.contentType?.mimeType, 'audio/mpeg');
    expect((await res.fold<List<int>>([], (a, b) => a..addAll(b))).length, audio.length);
    client.close();

    // QQ 音乐只声明到 320k：要求无损时降到它支持的最高音质。
    final qq = Song(id: '0039MnYb0qxYhV:M500:97773', sourceId: 'qq', name: '晴天', artists: const [ArtistRef('qq:周杰伦', '周杰伦')], duration: const Duration(minutes: 4));
    final q = await lx.resolve(qq, AudioQuality.lossless);
    expect(q!.quality, AudioQuality.exhigh);
    expect(forms.last, containsPair('quality', '320k'));

    // 停用后不再参与兜底；全部停用时返回 null（交给平台自己的结果）。
    await lx.setEnabled(working.id, false);
    await expectLater(lx.resolve(song, AudioQuality.standard), throwsA(predicate((e) => '$e'.contains('接口已失效'))));
    await lx.setEnabled(broken.id, false);
    expect(await lx.resolve(song, AudioQuality.standard), isNull);

    SourcePolicy.custom = null;
    await server.close(force: true);
    await tmp.delete(recursive: true);
  }, skip: _skip, timeout: const Timeout(Duration(minutes: 1)));
}

/// 未登录的酷狗：自己的接口不给播放地址。
class _RefusingKugou extends KugouSource {
  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async => throw Exception('需要验证或会员');
}
