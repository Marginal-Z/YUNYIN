import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/icons.dart';
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
    final desktop = LayoutScope.isDesktop(context);
    Future<void> open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 78,
      overlay: [
        Positioned(
          left: 16,
          top: 20,
          child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
        ),
      ],
      children: [
        PageTitle('关于', size: desktop ? 40 : 36),
        const GroupLabel('隐私与权限', top: 18),
        CardList(
          indent: 56,
          children: [
            SettingsRow(icon: YIcons.shield, tile: TileColor.graphite, title: '隐私政策', onTap: () => go(context, AboutRoute(AboutPage.privacy))),
            SettingsRow(icon: YIcons.lock, tile: TileColor.teal, title: '权限管理', onTap: () => go(context, AboutRoute(AboutPage.permissions))),
          ],
        ),
        const GroupLabel('关于云音'),
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
            SettingsRow(icon: YIcons.document, tile: TileColor.orange, title: '用户协议', onTap: () => go(context, AboutRoute(AboutPage.agreement))),
            SettingsRow(
              icon: YIcons.code,
              tile: TileColor.graphite,
              title: '开源许可',
              onTap: () async {
                final info = await PackageInfo.fromPlatform();
                if (context.mounted) showLicensePage(context: context, applicationName: '云音', applicationVersion: info.version);
              },
            ),
            SettingsRow(icon: YIcons.feedback, tile: TileColor.red, title: '意见反馈', onTap: () => go(context, AboutRoute(AboutPage.feedback))),
            SettingsRow(icon: YIcons.code, tile: TileColor.graphite, title: '项目主页', value: 'GitHub', onTap: () => open(kRepoUrl)),
          ],
        ),
      ],
    );
  }
}
