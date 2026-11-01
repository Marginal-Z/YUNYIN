import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/cover_colors.dart';
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
    case AlbumRoute(:final id, :final preview, :final sourceId):
      final a = await sm.byId(sourceId ?? preview?.sourceId ?? sm.current.id).album(id);
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
          // 没有账号“喜欢”功能的平台：显示保存在本机的喜欢；登录后账号里的“我喜欢”排在前面。
          if (!source.supports(SourceFeature.likeSong)) {
            final local = player.localLikedSongs(source.id);
            if (source.loggedIn && source.supports(SourceFeature.userPlaylists)) {
              final liked = (await source.userPlaylists()).where((l) => l.isLikedList).firstOrNull;
              if (liked != null) {
                final list = await source.playlist(liked.id);
                final ids = {for (final s in list.tracks ?? const <Song>[]) s.key};
                final tracks = [...?list.tracks, ...local.where((s) => !ids.contains(s.key))];
                return PlaylistInfo(
                  id: list.id,
                  sourceId: list.sourceId,
                  name: list.name,
                  cover: list.cover,
                  creator: list.creator,
                  trackCount: tracks.length,
                  isLikedList: true,
                  ownedByMe: true,
                  kind: PlaylistKind.liked,
                  tracks: tracks,
                );
              }
            }
            final songs = local;
            return PlaylistInfo(
              id: 'liked:${source.id}',
              sourceId: source.id,
              name: '我喜欢的音乐',
              kind: PlaylistKind.liked,
              cover: songs.firstOrNull?.coverUrl,
              creator: '本机',
              tracks: songs,
            );
          }
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
      // 歌单、专辑等内容不常变化；我喜欢、最近播放等集合每次进入都在后台刷新。
      cacheKey: switch (route) {
        PlaylistRoute(:final id, :final sourceId) => 'playlist:${sourceId ?? context.read<SourceManager>().current.id}:$id',
        AlbumRoute(:final id, :final preview, :final sourceId) => 'album:${sourceId ?? preview?.sourceId ?? context.read<SourceManager>().current.id}:$id',
        CollectionRoute(:final kind) => 'collection:${kind.name}:$localCount',
        RadioRoute(:final radio) => 'radio:${radio.id}',
        _ => null,
      },
      maxAge: route is CollectionRoute ? Duration.zero : const Duration(minutes: 10),
      load: () => loadCollection(context, route),
      loading: desktop ? _DesktopPlaylist.loading(preview) : _MobilePlaylist.placeholder(context, preview),
      builder: (context, pl, reload) => desktop ? _DesktopPlaylist(playlist: pl) : _MobilePlaylist(playlist: pl),
    );
  }
}

/// 移动端歌单 / 专辑详情：封面铺满顶部并渐隐到取自封面的底色，下面是标题、创建者、简介、
/// 操作按钮与歌曲列表（整页使用浅色文字）。
class _MobilePlaylist extends StatefulWidget {
  const _MobilePlaylist({required this.playlist, this.loading = false});

  final PlaylistInfo playlist;
  final bool loading;

  static Widget placeholder(BuildContext context, PlaylistInfo? preview) => _MobilePlaylist(
    playlist: (preview ?? const PlaylistInfo(id: '', sourceId: '', name: '')).withTracks(const []),
    loading: true,
  );

  @override
  State<_MobilePlaylist> createState() => _MobilePlaylistState();
}

class _MobilePlaylistState extends State<_MobilePlaylist> {
  Color? _tone;

  /// 封面区已经滚出屏幕：顶部显示与页面同色的渐隐，歌曲不会压在状态栏与按钮下面。
  final _pastHero = ValueNotifier(false);

  @override
  void dispose() {
    _pastHero.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadTone();
  }

  @override
  void didUpdateWidget(_MobilePlaylist old) {
    super.didUpdateWidget(old);
    if (old.playlist.cover != widget.playlist.cover) _loadTone();
  }

