import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/diagnostics.dart';

void main() {
  test('导出的日志去掉 Cookie、密钥等登录凭据', () {
    const raw = 'GET https://music.163.com/api?id=1&MUSIC_U=abc123&csrf_token=xyz\n'
        'Cookie: KuGoo=KugooID=123&t=deadbeef; kg_dfid=AAA\n'
        'Authorization: Bearer eyJhbGciOi.payload.sig\n'
        'llm key sk-proj-ABCDEFGHijkl1234\n'
        'password="hunter2" 歌名=晴天';
    final out = Diagnostics.redact(raw);
    for (final secret in ['abc123', 'xyz', 'deadbeef', 'eyJhbGciOi', 'ABCDEFGHijkl1234', 'hunter2']) {
      expect(out, isNot(contains(secret)), reason: secret);
    }
    expect(out, contains('id=1'));
    expect(out, contains('歌名=晴天'));
  });

  test('最近日志只保留最后 400 行，记录级别', () {
    final d = Diagnostics.instance;
    for (var i = 0; i < 450; i++) {
      d.log('第 $i 行');
    }
    d.error(StateError('坏了'), null);
    expect(d.recent.length, 400);
    expect(d.recent.last, contains(' E '));
    expect(d.recent.last, contains('坏了'));
    expect(d.errors, 1);
  });
}
