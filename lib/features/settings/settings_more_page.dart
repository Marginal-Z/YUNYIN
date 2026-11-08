import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../core/update/updater.dart';
import '../common/layout.dart';
import '../shell/nav.dart';
import '../common/actions.dart';
import 'about_pages.dart';
import 'update_dialog.dart';

/// 关于云音：协议、隐私、权限与版本。
class SettingsMorePage extends StatelessWidget {
  const SettingsMorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AppSettings>();
    final updater = context.watch<UpdateManager>();
    Future<void> open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 22,
            children: [
        PageHeader('关于云音', subtitle: '音乐 · 生活 · 云音'),
        const SizedBox(height: 18),
        Center(
          child: Column(
            children: [
              const AppLogo(size: 88, gradient: true),
              const SizedBox(height: 14),
              Text('云音', style: ts(24, weight: w700, color: p.text)),
              const SizedBox(height: 4),
              Text(updater.current.isEmpty ? '' : '版本 v${updater.current}', style: ts(14, color: p.text2)),
            ],
          ),
        ),
        const GroupLabel('应用与更新'),
        CardList(
          indent: 56,
          children: [
            SettingsRow(icon: YIcons.info, tile: TileColor.blue, title: '当前版本', value: updater.current.isEmpty ? '' : 'v${updater.current}'),
            SettingsRow(
              icon: YIcons.refresh,
              tile: TileColor.teal,
              title: '检查更新',
              value: switch (updater.stage) {
                UpdateStage.checking => '正在检查…',
                UpdateStage.downloading => '正在下载 ${(updater.progress * 100).toStringAsFixed(0)}%',
                _ => updater.hasUpdate ? '新版本 v${updater.latest!.version}' : null,
              },
              trailing: updater.hasUpdate
                  ? Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: p.danger, shape: BoxShape.circle),
                    )
                  : null,
              onTap: updater.stage == UpdateStage.checking ? null : () => updater.hasUpdate ? showUpdateDialog(context) : checkForUpdate(context),
            ),
            SettingsRow(
              icon: YIcons.bell,
              tile: TileColor.orange,
              title: '启动时检查更新',
              trailing: YSwitch(value: s.autoUpdate, label: '启动时检查更新', onChanged: (v) => s.setFlag('autoUpdate', v)),
            ),
            SettingsRow(
              icon: YIcons.equalizer,
              tile: TileColor.graphite,
              title: '流畅度检测',
              subtitle: '右上角显示帧率与最慢一帧的耗时，用于反馈卡顿',
              trailing: YSwitch(value: s.perfOverlay, label: '流畅度检测', onChanged: (v) => s.setFlag('perfOverlay', v)),
            ),
            // 对照实验（只在检测时显示，不保存）：逐个关闭，看哪一项让页面切换掉帧。
            if (s.perfOverlay) ...[
              SettingsRow(
                title: '实验：页面切换不缩放',
                trailing: YSwitch(value: s.perfNoScale, label: '页面切换不缩放', onChanged: (v) => s.setFlag('perfNoScale', v)),
              ),
              SettingsRow(
                title: '实验：不画卡片阴影',
                trailing: YSwitch(value: s.perfNoShadow, label: '不画卡片阴影', onChanged: (v) => s.setFlag('perfNoShadow', v)),
              ),
              SettingsRow(
                title: '实验：隐藏底部栏与播放条',
                trailing: YSwitch(value: s.perfNoChrome, label: '隐藏底部栏与播放条', onChanged: (v) => s.setFlag('perfNoChrome', v)),
              ),
            ],
          ],
        ),
        const GroupLabel('隐私与权限'),
        CardList(
          indent: 56,
          children: [
            SettingsRow(icon: YIcons.shield, tile: TileColor.teal, title: '隐私政策', onTap: () => go(context, AboutRoute(AboutPage.privacy))),
            SettingsRow(icon: YIcons.lock, tile: TileColor.red, title: '权限管理', onTap: () => go(context, AboutRoute(AboutPage.permissions))),
          ],
        ),
        const GroupLabel('协议与开源'),
        CardList(
          indent: 56,
          children: [
            SettingsRow(icon: YIcons.document, tile: TileColor.orange, title: '用户协议', onTap: () => go(context, AboutRoute(AboutPage.agreement))),
            SettingsRow(
              icon: YIcons.code,
              tile: TileColor.teal,
              title: '开源许可',
              onTap: () async {
                final info = await PackageInfo.fromPlatform();
                if (context.mounted) showLicensePage(context: context, applicationName: '云音', applicationVersion: info.version);
              },
            ),
            SettingsRow(icon: YIcons.share, tile: TileColor.blue, title: '项目主页', value: 'GitHub', onTap: () => open(kRepoUrl)),
          ],
        ),
        const GroupLabel('意见反馈'),
        CardList(
          indent: 56,
          children: [SettingsRow(icon: YIcons.feedback, tile: TileColor.graphite, title: '意见反馈', onTap: () => go(context, AboutRoute(AboutPage.feedback)))],
        ),
      ],
    );
  }
}
