import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/lx/lx_runtime.dart';

/// 按洛雪自定义音源格式写的测试脚本：声明平台、发请求、用工具函数加密并返回地址。
String _script(int port) =>
    '''
/*!
 * @name 测试音源
 * @version 1.0.0
 */
const { EVENT_NAMES, request, on, send, utils } = globalThis.lx
const httpGet = (url, opts) => new Promise((resolve, reject) => {
  request(url, opts, (err, resp) => err ? reject(err) : resolve(resp))
})
on(EVENT_NAMES.request, async ({ source, action, info }) => {
  if (action !== 'musicUrl') throw new Error('不支持')
  const md5 = utils.crypto.md5(info.musicInfo.songmid)
  const enc = utils.crypto.aesEncrypt(utils.buffer.from('hello'), 'aes-128-ecb', utils.buffer.from('0123456789abcdef'), '').toString('base64')
  const zipped = await utils.zlib.deflate(utils.buffer.from('压缩测试'))
  const unzipped = (await utils.zlib.inflate(zipped)).toString()
  const resp = await httpGet('http://127.0.0.1:$port/url?id=' + info.musicInfo.songmid + '&q=' + info.type, {
    method: 'POST', headers: { 'X-Md5': md5 }, body: { enc, unzipped, hex: utils.buffer.from('ab').toString('hex') }
  })
  if (resp.statusCode !== 200) throw new Error('状态码 ' + resp.statusCode)
  return resp.body.url
})
send(EVENT_NAMES.inited, { status: true, sources: { wy: { name: '网易云', type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k', 'flac'] } } })
''';

/// QuickJS 动态库的位置（CI 与本地运行测试时通过环境变量提供）。
final _skip = (Platform.environment['LIBQUICKJSC_TEST_PATH'] ?? '').isEmpty ? '需要 LIBQUICKJSC_TEST_PATH 指向 libquickjs_c_bridge_plugin.so' : null;

void main() {
  test('洛雪音源运行环境：初始化、请求、工具函数与返回播放地址', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    Map<String, dynamic>? got;
    String? md5Header;
    server.listen((req) async {
      md5Header = req.headers.value('x-md5');
      got = jsonDecode(await utf8.decoder.bind(req).join()) as Map<String, dynamic>;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'url': 'https://cdn.example.com/${req.uri.queryParameters['id']}_${req.uri.queryParameters['q']}.flac'}));
      await req.response.close();
    });
    final rt = await LxRuntime.start(_script(server.port));
    expect(rt.sources['wy'], ['128k', '320k', 'flac']);
    final url = await rt.musicUrl('wy', 'flac', {'songmid': '186016', 'name': '晴天'});
    expect(url, 'https://cdn.example.com/186016_flac.flac');
    expect(md5Header, md5.convert(utf8.encode('186016')).toString());
    expect(got!['unzipped'], '压缩测试');
    expect(got!['hex'], '6162');
    expect(got!['enc'], 'Z0x+8454yr2c7JwSWCOmOQ==', reason: 'AES-128-ECB + PKCS7（与 Python cryptography 的结果一致）');
    await expectLater(rt.musicUrl('wy', 'flac', {'songmid': 'x'}, timeout: const Duration(seconds: 5)), completion(contains('x_flac')));
    rt.dispose();
    await server.close(force: true);
  }, skip: _skip);

  test('脚本出错或没有初始化时给出原因', () async {
    await expectLater(LxRuntime.start('throw new Error("坏脚本")'), throwsA(predicate((e) => '$e'.contains('坏脚本'))));
    await expectLater(LxRuntime.start('1 + 1', timeout: const Duration(seconds: 1)), throwsA(predicate((e) => '$e'.contains('inited'))));
  }, skip: _skip);
}
