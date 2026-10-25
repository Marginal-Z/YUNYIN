import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../../data/sources/source_manager.dart';
import '../common/layout.dart';
import '../discover/discover_page.dart';
import '../shell/nav.dart';
import 'library_page.dart';

/// 我的收藏：歌单 / 专辑 / 歌手。
class CollectionsPage extends StatefulWidget {
  const CollectionsPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<CollectionsPage> createState() => _CollectionsPageState();
}

class _CollectionsPageState extends State<CollectionsPage> {
  late int _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final sources = context.watch<SourceManager>();
    final source = sources.current;
    final desktop = LayoutScope.isDesktop(context);
    final needLogin = !source.loggedIn && source.supports(SourceFeature.login);
    return AdaptivePage(
      mobileTop: 78,
      overlay: [
        Positioned(left: 16, top: 20, child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop())),
      ],
      children: [
        PageTitle('我的收藏', subtitle: '歌单 · 专辑 · 歌手', size: desktop ? 40 : 36),
        const SizedBox(height: 18),
        ChipBar(labels: const ['歌单', '专辑', '歌手'], index: _tab, onChanged: (i) => setState(() => _tab = i)),
        KeyedSubtree(
          key: ValueKey('${sources.generation}-$_tab'),
          child: needLogin
              ? LoginPrompt(source: source)
              : switch (_tab) {
                  0 => Padding(
                      padding: const EdgeInsets.only(top: 20),
                      child: AsyncView<List<PlaylistInfo>>(
                        load: source.userPlaylists,
                        builder: (context, lists, _) {
                          if (lists.isEmpty) {
                            return YCard(child: StateView.empty(title: '还没有歌单', message: '收藏或创建的歌单会显示在这里。', icon: YIcons.library));
                          }
                          return desktop
                              ? PlaylistGrid(items: lists)
                              : CardList(indent: 78, children: [for (final pl in lists) PlaylistRow(playlist: pl)]);
                        },
                      ),
                    ),
                  1 => const SubscribedAlbums(),
                  _ => const FollowedArtists(),
                },
        ),
      ],
    );
  }
}
