import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../data/sources/source_manager.dart';
import '../comments/comments_page.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 白色胶囊搜索框（移动端）。
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.onSubmit,
    this.autofocus = false,
    this.onClear,
    this.focusNode,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final bool autofocus;
  final VoidCallback? onClear;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return YBox(
      height: 44,
      radius: BorderRadius.circular(22),
      color: p.card,
      shadows: p.cardShadow,
      insets: p.cardInset,
      padding: EdgeInsets.fromLTRB(16, 0, onClear != null ? 12 : 16, 0),
      child: Row(children: [
        YIcon(YIcons.search, size: 18, color: p.text2),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            autofocus: autofocus,
            onSubmitted: onSubmit,
            textInputAction: TextInputAction.search,
            style: ts(16, color: p.text),
            cursorColor: p.accentText,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: '搜索歌曲、歌手、歌单',
              hintStyle: ts(16, color: p.text2),
            ),
          ),
        ),
        if (onClear != null)
          ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox.shrink()
                : Pressable(
                    onTap: onClear,
                    scale: 0.9,
                    semanticLabel: '清除',
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(color: p.clearButton, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const YIcon(YIcons.close, size: 12, color: Colors.white),
                    ),
                  ),
          ),
      ]),
    );
  }
}

void submitSearch(BuildContext context, String q) {
  final k = q.trim();
  if (k.isEmpty) return;
  context.read<AppSettings>().addSearch(k);
  final nav = context.read<AppNav>();
  if (nav.top is SearchResultRoute) {
    nav.replace(SearchResultRoute(k));
  } else {
    nav.push(SearchResultRoute(k));
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final desktop = LayoutScope.isDesktop(context);
    return AdaptivePage(
      chrome: Chrome.none,
      mobileTop: 22,
      children: [
        if (!desktop)
          Row(children: [
            Expanded(child: SearchField(controller: _c, autofocus: true, onSubmit: (q) => submitSearch(context, q))),
            const SizedBox(width: 12),
            Pressable(
              onTap: () => context.read<AppNav>().pop(),
              pressedOpacity: 0.6,
              child: Text('取消', style: ts(16, color: p.accentText)),
            ),
          ])
        else
          const PageTitle('搜索', size: 40),
        const SearchSuggestions(),
      ],
    );
  }
}

/// 搜索历史 + 热搜榜。
class SearchSuggestions extends StatelessWidget {
  const SearchSuggestions({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.watch<AppSettings>();
    final sources = context.watch<SourceManager>();
    final history = settings.searchHistory;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (history.isNotEmpty) ...[
        Padding(
          padding: const EdgeInsets.only(top: 28, bottom: 12),
          child: Row(children: [
            Expanded(child: Text('搜索历史', style: ts(22, weight: w700, em: -0.015, color: p.text))),
            CircleButton(YIcons.trash, size: 36, iconSize: 18, color: p.text2, label: '清空搜索历史', onTap: settings.clearSearch),
          ]),
        ),
        Wrap(spacing: 10, runSpacing: 10, children: [
          for (final h in history) YChip(h, height: 36, onTap: () => submitSearch(context, h)),
        ]),
      ],
      SectionHeader('热搜榜', action: '完整榜单', onAction: () => context.read<AppNav>().push(DiscoverRoute(tab: 1))),
      AsyncView<List<HotSearch>>(
        keyValue: sources.generation,
        load: sources.current.hotSearches,
        builder: (context, list, _) => CardList(
          indent: 50,
          children: [
            for (var i = 0; i < list.length && i < 20; i++)
              Pressable(
                onTap: () => submitSearch(context, list[i].keyword),
                scale: 1,
                hoverColor: p.separator.withValues(alpha: 0.06),
                child: SizedBox(
                  height: 46,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      SizedBox(
                        width: 22,
                        child: Text('${i + 1}', style: ts(16, weight: w700, color: i < 3 ? p.accentText : p.muted, tabular: true)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Row(children: [
                          Flexible(child: Text(list[i].keyword, style: ts(15, weight: w600, color: p.text), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (list[i].tag != null) ...[
                            const SizedBox(width: 8),
                            Tag(
                              switch (list[i].tag) { 'hot' => '热', 'new' => '新', _ => '升' },
                              kind: switch (list[i].tag) { 'hot' => TagKind.hot, 'new' => TagKind.fresh, _ => TagKind.up },
                            ),
                          ],
                        ]),
                      ),
                      if (list[i].score > 0) Text(formatCount(list[i].score), style: ts(12, color: p.text2, tabular: true)),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    ]);
  }
}
