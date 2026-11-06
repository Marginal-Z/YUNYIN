import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../data/cover_resolver.dart';
import '../../data/models.dart';
import '../../data/sources/source_manager.dart';

/// 歌曲封面。列表里没有封面的歌曲（洛雪曲库榜单的后半部分、部分歌单与电台节目等）在显示时
/// 向所属平台查询一次封面，查到后淡入；查不到时显示带音符的占位图。
class SongCover extends StatefulWidget {
  const SongCover(this.song, {super.key, required this.size, this.radius = 10, this.circle = false, this.shadows = const [], this.imageSize});

  final Song? song;
  final double size;
  final double radius;
  final bool circle;
  final List<Shadow2> shadows;
  final int? imageSize;

  @override
  State<SongCover> createState() => _SongCoverState();
}

class _SongCoverState extends State<SongCover> {
  String? _url;

  @override
  void initState() {
    super.initState();
    _lookup();
  }

  @override
  void didUpdateWidget(SongCover old) {
    super.didUpdateWidget(old);
    if (old.song?.key != widget.song?.key || old.song?.coverUrl != widget.song?.coverUrl) _lookup();
  }

  void _lookup() {
    final song = widget.song;
    _url = song == null ? null : CoverResolver.instance.known(song);
    if (song == null || _url != null || CoverResolver.instance.tried(song)) return;
    final sources = Provider.of<SourceManager?>(context, listen: false);
    if (sources == null) return;
    CoverResolver.instance.resolve(sources, song).then((url) {
      if (mounted && url != null && widget.song?.key == song.key) setState(() => _url = url);
    });
  }

  @override
  Widget build(BuildContext context) =>
      Cover(_url ?? widget.song?.coverUrl, size: widget.size, radius: widget.radius, circle: widget.circle, shadows: widget.shadows, imageSize: widget.imageSize);
}
