import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hash;
import 'package:meta/meta.dart';
import 'package:pointycastle/export.dart';

/// 网易云音乐 Web / 客户端接口的加密方式（weapi、eapi）。
abstract final class NeteaseCrypto {
  static const _presetKey = '0CoJUm6Qyw8W8jud';
  static const _iv = '0102030405060708';
  static const _eapiKey = 'e82ckenh8dichen8';
  static const _base62 = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  static final _modulus = BigInt.parse(
    'e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135'
    'fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef5'
    '2741d546b8e289dc6935b3ece0462db0a22b8e7',
    radix: 16,
  );
  static final _exponent = BigInt.from(0x010001);
  static final _rand = Random.secure();

  static Uint8List _aes(Uint8List data, Uint8List key, {Uint8List? iv}) {
    final BlockCipher cipher = iv == null ? ECBBlockCipher(AESEngine()) : CBCBlockCipher(AESEngine());
    final params = iv == null ? KeyParameter(key) : ParametersWithIV<KeyParameter>(KeyParameter(key), iv);
    final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher)
      ..init(true, PaddedBlockCipherParameters<CipherParameters, CipherParameters?>(params, null));
    return padded.process(data);
  }

  static Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

  /// weapi：两次 AES-CBC + RSA（无填充）加密随机密钥。
  static Map<String, String> weapi(Map<String, dynamic> data) {
    final text = jsonEncode(data);
    final secret = String.fromCharCodes(List.generate(16, (_) => _base62.codeUnitAt(_rand.nextInt(62))));
    final first = base64.encode(_aes(_utf8(text), _utf8(_presetKey), iv: _utf8(_iv)));
    final params = base64.encode(_aes(_utf8(first), _utf8(secret), iv: _utf8(_iv)));
    return {'params': params, 'encSecKey': _rsa(secret.split('').reversed.join())};
  }

  /// weapi 第一层：AES-128-CBC(presetKey) 后 Base64。
  @visibleForTesting
  static String presetLayer(String text) => base64.encode(_aes(_utf8(text), _utf8(_presetKey), iv: _utf8(_iv)));

  @visibleForTesting
  static String rsa(String text) => _rsa(text);

  static String _rsa(String text) {
    final hex = text.codeUnits.map((c) => c.toRadixString(16).padLeft(2, '0')).join();
    final m = BigInt.parse(hex, radix: 16);
    return m.modPow(_exponent, _modulus).toRadixString(16).padLeft(256, '0');
  }

  /// eapi：AES-ECB，摘要为 md5("nobody{url}use{text}md5forencrypt")。
  static Map<String, String> eapi(String url, Map<String, dynamic> data) {
    final text = jsonEncode(data);
    final digest = hash.md5.convert(utf8.encode('nobody${url}use${text}md5forencrypt')).toString();
    final payload = '$url-36cd479b6b5-$text-36cd479b6b5-$digest';
    final enc = _aes(_utf8(payload), _utf8(_eapiKey));
    return {'params': enc.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase()};
  }

  static String md5(String s) => hash.md5.convert(utf8.encode(s)).toString();

  static String randomHex(int length) =>
      List.generate(length, (_) => _rand.nextInt(16).toRadixString(16)).join();
}
