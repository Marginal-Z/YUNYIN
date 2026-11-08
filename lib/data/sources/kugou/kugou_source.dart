import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/text_decode.dart';
import '../../models.dart';
import '../json_decode.dart';
import '../music_source.dart';
import '../net_retry.dart';
import '../netease/netease_source.dart' show parseLrc;

/// 酷狗音乐播放源：搜索、热搜、排行榜、歌单、专辑、歌手、评论、封面与歌词来自酷狗公开接口。
///
/// 播放与账号按酷狗安卓客户端的方式请求：本机先向酷狗注册一次设备（得到 dfid），之后取播放地址不再触发人机验证；
/// 账号用酷狗 App 扫码登录，得到客户端的登录凭据，歌单、收藏与会员接口都认可它。
class KugouSource extends MusicSource {
  KugouSource({Dio? dio})
    : _dio =
          dio ?? withRetry(Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 15), responseType: ResponseType.plain)));

  static const sourceId = 'kugou';
  static const _api = 'https://mobiles.kugou.com/api/v3';

  final Dio _dio;

  /// 网页接口使用的设备标识（kg_mid）。
  String _deviceId = md5.convert(utf8.encode('${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextDouble()}')).toString();

  /// 客户端接口的设备：guid 随机生成并保存，mid 由 guid 计算（与酷狗客户端相同），dfid 向酷狗注册设备后得到。
  String _guid = '';
  String get _mid => _guid.isEmpty ? _deviceId : BigInt.parse(md5.convert(utf8.encode(_guid)).toString(), radix: 16).toString();
  /// 向酷狗注册设备得到的 dfid：普通版与概念版是两个客户端，各自注册。
  String? _dfidStd;
  String? _dfidLite;
  String? get _dfid => _lite ? _dfidLite : _dfidStd;
  set _dfid(String? v) => _lite ? _dfidLite = v : _dfidStd = v;
  String get _dfidPrefsKey => _lite ? 'kugou.dfid.lite' : 'kugou.dfid';

  /// 扫码登录时使用的客户端：true 为酷狗概念版（登录页选择）。
  bool loginLite = false;

  @override
  String get id => sourceId;

  @override
  String get name => '酷狗音乐';

  @override
  String get description => '酷狗的搜索、排行榜、歌单与账号，酷狗音乐或酷狗概念版 App 扫码登录后按账号权限播放';

  @override
  Set<SourceFeature> get features => {
    SourceFeature.search,
    SourceFeature.hotSearch,
    SourceFeature.charts,
    SourceFeature.playlistCategories,
    SourceFeature.newAlbums,
    SourceFeature.lyrics,
    SourceFeature.dailyRecommend,
    SourceFeature.artist,
    SourceFeature.album,
    SourceFeature.comments,
    SourceFeature.login,
    SourceFeature.qrLogin,
    SourceFeature.cookieLogin,
    if (_account != null) SourceFeature.userPlaylists,
  };

  // ── 账号 ──────────────────────────────────────────
  //
  // 推荐用酷狗 App 扫码登录：得到的是客户端的登录凭据（token + userid），账号接口与播放接口都认可。
  // 兼容早先的网页登录 / 粘贴 Cookie（KuGoo Cookie 中的 KugooID、t、NickName、Pic），这种凭据只有网页接口认可。

  static const _prefsKey = 'kugou.account';
  Map<String, String>? _account;
  UserProfile? _user;

  /// 扫码登录得到的客户端凭据（网页登录的凭据为 false）。
  bool get _appAccount => _account?['_app'] == '1';

  /// 酷狗概念版的账号：概念版是单独的客户端（appid、签名、设备注册都不同），登录凭据与普通版不通用，
  /// 概念版 VIP 也只在概念版客户端的接口中生效。
  bool get _lite => _appAccount && _account?['_lite'] == '1';

  /// 当前账号是否为酷狗概念版。
  bool get isLiteAccount => _lite;

  @override
  UserProfile? get user => _user;

  @override
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _deviceId = prefs.getString('kugou.deviceId') ?? _deviceId;
      await prefs.setString('kugou.deviceId', _deviceId);
      _guid = prefs.getString('kugou.guid') ?? '';
      if (_guid.isEmpty) {
        _guid = md5.convert(utf8.encode('${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextDouble()}-guid')).toString();
        await prefs.setString('kugou.guid', _guid);
      }
      _dfidStd = prefs.getString('kugou.dfid');
      _dfidLite = prefs.getString('kugou.dfid.lite');
      final raw = prefs.getString(_prefsKey);
      if (raw != null) _setAccount(Map<String, String>.from(jsonDecode(raw) as Map));
    } catch (e) {
      debugPrint('kugou account: $e');
    }
  }

  void _setAccount(Map<String, String>? a) {
    if (a != null && ((a['KugooID'] ?? '').isEmpty || a['KugooID'] == '0' || (a['t'] ?? '').isEmpty)) {
      throw const FormatException('酷狗账号信息不完整，请重新登录');
    }
    _account = a;
    // 换了账号：之前按旧账号权限取到的地址不再使用。
    _streams.clear();
    _user = a == null
        ? null
        : UserProfile(
            id: a['KugooID']!,
            nickname: (a['NickName'] ?? '').isEmpty ? '酷狗用户 ${a['KugooID']}' : a['NickName']!,
            avatar: (a['Pic'] ?? '').replaceFirst('http://', 'https://').ifEmpty(null),
          );
  }

  Future<void> _saveAccount() async {
    final prefs = await SharedPreferences.getInstance();
    if (_account == null) {
      await prefs.remove(_prefsKey);
    } else {
      await prefs.setString(_prefsKey, jsonEncode(_account));
    }
  }

  /// 解析 Cookie：可以是整段 Cookie 头，也可以只是 KuGoo 的值。值中的中文使用 %uXXXX 编码。
  static Map<String, String>? parseKugooCookie(String cookie) {
    if (cookie.contains('\r') || cookie.contains('\n')) return null;
    var text = cookie.trim();
    final m = RegExp(r'(?:^|;\s*)KuGoo=([^;]+)').firstMatch(text);
    if (m != null) text = m.group(1)!;
    final out = <String, String>{};
    for (final part in text.split('&')) {
      final i = part.indexOf('=');
      if (i <= 0) continue;
      out[part.substring(0, i).trim()] = _unescape(part.substring(i + 1).trim());
    }
    final id = out['KugooID'] ?? '';
    if (id.isEmpty || id == '0' || (out['t'] ?? '').isEmpty) return null;
    // 原样保存 KuGoo 的值，请求时原样带回（各字段的编码保持不变）。
    out['_raw'] = text;
    final cookies = <String, String>{};
    for (final part in cookie.split(';')) {
      final equal = part.indexOf('=');
      if (equal > 0) cookies[part.substring(0, equal).trim()] = part.substring(equal + 1).trim();
    }
    final mid = cookies['kg_mid'] ?? cookies['kg_mid_temp'];
    if (mid != null && mid.isNotEmpty) out['_mid'] = mid;
    final dfid = cookies['kg_dfid'];
    if (dfid != null && dfid.isNotEmpty) out['_dfid'] = dfid;
    return out;
  }

  /// JavaScript escape() 的逆操作：%uXXXX 与 %XX。
  static String _unescape(String s) {
    final u = s.replaceAllMapped(RegExp(r'%u([0-9a-fA-F]{4})'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
    try {
      return Uri.decodeComponent(u);
    } catch (_) {
      return u.replaceAllMapped(RegExp(r'%([0-9a-fA-F]{2})'), (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)));
    }
  }

  @override
  Future<void> loginWithCookie(String cookie) async {
    final a = parseKugooCookie(cookie);
    if (a == null) throw Exception('没有找到酷狗的登录信息（需要包含 KuGoo 的 Cookie）');
    _setAccount(a);
    await _saveAccount();
    notifyListeners();
  }

  @override
  Future<void> logout() async {
    cancelQrLogin();
    _setAccount(null);
    await _saveAccount();
    notifyListeners();
  }

  // ── 扫码登录（酷狗 App 扫码） ─────────────────────────────

  int _qrGeneration = 0;

  @override
  Future<QrTicket> createQrLogin() async {
    cancelQrLogin();
    final generation = _qrGeneration;
    final lite = loginLite;
    final j = await _web('https://login-user.kugou.com/v2/qrcode', {
      'appid': '1001',
      'type': '1',
      'plat': '4',
      'qrcode_txt': 'https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=${lite ? _liteAppId : _stdAppId}&',
      'srcappid': '2919',
      if (lite) 'clientver': '$_liteClientVer',
    });
    if (generation != _qrGeneration) throw StateError('扫码登录已取消，请重新扫码');
    final key = '${(j['data'] as Map?)?['qrcode'] ?? ''}';
    if ('${j['status']}' != '1' || key.isEmpty) throw Exception('获取酷狗登录二维码失败${_why(j)}');
    return QrTicket(key, 'https://h5.kugou.com/apps/loginQRCode/html/index.html?qrcode=$key', app: lite ? '酷狗概念版 App' : '酷狗音乐 App');
  }

  @override
  void cancelQrLogin() => _qrGeneration++;

  @override
  Future<QrState> checkQrLogin(QrTicket ticket) async {
    final generation = _qrGeneration;
    final lite = loginLite;
    final j = await _web('https://login-user.kugou.com/v2/get_userinfo_qrcode', {
      'plat': '4',
      'appid': '${lite ? _liteAppId : _stdAppId}',
      'srcappid': '2919',
      'qrcode': ticket.key,
      if (lite) 'clientver': '$_liteClientVer',
    });
    if (generation != _qrGeneration) throw StateError('扫码登录已取消，请重新扫码');
    if ('${j['status']}' != '1') throw Exception('查询扫码状态失败${_why(j)}');
    final d = j['data'] as Map? ?? const {};
    switch ('${d['status']}') {
      case '0':
        return QrState.expired;
      case '1':
        return QrState.waiting;
      case '2':
        return QrState.scanned;
      case '4':
        final token = '${d['token'] ?? ''}';
        final userid = '${d['userid'] ?? ''}';
        if (token.isEmpty || userid.isEmpty || userid == '0') throw Exception('酷狗没有返回登录凭据，请重新扫码');
        _setAccount({'KugooID': userid, 't': token, 'NickName': '${d['nickname'] ?? ''}', 'Pic': '${d['pic'] ?? ''}', '_app': '1', if (lite) '_lite': '1'});
        await _saveAccount();
        // 新账号在本机重新注册一次设备，按账号身份校验。
        unawaited(_registerDevice(force: true).catchError((Object _) => '-'));
        notifyListeners();
        return QrState.confirmed;
      default:
        throw Exception('酷狗扫码登录失败（状态 ${d['status']}）');
    }
  }

  static String _why(Map j) {
    final code = j['error_code'] ?? j['errcode'] ?? j['err_code'];
    final msg = '${j['error_msg'] ?? j['error'] ?? j['msg'] ?? ''}'.trim();
    final parts = [if (code != null && '$code' != '0') '错误码 $code', if (msg.isNotEmpty) msg];
    return parts.isEmpty ? '' : '（${parts.join('，')}）';
  }

  // ── 客户端接口 ──────────────────────────────────────
  // 酷狗安卓客户端的请求方式：带设备标识（dfid / mid / uuid）、客户端版本与签名，登录后带 token 与 userid。

  static const _stdAppId = 1005;
  static const _stdClientVer = 20489;
  static const _stdKey = 'OIlwieks28dk2k092lksi2UIkp';

  /// 酷狗概念版客户端（参数与签名盐值参考 MakcRe/KuGouMusicApi，MIT 协议）。
  static const _liteAppId = 3116;
  static const _liteClientVer = 11440;
  static const _liteKey = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';

  int get _appId => _lite ? _liteAppId : _stdAppId;
  int get _clientVer => _lite ? _liteClientVer : _stdClientVer;
  String get _appKey => _lite ? _liteKey : _stdKey;
  static const _webKey = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
  static const _appUa = 'Android15-1070-11083-46-0-DiscoveryDRADProtocol-wifi';

  static String _sign(String key, Map<String, String> params, [String body = '']) {
    final keys = params.keys.toList()..sort();
    return md5.convert(utf8.encode('$key${keys.map((k) => '$k=${params[k]}').join()}$body$key')).toString();
  }

  /// 登录接口（网页签名）。
  Future<Map<String, dynamic>> _web(String url, Map<String, String> query) async {
    final params = <String, String>{
      'dfid': _dfid ?? '-',
      'mid': _mid,
      'uuid': '-',
      'clientver': '$_clientVer',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      ...query,
    };
    params['signature'] = _sign(_webKey, params);
    final res = await _dio.get<String>(url, queryParameters: params, options: Options(validateStatus: (_) => true, headers: {'User-Agent': _appUa}));
    return (await decodeJson(res.data)) as Map<String, dynamic>;
  }

  /// 客户端接口，返回完整的 JSON（不检查 status）。[withToken] 为 false 时不带账号（按游客请求）。
  Future<Map<String, dynamic>> _app(
    String path, {
    String base = 'https://gateway.kugou.com',
    Map<String, Object?> query = const {},
    Object? body,
    String? router,
    String method = 'GET',
    bool withToken = true,
  }) async {
    final a = withToken && _appAccount ? _account : null;
    final dfid = await _deviceDfid();
    final params = <String, String>{
      'dfid': dfid,
      'mid': _mid,
      'uuid': '-',
      'appid': '$_appId',
      'clientver': '$_clientVer',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      if (a != null) ...{'token': a['t'] ?? '', 'userid': a['KugooID'] ?? '0'},
      for (final e in query.entries) e.key: '${e.value}',
    };
    final data = body == null ? '' : (body is String ? body : jsonEncode(body));
    params['signature'] = _sign(_appKey, params, data);
    final res = await _dio.request<String>(
      '$base$path',
      queryParameters: params,
      data: body == null ? null : data,
      options: Options(
        method: body == null ? method : 'POST',
        // 401 / 403 等也读出酷狗返回的原因。
        validateStatus: (_) => true,
        headers: {
          'User-Agent': _appUa,
          'dfid': dfid,
          'mid': _mid,
          'clienttime': params['clienttime'],
          'kg-rc': '1',
          'kg-thash': '5d816a0',
          'kg-rec': '1',
          'kg-rf': 'B9EDA08A64250DEFFBCADDEE00F8F25F',
          'x-router': ?router,
          if (body != null) 'Content-Type': 'application/json',
        },
      ),
    );
    try {
      return (await decodeJson(res.data)) as Map<String, dynamic>;
    } catch (_) {
      throw _KugouRefusal('HTTP ${res.statusCode}', '');
    }
  }

  // ── 设备注册 ──────────────────────────────────────
  // 未注册的设备取播放地址会被要求验证（20028 / 30020）。注册接口的请求体用随机密钥做 AES 加密，
  // 密钥用酷狗客户端内置的 RSA 公钥加密后放在 p 参数中；返回的 dfid 保存在本机，之后一直使用。

  BigInt get _rsaModulus => _lite ? _liteModulus : _stdModulus;

  /// 酷狗概念版客户端内置的 RSA 公钥模数。
  static final _liteModulus = BigInt.parse(
    'c40a2d0da76511f3bb1cc2bbd3afbd8bea83b4d6b05b6c13eb8920c53f1af7679b32ba0d0edb843240ef1b836efed3ee240734c14c1399fd6594d16af22f5252'
    '5d14d72e0155c6dcc8638d4f7bb94f3a0b1f4c29f991972f2a160a25eb0a9e724336be7f69bbd319ffab1c6dd8470b021dc434f3faba89f4a2a01b33bdbdd08b',
    radix: 16,
  );

  /// 酷狗客户端内置的 RSA 公钥模数。
  static final _stdModulus = BigInt.parse(
    'c8006ed03842d2628209bd314984ca5ed6cfe06e30c95f9d4704d9c49791d7a935ba950ecb0bc8ebf5f5994f0bac927a7eb151b3c1de343303fa539c83136ecc'
    'fd7d7e511e2dbce18eaa9f784c9b50d443e75865979e0a5e216e46c684066a8d6b998580bbaa22d73f5790286bb14742e83244e44db6d707ffe162c5c7002d45',
    radix: 16,
  );

  /// 账号接口的 p 参数：JSON 末尾补 0 到 128 字节后做 RSA 运算（不带填充）。
  String _rsa(Map<String, Object?> data) {
    final bytes = utf8.encode(jsonEncode(data));
    final padded = List<int>.filled(128, 0)..setRange(0, bytes.length, bytes);
    final m = padded.fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));
    return m.modPow(BigInt.from(65537), _rsaModulus).toRadixString(16).padLeft(256, '0').toUpperCase();
  }

  /// RSA PKCS#1 v1.5 加密（设备注册的 p 参数）。
  String _rsaPkcs1(List<int> message) {
    final r = math.Random.secure();
    final em = <int>[0, 2, for (var i = 0; i < 128 - 3 - message.length; i++) 1 + r.nextInt(255), 0, ...message];
    final m = em.fold(BigInt.zero, (v, b) => (v << 8) | BigInt.from(b));
    return m.modPow(BigInt.from(65537), _rsaModulus).toRadixString(16).padLeft(256, '0');
  }

  /// 设备注册数据的 AES-128-CBC：密钥与 IV 分别是 md5(随机密钥) 的前后 16 个字符。
  static Uint8List _aes(bool encrypt, Uint8List data, String key) {
    final h = md5.convert(utf8.encode(key)).toString();
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), CBCBlockCipher(AESEngine()))
      ..init(
        encrypt,
        PaddedBlockCipherParameters<CipherParameters, CipherParameters?>(
          ParametersWithIV<KeyParameter>(KeyParameter(Uint8List.fromList(utf8.encode(h.substring(0, 16)))), Uint8List.fromList(utf8.encode(h.substring(16, 32)))),
          null,
        ),
      );
    return cipher.process(data);
  }

  Future<String>? _registering;
  DateTime _registerFailedAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// 本机注册得到的 dfid；还没有时先注册（失败时用“-”，10 分钟后再试）。
  Future<String> _deviceDfid() async {
    final dfid = _dfid;
    if (dfid != null && dfid.isNotEmpty) return dfid;
    if (DateTime.now().difference(_registerFailedAt) < const Duration(minutes: 10)) return '-';
    return _registerDevice();
  }

  Future<String> _registerDevice({bool force = false}) {
    if (force) {
      _dfid = null;
      _registerFailedAt = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return _registering ??= () async {
      try {
        const letters = 'abcdefghijklmnopqrstuvwxyz0123456789';
        final r = math.Random.secure();
        final key = String.fromCharCodes([for (var i = 0; i < 6; i++) letters.codeUnitAt(r.nextInt(letters.length))]);
        final a = _appAccount ? _account : null;
        final device = {
          'availableRamSize': 4983533568,
          'availableRomSize': 48114719,
          'availableSDSize': 48114717,
          'basebandVer': '',
          'batteryLevel': 100,
          'batteryStatus': 3,
          'brand': 'Redmi',
          'buildSerial': 'unknown',
          'device': 'marble',
          'imei': _guid,
          'imsi': '',
          'manufacturer': 'Xiaomi',
          'uuid': _guid,
          for (final sensor in const ['accelerometer', 'gravity', 'gyroscope', 'light', 'magnetic', 'orientation', 'pressure', 'step_counter', 'temperature']) ...{
            sensor: false,
            '${sensor}Value': '',
          },
        };
        final body = base64.encode(_aes(true, Uint8List.fromList(utf8.encode(jsonEncode(device))), key));
        final params = <String, String>{
          'dfid': '-',
          'mid': _mid,
          'uuid': '-',
          'appid': '$_appId',
          'clientver': '$_clientVer',
          'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          'part': '1',
          'platid': '1',
          'p': _rsaPkcs1(utf8.encode(jsonEncode({'aes': key, 'uid': int.tryParse(a?['KugooID'] ?? '') ?? 0, 'token': a?['t'] ?? ''}))),
        };
        params['signature'] = _sign(_appKey, params, body);
        final res = await _dio.post<List<int>>(
          'https://userservice.kugou.com/risk/v3/r_register_dev',
          queryParameters: params,
          data: body,
          options: Options(
            responseType: ResponseType.bytes,
            validateStatus: (_) => true,
            headers: {'User-Agent': _appUa, 'dfid': '-', 'mid': _mid, 'clienttime': params['clienttime'], 'Content-Type': 'text/plain'},
          ),
        );
        final bytes = Uint8List.fromList(res.data ?? const []);
        Map<String, dynamic> j;
        try {
          // 失败时返回明文 JSON（例如 rsa failure），成功时返回加密数据。
          j = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        } catch (_) {
          j = jsonDecode(utf8.decode(_aes(false, bytes, key))) as Map<String, dynamic>;
        }
        final dfid = '${(j['data'] is Map ? j['data']['dfid'] : null) ?? ''}';
        if ('${j['status']}' != '1' || dfid.isEmpty) throw _KugouRefusal('${j['error_code'] ?? ''}', '${j['data'] is String ? j['data'] : ''}');
        _dfid = dfid;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_dfidPrefsKey, dfid);
        return dfid;
      } catch (e) {
        debugPrint('kugou register device: $e');
        _registerFailedAt = DateTime.now();
        return '-';
      } finally {
        _registering = null;
      }
    }();
  }

  // ── 账号数据 ──────────────────────────────────────
  // 歌单、关注与会员信息来自酷狗客户端的账号接口，用登录得到的 token 查询本人的数据。

  /// 网页登录的账号：先按网页版（与网页登录得到的 token 相同的 appid，网页签名）请求，不通过时再按客户端请求；
  /// 记住能用的方式，下次先用它。扫码登录的账号直接按客户端请求。
  bool _androidFirst = false;

  Future<Map<String, dynamic>> _account2(String path, {String base = 'https://gateway.kugou.com', Map<String, Object?> query = const {}, Object? body, String? router}) async {
    final a = _account;
    if (a == null) throw const SourceUnsupported('请先登录酷狗账号');
    if (_appAccount) {
      final j = await _app(path, base: base, query: query, body: body, router: router);
      if ('${j['status']}' == '1') return (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final code = '${j['error_code'] ?? j['errcode'] ?? j['err_code'] ?? ''}';
      // 20018 / 34175 / 51002 等：登录已失效。
      throw Exception('酷狗账号接口没有返回数据${_why(j)}${const {'20018', '34175', '51002', '20017'}.contains(code) ? '，登录已失效，请重新扫码登录酷狗' : ''}');
    }
    final failures = <String>[];
    for (final android in _androidFirst ? const [true, false] : const [false, true]) {
      try {
        final d = await _accountRequest(a, android: android, path: path, base: base, query: query, body: body, router: router);
        _androidFirst = android;
        return d;
      } on _KugouRefusal catch (e) {
        failures.add('${android ? '客户端' : '网页'}${e.code == null ? '' : ' 错误码 ${e.code}'}${e.message.isEmpty ? '' : '：${e.message}'}');
      }
    }
    throw Exception('酷狗账号接口没有返回数据（${failures.join('；')}）。网页登录的凭据不被酷狗客户端接口认可，请退出后用“酷狗 App 扫码登录”重新登录');
  }

  Future<Map<String, dynamic>> _accountRequest(
    Map<String, String> a, {
    required bool android,
    required String path,
    required String base,
    required Map<String, Object?> query,
    required Object? body,
    required String? router,
  }) async {
    final mid = a['_mid'] ?? _deviceId;
    final dfid = a['_dfid'] ?? '-';
    final params = <String, String>{
      'dfid': dfid,
      'mid': mid,
      'uuid': android ? '-' : mid,
      'appid': android ? '$_appId' : (a['a_id'] ?? '').ifEmpty('1014')!,
      'clientver': android ? '$_clientVer' : '20000',
      if (!android) 'srcappid': '2919',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
      'token': a['t'] ?? '',
      'userid': a['KugooID'] ?? '0',
      for (final e in query.entries) e.key: '${e.value}',
    };
    final data = body == null ? '' : jsonEncode(body);
    params['signature'] = _sign(android ? _appKey : _webKey, params, data);
    final res = await _dio.request<String>(
      '$base$path',
      queryParameters: params,
      data: body == null ? null : data,
      options: Options(
        method: body == null ? 'GET' : 'POST',
        // 401 / 403 等也读出酷狗返回的原因。
        validateStatus: (_) => true,
        headers: {
          'dfid': dfid,
          'mid': mid,
          'clienttime': params['clienttime'],
          'x-router': ?router,
          if (body != null) 'Content-Type': 'application/json',
          if (!android) ...{
            'User-Agent': 'Mozilla/5.0',
            'Referer': 'https://www.kugou.com/',
            'Cookie': 'kg_mid=$mid; kg_dfid=$dfid; KuGoo=${a['_raw'] ?? ''}',
          },
        },
      ),
    );
    Map<String, dynamic> j;
    try {
      j = (await decodeJson(res.data)) as Map<String, dynamic>;
    } catch (_) {
      throw _KugouRefusal('HTTP ${res.statusCode}', '');
    }
    if ('${j['status']}' != '1') {
      final code = j['error_code'] ?? j['errcode'] ?? j['err_code'];
      throw _KugouRefusal(code == null ? null : '$code', '${j['error_msg'] ?? j['error'] ?? j['msg'] ?? ''}'.trim());
    }
    return (j['data'] as Map?)?.cast<String, dynamic>() ?? const {};
  }

  static const _webRelogin = Membership(
    platform: '酷狗音乐',
    title: '请重新登录',
    relogin: true,
    benefits: ['当前是网页登录 / Cookie 的凭据，酷狗客户端接口不认可：查不到会员，会员歌曲只能试听', '请退出后用“酷狗 App 扫码登录”'],
  );

  @override
  Future<Membership?> membership() async {
    if (_account == null) return null;
    if (!_appAccount) {
      // 网页登录的凭据：能查到就显示；查不到时（通常如此）提示改用扫码登录。
      try {
        return kugouMembership(await _account2('/v1/get_union_vip', base: 'https://kugouvip.kugou.com', query: const {'busi_type': 'concept'}));
      } catch (e) {
        debugPrint('kugou vip (web): $e');
        return _webRelogin;
      }
    }
    try {
      final d = await _account2('/v1/get_union_vip', base: 'https://kugouvip.kugou.com', query: const {'busi_type': 'concept'});
      final m = kugouMembership(d);
      if (!_lite) return m;
      return Membership(platform: '酷狗概念版', title: m.title, active: m.active, level: m.level, expires: m.expires, benefits: m.benefits, relogin: m.relogin);
    } catch (e) {
      debugPrint('kugou vip: $e');
      final text = '$e'.replaceFirst('Exception: ', '');
      return Membership(
        platform: '酷狗音乐',
        title: text.contains('重新扫码') ? '登录已失效' : '已登录',
        relogin: text.contains('重新扫码'),
        benefits: ['暂时查询不到会员信息：$text'],
      );
    }
  }

  /// 解析酷狗的会员信息（get_union_vip）：
  /// - 顶层 user_type 的第 16 位为超级 VIP，vip_type 为 6 是豪华 VIP（酷狗主应用的会员）；
  /// - busi_vip 中 product_type 为 tvip 的是畅听 VIP，svip 的是概念版 VIP（is_vip 为 1 表示生效）；
  /// - 顶层 is_vip 为 1 或 vip_type 大于 0 时也是会员。
  /// 此前只看 busi_vip、还把 svip 当成豪华 VIP，开通豪华 VIP 的账号会显示为“未开通”。
  @visibleForTesting
  static Membership kugouMembership(Map d) {
    int n(Object? v) => int.tryParse('${v ?? ''}') ?? 0;
    DateTime? day(Object? v) {
      final t = '${v ?? ''}'.trim();
      if (t.isEmpty || t.startsWith('0000')) return null;
      final seconds = int.tryParse(t);
      if (seconds != null && seconds > 1000000000) return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
      return DateTime.tryParse(t.replaceFirst(' ', 'T'));
    }

    final products = (d['busi_vip'] as List? ?? const []).whereType<Map>().toList();
    Map? product(String type) => products.where((p) => p['product_type'] == type && n(p['is_vip']) == 1).firstOrNull;
    final userType = n(d['user_type']);
    final vipType = n(d['vip_type']);
    final superVip = userType > 0 && userType & 16 != 0;
    final deluxe = vipType == 6;
    final music = product('tvip');
    final concept = product('svip');
    final other = products.where((p) => n(p['is_vip']) == 1).firstOrNull;
    final top = n(d['is_vip']) == 1 || vipType > 0;
    final (String? title, DateTime? expires) = superVip
        ? ('超级 VIP', day(d['su_vip_end_time']) ?? day(d['vip_end_time']))
        : deluxe
        ? ('豪华 VIP', day(d['vip_end_time']))
        : music != null
        ? ('畅听 VIP', day(music['vip_end_time']))
        : top
        ? ('VIP 会员', day(d['vip_end_time']))
        : concept != null
        ? ('概念版 VIP', day(concept['vip_end_time']))
        : other != null
        ? ('VIP 会员', day(other['vip_end_time']))
        : (null, null);
    if (title == null) return const Membership(platform: '酷狗音乐', title: '未开通 VIP', benefits: ['免费歌曲可完整播放', '会员歌曲为试听片段']);
    return Membership(
      platform: '酷狗音乐',
      title: title,
      active: true,
      expires: expires,
      benefits: superVip || deluxe ? const ['无损与 Hi-Res 音质', '播放与下载会员歌曲', '畅听 VIP 全部权益'] : const ['播放会员歌曲', '高品质音质'],
    );
  }

  @override
  Future<String> diagnose() async {
    final out = StringBuffer('酷狗账号诊断（${DateTime.now().toIso8601String().substring(0, 19)}）\n');
    final a = _account;
    if (a == null) return '$out未登录';
    final id = a['KugooID'] ?? '';
    out.writeln('账号：${id.length > 4 ? '${id.substring(0, 2)}***${id.substring(id.length - 2)}' : '***'}，${_appAccount ? (_lite ? '酷狗概念版 App 扫码登录（概念版客户端凭据）' : '酷狗 App 扫码登录（客户端凭据）') : '网页登录 / Cookie（网页凭据，客户端接口不认可）'}');
    out.writeln('设备：${(_dfid ?? '').isEmpty ? '未注册' : '已注册'}');
    Future<void> step(String name, Future<String> Function() run) async {
      try {
        out.writeln('$name：${await run()}');
      } catch (e) {
        out.writeln('$name：失败 $e');
      }
    }

    await step('会员接口', () async {
      final j = await _app('/v1/get_union_vip', base: 'https://kugouvip.kugou.com', query: const {'busi_type': 'concept'});
      final d = j['data'] is Map ? j['data'] as Map : const {};
      final busi = [for (final p in (d['busi_vip'] as List? ?? const []).whereType<Map>()) '${p['product_type']}=${p['is_vip']}'].join(',');
      return 'status=${j['status']} error_code=${j['error_code'] ?? j['errcode'] ?? ''} is_vip=${d['is_vip']} vip_type=${d['vip_type']} user_type=${d['user_type']} busi_vip=[$busi] → ${'${j['status']}' == '1' ? kugouMembership(d).title : '-'}';
    });
    // 一首 VIP 歌曲（周杰伦《晴天》）：各音质的结果。
    const ids = (hash: 'b3a52a7a958bf0aed0ebfba2e9a818b7', audio: '32100650', album: '966846');
    for (final q in const ['128', '320', 'flac']) {
      await step('播放接口 $q', () async {
        final j = await _urlRequest(ids, q);
        final urls = [j['url'], j['backupUrl']].expand((v) => v is List ? v : [v]).whereType<String>().where((u) => u.isNotEmpty);
        return 'status=${j['status']} errcode=${j['errcode'] ?? j['error_code'] ?? ''} fail_process=${j['fail_process'] ?? ''} 试听=${j['hash_offset'] is Map ? '是' : '否'} 地址=${urls.isEmpty ? '无' : '有'}';
      });
    }
    return out.toString();
  }

  /// 只拿到试听片段时告诉用户原因。
  String? get _trialNote {
    if (_account == null) return '用酷狗 App 扫码登录有会员的账号后可以播放完整版';
    if (!_appAccount) return '当前是网页登录的凭据，无法播放完整的会员歌曲，请退出后用“酷狗 App 扫码登录”';
    return '酷狗没有给出完整版：可能需要 VIP，或登录已失效。可在“我的 → 会员卡片 → 账号诊断”中查看原因';
  }

  /// 账号下的全部歌单（自建、“我喜欢”、收藏的歌单与专辑）。
  Future<List<Map>> _allLists() async {
    final a = _account!;
    final d = await _account2(
      '/v7/get_all_list',
      query: {'plat': 1},
      body: {'userid': int.tryParse(a['KugooID'] ?? '') ?? 0, 'token': a['t'] ?? '', 'total_ver': 979, 'type': 2, 'page': 1, 'pagesize': 300},
      router: 'cloudlist.service.kugou.com',
    );
    return (d['info'] as List? ?? const []).whereType<Map>().toList();
  }

  static String _gcid(Map l) => '${l['list_create_gid'] ?? ''}'.ifEmpty(null) ?? '${l['global_collection_id'] ?? ''}';

  @override
  Future<List<PlaylistInfo>> userPlaylists() async {
    if (_account == null) return const [];
    final me = _account!['KugooID'];
    final out = <PlaylistInfo>[];
    for (final l in await _allLists()) {
      // 带作者信息的是收藏的专辑，在“专辑”里显示。
      if (l['authors'] != null || _gcid(l).isEmpty) continue;
      final liked = l['name'] == '我喜欢';
      final mine = '${l['list_create_userid']}' == me;
      out.add(
        PlaylistInfo(
          id: 'gcid:${_gcid(l)}',
          sourceId: sourceId,
          name: liked ? '我喜欢的音乐' : '${l['name'] ?? ''}',
          cover: _cover(l['pic'] as String?),
          trackCount: int.tryParse('${l['count'] ?? 0}') ?? 0,
          creator: mine ? _user?.nickname : '${l['list_create_username'] ?? ''}'.ifEmpty(null),
          isLikedList: liked,
          ownedByMe: mine || liked,
        ),
      );
    }
    out.sort((a, b) => (b.isLikedList ? 1 : 0) - (a.isLikedList ? 1 : 0));
    return out;
  }

  /// 账号歌单里的歌曲（每页 300 首，最多 3000 首）。
  Future<List<Song>> _listSongs(String gcid) async {
    const size = 300;
    final out = <Song>[];
    for (var begin = 0; begin < 3000; begin += size) {
      final d = await _account2(
        '/pubsongs/v2/get_other_list_file_nofilt',
        query: {
          'area_code': 1,
          'begin_idx': begin,
          'plat': 1,
          'type': 1,
          'mode': 1,
          'personal_switch': 1,
          'extend_fields': 'abtags,hot_cmt,popularization',
          'pagesize': size,
          'global_collection_id': gcid,
        },
      );
      final songs = (d['songs'] as List? ?? const []).whereType<Map>().toList();
      for (final x in songs) {
        if ('${x['hash'] ?? ''}'.isEmpty) continue;
        final album = x['albuminfo'] is Map ? x['albuminfo'] as Map : const {};
        final name = '${x['name'] ?? ''}';
        final i = name.indexOf(' - ');
        final trans = x['trans_param'] is Map ? x['trans_param'] as Map : const {};
        out.add(
          _song({
            'hash': x['hash'],
            'album_audio_id': x['add_mixsongid'] ?? x['mixsongid'] ?? x['album_audio_id'] ?? x['audio_id'] ?? '',
            'album_id': album['id'] ?? x['album_id'] ?? '',
            'songname': i > 0 ? name.substring(i + 3) : name,
            'singername': i > 0 ? name.substring(0, i) : (x['singername'] ?? ''),
            'album_name': album['name'] ?? '',
            // 封面可能在 cover、trans_param.union_cover 或专辑信息中。
            'album_sizable_cover': '${x['cover'] ?? ''}'.ifEmpty(null) ?? '${trans['union_cover'] ?? ''}'.ifEmpty(null) ?? '${album['sizable_cover'] ?? album['cover'] ?? ''}'.ifEmpty(null),
            'duration': (int.tryParse('${x['timelen'] ?? 0}') ?? 0) ~/ 1000,
            'privilege': x['privilege'],
            'pay_type': x['pay_type'],
            'pkg_price': x['pkg_price'],
            'trans_param': trans,
            'sqhash': x['sqhash'],
          }),
        );
      }
      if (songs.length < size) break;
    }
    return out;
  }

  Future<PlaylistInfo> _accountList(String gcid) async {
    final lists = await _allLists().catchError((Object _) => <Map>[]);
    final l = lists.where((l) => _gcid(l) == gcid).firstOrNull ?? const {};
    final songs = await _listSongs(gcid);
    final liked = l['name'] == '我喜欢';
    final mine = '${l['list_create_userid']}' == _account?['KugooID'];
    return PlaylistInfo(
      id: 'gcid:$gcid',
      sourceId: sourceId,
      name: liked ? '我喜欢的音乐' : '${l['name'] ?? '酷狗歌单'}',
      cover: _cover(l['pic'] as String?) ?? songs.firstOrNull?.coverUrl,
      creator: mine || liked ? _user?.nickname : '${l['list_create_username'] ?? ''}'.ifEmpty(null),
      description: '${l['intro'] ?? ''}'.trim().ifEmpty(null),
      trackCount: songs.length,
      isLikedList: liked,
      ownedByMe: mine || liked,
      kind: liked ? PlaylistKind.liked : PlaylistKind.playlist,
      tracks: songs,
    );
  }

  @override
  Future<Set<String>> likedSongIds() async {
    if (_account == null) return const {};
    final liked = (await _allLists()).where((l) => l['name'] == '我喜欢').firstOrNull;
    if (liked == null) return const {};
    return {for (final s in await _listSongs(_gcid(liked))) s.id};
  }

  @override
  Future<List<AlbumInfo>> subscribedAlbums() async {
    if (_account == null) return const [];
    return [
      for (final l in await _allLists())
        // 只列出带专辑 id 的收藏（其余 id 是歌单 id，打不开专辑页）。
        if (l['authors'] != null && '${l['album_id'] ?? l['albumid'] ?? ''}'.isNotEmpty)
          AlbumInfo(
            id: '${l['album_id'] ?? l['albumid']}',
            sourceId: sourceId,
            name: '${l['name'] ?? ''}',
            cover: _cover(l['pic'] as String?),
            artist: switch (l['authors']) {
              final List a when a.isNotEmpty && a.first is Map => ArtistRef('kugou:${a.first['author_name']}', '${a.first['author_name'] ?? ''}'),
              _ => null,
            },
          ),
    ];
  }

  @override
  Future<List<ArtistInfo>> followedArtists() async {
    if (_account == null) return const [];
    final a = _account!;
    final d = await _account2(
      '/v4/follow_list',
      query: {'plat': 1},
      body: {
        'merge': 2,
        'need_iden_type': 1,
        'ext_params': 'k_pic,jumptype,singerid,score',
        'userid': a['KugooID'],
        'type': 0,
        'id_type': 0,
        'p': _rsa({'clienttime': DateTime.now().millisecondsSinceEpoch ~/ 1000, 'token': a['t'] ?? ''}),
      },
      router: 'relationuser.kugou.com',
    );
    return [
      for (final x in (d['lists'] as List? ?? const []).whereType<Map>())
        if ('${x['singerid'] ?? ''}'.isNotEmpty && '${x['singerid']}' != '0')
          ArtistInfo(
            id: '${x['singerid']}',
            sourceId: sourceId,
            name: '${x['nickname'] ?? ''}',
            avatar: '${x['pic'] ?? ''}'.replaceFirst('/100/', '/480/').replaceFirst('http://', 'https://').ifEmpty(null),
            followed: true,
          ),
    ];
  }

  /// 酷狗榜单的分类（rank/list 返回的 classify）。
  static const _rankGroups = {1: '酷狗榜', 2: '地区榜', 3: '特色榜', 4: '全球榜', 5: '曲风榜'};

  /// 榜单 ID → 名称，打开榜单详情时显示（来自 [charts]）。
  final _rankNames = <String, String>{};

  Future<Map<String, dynamic>> _get(String url) async {
    final res = await _dio.get<String>(url, options: Options(headers: {'User-Agent': 'Mozilla/5.0 (Linux; Android 14) YunYin'}));
    // 部分接口返回的文字里有未转义的控制字符，宽松解析。
    final body = (res.data ?? '').replaceAll(RegExp(r'[\u0000-\u0008\u000b\u000c\u000e-\u001f]'), ' ');
    return jsonDecode(body) as Map<String, dynamic>;
  }

  static String? _cover(String? template, [int size = 400]) {
    if (template == null || template.isEmpty) return null;
    return template.replaceAll('{size}', '$size').replaceFirst('http://', 'https://');
  }

  /// 酷狗歌曲：id 编码为“hash:album_audio_id:album_id”，播放与歌词都需要。
  Song _song(Map<String, dynamic> j) {
    final hash = '${j['hash'] ?? j['FileHash'] ?? ''}'.toLowerCase();
    final audio = '${j['album_audio_id'] ?? j['MixSongID'] ?? ''}';
    final albumId = '${j['album_id'] ?? j['AlbumID'] ?? ''}';
    var name = '${j['songname'] ?? j['SongName'] ?? ''}'.trim();
    var singer = '${j['singername'] ?? j['SingerName'] ?? ''}'.trim();
    final filename = '${j['filename'] ?? ''}';
    if ((name.isEmpty || singer.isEmpty) && filename.contains(' - ')) {
      final i = filename.indexOf(' - ');
      singer = singer.isEmpty ? filename.substring(0, i).trim() : singer;
      name = name.isEmpty ? filename.substring(i + 3).trim() : name;
    }
    final cover = _cover(j['album_sizable_cover'] as String? ?? (j['trans_param'] is Map ? j['trans_param']['union_cover'] as String? : null));
    final albumName = '${j['album_name'] ?? j['AlbumName'] ?? ''}';
    final seconds = int.tryParse('${j['duration'] ?? j['Duration'] ?? 0}') ?? 0;
    return Song(
      id: '$hash:$audio:$albumId',
      sourceId: sourceId,
      name: name.isEmpty ? filename : name,
      artists: [
        for (final a in singer.split(RegExp(r'\s*[、/]\s*')))
          if (a.isNotEmpty) ArtistRef('kugou:$a', a),
      ],
      album: albumName.isEmpty && cover == null ? null : AlbumRef(albumId, albumName, cover: cover),
      duration: Duration(seconds: seconds),
      cover: cover,
      // privilege 为 5：下架或没有版权。
      playable: '${j['privilege'] ?? ''}' != '5',
      fee: kugouFee(j),
      maxQuality: '${j['sqhash'] ?? j['SQFileHash'] ?? ''}'.replaceAll('0', '').isNotEmpty
          ? AudioQuality.lossless
          : ('${j['320hash'] ?? j['HQFileHash'] ?? ''}'.replaceAll('0', '').isNotEmpty ? AudioQuality.exhigh : null),
    );
  }

  /// 酷狗的付费规则：
  /// - privilege 为 10 表示需要付费才能完整播放：在音乐包内（pkg_price 大于 0、musicpack_advance 为 1，或 pay_type 为 3）
  ///   的是 VIP 歌曲；不在音乐包内、需要单独购买的（pay_type 为 2 的付费单曲 / 数字专辑）是付费歌曲；
  /// - privilege 为 8 可以免费播放（VIP 才能下载与听高音质），0 / 4 为免费歌曲。
  @visibleForTesting
  static SongFee kugouFee(Map j) {
    final privilege = int.tryParse('${j['privilege'] ?? j['Privilege'] ?? ''}') ?? 0;
    if (privilege != 10) return SongFee.free;
    final trans = j['trans_param'] is Map ? j['trans_param'] as Map : const {};
    final pkg = int.tryParse('${j['pkg_price'] ?? ''}');
    final pay = int.tryParse('${j['pay_type'] ?? j['PayType'] ?? ''}');
    if (trans['musicpack_advance'] == 1 || (pkg ?? 0) > 0 || pay == 3) return SongFee.vip;
    if (pay == 2 && pkg == 0) return SongFee.paid;
    return SongFee.vip;
  }

  ({String hash, String audio, String album}) _ids(Song s) {
    final p = s.id.split(':');
    return (hash: p.first, audio: p.length > 1 ? p[1] : '', album: p.length > 2 ? p[2] : '');
  }

  // ── 搜索 ──────────────────────────────────────────

  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async {
    final page = offset ~/ limit + 1;
    final kw = Uri.encodeQueryComponent(keyword);
    Future<List<Map<String, dynamic>>> list(String kind, int size, {bool flat = false}) async {
      final j = await _get('$_api/search/$kind?format=json&keyword=$kw&page=$page&pagesize=$size&showtype=1');
      final data = j['data'];
      // 歌手搜索的 data 直接是列表，其余为 {info: [...]}。
      final items = flat ? data : (data is Map ? data['info'] : null);
      return (items is List ? items : const []).cast<Map<String, dynamic>>();
    }

    Future<List<Song>> songs() async => [for (final x in await list('song', limit)) _song(x)];
    // 歌手搜索不返回头像：并行查询每位歌手的资料补上头像（取不到时界面显示名字首字）。
    Future<List<ArtistInfo>> artists(int size) async {
      final found = await list('singer', size, flat: true);
      return Future.wait([
        for (final a in found)
          _get('$_api/singer/info?singerid=${a['singerid']}&plat=0')
              .then((j) => _cover((j['data'] as Map?)?['imgurl'] as String?, 240))
              .timeout(const Duration(seconds: 4))
              .catchError((Object _) => null)
              .then((avatar) => ArtistInfo(id: '${a['singerid']}', sourceId: sourceId, name: '${a['singername']}', avatar: avatar)),
      ]);
    }

    Future<List<AlbumInfo>> albums(int size) async => [for (final a in await list('album', size)) _album(a)];
    Future<List<PlaylistInfo>> playlists(int size) async => [for (final p in await list('special', size)) _special(p)];
    switch (type) {
      case SearchType.song:
        final s = await songs();
        return SearchResult(songs: s, bestSong: s.firstOrNull);
      case SearchType.artist:
        return SearchResult(artists: await artists(limit));
      case SearchType.album:
        return SearchResult(albums: await albums(limit));
      case SearchType.playlist:
        return SearchResult(playlists: await playlists(limit));
      case SearchType.all:
        final r = await Future.wait([
          songs(),
          artists(4).then((a) => a.take(4).toList()).catchError((Object _) => <ArtistInfo>[]),
          albums(6).catchError((Object _) => <AlbumInfo>[]),
          playlists(6).catchError((Object _) => <PlaylistInfo>[]),
        ]);
        final s = r[0] as List<Song>;
        final pls = r[3] as List<PlaylistInfo>;
        return SearchResult(
          songs: s,
          artists: r[1] as List<ArtistInfo>,
          albums: r[2] as List<AlbumInfo>,
          playlists: pls,
          bestSong: s.firstOrNull,
          bestPlaylist: pls.firstOrNull,
        );
    }
  }

  AlbumInfo _album(Map a) => AlbumInfo(
    id: '${a['albumid']}',
    sourceId: sourceId,
    name: '${a['albumname'] ?? ''}',
    cover: _cover(a['imgurl'] as String?),
    artist: ArtistRef('kugou:${a['singername'] ?? ''}', '${a['singername'] ?? ''}'),
    publishTime: DateTime.tryParse('${a['publishtime'] ?? ''}'.replaceFirst(' ', 'T')),
    description: (a['intro'] as String?)?.trim(),
    size: (a['songcount'] as num?)?.toInt() ?? 0,
  );

  PlaylistInfo _special(Map p) => PlaylistInfo(
    id: 'special:${p['specialid']}',
    sourceId: sourceId,
    name: '${p['specialname'] ?? ''}',
    cover: _cover(p['imgurl'] as String?),
    creator: '${p['username'] ?? p['nickname'] ?? ''}',
    description: (p['intro'] as String?)?.trim(),
    playCount: (p['playcount'] as num?)?.toInt() ?? 0,
    trackCount: (p['songcount'] as num?)?.toInt() ?? 0,
  );

  @override
  Future<List<HotSearch>> hotSearches() async {
    final j = await _get('$_api/search/hot?format=json&plat=0&count=20');
    final info = ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>();
    return [for (final x in info) HotSearch('${x['keyword']}')];
  }

  // ── 排行榜与首页 ──────────────────────────────────────

  /// 榜单歌曲。酷狗每页最多 100 首，TOP500 等长榜单并行读取其余各页。
  Future<List<Song>> _rank(String rankId, {int size = 100, int max = 500}) async {
    Future<Map<String, dynamic>> page(int n) => _get('$_api/rank/song?rankid=$rankId&page=$n&pagesize=$size&area_code=1&plat=2&version=9108');
    List<Song> songs(Map<String, dynamic> j) => [for (final x in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
    final first = await page(1);
    final out = songs(first);
    final total = math.min(max, ((first['data'] as Map?)?['total'] as num?)?.toInt() ?? 0);
    if (size < 100 || out.length >= total) return out;
    final rest = await Future.wait([for (var n = 2; (n - 1) * size < total; n++) page(n).then(songs).catchError((Object _) => <Song>[])]);
    final seen = {for (final s in out) s.id};
    for (final list in rest) {
      out.addAll(list.where((s) => seen.add(s.id)));
    }
    return out;
  }

  @override
  Future<PlaylistInfo> playlist(String id) async {
    if (id.startsWith('special:')) return _specialDetail(id.substring(8));
    if (id.startsWith('gcid:')) return _accountList(id.substring(5));
    final rankId = id.startsWith('rank:') ? id.substring(5) : id;
    if (!_rankNames.containsKey(rankId)) await charts().catchError((Object _) => <ChartInfo>[]);
    final songs = await _rank(rankId);
    return PlaylistInfo(
      id: 'rank:$rankId',
      sourceId: sourceId,
      name: _rankNames[rankId] ?? '酷狗榜单',
      cover: songs.firstOrNull?.coverUrl,
      creator: '酷狗音乐',
      trackCount: songs.length,
      kind: PlaylistKind.chart,
      tracks: songs,
    );
  }

  @override
  Future<PlaylistInfo> soaringChart() => playlist('rank:6666');

  @override
  Future<List<ChartInfo>> charts() async {
    final j = await _get('$_api/rank/list?version=9108&plat=0&showtype=2&parentid=0&apiver=6&area_code=1&withsong=0');
    final info = ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>();
    final out = <ChartInfo>[];
    for (final classify in _rankGroups.keys) {
      for (final r in info.where((r) => r['classify'] == classify)) {
        final id = '${r['rankid']}';
        _rankNames[id] = '${r['rankname']}';
        out.add(
          ChartInfo(
            id: 'rank:$id',
            name: '${r['rankname']}',
            cover: _cover(r['imgurl'] as String?),
            update: '${r['update_frequency'] ?? ''}'.trim().ifEmpty(null),
            group: _rankGroups[classify],
            preview: ['${r['intro'] ?? ''}'.trim()].where((t) => t.isNotEmpty).toList(),
          ),
        );
      }
    }
    return out;
  }

  @override
  Future<List<PlaylistCategory>> playlistCategories() async {
    final j = await _get('$_api/category/list?pid=0&apiver=2&plat=0');
    return [
      const PlaylistCategory(id: '0', name: '推荐'),
      for (final c in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>())
        PlaylistCategory(id: '${c['categoryid']}', name: '${c['categoryname']}', group: '分类'),
    ];
  }

  @override
  Future<List<PlaylistInfo>> categoryPlaylists(String categoryId, {int offset = 0, int limit = 30}) async {
    final j = await _get('$_api/category/special?categoryid=$categoryId&page=${offset ~/ limit + 1}&pagesize=$limit&withsong=0&sort=2&plat=2');
    return [for (final p in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>()) _special(p)];
  }

  @override
  Future<List<AlbumInfo>> newAlbums({int limit = 12}) async {
    final j = await _get('$_api/album/list?plat=0&page=1&pagesize=$limit&type=1');
    return [for (final a in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>()) _album(a)];
  }

  /// 推荐歌单：歌单广场按热度排序。
  @override
  Future<List<PlaylistInfo>> recommendPlaylists({int limit = 12}) => categoryPlaylists('0', limit: limit);

  Future<PlaylistInfo> _specialDetail(String specialId) async {
    final results = await Future.wait([
      _get('$_api/special/song?specialid=$specialId&page=1&pagesize=300&plat=2&version=9108'),
      _get('$_api/special/info?specialid=$specialId&plat=2').catchError((Object _) => <String, dynamic>{}),
    ]);
    final songs = [for (final x in ((results[0]['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
    final info = results[1]['data'] as Map? ?? const {};
    return PlaylistInfo(
      id: 'special:$specialId',
      sourceId: sourceId,
      name: '${info['specialname'] ?? '酷狗歌单'}',
      cover: _cover(info['imgurl'] as String?) ?? songs.firstOrNull?.coverUrl,
      creator: '${info['nickname'] ?? info['username'] ?? ''}',
      description: (info['intro'] as String?)?.trim(),
      playCount: (info['playcount'] as num?)?.toInt() ?? 0,
      trackCount: songs.length,
      tracks: songs,
    );
  }

  @override
  Future<HomeFeed> homeFeed() async {
    final results = await Future.wait([_rank('6666', size: 30), recommendPlaylists(limit: 12)]);
    return HomeFeed(daily: results[0] as List<Song>, playlists: results[1] as List<PlaylistInfo>);
  }

  // ── 专辑与歌手 ──────────────────────────────────────

  @override
  Future<AlbumInfo> album(String id) async {
    final r = await Future.wait([_get('$_api/album/info?albumid=$id&plat=0'), _get('$_api/album/song?albumid=$id&page=1&pagesize=200&plat=2&version=9108')]);
    final info = r[0]['data'] as Map? ?? const {};
    final songs = [for (final x in ((r[1]['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
    final a = _album({...info, 'albumid': id});
    return AlbumInfo(
      id: id,
      sourceId: sourceId,
      name: a.name,
      cover: a.cover ?? songs.firstOrNull?.coverUrl,
      artist: a.artist,
      publishTime: a.publishTime,
      description: a.description,
      songs: songs,
      size: songs.length,
    );
  }

  /// 歌曲里的歌手只有名字（id 为“kugou:名字”）：按名字搜索出歌手 id。
  Future<String> _singerId(String id) async {
    if (!id.startsWith('kugou:')) return id;
    final r = await search(id.substring(6), type: SearchType.artist, limit: 1);
    final found = r.artists.firstOrNull;
    if (found == null) throw Exception('没有找到这位歌手');
    return found.id;
  }

  @override
  Future<ArtistInfo> artist(String id) async {
    final singerId = await _singerId(id);
    final r = await Future.wait([
      _get('$_api/singer/info?singerid=$singerId&plat=0'),
      _get('$_api/singer/song?singerid=$singerId&page=1&pagesize=50&plat=2&version=9108'),
    ]);
    final info = r[0]['data'] as Map? ?? const {};
    final songs = [for (final x in ((r[1]['data'] as Map?)?['info'] as List? ?? const []).cast<Map<String, dynamic>>()) _song(x)];
    return ArtistInfo(
      id: singerId,
      sourceId: sourceId,
      name: '${info['singername'] ?? ''}',
      avatar: _cover(info['imgurl'] as String?),
      description: ((info['intro'] ?? info['profile']) as String?)?.trim(),
      hotSongs: songs,
    );
  }

  @override
  Future<List<AlbumInfo>> artistAlbums(String id, {int limit = 30}) async {
    final singerId = await _singerId(id);
    final j = await _get('$_api/singer/album?singerid=$singerId&page=1&pagesize=$limit&plat=0');
    return [for (final a in ((j['data'] as Map?)?['info'] as List? ?? const []).cast<Map>()) _album(a)];
  }

  // ── 评论 ──────────────────────────────────────────

  @override
  Future<CommentPage> comments(Song song, {CommentSort sort = CommentSort.recommend, int offset = 0}) async {
    final ids = _ids(song);
    // 推荐 / 热门：酷狗客户端的评论接口，按歌曲（album_audio_id）汇总所有版本的评论，可以一直向后翻。
    if (sort != CommentSort.latest && ids.audio.isNotEmpty && ids.audio != '0') {
      try {
        return await _appComments(ids.audio, offset);
      } catch (e) {
        debugPrint('kugou comments: $e');
      }
    }
    // 最新：按时间排列的评论（按歌曲文件 hash 查询）。
    const size = 20;
    final page = offset ~/ size + 1;
    final j = await _get(
      'https://mcomment.kugou.com/index.php?r=commentsv2/getCommentWithLike&code=fc4be23b4e972707f36b8a828a93ba8a&extdata=${ids.hash.toUpperCase()}&p=$page&pagesize=$size',
    );
    final latest = (j['list'] as List? ?? const []).whereType<Map>().toList();
    final total = (j['count'] as num?)?.toInt() ?? latest.length;
    return CommentPage(total: total, comments: [for (final c in latest) ?_comment(c)], hasMore: latest.isNotEmpty && page * size < total, next: page * size);
  }

  Future<CommentPage> _appComments(String mixId, int offset) async {
    const size = 30;
    final page = offset ~/ size + 1;
    final j = await _app(
      '/mcomment/v1/cmtlist',
      method: 'POST',
      query: {
        'ver': 6,
        'mixsongid': mixId,
        'need_show_image': 1,
        'p': page,
        'pagesize': size,
        'show_classify': 1,
        'show_hotword_list': 1,
        'extdata': '0',
        'code': 'fc4be23b4e972707f36b8a828a93ba8a',
      },
    );
    if ('${j['status']}' != '1') throw _KugouRefusal('${j['err_code'] ?? j['error_code'] ?? ''}', '${j['msg'] ?? j['message'] ?? ''}');
    final list = (j['list'] as List? ?? const []).whereType<Map>().toList();
    final total = (j['count'] as num?)?.toInt() ?? (j['combine_count'] as num?)?.toInt() ?? list.length;
    final maxPage = (j['maxPage'] as num?)?.toInt() ?? 1 << 20;
    return CommentPage(
      total: total,
      comments: [for (final c in list) ?_comment(c)],
      hasMore: list.isNotEmpty && page < maxPage && page * size < total,
      next: page * size,
    );
  }

  Comment? _comment(Map c) {
    final content = '${c['content'] ?? ''}'.trim();
    if (content.isEmpty) return null;
    return Comment(
      id: '${c['id']}',
      userName: '${c['user_name'] ?? ''}',
      avatar: (c['user_pic'] as String? ?? '').replaceFirst('http://', 'https://').ifEmpty(null),
      content: content,
      time: DateTime.tryParse('${c['addtime'] ?? ''}'.replaceFirst(' ', 'T')),
      location: '${c['location'] ?? ''}'.trim().ifEmpty(null),
      likedCount: ((c['like'] as Map?)?['likenum'] as num?)?.toInt() ?? 0,
      liked: (c['like'] as Map?)?['haslike'] == true,
      replyCount: (c['reply_num'] as num?)?.toInt() ?? 0,
      // 查询回复需要评论所属的专题与子专题（每条评论自带）。
      ref: c['special_id'] == null ? null : jsonEncode({'special_id': '${c['special_id']}', 'child': '${c['special_child_id'] ?? ''}', 'extdata': c['extdata'] is String ? c['extdata'] : jsonEncode(c['extdata'] ?? '0')}),
    );
  }

  @override
  Future<CommentPage> commentReplies(Song song, Comment parent, {int offset = 0}) async {
    final ref = parent.ref == null ? const <String, dynamic>{} : jsonDecode(parent.ref!) as Map<String, dynamic>;
    const size = 30;
    final page = offset ~/ size + 1;
    final j = await _app(
      '/mcomment/v1/hot_replylist',
      method: 'POST',
      query: {
        'mixsongid': _ids(song).audio,
        'special_id': ref['special_id'] ?? '',
        'tid': parent.id,
        'childrenid': ref['child'] ?? '',
        'extdata': ref['extdata'] ?? '0',
        'p': page,
        'pagesize': size,
        'need_show_image': 1,
        'code': 'fc4be23b4e972707f36b8a828a93ba8a',
      },
    );
    if ('${j['status']}' != '1') throw _KugouRefusal('${j['err_code'] ?? ''}', '${j['msg'] ?? j['message'] ?? ''}');
    final list = [for (final c in (j['list'] as List? ?? const []).whereType<Map>()) ?_comment(c)];
    final total = (j['comments_num'] as num?)?.toInt() ?? parent.replyCount;
    return CommentPage(total: total, comments: list, hasMore: list.isNotEmpty && page * size < total, next: page * size);
  }

  // ── 播放 ──────────────────────────────────────────

  /// 取到的播放地址保留 20 分钟：重新播放、拖动进度或重新载入同一首歌时不再请求播放接口。
  final _streams = <String, (StreamInfo, DateTime)>{};

  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async {
    final key = '${song.id}@${quality.name}';
    final cached = _streams[key];
    if (cached != null && DateTime.now().difference(cached.$2) < const Duration(minutes: 20)) return cached.$1;
    final info = await _resolve(song, quality);
    _streams.remove(key);
    _streams[key] = (info, DateTime.now());
    if (_streams.length > 200) _streams.remove(_streams.keys.first);
    return info;
  }

  /// 依次尝试：
  /// 1. 客户端播放接口（设备已注册，不需要人机验证；扫码登录后按账号会员权限给出完整地址与高音质）；
  /// 2. 移动版接口（免费歌曲的标准音质，不需要验证）；
  /// 3. 网页登录的账号：网页播放接口（按网页账号的会员权限取地址，酷狗可能要求人机验证）。
  /// 都只有试听片段时播放试听片段。
  Future<StreamInfo> _resolve(Song song, AudioQuality quality) async {
    final ids = _ids(song);
    if (ids.hash.isEmpty) throw Exception('这首歌缺少酷狗播放标识');
    final errors = <String>[];
    StreamInfo? trial;
    try {
      final info = await _appUrl(song, quality);
      if (!info.trial) return info;
      trial = info;
    } catch (e) {
      errors.add('$e'.replaceFirst('Exception: ', ''));
    }
    if (trial == null) {
      try {
        final info = await _mobileUrl(song);
        if (info != null) return info;
      } catch (e) {
        debugPrint('kugou mobile url: $e');
      }
    }
    if (_account != null && !_appAccount) {
      try {
        final info = await _webPlayInfo(song);
        if (!info.trial || trial == null) return info;
      } on SourceVerificationRequired {
        if (trial != null) return trial;
        rethrow;
      } catch (e) {
        errors.add('$e'.replaceFirst('Exception: ', ''));
      }
    }
    if (trial != null) return trial;
    if (song.fee == SongFee.paid) throw Exception('这首歌是酷狗的付费歌曲（单曲或数字专辑），需要在酷狗购买后播放');
    throw Exception(errors.isEmpty ? '酷狗没有返回这首歌的播放地址' : errors.first);
  }

  /// 客户端接口的音质参数，从高到低。
  static const _appQualities = [(AudioQuality.hires, 'high'), (AudioQuality.lossless, 'flac'), (AudioQuality.exhigh, '320'), (AudioQuality.standard, '128')];

  Future<StreamInfo> _appUrl(Song song, AudioQuality quality) async {
    final ids = _ids(song);
    final wanted = [
      for (final q in _appQualities)
        if (q.$1.index <= quality.index || q.$1 == AudioQuality.standard) q,
    ];
    var reregistered = false;
    var hasTrial = false;
    String? lastCode;
    String lastMessage = '';
    var i = 0;
    while (i < wanted.length) {
      final j = await _urlRequest(ids, wanted[i].$2);
      final info = _urlInfo(j, wanted[i].$1);
      if (info != null) return info;
      final code = '${j['errcode'] ?? j['error_code'] ?? j['err_code'] ?? ''}';
      // 20028：设备需要验证。重新注册一次设备后重试。
      if (code == '20028' && !reregistered) {
        reregistered = true;
        await _registerDevice(force: true);
        continue;
      }
      if (j['hash_offset'] is Map) hasTrial = true;
      if (code.isNotEmpty && code != '0') lastCode = code;
      lastMessage = '${j['error'] ?? j['msg'] ?? ''}'.trim();
      // 这一档音质没有权限或没有文件（status 为 2）：试下一档。
      i++;
    }
    if (hasTrial) {
      final j = await _urlRequest(ids, '128', freePart: true);
      final info = _urlInfo(j, AudioQuality.standard, trial: true, note: _trialNote);
      if (info != null) return info;
    }
    final why = [if (lastCode != null) '错误码 $lastCode', if (lastMessage.isNotEmpty) lastMessage].join('，');
    if (lastCode == '20028') throw Exception('酷狗要求验证本机设备（$why），请稍后重试');
    throw Exception(hasTrial || song.vip ? '这首歌需要酷狗 VIP（请用酷狗 App 扫码登录有会员的账号）' : '酷狗没有返回这首歌的播放地址${why.isEmpty ? '' : '（$why）'}');
  }

  Future<Map<String, dynamic>> _urlRequest(({String hash, String audio, String album}) ids, String quality, {bool freePart = false}) {
    final a = _appAccount ? _account : null;
    return _app(
      '/v5/url',
      router: 'trackercdn.kugou.com',
      query: {
        'album_id': int.tryParse(ids.album) ?? 0,
        'area_code': 1,
        'hash': ids.hash.toLowerCase(),
        'ssa_flag': 'is_fromtrack',
        'version': 11430,
        'page_id': _lite ? 967177915 : 151369488,
        'quality': quality,
        'album_audio_id': int.tryParse(ids.audio) ?? 0,
        'behavior': 'play',
        'pid': _lite ? 411 : 2,
        'cmd': 26,
        'pidversion': 3001,
        'IsFreePart': freePart ? 1 : 0,
        'ppage_id': _lite ? '356753938,823673182,967485191' : '463467626,350369493,788954147',
        'cdnBackup': 1,
        'module': '',
        'clientver': 11430,
        'key': md5.convert(utf8.encode('${ids.hash.toLowerCase()}${_lite ? '185672dd44712f60bb1736df5a377e82' : '57ae12eb6890223e355ccfcb74edf70d'}$_appId$_mid${a?['KugooID'] ?? 0}')).toString(),
      },
    );
  }

  static StreamInfo? _urlInfo(Map<String, dynamic> j, AudioQuality quality, {bool trial = false, String? note}) {
    if ('${j['status']}' != '1') return null;
    final urls = [
      for (final value in [j['url'], j['backupUrl']].expand((v) => v is List ? v : [v]))
        if (value is String && _validUrl(value) != null) _validUrl(value)!,
    ];
    if (urls.isEmpty) return null;
    final ext = '${j['extName'] ?? ''}'.toLowerCase();
    final transParam = j['trans_param'] is Map ? j['trans_param'] as Map : const {};
    return StreamInfo(
      url: urls.firstWhere((u) => u.startsWith('https://'), orElse: () => urls.first),
      quality: ext == 'flac' && quality.index < AudioQuality.lossless.index ? AudioQuality.lossless : quality,
      trial: trial,
      note: note,
      headers: const {'User-Agent': _appUa},
      cover: _cover(transParam['union_cover'] as String?),
      // volume_peak：这个文件的峰值（线性）。
      peak: (j['volume_peak'] as num?)?.toDouble(),
    );
  }

  static String? _validUrl(String value) {
    final url = Uri.tryParse(value.trim());
    if (url == null || (url.scheme != 'http' && url.scheme != 'https') || url.host.isEmpty || url.userInfo.isNotEmpty) return null;
    return url.toString();
  }

  /// 移动版接口：免费歌曲给出标准音质的完整地址，不需要设备验证；会员歌曲返回“需要付费”。
  Future<StreamInfo?> _mobileUrl(Song song) async {
    final j = await _get('https://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash=${_ids(song).hash}');
    if ('${j['status']}' != '1') return null;
    final url = _validUrl('${j['url'] ?? ''}') ?? [for (final u in (j['backup_url'] is List ? j['backup_url'] as List : const [])) _validUrl('$u')].nonNulls.firstOrNull;
    if (url == null) return null;
    final bitrate = int.tryParse('${j['bitRate'] ?? 0}') ?? 0;
    return StreamInfo(
      url: url,
      quality: '${j['extName']}'.toLowerCase() == 'flac' ? AudioQuality.lossless : (bitrate >= 320 ? AudioQuality.exhigh : AudioQuality.standard),
      cover: _cover(j['album_img'] as String?),
    );
  }

  /// 列表里没有封面的歌曲：移动版歌曲信息中的专辑封面（没有时用歌手照片）。
  @override
  Future<String?> songCover(Song song) async {
    final hash = _ids(song).hash;
    if (hash.isEmpty) return null;
    final j = await _get('https://m.kugou.com/app/i/getSongInfo.php?cmd=playInfo&hash=$hash');
    return _cover('${j['album_img'] ?? ''}'.ifEmpty(null) ?? '${j['imgUrl'] ?? ''}'.ifEmpty(null));
  }

  Future<StreamInfo> _webPlayInfo(Song song) async {
    const key = 'NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt';
    final ids = _ids(song);
    if (ids.hash.isEmpty) throw Exception('这首歌缺少酷狗播放标识');
    final mid = _account?['_mid'] ?? _deviceId;
    final dfid = _account?['_dfid'] ?? '-';
    final params = <String, String>{
      'srcappid': '2919',
      'clientver': '20000',
      'clienttime': '${DateTime.now().millisecondsSinceEpoch}',
      'mid': mid,
      'uuid': mid,
      'dfid': dfid,
      'appid': '1014',
      'platid': '4',
      'hash': ids.hash,
      'album_id': ids.album.isEmpty ? '0' : ids.album,
      'album_audio_id': ids.audio,
      'token': _account?['t'] ?? '',
      'userid': _account?['KugooID'] ?? '0',
    };
    final keys = params.keys.toList()..sort();
    params['signature'] = md5.convert(utf8.encode('$key${keys.map((k) => '$k=${params[k]}').join()}$key')).toString();
    final res = await _dio.get<String>(
      'https://wwwapi.kugou.com/play/songinfo',
      queryParameters: params,
      options: Options(
        headers: {
          'Cookie': 'kg_mid=$mid; kg_dfid=$dfid${_account == null ? '' : '; KuGoo=${_account!['_raw'] ?? ''}'}',
          'User-Agent': 'Mozilla/5.0',
          'Referer': 'https://www.kugou.com/',
        },
        receiveTimeout: const Duration(seconds: 6),
      ),
    );
    final j = (await decodeJson(res.data)) as Map<String, dynamic>;
    final data = j['data'];
    final code = j['err_code'] ?? j['error_code'] ?? j['errcode'];
    if ('$code' == '30020' && data is Map) {
      if ('${data['is_publish']}' == '0' || '${data['privilege']}' == '5') {
        throw Exception('酷狗暂不允许播放这首歌（错误码 30020），请在酷狗官方客户端查看歌曲状态');
      }
      final event = '${data['SSA-CODE'] ?? res.headers.value('SSA-CODE') ?? ''}';
      final challengeMid = '${data['SSA-HMID'] ?? res.headers.value('SSA-HMID') ?? mid}';
      if (event.isNotEmpty) {
        final songUrl = Uri.https('www.kugou.com', '/song/', {'hash': ids.hash, 'album_id': ids.album, 'album_audio_id': ids.audio}).toString();
        final fragment = '/index/${[event, '1014', songUrl, challengeMid].map(Uri.encodeComponent).join('/')}';
        throw SourceVerificationRequired(
          message: '酷狗要求人机验证（错误码 30020）。请打开官方验证页完成验证，返回后重新点播放；若仍失败，请在酷狗官网播放一次并重新导入完整 Cookie（含 kg_mid、kg_dfid）。',
          url: Uri.parse('https://h5.kugou.com/apps/verify-h5/dist/').replace(fragment: fragment),
        );
      }
    }
    if (data is Map && '${j['status']}' == '1') {
      final candidates = [data['play_url'], data['play_backup_url']].expand((value) => value is List ? value : [value]);
      for (final value in candidates) {
        final url = value is String ? Uri.tryParse(value.trim()) : null;
        if (url == null || (url.scheme != 'http' && url.scheme != 'https') || url.host.isEmpty || url.userInfo.isNotEmpty) continue;
        var bitrate = int.tryParse('${data['bitrate'] ?? 0}') ?? 0;
        if (bitrate > 1000) bitrate ~/= 1000;
        final lossless = url.path.toLowerCase().endsWith('.flac') || '${data['extname']}'.toLowerCase() == 'flac';
        return StreamInfo(
          url: url.toString(),
          quality: lossless
              ? AudioQuality.lossless
              : bitrate >= 320
              ? AudioQuality.exhigh
              : bitrate >= 192
              ? AudioQuality.higher
              : AudioQuality.standard,
          trial: data['is_free_part'] == true || '${data['is_free_part']}' == '1',
          headers: const {'User-Agent': 'Mozilla/5.0', 'Referer': 'https://www.kugou.com/'},
        );
      }
    }
    final msg = '${j['error'] ?? j['err_msg'] ?? j['msg'] ?? ''}'.trim();
    final refusal = [if (code != null) '错误码 $code', if (msg.isNotEmpty) msg].join('，');
    throw Exception('酷狗没有返回这首歌的播放地址${refusal.isEmpty ? '' : '（$refusal）'}');
  }

  // ── 歌词 ──────────────────────────────────────────

  @override
  Future<Lyrics> lyrics(Song song) async {
    final ids = _ids(song);
    try {
      final c = await _get(
        'https://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration=${song.duration.inMilliseconds}&hash=${ids.hash}&album_audio_id=${ids.audio}',
      );
      final candidates = (c['candidates'] as List? ?? const []).cast<Map<String, dynamic>>();
      if (candidates.isNotEmpty) {
        final first = candidates.first;
        final d = await _get('https://lyrics.kugou.com/download?ver=1&client=pc&id=${first['id']}&accesskey=${first['accesskey']}&fmt=lrc&charset=utf8');
        final content = d['content'] as String?;
        if (content != null && content.isNotEmpty) {
          final text = decodeText(base64.decode(content));
          final ly = parseLrc(text);
          if (ly.lines.isNotEmpty) return ly;
        }
      }
    } catch (e) {
      debugPrint('kugou lyrics: $e');
    }
    // 酷狗没有歌词时用网易云同一首歌的歌词（含翻译）。
    return Lyrics.empty;
  }
}

extension on String {
  String? ifEmpty(String? other) => isEmpty ? other : this;
}

/// 酷狗账号接口拒绝了请求（错误码与原因）。
class _KugouRefusal implements Exception {
  const _KugouRefusal(this.code, this.message);

  final String? code;
  final String message;
}
