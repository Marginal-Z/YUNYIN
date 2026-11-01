import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('QQ 账号数据：歌单（含“我喜欢”与收藏）、我喜欢的歌曲、收藏的专辑、关注的歌手与会员', () async {
    SharedPreferences.setMockInitialValues({
      'qq.account': jsonEncode({'uin': '42', 'key': 'k', 'nickname': '测试用户', 'euin': 'enc42'}),
    });
    final params = <String, Map>{};
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (o, h) {
            final req = (jsonDecode(o.data as String) as Map)['req'] as Map;
            params['${req['method']}'] = req['param'] as Map;
            final data = switch (req['method']) {
              'GetPlaylistByUin' => {
                'v_playlist': [
                  {'tid': 0, 'dirId': 201, 'dirName': '我喜欢', 'songNum': 2},
                  {'tid': 77, 'dirId': 3, 'dirName': '自建歌单', 'songNum': 5, 'picUrl': 'http://y.gtimg.cn/a.jpg'},
                ],
              },
              'CgiGetPlaylistFavInfo' => {
                'v_list': [
                  {'tid': 88, 'name': '收藏的歌单', 'nickname': '别人', 'songnum': 9},
                ],
              },
              'CgiGetDiss' => {
                'songlist': [
                  {'mid': 'm1', 'name': '歌一', 'file': {'media_mid': 'f1'}},
                  {'mid': 'm2', 'name': '歌二'},
                ],
              },
              'CgiGetAlbumFavInfo' => {
                'v_list': [
                  {'albummid': 'al1', 'albumname': '专辑', 'v_singer': [{'mid': 's1', 'name': '歌手'}]},
                ],
              },
              'GetFollowSingerList' => {
                'List': [
                  {'MID': 's9', 'Name': '关注的歌手', 'AvatarUrl': 'http://y.gtimg.cn/s9.jpg'},
                ],
              },
              'vip_login_base' => {
                'identity': {'vip': 1, 'HugeVip': 1, 'level': 6, 'HugeVipEnd': '2027-03-04'},
                'svip': 0,
              },
              _ => <String, Object>{},
            };
            h.resolve(Response(requestOptions: o, statusCode: 200, data: jsonEncode({'code': 0, 'req': {'code': 0, 'data': data}})));
          },
        ),
      );
    final qq = QQMusicSource(dio: dio);
    await qq.init();

    final lists = await qq.userPlaylists();
    expect(lists.map((l) => l.name), ['我喜欢的音乐', '自建歌单', '收藏的歌单']);
    expect(lists.first.id, 'fav:201');
    expect(lists.first.isLikedList, isTrue);
    expect(lists[1].ownedByMe, isTrue);
    expect(lists[1].cover, 'https://y.gtimg.cn/a.jpg');
    expect(lists[2].ownedByMe, isFalse);
    expect(params['GetPlaylistByUin']!['uin'], '42');
    expect(params['CgiGetPlaylistFavInfo']!['uin'], 'enc42');

    final liked = await qq.playlist('fav:201');
    expect(liked.isLikedList, isTrue);
    expect(liked.tracks!.map((s) => s.name), ['歌一', '歌二']);
    expect(params['CgiGetDiss']!['dirid'], 201);
    expect(await qq.likedSongIds(), hasLength(2));

    final albums = await qq.subscribedAlbums();
    expect(albums.single.name, '专辑');
    expect(albums.single.artist?.name, '歌手');

    final artists = await qq.followedArtists();
    expect(artists.single.name, '关注的歌手');
    expect(artists.single.followed, isTrue);

    final vip = await qq.membership();
    expect(vip?.active, isTrue);
    expect(vip?.title, '豪华绿钻');
    expect(vip?.level, 'Lv.6');
    expect(vip?.expires, DateTime(2027, 3, 4));
    dio.close();
  });
}
