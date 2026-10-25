import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/downloads.dart';
import '../../data/local_library.dart';
import '../../data/sources/local/local_source.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../../data/sources/source_manager.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../common/song_row.dart';
import '../library/local_import.dart';
import '../shell/nav.dart';

/// 加载歌单 / 专辑 / 电台 / 我喜欢 / 最近播放 / 已下载，统一成 [PlaylistInfo]。
Future<PlaylistInfo> loadCollection(BuildContext context, AppRoute route) async {
  final sm = context.read<SourceManager>();
  final player = context.read<PlayerController>();
  final downloads = context.read<DownloadManager>();
  final local = context.read<LocalLibrary>();
  switch (route) {
    case PlaylistRoute(:final id, :final preview, :final sourceId):
      if (preview?.tracks != null) return preview!;
      return sm.byId(sourceId ?? sm.current.id).playlist(id);
    case AlbumRoute(:final id, :final preview):
      final a = await sm.byId(preview?.sourceId ?? sm.current.id).album(id);
      return PlaylistInfo(
        id: a.id,
        sourceId: a.sourceId,
        name: a.name,
        cover: a.cover,
        creator: a.artist?.name,
        description: a.description,
        trackCount: a.songs?.length ?? a.size,
        kind: PlaylistKind.album,
        tracks: a.songs ?? const [],
        tags: [if (a.publishTime != null) '${a.publishTime!.year}'],
      );
    case RadioRoute(:final radio):
      return sm.byId(radio.sourceId).radioPrograms(radio);
    case CollectionRoute(:final kind):
      final source = sm.current;
      switch (kind) {
        case PlaylistKind.liked:
          final lists = await source.userPlaylists();
          final liked = lists.firstWhere((l) => l.isLikedList, orElse: () => throw Exception('未找到“我喜欢的音乐”'));
          return source.playlist(liked.id);
        case PlaylistKind.recent:
          List<Song> songs = player.history;
          if (source.loggedIn && source.supports(SourceFeature.recentPlays) && songs.isEmpty) {
            songs = await source.recentSongs();
          }
          return PlaylistInfo(
            id: 'recent',
            sourceId: source.id,
            name: '最近播放',
            kind: PlaylistKind.recent,
            cover: songs.firstOrNull?.coverUrl,
            creator: '本机',
            tracks: songs,
          );
        case PlaylistKind.local:
          final songs = local.songs;
          return PlaylistInfo(
            id: 'local',
            sourceId: LocalSource.sourceId,
            name: '本地音乐',
            kind: PlaylistKind.local,
            cover: songs.where((s) => s.coverUrl != null).firstOrNull?.coverUrl,
            creator: '本机',
            tracks: songs,
          );
        case PlaylistKind.downloaded:
          final songs = downloads.items;
          return PlaylistInfo(
            id: 'downloaded',
            sourceId: source.id,
            name: '已下载',
            kind: PlaylistKind.downloaded,
            cover: songs.firstOrNull?.coverUrl,
            creator: '本机',
            tracks: songs,
          );
        default:
          throw Exception('不支持的列表');
      }
    default:
      throw Exception('不支持的页面');
  }
}

String durationText(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h > 0) return '$h 小时 $m 分';
  return '${d.inMinutes} 分钟';
}

String collectionMeta(PlaylistInfo p) {
  final count = '${p.tracks?.length ?? p.trackCount} 首';
  final dur = p.totalDuration > Duration.zero ? durationText(p.totalDuration) : null;
  final who = switch (p.kind) {
    PlaylistKind.album => p.creator,
    PlaylistKind.playlist || PlaylistKind.liked => p.creator == null ? null : '${p.creator} 创建',
    _ => p.creator,
  };
  return [who, if (p.kind == PlaylistKind.album && p.tags.isNotEmpty) p.tags.first, count, dur].whereType<String>().join(' · ');
}

