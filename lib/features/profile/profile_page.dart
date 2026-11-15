import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        Text('五个平台彼此独立：切换后首页、发现、搜索、排行榜、账号、播放队列与界面样式都换成该平台，只播放该平台的歌曲。', style: ts(13, height: 1.5, color: p.text2)),
        const SizedBox(height: 12),
        // 网格：每个平台的名称都能完整显示（手机上并排会被截断，用两列）。
        LayoutBuilder(
          builder: (context, c) {
            final cols = c.maxWidth >= 760 ? 5 : (c.maxWidth >= 640 ? 3 : 2);
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
  // 汽水音乐：图标的荧光绿渐变到黑底。
  'qishui' => (const Color(0xFF13B866), const Color(0xFF0B1F16)),
  'lx' => (const Color(0xFFFF9F43), const Color(0xFFD9680A)),
  _ => (const Color(0xFF3A3A40), const Color(0xFF111114)),
};

/// 平台标志：各平台的官方应用图标（assets/platforms/），裁成圆角方形。
///
/// 网易云音乐、QQ 音乐、酷狗音乐、汽水音乐的图标取自各自在 App Store 的官方图标，商标归各平台所有，只用于标明平台；
/// 洛雪音乐的图标来自 lx-music-desktop（Apache 2.0）。[inverted] 为 true 时（放在彩色按钮或卡片上）加一圈白边。
class PlatformMark extends StatelessWidget {
  const PlatformMark(this.id, {super.key, this.size = 30, this.inverted = false});

  final String id;
  final double size;
  final bool inverted;

  static String asset(String id) => switch (id) {
    'qq' => 'assets/platforms/qq.png',
    'kugou' => 'assets/platforms/kugou.png',
    'qishui' => 'assets/platforms/qishui.png',
    'lx' => 'assets/platforms/lx.png',
    _ => 'assets/platforms/netease.png',
  };

  @override
  Widget build(BuildContext context) {
    // 应用图标的圆角约为边长的 22.5%。
    final radius = BorderRadius.circular(size * 0.225);
    final image = ClipRRect(
      borderRadius: radius,
      child: ColoredBox(
        // 洛雪的图标是透明底。
        color: Colors.white,
        child: Image.asset(asset(id), width: size, height: size, fit: BoxFit.cover, filterQuality: FilterQuality.medium),
      ),
    );
    if (!inverted) return SizedBox.square(dimension: size, child: image);
    return Container(
      width: size,
      height: size,
      foregroundDecoration: BoxDecoration(borderRadius: radius, border: Border.all(color: const Color(0xCCFFFFFF), width: 1.2)),
      child: image,
    );
  }
}

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
        height: 82,
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
                PlatformMark(source.id, size: 26, inverted: selected),
                const SizedBox(width: 8),
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
      radius: BorderRadius.circular(22),
      gradient: LinearGradient(colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
      shadows: [Shadow2(0, 10, 22, b.withValues(alpha: 0.26))],
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: DefaultTextStyle(
        style: ts(14, color: Colors.white),
        child: child,
      ),
    );
    final accent = gold ? const Color(0xFFF3D7A1) : Colors.white;
    if (source.user == null) {
      // 未登录：一行紧凑的提示（标志 + 平台会员 + 说明），不占用大块空间。
      return card(
        Row(
          children: [
            PlatformMark(source.id, size: 38, inverted: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.supports(SourceFeature.login) ? '登录后查看会员信息' : '游客模式',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: ts(16, weight: w700, color: accent),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    source.supports(SourceFeature.login)
                        ? '${source.name}会员可播放会员歌曲与更高音质'
                        : source.id == 'qishui'
                        ? '无需账号：免费歌曲完整播放，会员歌曲只能试听（云音不接入汽水音乐的登录与会员）'
                        : '无需账号，曲库与音源在“设置 → 洛雪音源”中管理',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: ts(12.5, height: 1.4, color: const Color(0xD9FFFFFF)),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return AsyncView<Membership?>(
      load: source.membership,
      loading: card(
        const SizedBox(
          height: 64,
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
                  PlatformMark(source.id, size: 22, inverted: true),
                  const SizedBox(width: 8),
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
              // 会员名称与到期时间放在同一行，卡片更紧凑。
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: Text(
                      m?.title ?? '暂时无法获取会员信息',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ts(19, weight: FontWeight.w800, color: accent),
                    ),
                  ),
                  if (expires != null) ...[
                    const SizedBox(width: 10),
                    Text('${expires.year}.${expires.month}.${expires.day} 到期', style: ts(12, color: const Color(0xD9FFFFFF))),
                  ],
                ],
              ),
              if (m != null && m.benefits.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final b in m.benefits.take(4))
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: const Color(0x26FFFFFF), borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          b,
                          style: ts(11.5, weight: w500, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ],
              if (m != null && !m.active && !m.relogin) ...[const SizedBox(height: 6), Text('开通会员后可播放会员歌曲与更高音质。', style: ts(12.5, color: const Color(0xD9FFFFFF)))],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (m?.relogin ?? false) ...[
                    _CardButton(
                      label: '重新扫码登录',
                      icon: YIcons.qr,
                      onTap: () async {
                        await source.logout();
                        if (context.mounted) go(context, LoginRoute());
                      },
                    ),
                    const SizedBox(width: 10),
                  ],
                  _CardButton(label: '账号诊断', icon: YIcons.info, onTap: () => _diagnose(context, source)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 会员卡片上的半透明小按钮。
class _CardButton extends StatelessWidget {
  const _CardButton({required this.label, required this.icon, required this.onTap});

  final String label;
  final YIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(17)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            YIcon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(label, style: ts(13, weight: w600, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

/// 账号诊断：依次请求平台的会员与取地址接口，显示各接口的结果码，可以复制后发给开发者。
Future<void> _diagnose(BuildContext context, MusicSource source) async {
  final report = source.diagnose();
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final p = Palette.of(ctx);
      return AlertDialog(
        backgroundColor: p.dialog,
        title: Text('${source.name}账号诊断', style: ts(18, weight: w700, color: p.text)),
        content: SizedBox(
          width: 460,
          child: FutureBuilder<String>(
            future: report,
            builder: (ctx, snap) {
              if (!snap.hasData && !snap.hasError) {
                return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
              }
              final text = snap.data ?? '诊断失败：${snap.error}';
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('结果中不包含登录凭据。会员歌曲只能试听时，把它复制给开发者即可定位原因。', style: ts(12.5, height: 1.4, color: p.text2)),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: SingleChildScrollView(
                      child: SelectableText(text, style: ts(12.5, height: 1.5, color: p.text)),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('关闭')),
          TextButton(
            onPressed: () async {
              final text = await report.catchError((Object e) => '诊断失败：$e');
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Toast.show(ctx, '已复制诊断结果', icon: YIcons.check);
            },
            child: const Text('复制'),
          ),
        ],
      );
    },
  );
}
