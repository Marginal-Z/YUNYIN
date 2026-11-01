import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/sources/music_source.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';

void main() {
  const cookie =
      'kg_mid=abc; kg_dfid=xyz; KuGoo=KugooID=123456789&KugooPwd=ABCDEF&NickName=%u4e91%u97f3%u7528%u6237&Pic=http://imge.kugou.com/kugouicon/165/a.jpg&RegState=1&RegFrom=&t=tok123&a_id=1014&ct=1700000000&UserName=%u4e91%u97f3; kg_mid_temp=1';

  test('解析酷狗 KuGoo Cookie（整段 Cookie 或只有 KuGoo 的值）', () {
    final a = KugouSource.parseKugooCookie(cookie)!;
    expect(a['KugooID'], '123456789');
    expect(a['t'], 'tok123');
    expect(a['NickName'], '云音用户');
    expect(a['_raw'], startsWith('KugooID=123456789&'));
    expect(a['_mid'], 'abc');
    expect(a['_dfid'], 'xyz');
    expect(KugouSource.parseKugooCookie('KugooID=1&t=x&NickName=a')!['KugooID'], '1');
    expect(KugouSource.parseKugooCookie('kg_mid=abc'), isNull, reason: '没有登录信息');
    expect(KugouSource.parseKugooCookie('KuGoo=KugooID=0&t='), isNull, reason: '未登录的游客 Cookie');
    expect(KugouSource.parseKugooCookie('KuGoo=KugooID=1&t=x\r\nOther: invalid'), isNull);
  });

  test('Cookie 登录后保存账号，重新启动仍为登录状态，退出后清除', () async {
    SharedPreferences.setMockInitialValues({});
    final kg = KugouSource();
    await kg.loginWithCookie(cookie);
    expect(kg.user?.nickname, '云音用户');
    expect(kg.user?.avatar, startsWith('https://'));
    final offline = Dio()..interceptors.add(InterceptorsWrapper(onRequest: (o, h) => h.reject(DioException(requestOptions: o))));
    final again = KugouSource(dio: offline);
    await again.init();
    expect(again.loggedIn, isTrue);
    expect((await again.membership())?.title, '已登录', reason: '查不到会员信息时仍显示已登录');
    await again.logout();
    final third = KugouSource();
    await third.init();
    expect(third.loggedIn, isFalse);
    await expectLater(kg.loginWithCookie('kg_mid=1'), throwsA(isA<Exception>()));
  });

  test('酷狗账号数据：歌单（含“我喜欢”与收藏）、歌单歌曲、关注的歌手与会员', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <RequestOptions>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            requests.add(o);
            final data = switch (o.uri.path) {
              '/v7/get_all_list' => {
                'info': [
                  {'name': '自建歌单', 'list_create_userid': 123456789, 'list_create_gid': 'collection_3_1_1_0', 'count': 3, 'pic': 'http://p.kugou.com/{size}/a.jpg'},
                  {'name': '我喜欢', 'list_create_userid': 123456789, 'global_collection_id': 'collection_3_1_2_0', 'count': 1},
                  {'name': '别人的歌单', 'list_create_userid': 42, 'list_create_username': '别人', 'global_collection_id': 'collection_3_42_5_0', 'count': 9},
                  {
                    'name': '一张专辑',
                    'list_create_userid': 42,
                    'album_id': 777,
                    'global_collection_id': 'collection_x',
                    'authors': [
                      {'author_name': '歌手'},
                    ],
                  },
                ],
              },
              '/pubsongs/v2/get_other_list_file_nofilt' => {
                'songs': [
                  {
                    'hash': 'ABC',
                    'name': '歌手 - 歌名',
                    'add_mixsongid': 9,
                    'albuminfo': {'id': 8, 'name': '专辑'},
                    'timelen': 200000,
                    'privilege': 10,
                  },
                ],
              },
              '/v4/follow_list' => {
                'lists': [
                  {'singerid': 55, 'nickname': '关注的歌手', 'pic': 'http://x/100/a.jpg'},
                  {'singerid': 0, 'nickname': '普通用户'},
                ],
              },
              '/v1/get_union_vip' => {
                'busi_vip': [
                  {'is_vip': 0, 'product_type': 'tvip'},
                  {'is_vip': 1, 'product_type': 'svip', 'vip_end_time': '2027-01-02 00:00:00'},
                ],
              },
              _ => <String, Object>{},
            };
            h.resolve(Response(requestOptions: o, statusCode: 200, data: jsonEncode({'status': 1, 'data': data})));
          },
        ),
      );
    final kg = KugouSource(dio: dio);
    await kg.loginWithCookie(cookie);
    expect(kg.supports(SourceFeature.userPlaylists), isTrue);

    final lists = await kg.userPlaylists();
    expect(lists.map((l) => l.name), ['我喜欢的音乐', '自建歌单', '别人的歌单']);
    expect(lists.first.isLikedList, isTrue);
    expect(lists[1].ownedByMe, isTrue);
    expect(lists[1].cover, 'https://p.kugou.com/400/a.jpg');
    expect(lists[2].ownedByMe, isFalse);
    final list = requests.firstWhere((r) => r.uri.path == '/v7/get_all_list');
    expect(list.queryParameters['token'], 'tok123');
    expect(list.queryParameters['signature'], hasLength(32));
    expect(list.headers['x-router'], 'cloudlist.service.kugou.com');

    final liked = await kg.playlist(lists.first.id);
    expect(liked.isLikedList, isTrue);
    expect(liked.tracks!.single.name, '歌名');
    expect(liked.tracks!.single.artists.single.name, '歌手');
    expect(liked.tracks!.single.id, 'abc:9:8');
    expect(liked.tracks!.single.duration, const Duration(seconds: 200));
    expect(liked.tracks!.single.vip, isTrue);
    expect(await kg.likedSongIds(), {'abc:9:8'});

    final albums = await kg.subscribedAlbums();
    expect(albums.single.id, '777');
    expect(albums.single.artist?.name, '歌手');

    final artists = await kg.followedArtists();
    expect(artists.single.name, '关注的歌手');
    expect(artists.single.avatar, 'https://x/480/a.jpg');
    final follow = requests.firstWhere((r) => r.uri.path == '/v4/follow_list');
    expect((jsonDecode(follow.data as String) as Map)['p'], matches(RegExp(r'^[0-9A-F]{256}$')));

    final vip = await kg.membership();
    expect(vip?.active, isTrue);
    expect(vip?.title, '豪华 VIP');
    expect(vip?.expires, DateTime(2027, 1, 2));
    dio.close();
  });
}
