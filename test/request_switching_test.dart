import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yunyin/core/data_cache.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/music_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/comments/comments_page.dart';
import 'package:yunyin/features/discover/discover_page.dart';

class _Source extends MusicSource {
  final commentsPending = <CommentSort, Completer<CommentPage>>{};
  final playlistsPending = <String, Completer<List<PlaylistInfo>>>{};
  @override
  String get id => 'test';
  @override
  String get name => 'test';
  @override
  String get description => '';
  @override
  Set<SourceFeature> get features => const {};
  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async => const StreamInfo();
  @override
  Future<CommentPage> comments(Song song, {CommentSort sort = CommentSort.recommend, int offset = 0}) =>
      (commentsPending[sort] = Completer<CommentPage>()).future;
  @override
  Future<List<PlaylistCategory>> playlistCategories() async => const [
    PlaylistCategory(id: 'first', name: '分类一'),
    PlaylistCategory(id: 'second', name: '分类二', group: '风格'),
  ];
  @override
  Future<List<PlaylistInfo>> categoryPlaylists(String categoryId, {int offset = 0, int limit = 30}) =>
      (playlistsPending[categoryId] = Completer<List<PlaylistInfo>>()).future;
}

void main() {
  setUp(DataCache.clear);

  Future<void> pump(WidgetTester tester, _Source source, Widget page) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: SourceManager([source])),
          ChangeNotifierProvider(create: (_) => AppSettings()),
        ],
        child: PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: MaterialApp(home: Material(child: page)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  testWidgets('评论请求未结束时切换排序，旧结果不会覆盖新结果', (tester) async {
    final source = _Source();
    await pump(
      tester,
      source,
      const CommentsPage(
        song: Song(id: '1', sourceId: 'test', name: '歌曲'),
      ),
    );
    expect(source.commentsPending, contains(CommentSort.recommend));
    await tester.tap(find.text('最新'));
    await tester.pump();
    expect(source.commentsPending, contains(CommentSort.latest));
    source.commentsPending[CommentSort.latest]!.complete(
      const CommentPage(
        total: 1,
        comments: [Comment(id: 'new', userName: '用户', content: '最新评论')],
      ),
    );
    await tester.pump();
    source.commentsPending[CommentSort.recommend]!.complete(
      const CommentPage(
        total: 1,
        comments: [Comment(id: 'old', userName: '用户', content: '旧的推荐')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('最新评论'), findsOneWidget);
    expect(find.text('旧的推荐'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('歌单分类加载期间切换分类，新分类会正常请求', (tester) async {
    final source = _Source();
    await pump(tester, source, const SingleChildScrollView(child: PlaylistPlaza()));
    expect(source.playlistsPending, contains('first'));
    await tester.tap(find.text('分类二'));
    await tester.pump();
    expect(source.playlistsPending, contains('second'));
    source.playlistsPending['second']!.complete(const [PlaylistInfo(id: 'new', sourceId: 'test', name: '新分类歌单')]);
    await tester.pump();
    source.playlistsPending['first']!.complete(const [PlaylistInfo(id: 'old', sourceId: 'test', name: '旧分类歌单')]);
    await tester.pumpAndSettle();
    expect(find.text('新分类歌单'), findsOneWidget);
    expect(find.text('旧分类歌单'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
