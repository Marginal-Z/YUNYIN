import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/local_library.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 本地歌曲手动匹配：在网易云、QQ 音乐、酷狗中搜索，选中一首后用它的封面与歌词替换。
class LocalMatchPage extends StatefulWidget {
  const LocalMatchPage({super.key, required this.song});

  final Song song;

  @override
  State<LocalMatchPage> createState() => _LocalMatchPageState();
}

class _LocalMatchPageState extends State<LocalMatchPage> {
  late final _query = TextEditingController(text: [widget.song.name, if (widget.song.artistText != '未知歌手') widget.song.artistText].join(' '));
  Future<List<(MusicSource, Song)>>? _results;
  String? _applying;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() => _results = context.read<LocalLibrary>().searchMatches(q));
  }

  Future<void> _pick(MusicSource src, Song match) async {
    setState(() => _applying = match.key);
    final r = await context.read<LocalLibrary>().applyMatch(widget.song, src, match);
    if (!mounted) return;
    setState(() => _applying = null);
    final parts = [if (r.cover) '封面', if (r.lyrics) '歌词'];
    Toast.show(context, parts.isEmpty ? '这首歌没有可用的封面与歌词' : '已更新${parts.join('与')}', icon: parts.isEmpty ? YIcons.info : YIcons.check);
    if (parts.isNotEmpty) context.read<AppNav>().pop();
  }

  String _durationText(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final desktop = LayoutScope.isDesktop(context);
    return AdaptivePage(
      chrome: Chrome.none,
      mobileTop: 78,
      overlay: [
        Positioned(
          left: 16,
          top: 20,
          child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
        ),
      ],
      children: [
        PageTitle('匹配歌词与封面', subtitle: '${widget.song.name} · ${_durationText(widget.song.duration)}', size: desktop ? 40 : 32),
        const SizedBox(height: 16),
        Container(
          height: 50,
          padding: const EdgeInsets.only(left: 16, right: 6),
          decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              YIcon(YIcons.search, size: 18, color: p.text2),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _query,
                  style: ts(16, color: p.text),
                  cursorColor: p.accentText,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _search(),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: '歌名与歌手',
                    hintStyle: ts(16, color: p.text3),
                  ),
                ),
              ),
              PrimaryButton(label: '搜索', height: 38, fontSize: 14, onTap: _search),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text('结果来自网易云、QQ 音乐与酷狗。时长与本地文件接近的通常就是同一首歌。', style: ts(13, height: 1.5, color: p.text2)),
        const SizedBox(height: 14),
        FutureBuilder<List<(MusicSource, Song)>>(
          future: _results,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return YCard(
                child: StateView.empty(title: '没有找到', message: '换个关键词试试，例如只输入歌名。', icon: YIcons.search),
              );
            }
            return CardList(
              indent: 70,
              children: [
                for (final (src, s) in items)
                  Pressable(
                    onTap: _applying == null ? () => _pick(src, s) : null,
                    scale: 1,
                    child: SizedBox(
                      height: 66,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Cover(s.coverUrl, size: 46, radius: 10),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ts(15, weight: w600, color: p.text),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${s.artistText}${s.albumName.isEmpty ? '' : ' · ${s.albumName}'}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ts(13, color: p.text2),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  src.name,
                                  style: ts(11, weight: w600, color: p.accentText),
                                ),
                                const SizedBox(height: 3),
                                if (_applying == s.key)
                                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                else
                                  Text(_durationText(s.duration), style: ts(12, color: p.text2, tabular: true)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
