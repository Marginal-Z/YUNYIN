import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../data/sources/source_manager.dart';

String formatCount(int n) {
  if (n >= 100000000) return '${(n / 100000000).toStringAsFixed(1)}亿';
  if (n >= 10000) {
    final v = n / 10000;
    return '${v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.0', '')}万';
  }
  return groupDigits(n);
}

/// 千分位：23418 → 23,418。
String groupDigits(int n) {
  final s = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String relativeTime(DateTime? t) {
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return '刚刚';
  if (d.inHours < 1) return '${d.inMinutes} 分钟前';
  if (d.inDays < 1) return '${d.inHours} 小时前';
  if (d.inDays == 1) return '昨天';
  if (d.inDays < 7) return '${d.inDays} 天前';
  if (d.inDays < 14) return '上周';
  if (t.year == DateTime.now().year) return '${t.month}月${t.day}日';
  return '${t.year}年${t.month}月${t.day}日';
}

class CommentsPage extends StatefulWidget {
  const CommentsPage({super.key, required this.song});

  final Song song;

  @override
  State<CommentsPage> createState() => _CommentsPageState();
}

class _CommentsPageState extends State<CommentsPage> {
  CommentSort _sort = CommentSort.recommend;
  final List<Comment> _items = [];
  final Set<String> _likedIds = {};
  int _total = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) _load();
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loading || (!reset && !_hasMore)) return;
    setState(() {
      _loading = true;
      _error = null;
      if (reset) {
        _items.clear();
        _hasMore = true;
      }
    });
    try {
      final src = context.read<SourceManager>().byId(widget.song.sourceId);
      final page = await src.comments(widget.song, sort: _sort, offset: _items.length);
      if (!mounted) return;
      setState(() {
        _total = page.total;
        _items.addAll(page.comments.where((c) => !_items.any((x) => x.id == c.id)));
        _hasMore = page.hasMore && page.comments.isNotEmpty;
        _likedIds.addAll(page.comments.where((c) => c.liked).map((c) => c.id));
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final src = context.read<SourceManager>().byId(widget.song.sourceId);
    try {
      await src.postComment(widget.song, text);
      _input.clear();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      Toast.show(context, '评论已发布');
      _load(reset: true);
    } catch (e) {
      if (mounted) Toast.show(context, errorText(e), icon: YIcons.info);
    }
  }

  Future<void> _like(Comment c) async {
    final src = context.read<SourceManager>().byId(widget.song.sourceId);
    final liked = _likedIds.contains(c.id);
    setState(() => liked ? _likedIds.remove(c.id) : _likedIds.add(c.id));
    try {
      await src.likeComment(widget.song, c, !liked);
    } catch (e) {
      if (!mounted) return;
      setState(() => liked ? _likedIds.add(c.id) : _likedIds.remove(c.id));
      Toast.show(context, errorText(e), icon: YIcons.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pad = MediaQuery.paddingOf(context);
    final song = widget.song;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Material(
      type: MaterialType.transparency,
      child: GlowBackground.page(
        context,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Stack(children: [
              Positioned.fill(
                child: ListView(
                  controller: _scroll,
                  padding: EdgeInsets.fromLTRB(20, pad.top + 84, 20, pad.bottom + 22 + 60 + 24 + bottomInset),
                  children: [
                    Pressable(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: YCard(
                        radius: 22,
                        child: SizedBox(
                          height: 64,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(children: [
                              Cover(song.coverUrl, size: 44, radius: 11),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(song.name, style: ts(15, weight: w600, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text(song.subtitle, style: ts(13, color: p.text2), maxLines: 1, overflow: TextOverflow.ellipsis),
                                ]),
                              ),
                              const YIcon(YIcons.chevronRight, size: 16, color: Color(0xFF8E8E93)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Segmented(
                      labels: const ['推荐', '最热', '最新'],
                      index: _sort.index,
                      onChanged: (i) {
                        setState(() => _sort = CommentSort.values[i]);
                        _load(reset: true);
                      },
                    ),
                    const SizedBox(height: 14),
                    if (_error != null && _items.isEmpty)
                      YCard(child: StateView.network(onRetry: () => _load(reset: true), message: errorText(_error)))
                    else if (_items.isEmpty && _loading)
                      const SkeletonList()
                    else if (_items.isEmpty)
                      YCard(child: StateView.empty(title: '还没有评论', message: '来抢沙发吧。', icon: YIcons.comment, tile: TileColor.red))
                    else
                      CardList(
                        indent: 66,
                        children: [for (final c in _items) _CommentRow(comment: c, liked: _likedIds.contains(c.id), onLike: () => _like(c))],
                      ),
                    if (_loading && _items.isNotEmpty)
                      const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
                  ],
                ),
              ),
              Positioned(
                left: 16,
                top: pad.top + 20,
                child: GlassButton(YIcons.back, label: '返回', onTap: () => Navigator.of(context).maybePop()),
              ),
              Positioned(
                left: 76,
                right: 76,
                top: pad.top + 20,
                height: 44,
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('评论', style: ts(17, weight: w700, color: p.text)),
                  const SizedBox(height: 1),
                  Text('${groupDigits(_total)} 条', style: ts(12, color: p.text2, tabular: true)),
                ]),
              ),
              Positioned(
                right: 16,
                top: pad.top + 20,
                child: GlassButton(YIcons.share, label: '分享', onTap: () {
                  final url = song.sourceId == 'netease' ? 'https://music.163.com/song?id=${song.id}' : '${song.name} - ${song.artistText}';
                  Clipboard.setData(ClipboardData(text: url));
                  Toast.show(context, '链接已复制');
                }),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: pad.bottom + 22 + bottomInset,
                child: Glass(
                  radius: 30,
                  height: 60,
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        onSubmitted: (_) => _send(),
                        textInputAction: TextInputAction.send,
                        style: ts(16, color: p.text),
                        cursorColor: p.accentText,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: '说点什么吧…',
                          hintStyle: ts(16, color: p.text2),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Pressable(
                      onTap: _send,
                      scale: 0.92,
                      semanticLabel: '发送',
                      child: YBox(
                        width: 44,
                        height: 44,
                        radius: BorderRadius.circular(22),
                        gradient: CssGradient.vertical(p.buttonGradient),
                        shadows: p.buttonShadow,
                        insets: [Shadow2(0, 1, 0, p.buttonInsetHighlight)],
                        alignment: Alignment.center,
                        child: const YIcon(YIcons.send, size: 20, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({required this.comment, required this.liked, required this.onLike});

  final Comment comment;
  final bool liked;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final c = comment;
    final count = c.likedCount + (liked && !c.liked ? 1 : 0) - (!liked && c.liked ? 1 : 0);
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Cover(c.avatar, size: 40, circle: true),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.userName, style: ts(14, weight: w600, color: p.text)),
                  const SizedBox(height: 1),
                  Text([relativeTime(c.time), if (c.location != null) c.location!].join(' · '), style: ts(12, color: p.text2)),
                ]),
              ),
              Pressable(
                onTap: onLike,
                scale: 0.92,
                semanticLabel: '点赞',
                child: SizedBox(
                  height: 28,
                  child: Row(children: [
                    YIcon(liked ? YIcons.heart : YIcons.heartOutline, size: 17, color: liked ? p.accentText : p.text2),
                    const SizedBox(width: 4),
                    Text(formatCount(count), style: ts(13, color: liked ? p.accentText : p.text2, tabular: true)),
                  ]),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Text(c.content, style: ts(15, height: 1.5, color: p.text)),
            if (c.replyCount > 0) ...[
              const SizedBox(height: 8),
              Text('${c.replyCount} 条回复', style: ts(13, weight: w600, color: p.accentText)),
            ],
          ]),
        ),
      ]),
    );
  }
}
