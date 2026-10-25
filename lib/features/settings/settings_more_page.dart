import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../core/update/updater.dart';
import '../../data/sources/source_manager.dart';
import '../common/layout.dart';
import '../shell/nav.dart';
import 'update_dialog.dart';

const kRepoUrl = 'https://github.com/Marginal-Z/YUNYIN';

/// 账号与关于。
class SettingsMorePage extends StatelessWidget {
  const SettingsMorePage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AppSettings>();
    final sm = context.watch<SourceManager>();
    final source = sm.current;
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
        PageTitle('账号与关于', size: desktop ? 40 : 36),
        const GroupLabel('通知与隐私', top: 18),
        CardList(
          indent: 56,
          children: [
            SettingsRow(
              icon: YIcons.bell,
              tile: TileColor.red,
              title: '推送通知',
              trailing: YSwitch(value: s.pushNotify, label: '推送通知', onChanged: (v) => s.setFlag('pushNotify', v)),
            ),
            SettingsRow(
              icon: YIcons.sparkle,
              tile: TileColor.blue,
              title: '个性化推荐',
              trailing: YSwitch(value: s.personalized, label: '个性化推荐', onChanged: (v) => s.setFlag('personalized', v)),
            ),
            SettingsRow(icon: YIcons.shield, tile: TileColor.graphite, title: '隐私政策', onTap: () => open('$kRepoUrl#隐私')),
            SettingsRow(
              icon: YIcons.lock,
              tile: TileColor.teal,
              title: '权限管理',
              onTap: () => Toast.show(context, '云音仅使用网络、存储与通知权限', icon: YIcons.lock),
            ),
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
            SettingsRow(icon: YIcons.document, tile: TileColor.orange, title: '用户协议', onTap: () => open('$kRepoUrl#免责声明')),
            SettingsRow(
              icon: YIcons.code,
              tile: TileColor.graphite,
              title: '开源许可',
              onTap: () async {
                final info = await PackageInfo.fromPlatform();
                if (context.mounted) showLicensePage(context: context, applicationName: '云音', applicationVersion: info.version);
              },
            ),
            SettingsRow(icon: YIcons.feedback, tile: TileColor.red, title: '意见反馈', onTap: () => open('$kRepoUrl/issues')),
            SettingsRow(icon: YIcons.code, tile: TileColor.graphite, title: '项目主页', value: 'GitHub', onTap: () => open(kRepoUrl)),
          ],
        ),
        const SizedBox(height: 22),
        if (source.loggedIn)
          Pressable(
            onTap: () async {
              final ok = await showConfirm(context, title: '退出登录？', message: '退出后将无法同步${source.name}的歌单与喜欢。', confirm: '退出');
              if (!ok || !context.mounted) return;
              await source.logout();
              if (context.mounted) {
                final nav = context.read<AppNav>();
                nav.pop();
                nav.push(LoginRoute());
              }
            },
            child: YCard(
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    '退出登录',
                    style: ts(16, weight: w600, color: p.danger),
                  ),
                ),
              ),
            ),
          )
        else
          Pressable(
            onTap: () => context.read<AppNav>().push(LoginRoute()),
            child: YCard(
              child: SizedBox(
                height: 52,
                child: Center(
                  child: Text(
                    '登录${source.name}',
                    style: ts(16, weight: w600, color: p.accentText),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
