@Tags(['live'])
// ignore_for_file: avoid_print
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';

void main() {
  test('probe', () async {
    SharedPreferences.setMockInitialValues({});
    final s = NeteaseSource();
    await s.init();
    await s.ensureAnonymous();
    final cases = <(String, Map<String, dynamic>)>[
      ('/v6/playlist/detail', {'id': '19723756', 'n': 1000, 's': 8}),
      ('/personalized/playlist', {'limit': 3, 'total': true, 'n': 1000}),
      ('/v3/song/detail', {'c': '[{"id":"2116407047"}]'}),
      ('/login/qrcode/unikey', {'type': 3}),
      ('/toplist', {}),
      ('/v1/artist/12138269', {}),
      ('/song/enhance/player/url/v1', {'ids': '[2116407047]', 'level': 'standard', 'encodeType': 'flac'}),
    ];
    for (final c in cases) {
      for (final kind in ['weapi', 'eapi']) {
        try {
          final j = kind == 'weapi' ? await s.debugWeapi(c.$1, c.$2) : await s.debugEapi(c.$1, c.$2);
          print('$kind ${c.$1}: OK code=${j['code']} keys=${j.keys.take(5).toList()}');
        } catch (e) {
          print('$kind ${c.$1}: FAIL $e');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
