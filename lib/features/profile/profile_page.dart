import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/cover.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../../data/sources/source_manager.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 个人中心：账号、当前平台的会员信息（随平台切换），平台模式切换与常用入口。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final sm = context.watch<SourceManager>();
    final source = sm.current;
    final user = source.user;
    final desktop = LayoutScope.isDesktop(context);
    return AdaptivePage(
      mobileTop: 78,
      overlay: [
        Positioned(
          left: 16,
          top: 20,
          child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
        ),
      ],
      children: [
        PageTitle('个人中心', size: desktop ? 40 : 36),
        const SizedBox(height: 16),
        YCard(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Avatar(user?.avatar, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user?.nickname ?? '未登录',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(21, weight: w700, color: p.text),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      user == null ? (source.supports(SourceFeature.login) ? '登录${source.name}，同步歌单与会员音质' : '${source.name}无需登录') : '${source.name}账号',
                      style: ts(13, color: p.text2),
                    ),
                  ],
                ),
              ),
              if (user == null && source.supports(SourceFeature.login))
                PrimaryButton(label: '登录', height: 40, fontSize: 15, onTap: () => go(context, LoginRoute())),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _MembershipCard(key: ValueKey('${source.id}:${user?.id}:${sm.generation}'), source: source),
        SectionHeader('平台模式', top: 26),
        Text('四个平台彼此独立：切换后首页、发现、搜索、排行榜、账号、播放队列与界面样式都换成该平台，只播放该平台的歌曲。', style: ts(13, height: 1.5, color: p.text2)),
        const SizedBox(height: 12),
        // 两列网格：每个平台的名称都能完整显示（手机上四个并排会被截断）。
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 640 ? 4 : 2;
            final w = (c.maxWidth - 10 * (cols - 1)) / cols;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final s in sm.selectable)
                  SizedBox(width: w, child: _PlatformTile(source: s, selected: s.id == source.id, onTap: () => _switch(context, s))),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        CardList(
          indent: 56,
          children: [
            SettingsRow(icon: YIcons.sliders, tile: TileColor.graphite, title: '设置', onTap: () => go(context, SettingsRoute())),
            if (user != null)
              SettingsRow(
                icon: YIcons.user,
                tile: TileColor.red,
                title: '退出${source.name}登录',
                titleColor: p.danger,
                chevron: false,
                onTap: () async {
                  final ok = await showConfirm(context, title: '退出登录？', message: '退出后将无法同步${source.name}的歌单与喜欢。', confirm: '退出');
                  if (ok) await source.logout();
                },
              ),
          ],
        ),
      ],
    );
  }

  static Future<void> _switch(BuildContext context, MusicSource s) async {
    final sm = context.read<SourceManager>();
    if (sm.current.id == s.id) return;
    await sm.select(s.id);
    if (!context.mounted) return;
    context.read<AppNav>().resetForPlatform();
    Toast.show(context, '已切换到${s.name}模式');
  }
}

/// 平台配色：会员卡片与平台切换按钮使用。
(Color, Color) _platformColors(String id) => switch (id) {
  'qq' => (const Color(0xFF1FC27C), const Color(0xFF0A7F55)),
  'kugou' => (const Color(0xFF3A9BFF), const Color(0xFF1560C9)),
  'lx' => (const Color(0xFFFF9F43), const Color(0xFFD9680A)),
  _ => (const Color(0xFF3A3A40), const Color(0xFF111114)),
};

class _PlatformTile extends StatelessWidget {
  const _PlatformTile({required this.source, required this.selected, required this.onTap});

  final MusicSource source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final (a, b) = _platformColors(source.id);
    return Pressable(
      onTap: onTap,
      semanticLabel: '${source.name}模式${selected ? '，当前' : ''}',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 86,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected ? LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          color: selected ? null : p.card,
          border: Border.all(color: selected ? Colors.transparent : p.separator),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    // 平台按钮较窄，使用简称。
                    const {'netease': '网易云'}[source.id] ?? source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(15, weight: w700, color: selected ? Colors.white : p.text),
                  ),
                ),
                if (selected) const YIcon(YIcons.check, size: 16, strokeWidth: 2.6, color: Colors.white),
              ],
            ),
            const Spacer(),
            Text(
              source.user != null ? '已登录' : (source.supports(SourceFeature.login) ? '未登录' : '游客模式'),
              style: ts(12, weight: w500, color: selected ? const Color(0xD9FFFFFF) : p.text2),
            ),
          ],
        ),
      ),
    );
  }
}

/// 会员卡片：按当前平台读取会员名称、等级、到期时间与权益。
class _MembershipCard extends StatelessWidget {
  const _MembershipCard({super.key, required this.source});

  final MusicSource source;

  @override
  Widget build(BuildContext context) {
    final (a, b) = _platformColors(source.id);
    final gold = source.id == 'netease';
    Widget card(Widget child) => YBox(
      radius: BorderRadius.circular(26),
      gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
      shadows: [Shadow2(0, 16, 32, b.withValues(alpha: 0.3))],
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: DefaultTextStyle(
        style: ts(14, color: Colors.white),
        child: child,
      ),
    );
    final accent = gold ? const Color(0xFFF3D7A1) : Colors.white;
    if (source.user == null) {
      return card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              source.supports(SourceFeature.login) ? '${source.name}会员' : source.name,
              style: ts(13, weight: w600, color: const Color(0xCCFFFFFF)),
            ),
            const SizedBox(height: 6),
            Text(
              source.supports(SourceFeature.login) ? '登录后查看会员信息' : '游客模式',
              style: ts(22, weight: w700, color: accent),
            ),
            const SizedBox(height: 8),
            Text(
              source.supports(SourceFeature.login) ? '会员账号可播放会员歌曲与更高音质。' : '${source.name}不需要账号：曲库来自酷我，播放使用“设置 → 洛雪音源”中启用的音源。',
              style: ts(13, height: 1.5, color: const Color(0xD9FFFFFF)),
            ),
          ],
        ),
      );
    }
    return AsyncView<Membership?>(
      load: source.membership,
      loading: card(
        const SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
        ),
      ),
      builder: (context, m, _) {
        final expires = m?.expires;
        return card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    source.supports(SourceFeature.login) ? '${source.name}会员' : source.name,
                    style: ts(13, weight: w600, color: const Color(0xCCFFFFFF)),
                  ),
                  const Spacer(),
                  if (m?.level != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: accent.withValues(alpha: 0.7)),
                      ),
                      child: Text(
                        m!.level!,
                        style: ts(12, weight: w700, color: accent),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                m?.title ?? '暂时无法获取会员信息',
                style: ts(24, weight: FontWeight.w800, color: accent),
              ),
              if (expires != null) ...[
                const SizedBox(height: 4),
                Text('${expires.year} 年 ${expires.month} 月 ${expires.day} 日到期', style: ts(13, color: const Color(0xD9FFFFFF))),
              ],
              if (m != null && m.benefits.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in m.benefits)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          b,
                          style: ts(12, weight: w500, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ],
              if (m != null && !m.active) ...[const SizedBox(height: 8), Text('开通会员后可播放会员歌曲与更高音质。', style: ts(13, color: const Color(0xD9FFFFFF)))],
            ],
          ),
        );
      },
    );
  }
}