String collectionLabel(PlaylistKind k) => switch (k) {
  PlaylistKind.album => '专辑',
  PlaylistKind.chart => '榜单',
  PlaylistKind.daily => '每日推荐',
  PlaylistKind.radio => '电台',
  _ => '歌单',
};

class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key, required this.route});

  final AppRoute route;

  @override
  Widget build(BuildContext context) {
    final gen = context.select<SourceManager, int>((s) => s.generation);
    // 本地音乐导入后刷新列表。
    final localCount = route is CollectionRoute ? context.select<LocalLibrary, int>((l) => l.songs.length) : 0;
    final desktop = LayoutScope.isDesktop(context);
    final preview = switch (route) {
      PlaylistRoute(:final preview) => preview,
      _ => null,
    };
    return AsyncView<PlaylistInfo>(
      keyValue: route is CollectionRoute ? '$gen-$localCount' : null,
      load: () => loadCollection(context, route),
      loading: desktop ? _DesktopPlaylist.loading(preview) : _MobilePlaylist.loading(context, preview),
      builder: (context, pl, reload) => desktop ? _DesktopPlaylist(playlist: pl) : _MobilePlaylist(playlist: pl),
    );
  }
}

class _MobilePlaylist extends StatelessWidget {
  const _MobilePlaylist({required this.playlist});

  final PlaylistInfo playlist;

  static Widget loading(BuildContext context, PlaylistInfo? preview) => _MobilePlaylist(
    playlist: (preview ?? const PlaylistInfo(id: '', sourceId: '', name: '')).withTracks(const []),
  );

  static List<Widget> topButtons(BuildContext context, {VoidCallback? onMore}) => [
    Positioned(
      left: 16,
      top: 20,
      child: GlassButton(YIcons.back, label: '返回', shadows: _btnShadow(context), onTap: () => context.read<AppNav>().pop()),
    ),
    if (onMore != null)
      Positioned(
        right: 16,
        top: 20,
        child: GlassButton(YIcons.more, label: '更多', shadows: _btnShadow(context), onTap: onMore),
      ),
  ];

  static List<Shadow2> _btnShadow(BuildContext context) {
    final p = Palette.of(context);
    return p.isDark ? p.glassButtonShadow : const [Shadow2(0, 6, 18, Color.fromRGBO(0, 0, 0, 0.12)), Shadow2(0, 1, 3, Color.fromRGBO(0, 0, 0, 0.08))];
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final songs = playlist.tracks ?? const <Song>[];
    return MobilePage(
      top: 80,
      overlay: topButtons(context, onMore: () => _showPlaylistMenu(context, playlist)),
      children: [
        Center(
          child: Cover(
            playlist.cover,
            size: 228,
            radius: 26,
            imageSize: 600,
            shadows: const [Shadow2(0, 20, 44, Color.fromRGBO(0, 0, 0, 0.2)), Shadow2(0, 2, 6, Color.fromRGBO(0, 0, 0, 0.08))],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          playlist.name,
          textAlign: TextAlign.center,
          style: ts(28, weight: w700, em: -0.02, height: 1.15, color: p.text),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),
        Text(
          collectionMeta(playlist),
          textAlign: TextAlign.center,
          style: ts(14, color: p.text2),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: PrimaryButton(
                label: '播放',
                icon: YIcons.play,
                expand: true,
                onTap: () => playAll(context, songs, title: playlist.name),
              ),
            ),
            const SizedBox(width: 10),
            SecondaryButton(
              icon: YIcons.shuffle,
              iconSize: 22,
              semanticLabel: '随机播放',
              onTap: () => playAll(context, songs, shuffle: true, title: playlist.name),
            ),
            const SizedBox(width: 10),
            SecondaryButton(icon: YIcons.download, iconSize: 22, semanticLabel: '下载', onTap: () => downloadSongs(context, songs)),
          ],
        ),
        const SizedBox(height: 18),
        if (playlist.kind == PlaylistKind.local) ...[const LocalImportBar(), const SizedBox(height: 18)],
      ],
      slivers: [
        if (songs.isEmpty && playlist.id.isNotEmpty)
          SliverToBoxAdapter(
            child: YCard(
              child: StateView.empty(title: '这里还没有歌曲', message: '去发现页找找喜欢的音乐吧。', icon: YIcons.library),
            ),
          )
        else
          SliverCard(
            indent: 48,
            itemCount: songs.length,
            itemBuilder: (context, i) => SongRow(
              song: songs[i],
              lead: SongLead.number,
              number: i + 1,
              height: 60,
              onTap: () => playAll(context, songs, start: i, title: playlist.name),
            ),
          ),
      ],
    );
  }
}