  /// 底色取自封面：饱和度与亮度限制在适合放白色文字的范围内。
  Future<void> _loadTone() async {
    final c = await CoverColors.of(widget.playlist.cover);
    if (!mounted || c == null) return;
    final hsl = HSLColor.fromColor(c.dominant.computeLuminance() > 0.02 ? c.dominant : c.vibrant);
    // 饱和度与亮度都压低：白色文字在任何封面底色上都有足够对比度。
    setState(() => _tone = hsl.withSaturation((hsl.saturation * 0.7).clamp(0.08, 0.42)).withLightness(hsl.lightness.clamp(0.16, 0.22)).toColor());
  }

  @override
  Widget build(BuildContext context) {
    final playlist = widget.playlist;
    final songs = playlist.tracks ?? const <Song>[];
    final dark = context.read<AppSettings>().palette(true);
    final tone = _tone ?? const Color(0xFF2C3440);
    final size = MediaQuery.sizeOf(context);
    final pad = MediaQuery.paddingOf(context);
    final heroH = math.min(size.width * 0.95, size.height * 0.5);
    return PaletteScope(
      palette: dark,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [tone, Color.lerp(tone, Colors.black, 0.35)!]),
                ),
              ),
            ),
            NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.depth == 0) _pastHero.value = n.metrics.pixels > heroH - pad.top - 40;
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _hero(context, heroH, tone)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _actions(context, songs),
                          const SizedBox(height: 22),
                          _listHeader(context, songs),
                          if (playlist.kind == PlaylistKind.local) ...[const SizedBox(height: 12), const LocalImportBar()],
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                  if (widget.loading)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                      ),
                    )
                  else if (songs.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: StateView.empty(title: '这里还没有歌曲', message: '去发现页找找喜欢的音乐吧。', icon: YIcons.library),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      // 长列表按需构建，几千首歌也不会卡顿。
                      sliver: SliverList.builder(
                        itemCount: songs.length,
                        itemBuilder: (context, i) => SongRow(
                          song: songs[i],
                          // 榜单显示名次。
                          lead: playlist.kind == PlaylistKind.chart ? SongLead.rank : SongLead.cover,
                          number: i + 1,
                          height: 62,
                          trailing: SongTrailing.likeMore,
                          onTap: () => playAll(context, songs, start: i, title: playlist.name),
                        ),
                      ),
                    ),
                  SliverToBoxAdapter(child: SizedBox(height: chromeClearance(context, Chrome.full))),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: pad.top + 84,
              child: IgnorePointer(
                child: ValueListenableBuilder<bool>(
                  valueListenable: _pastHero,
                  builder: (context, on, _) => AnimatedOpacity(
                    opacity: on ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [tone, tone.withValues(alpha: 0.92), tone.withValues(alpha: 0)],
                          stops: const [0, 0.6, 1],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: pad.top,
              child: SizedBox(
                height: 80,
                child: Stack(
                  children: [
                    Positioned(
                      left: 16,
                      top: 20,
                      child: _HeroButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
                    ),
                    Positioned(
                      right: 16,
                      top: 20,
                      child: _HeroButton(YIcons.more, label: '更多', onTap: () => _showPlaylistMenu(context, playlist)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(BuildContext context, double heroH, Color tone) {
    final playlist = widget.playlist;
    final desc = (playlist.description ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    return SizedBox(
      height: heroH + 120,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: heroH,
            child: ShaderMask(
              shaderCallback: (r) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black, Colors.black, Colors.transparent],
                stops: [0, 0.55, 1],
              ).createShader(r),
              blendMode: BlendMode.dstIn,
              child: CoverImage(playlist.cover, imageSize: 900),
            ),
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 0,
            child: Column(
              children: [
                Text(
                  playlist.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ts(
                    26,
                    weight: w700,
                    em: -0.01,
                    height: 1.2,
                    color: Colors.white,
                  ).copyWith(shadows: const [Shadow(color: Color(0x66000000), blurRadius: 12)]),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (playlist.creator != null) ...[
                      Container(
                        width: 22,
                        height: 22,
                        decoration: const BoxDecoration(color: Color(0x33FFFFFF), shape: BoxShape.circle),
                        alignment: Alignment.center,
                        child: const YIcon(YIcons.user, size: 13, color: Colors.white),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          playlist.creator!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(14, weight: w600, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), color: const Color(0x26FFFFFF)),
                      child: Text(
                        collectionLabel(playlist.kind),
                        style: ts(11, weight: w600, color: const Color(0xD9FFFFFF)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Pressable(
                  onTap: desc.isEmpty ? null : () => showConfirm(context, title: playlist.name, message: desc, confirm: '好', cancel: '关闭', destructive: false),
                  scale: 1,
                  child: Row(
                    children: [
                      const YIcon(YIcons.volume, size: 14, color: Color(0xB3FFFFFF)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          [if (playlist.playCount > 0) _countText(playlist.playCount), desc.isEmpty ? collectionMeta(playlist) : desc].join('   '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ts(13, color: const Color(0xD9FFFFFF)),
                        ),
                      ),
                      if (desc.isNotEmpty) const YIcon(YIcons.chevronRight, size: 14, color: Color(0xB3FFFFFF)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _countText(int n) => n >= 100000000 ? '${(n / 100000000).toStringAsFixed(1)} 亿' : (n >= 10000 ? '${(n / 10000).round()} 万' : '$n');

  Widget _circle(YIconData icon, String label, VoidCallback onTap) => Pressable(
    onTap: onTap,
    semanticLabel: label,
    child: Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0x1FFFFFFF),
        border: Border.all(color: const Color(0x33FFFFFF)),
      ),
      alignment: Alignment.center,
      child: YIcon(icon, size: 21, color: Colors.white),
    ),
  );

  Widget _actions(BuildContext context, List<Song> songs) {
    final playlist = widget.playlist;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _circle(YIcons.queue, '全部加入播放队列', () {
          context.read<PlayerController>().addToQueue(songs);
          Toast.show(context, '已加入播放队列');
        }),
        const SizedBox(width: 18),
        Pressable(
          onTap: () => playAll(context, songs, title: playlist.name),
          semanticLabel: '播放全部',
          child: Container(
            width: 112,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              color: const Color(0xE6FFFFFF),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
            ),
            alignment: Alignment.center,
            child: YIcon(YIcons.play, size: 22, color: _tone ?? const Color(0xFF2C3440)),
          ),
        ),
        const SizedBox(width: 18),
        _circle(YIcons.download, '下载全部', () => downloadSongs(context, songs)),
      ],
    );
  }

  Widget _listHeader(BuildContext context, List<Song> songs) {
    return Row(
      children: [
        Text(
          '${songs.isEmpty ? widget.playlist.trackCount : songs.length} 首歌曲',
          style: ts(15, weight: w700, color: Colors.white),
        ),
        const Spacer(),
        YIconButton(
          YIcons.shuffle,
          size: 36,
          iconSize: 20,
          color: Colors.white,
          label: '随机播放',
          onTap: () => playAll(context, songs, shuffle: true, title: widget.playlist.name),
        ),
        YIconButton(YIcons.more, size: 36, iconSize: 20, color: Colors.white, label: '更多', onTap: () => _showPlaylistMenu(context, widget.playlist)),
      ],
    );
  }
}

/// 封面上方的圆形按钮：半透明深色底，任何封面上都清晰可见。
class _HeroButton extends StatelessWidget {
  const _HeroButton(this.icon, {required this.label, required this.onTap});

  final YIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x47000000),
          border: Border.all(color: const Color(0x33FFFFFF)),
        ),
        alignment: Alignment.center,
        child: YIcon(icon, size: 22, color: Colors.white),
      ),
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
