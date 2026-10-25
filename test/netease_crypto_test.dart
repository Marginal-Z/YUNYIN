import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/data/sources/netease/netease_crypto.dart';

// 期望值由 openssl 与 Python 独立计算（见提交说明），用于校验加密实现。
void main() {
  test('eapi 与参考实现一致', () {
    final r = NeteaseCrypto.eapi('/api/song/enhance/player/url/v1', {'ids': '[1]', 'level': 'standard'});
    expect(
      r['params'],
      'FA90B329E9614F79E79598F37DC2EDB487F00D1BC4C9B24CD57E6C318B9073569338432CD7D98D1A3626E997A2C53121'
      'F2652556B9CAA141000D39A0C1D1AE12317F2B9E9ED1864F44D1D6A14668C078B8932DE8811372CC0A101C6E1850331A'
      '25659182F2FF2A0A1F2071E68CFF3C7CD5625E2FACE01B3EB523FBCBEF2F7274',
    );
  });

  test('weapi 第一层 AES-CBC', () {
    expect(NeteaseCrypto.presetLayer(jsonEncode({'a': 1})), 'U7nqija8yGUt9t6SPGXNjQ==');
  });

  test('weapi RSA（无填充，密钥反序）', () {
    expect(
      NeteaseCrypto.rsa('ponmlkjihgfedcba'),
      'd15a1683c992095d0c234c19966605c5c5964911268bbeda8cb8d08d834913e59d53b32358903a121b5fca784c1f5ae4'
      '4951fd02524df58ecc98e52cc7cf8689b42c2e93ddf05b0592512d87f5960467e2f086c018849d76014d323500e30f13'
      'ef4cafbb0cf5a66731a3f1776c75ca35d0062dac70a3e33245afabcf47938487',
    );
  });

  test('weapi 生成 params 与 256 位 encSecKey', () {
    final r = NeteaseCrypto.weapi({'id': 1});
    expect(r['encSecKey'], hasLength(256));
    expect(base64.decode(r['params']!).length % 16, 0);
  });
}