void _showPlaylistMenu(BuildContext context, PlaylistInfo pl) {
  final songs = pl.tracks ?? const <Song>[];
  showOptions<int>(context, title: pl.name, options: const [(0, '全部加入播放队列'), (1, '下载全部'), (2, '随机播放')]).then((v) {
    if (!context.mounted || v == null) return;
    switch (v) {
      case 0:
        context.read<PlayerController>().addToQueue(songs);
        Toast.show(context, '已加入播放队列');
      case 1:
        downloadSongs(context, songs);
      case 2:
        playAll(context, songs, shuffle: true, title: pl.name);
    }
  });
}

class _DesktopPlaylist extends StatelessWidget {
  const _DesktopPlaylist({required this.playlist});

  final PlaylistInfo playlist;

  static Widget loading(PlaylistInfo? preview) => _DesktopPlaylist(
    playlist: (preview ?? const PlaylistInfo(id: '', sourceId: '', name: '')).withTracks(const []),
  );

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final songs = playlist.tracks ?? const <Song>[];
    return DesktopPage(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Cover(
              playlist.cover,
              size: 232,
              radius: 26,
              imageSize: 600,
              shadows: const [Shadow2(0, 20, 44, Color.fromRGBO(0, 0, 0, 0.2)), Shadow2(0, 2, 6, Color.fromRGBO(0, 0, 0, 0.08))],
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      collectionLabel(playlist.kind),
                      style: ts(12, weight: w600, em: 0.12, color: p.text2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      playlist.name,
                      style: ts(44, weight: w700, em: -0.02, height: 1.1, color: p.text),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if ((playlist.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 520),
                        child: Text(
                          playlist.description!,
                          style: ts(14, height: 1.5, color: p.text4),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Text(collectionMeta(playlist), style: ts(13, color: p.text2)),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        PrimaryButton(
                          label: '播放',
                          icon: YIcons.play,
                          iconSize: 18,
                          height: 44,
                          fontSize: 15,
                          padding: const EdgeInsets.fromLTRB(20, 0, 26, 0),
                          onTap: () => playAll(context, songs, title: playlist.name),
                        ),
                        const SizedBox(width: 10),
                        SecondaryButton(
                          label: '随机播放',
                          icon: YIcons.shuffle,
                          height: 44,
                          fontSize: 15,
                          padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
                          onTap: () => playAll(context, songs, shuffle: true, title: playlist.name),
                        ),
                        const SizedBox(width: 10),
                        SecondaryButton(icon: YIcons.download, height: 44, semanticLabel: '下载', onTap: () => downloadSongs(context, songs)),
                        const SizedBox(width: 10),
                        SecondaryButton(icon: YIcons.more, height: 44, semanticLabel: '更多', onTap: () => _showPlaylistMenu(context, playlist)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        if (playlist.kind == PlaylistKind.local) ...[const LocalImportBar(), const SizedBox(height: 20)],
      ],
      slivers: [
        SliverCard(
          indent: 16,
          header: const DesktopTableHeader(),
          itemCount: songs.length,
          itemBuilder: (context, i) => DesktopSongRow(
            song: songs[i],
            number: i + 1,
            onTap: () => playAll(context, songs, start: i, title: playlist.name),
          ),
        ),
      ],
    );
  }
}
