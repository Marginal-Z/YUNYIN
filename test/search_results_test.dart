import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:yunyin/core/data_cache.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/music_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/common/layout.dart';
import 'package:yunyin/features/search/search_result_page.dart';
import 'package:yunyin/features/shell/nav.dart';
import 'package:yunyin/player/player_controller.dart';

class _SearchSource extends MusicSource {
  _SearchSource(this.result);
  final SearchResult result;
  @override
  String get id => 'test';
  @override
  String get name => '测试';
  @override
  String get description => '';
  @override
  Set<SourceFeature> get features => const {};
  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) async => const StreamInfo();
  @override
  Future<SearchResult> search(String keyword, {SearchType type = SearchType.all, int offset = 0, int limit = 30}) async => result;
}

void main() {
  setUp(DataCache.clear);
  final results = <(String, SearchResult)>[
    (
      '返回的专辑',
      const SearchResult(
        albums: [AlbumInfo(id: 'album', sourceId: 'test', name: '返回的专辑')],
      ),
    ),
    (
      '返回的歌手',
      const SearchResult(
        artists: [ArtistInfo(id: 'artist', sourceId: 'test', name: '返回的歌手')],
      ),
    ),
    (
      '返回的歌单',
      const SearchResult(
        playlists: [PlaylistInfo(id: 'playlist', sourceId: 'test', name: '返回的歌单')],
      ),
    ),
  ];
  for (final desktop in [false, true]) {
    for (final (name, result) in results) {
      testWidgets('综合搜索保留部分成功结果：$name，desktop=$desktop', (tester) async {
        tester.view.physicalSize = Size(desktop ? 1200 : 390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final settings = AppSettings();
        final sources = SourceManager([_SearchSource(result)]);
        final player = PlayerController(sources, settings);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider.value(value: sources),
              ChangeNotifierProvider.value(value: player),
              ChangeNotifierProvider(create: (_) => AppNav()),
            ],
            child: PaletteScope(
              palette: Palette.light(AccentColor.red),
              child: MaterialApp(
                home: LayoutScope(
                  desktop: desktop,
                  child: Material(child: SearchResultPage(route: SearchResultRoute('关键词'))),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text(name), findsWidgets);
        expect(find.text('没有找到“关键词”'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        player.dispose();
        sources.dispose();
        settings.dispose();
      });
    }
  }
}
