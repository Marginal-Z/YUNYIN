import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/downloads.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../../data/sources/source_manager.dart';
import '../../player/player_controller.dart';
import '../comments/comments_page.dart';
import '../player/desktop_player.dart';
import '../player/lyrics_page.dart';
import '../player/player_page.dart';
import '../queue/queue_sheet.dart';
import '../shell/nav.dart';
import 'layout.dart';

void go(BuildContext context, AppRoute route) => context.read<AppNav>().push(route);

void openPlaylist(BuildContext context, PlaylistInfo p) {
  if (p.kind == PlaylistKind.album) {
    go(context, AlbumRoute(p.id));
    return;
  }
  go(context, PlaylistRoute(p.id, preview: p, sourceId: p.sourceId));
}

void openArtist(BuildContext context, ArtistRef a) => go(context, ArtistRoute(a.id, name: a.name));

void openAlbum(BuildContext context, AlbumRef a) => go(context, AlbumRoute(a.id));

/// 从底部滑入的全屏页面。
Route<T> slideUpRoute<T>(Widget page) => PageRouteBuilder<T>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) => SlideTransition(
        position: Tween(begin: const Offset(0, 1), end: Offset.zero)
            .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic)),
        child: child,
      ),
    );

Route<T> fadeRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    );

void openPlayer(BuildContext context) {
  if (context.read<PlayerController>().current == null) return;
  if (LayoutScope.isDesktop(context)) {
    Navigator.of(context, rootNavigator: true).push(slideUpRoute(const DesktopPlayerPage()));
  } else {
    Navigator.of(context, rootNavigator: true).push(slideUpRoute(const PlayerPage()));
  }
}

void openLyrics(BuildContext context) {
  if (LayoutScope.isDesktop(context)) {
    openPlayer(context);
    return;
  }
  Navigator.of(context, rootNavigator: true).push(fadeRoute(const LyricsPage()));
}

void openQueue(BuildContext context) {
  if (LayoutScope.isDesktop(context)) {
    showDesktopQueue(context);
    return;
  }
  Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (_, _, _) => const QueueSheet(),
    transitionsBuilder: (_, a, _, child) => child,
  ));
}

void openComments(BuildContext context, Song song) {
  Navigator.of(context, rootNavigator: true).push(
    LayoutScope.isDesktop(context) ? fadeRoute(CommentsPage(song: song)) : MaterialPageRoute(builder: (_) => CommentsPage(song: song)),
  );
}

Future<void> playAll(BuildContext context, List<Song> songs, {bool shuffle = false, String? title, int start = 0}) async {
  if (songs.isEmpty) {
    Toast.show(context, '列表中还没有歌曲', icon: YIcons.info);
    return;
  }
  final dl = context.read<DownloadManager>();
  final resolved = [for (final s in songs) dl.local(s) ?? s];
  await context.read<PlayerController>().playSongs(resolved, shuffle: shuffle, title: title, start: start);
}

Future<void> downloadSongs(BuildContext context, List<Song> songs) async {
  final dl = context.read<DownloadManager>();
  if (!dl.supported) {
    Toast.show(context, '网页版不支持下载', icon: YIcons.info);
    return;
  }
  Toast.show(context, '已开始下载 ${songs.length} 首歌曲', icon: YIcons.download);
  final n = await dl.downloadAll(songs);
  if (context.mounted && n < songs.length) {
    Toast.show(context, '${songs.length - n} 首暂无下载权限', icon: YIcons.info);
  }
}

