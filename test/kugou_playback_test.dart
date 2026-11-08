import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/music_source.dart';

/// 按接口路径模拟酷狗的返回；设备注册返回明文错误（注册失败，使用“-”）。
Dio _dio(Map<String, Object? Function(RequestOptions o)> routes, {List<RequestOptions>? log}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        log?.add(o);
        final route = routes[o.uri.path];
        final body = route == null ? {'status': 0, 'error_code': 404} : route(o);
        final data = jsonEncode(body);
        h.resolve(Response(requestOptions: o, statusCode: 200, data: o.responseType == ResponseType.bytes ? utf8.encode(data) : data));
      },
    ),
  );
  return dio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const song = Song(id: 'abc123:556677:998', sourceId: 'kugou', name: '测试歌曲');

  test('客户端接口：按音质从高到低取地址，请求带签名、设备与播放 key', () async {
    final log = <RequestOptions>[];
    final dio = _dio({
      '/risk/v3/r_register_dev': (_) => {'status': 0, 'error_code': 20010, 'data': 'rsa failure'},
      '/v5/url': (o) => o.queryParameters['quality'] == '320'
          ? {'status': 1, 'url': ['http://fs.example/a.mp3'], 'backupUrl': ['https://fs.example/a.mp3'], 'extName': 'mp3', 'bitRate': 320000}
          : {'status': 2, 'fail_process': ['pkg']},
    }, log: log);
    final kg = KugouSource(dio: dio);
    await kg.init();
    final info = await kg.stream(song, AudioQuality.lossless);
    expect(info.url, 'https://fs.example/a.mp3', reason: '优先使用 https 地址');
    expect(info.quality, AudioQuality.exhigh);
    expect(info.trial, isFalse);
    final urls = log.where((o) => o.uri.path == '/v5/url').toList();
    expect([for (final o in urls) o.queryParameters['quality']], ['flac', '320']);
    final q = urls.last.queryParameters;
    expect(q['hash'], 'abc123');
    expect(q['album_audio_id'], '556677');
    expect(q['appid'], '1005');
    expect(q['key'], hasLength(32));
    expect(q['signature'], hasLength(32));
    expect(urls.last.headers['x-router'], 'trackercdn.kugou.com');
    // 同一首歌 20 分钟内不再请求。
    await kg.stream(song, AudioQuality.lossless);
    expect(log.where((o) => o.uri.path == '/v5/url').length, 2);
    dio.close();
  });

  test('酷狗概念版：扫码选概念版得到概念版账号；之后的请求用概念版的 appid、签名、设备与播放参数', () async {
    SharedPreferences.setMockInitialValues({'kugou.guid': 'guid-test', 'kugou.dfid': 'dfid-std', 'kugou.dfid.lite': 'dfid-lite'});
    final log = <RequestOptions>[];
    final dio = _dio({
      '/v2/qrcode': (_) => {'status': 1, 'data': {'qrcode': 'qr-key'}},
      '/v2/get_userinfo_qrcode': (_) => {'status': 1, 'data': {'status': 4, 'token': 'lite-token', 'userid': 42, 'nickname': '概念'}},
      '/risk/v3/r_register_dev': (_) => {'status': 0, 'error_code': 20010, 'data': 'rsa failure'},
      '/v5/url': (_) => {'status': 1, 'url': ['https://fs.example/a.mp3'], 'extName': 'mp3', 'bitRate': 128000},
    }, log: log);
    final kg = KugouSource(dio: dio);
    await kg.init();
    kg.loginLite = true;
    final ticket = await kg.createQrLogin();
    expect(ticket.app, '酷狗概念版 App');
    expect(log.last.queryParameters['qrcode_txt'], contains('appid=3116'));
    expect(await kg.checkQrLogin(ticket), QrState.confirmed);
    expect(log.last.queryParameters['appid'], '3116');
    expect(kg.isLiteAccount, isTrue);
    await kg.stream(song, AudioQuality.standard);
    final q = Map<String, String>.from(log.lastWhere((o) => o.uri.path == '/v5/url').queryParameters.map((k, v) => MapEntry(k, '$v')));
    expect(q['appid'], '3116');
    expect(q['page_id'], '967177915');
    expect(q['pid'], '411');
    expect(q['ppage_id'], '356753938,823673182,967485191');
    expect(q['token'], 'lite-token');
    // 登录后按新账号重新注册设备（这里模拟注册失败），注册请求也用概念版客户端。
    expect(log.firstWhere((o) => o.uri.path == '/risk/v3/r_register_dev').queryParameters['appid'], '3116');
    final mid = BigInt.parse(md5.convert(utf8.encode('guid-test')).toString(), radix: 16).toString();
    expect(q['key'], md5.convert(utf8.encode('abc123185672dd44712f60bb1736df5a377e823116${mid}42')).toString());
    final sig = q.remove('signature');
    final keys = q.keys.toList()..sort();
    const salt = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';
    expect(sig, md5.convert(utf8.encode('$salt${keys.map((k) => '$k=${q[k]}').join()}$salt')).toString());
    dio.close();
  });

  test('会员歌曲没有权限时取官方试听片段', () async {
    final log = <RequestOptions>[];
    final dio = _dio({
      '/v5/url': (o) => o.queryParameters['IsFreePart'] == '1'
          ? {'status': 1, 'url': ['https://fs.example/trial.mp3'], 'extName': 'mp3'}
          : {
              'status': 2,
              'fail_process': ['pkg', 'buy'],
              'hash_offset': {'end_ms': 60000},
            },
    }, log: log);
    final info = await KugouSource(dio: dio).stream(const Song(id: 'h:1:2', sourceId: 'kugou', name: 'VIP', fee: SongFee.vip), AudioQuality.exhigh);
    expect(info.url, 'https://fs.example/trial.mp3');
    expect(info.trial, isTrue);
    dio.close();
  });

  test('20028 要求验证设备：重新注册设备后重试；仍不行时免费歌曲改用移动版接口', () async {
    var registrations = 0;
    final dio = _dio({
      '/risk/v3/r_register_dev': (_) {
        registrations++;
        return {'status': 0, 'error_code': 20010};
      },
      '/v5/url': (_) => {'status': 2, 'errcode': 20028, 'error': '本次请求需要验证'},
      '/app/i/getSongInfo.php': (_) => {'status': 1, 'url': 'https://m.example/free.mp3', 'bitRate': 128, 'extName': 'mp3', 'album_img': 'http://img.example/{size}/a.jpg'},
    });
    final info = await KugouSource(dio: dio).stream(song, AudioQuality.exhigh);
    expect(info.url, 'https://m.example/free.mp3');
    expect(info.cover, 'https://img.example/400/a.jpg');
    expect(registrations, greaterThanOrEqualTo(1));
    dio.close();
  });

  test('网页登录的账号：客户端接口与移动版都取不到时用网页接口，30020 打开官方验证页', () async {
    final dio = _dio({
      '/v5/url': (_) => {'status': 2, 'fail_process': ['pkg']},
      '/app/i/getSongInfo.php': (_) => {'status': 0, 'error': '需要付费'},
      '/play/songinfo': (_) => {
        'status': 0,
        'err_code': 30020,
        'data': {'SSA-CODE': 'event/+?test', 'SSA-HMID': 'challenge-mid', 'is_publish': 1, 'privilege': 0},
      },
    });
    final kg = KugouSource(dio: dio);
    await kg.loginWithCookie('kg_mid=device-mid; kg_dfid=device-dfid; KuGoo=KugooID=123&t=token-test');
    await expectLater(
      kg.stream(song, AudioQuality.standard),
      throwsA(isA<SourceVerificationRequired>().having((e) => e.url.host, 'host', 'h5.kugou.com')),
    );
    dio.close();
  });

  test('付费歌曲取不到地址时说明需要购买', () async {
    final dio = _dio({
      '/v5/url': (_) => {'status': 2, 'fail_process': ['buy']},
      '/app/i/getSongInfo.php': (_) => {'status': 0},
    });
    await expectLater(
      KugouSource(dio: dio).stream(const Song(id: 'h:1:2', sourceId: 'kugou', name: '付费', fee: SongFee.paid), AudioQuality.standard),
      throwsA(predicate((e) => '$e'.contains('付费歌曲'))),
    );
    dio.close();
  });

  test('酷狗的付费规则：音乐包内为 VIP，单独购买为付费，privilege 8 免费', () {
    expect(KugouSource.kugouFee({'privilege': 10, 'pay_type': 3, 'pkg_price': 1}), SongFee.vip);
    expect(KugouSource.kugouFee({'privilege': 10, 'pay_type': 2, 'pkg_price': 0}), SongFee.paid);
    expect(
      KugouSource.kugouFee({
        'privilege': 10,
        'pay_type': 0,
        'trans_param': {'musicpack_advance': 1},
      }),
      SongFee.vip,
    );
    expect(KugouSource.kugouFee({'privilege': 8, 'pay_type': 3}), SongFee.free);
    expect(KugouSource.kugouFee({'privilege': 0}), SongFee.free);
  });

  test('评论：推荐评论按 album_audio_id 汇总，按页码翻页', () async {
    final pages = <String>[];
    final dio = _dio({
      '/mcomment/v1/cmtlist': (o) {
        pages.add('${o.queryParameters['p']}');
        return {
          'status': 1,
          'count': 100,
          'maxPage': 4,
          'list': [
            for (var i = 0; i < 30; i++)
              {
                'id': '${o.queryParameters['p']}-$i',
                'user_name': 'u',
                'content': i == 0 ? '' : '评论 $i',
                'addtime': '2026-01-01 10:00:00',
                'like': {'likenum': 3, 'haslike': false},
                'location': '上海',
              },
          ],
        };
      },
    });
    final kg = KugouSource(dio: dio);
    final first = await kg.comments(song);
    expect(first.comments.length, 29, reason: '空评论被跳过');
    expect(first.next, 30, reason: '下一页按页码计算，不受跳过的评论影响');
    expect(first.comments.first.location, '上海');
    final second = await kg.comments(song, offset: first.next!);
    expect(second.comments.first.id, '2-1');
    expect(pages, ['1', '2']);
    dio.close();
  });

  test('评论回复：带评论所属的专题参数请求楼层回复，按页码翻页', () async {
    final queries = <Map<String, dynamic>>[];
    final dio = _dio({
      '/mcomment/v1/cmtlist': (o) => {
        'status': 1,
        'count': 1,
        'list': [
          {'id': '99', 'user_name': 'u', 'content': '原评论', 'reply_num': 40, 'special_id': 2364, 'special_child_id': 20505418, 'extdata': '{"a":1}'},
        ],
      },
      '/mcomment/v1/hot_replylist': (o) {
        queries.add(Map<String, dynamic>.from(o.queryParameters));
        return {
          'status': 1,
          'comments_num': 40,
          'list': [
            for (var i = 0; i < 30; i++) {'id': 'r${o.queryParameters['p']}-$i', 'user_name': 'r', 'content': '回复 $i//@u:原评论'},
          ],
        };
      },
    });
    final kg = KugouSource(dio: dio);
    final parent = (await kg.comments(song)).comments.single;
    expect(parent.replyCount, 40);
    final first = await kg.commentReplies(song, parent);
    expect(first.total, 40);
    expect(first.comments, hasLength(30));
    expect(first.hasMore, isTrue);
    expect(queries.first['tid'], '99');
    expect(queries.first['special_id'], '2364');
    expect(queries.first['childrenid'], '20505418');
    final second = await kg.commentReplies(song, parent, offset: first.next!);
    expect(second.comments.first.id, 'r2-0');
    expect(second.hasMore, isFalse);
    dio.close();
  });
}