/// 歌曲更多操作（底部玻璃面板 / 桌面端居中面板）。
Future<void> showSongMenu(BuildContext context, Song song) async {
  final player = context.read<PlayerController>();
  final dl = context.read<DownloadManager>();
  final source = context.read<SourceManager>().byId(song.sourceId);
  final liked = player.isLiked(song);
  final downloaded = dl.isDownloaded(song);
  final desktop = LayoutScope.isDesktop(context);

  final actions = <(YIconData, String, VoidCallback)>[
    (YIcons.queue, '下一首播放', () {
      player.playNext(song);
      Toast.show(context, '已加入下一首播放');
    }),
    (YIcons.plus, '加入播放队列', () {
      player.addToQueue([song]);
      Toast.show(context, '已加入播放队列');
    }),
    (liked ? YIcons.heart : YIcons.heartOutline, liked ? '取消喜欢' : '喜欢', () => player.toggleLike(song)),
    if (dl.supported)
      (YIcons.download, downloaded ? '删除下载' : '下载', () {
        if (downloaded) {
          dl.remove(song);
          Toast.show(context, '已删除下载');
        } else {
          downloadSongs(context, [song]);
        }
      }),
    if (source.supports(SourceFeature.comments)) (YIcons.comment, '评论', () => openComments(context, song)),
    if (song.artists.isNotEmpty) (YIcons.user, '歌手：${song.artistText}', () => openArtist(context, song.artists.first)),
    if (song.album != null && song.album!.name.isNotEmpty) (YIcons.library, '专辑：${song.album!.name}', () => openAlbum(context, song.album!)),
  ];

  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.28),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (ctx, _, _) {
      final p = Palette.of(ctx);
      final sheet = YBox(
        radius: desktop ? BorderRadius.circular(26) : const BorderRadius.vertical(top: Radius.circular(34)),
        color: p.sheet,
        shadows: const [Shadow2(0, -12, 40, Color.fromRGBO(0, 0, 0, 0.2))],
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!desktop)
                    Container(width: 40, height: 5, decoration: BoxDecoration(color: const Color.fromRGBO(60, 60, 67, 0.3), borderRadius: BorderRadius.circular(3))),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 16, 6, 10),
                    child: Row(children: [
                      Cover(song.coverUrl, size: 48, radius: 12),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(song.name, style: ts(16, weight: w700, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(song.subtitle, style: ts(13, color: p.text2), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ]),
                  ),
                  for (final a in actions)
                    Pressable(
                      onTap: () {
                        Navigator.of(ctx).pop();
                        a.$3();
                      },
                      scale: 1,
                      hoverColor: p.separator,
                      radius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 52,
                        child: Row(children: [
                          const SizedBox(width: 8),
                          YIcon(a.$1, size: 22, color: p.text),
                          const SizedBox(width: 14),
                          Expanded(child: Text(a.$2, style: ts(16, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      if (desktop) return Center(child: SizedBox(width: 380, child: sheet));
      return Align(alignment: Alignment.bottomCenter, child: sheet);
    },
    transitionBuilder: (ctx, a, _, child) {
      final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      if (desktop) return FadeTransition(opacity: curved, child: ScaleTransition(scale: Tween(begin: 0.96, end: 1.0).animate(curved), child: child));
      return SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved), child: child);
    },
  );
}

/// 简单的选项面板（音质、睡眠定时等）。
Future<T?> showOptions<T>(BuildContext context, {required String title, required List<(T, String)> options, T? selected}) {
  final desktop = LayoutScope.isDesktop(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.28),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (ctx, _, _) {
      final p = Palette.of(ctx);
      final sheet = YBox(
        radius: desktop ? BorderRadius.circular(26) : const BorderRadius.vertical(top: Radius.circular(34)),
        color: p.sheet,
        child: Material(
          type: MaterialType.transparency,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                  child: Text(title, style: ts(20, weight: w700, em: -0.01, color: p.text)),
                ),
                for (final o in options)
                  Pressable(
                    onTap: () => Navigator.of(ctx).pop(o.$1),
                    scale: 1,
                    hoverColor: p.separator,
                    radius: BorderRadius.circular(16),
                    child: SizedBox(
                      height: 52,
                      child: Row(children: [
                        const SizedBox(width: 8),
                        Expanded(child: Text(o.$2, style: ts(16, weight: o.$1 == selected ? w600 : w400, color: o.$1 == selected ? p.accentText : p.text))),
                        if (o.$1 == selected) YIcon(YIcons.check, size: 20, color: p.accentText),
                        const SizedBox(width: 8),
                      ]),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      );
      if (desktop) return Center(child: SizedBox(width: 360, child: sheet));
      return Align(alignment: Alignment.bottomCenter, child: sheet);
    },
    transitionBuilder: (ctx, a, _, child) {
      final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      if (desktop) return FadeTransition(opacity: curved, child: child);
      return SlideTransition(position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved), child: child);
    },
  );
}
