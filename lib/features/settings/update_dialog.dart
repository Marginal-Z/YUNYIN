import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../core/update/updater.dart';

bool _open = false;

/// 新版本弹窗：更新说明、下载进度与安装。
Future<void> showUpdateDialog(BuildContext context) async {
  if (_open) return;
  _open = true;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '稍后',
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.25),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, _, _) => const Center(child: _UpdateCard()),
    transitionBuilder: (ctx, a, _, child) => FadeTransition(
      opacity: a,
      child: ScaleTransition(
        scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)),
        child: child,
      ),
    ),
  );
  _open = false;
}

/// 设置页“检查更新”：没有新版本时提示已是最新。
Future<void> checkForUpdate(BuildContext context) async {
  final u = context.read<UpdateManager>();
  final has = await u.check();
  if (!context.mounted) return;
  if (has) {
    await showUpdateDialog(context);
  } else {
    Toast.show(context, u.error ?? '已是最新版本 v${u.current}', icon: u.error == null ? YIcons.check : YIcons.info);
  }
}

/// 更新说明去掉 Markdown 标记，便于直接显示。
String _plain(String md) => md
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('**Full Changelog**'))
    .map((l) => l.replaceAll(RegExp(r'^#+\s*'), '').replaceAll(RegExp(r'^\s*[-*]\s+'), '• ').replaceAll('**', '').replaceAll('`', ''))
    .join('\n')
    .trim();

class _UpdateCard extends StatelessWidget {
  const _UpdateCard();

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final u = context.watch<UpdateManager>();
    final r = u.latest;
    if (r == null) return const SizedBox.shrink();
    final busy = u.stage == UpdateStage.downloading || u.stage == UpdateStage.installing;
    final notes = _plain(r.notes);
    return SizedBox(
      width: 360,
      child: YBox(
        radius: BorderRadius.circular(24),
        color: p.dialog,
        blur: true,
        shadows: const [Shadow2(0, 24, 50, Color.fromRGBO(28, 44, 92, 0.22))],
        insets: [Shadow2(0, 0, 0, p.isDark ? const Color.fromRGBO(255, 255, 255, 0.1) : const Color.fromRGBO(255, 255, 255, 0.9), spread: 1)],
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const AppLogo(size: 44, gradient: true),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '发现新版本 v${r.version}',
                            style: ts(18, weight: w700, color: p.text),
                          ),
                          const SizedBox(height: 2),
                          Text('当前 v${u.current} · ${u.kindLabel}', style: ts(13, color: p.text2)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: SingleChildScrollView(
                    child: Text(notes.isEmpty ? '修复问题并改进体验。' : notes, style: ts(14, height: 1.55, color: p.text2)),
                  ),
                ),
                const SizedBox(height: 16),
                if (busy) ...[
                  _Bar(value: u.stage == UpdateStage.installing ? 1 : u.progress),
                  const SizedBox(height: 8),
                  Text(
                    u.stage == UpdateStage.installing ? '正在安装，云音将自动重新打开…' : '正在下载 ${(u.progress * 100).toStringAsFixed(0)}%',
                    style: ts(13, color: p.text2, tabular: true),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                if (u.error != null) ...[
                  Text(
                    u.error!,
                    style: ts(13, height: 1.4, color: p.danger),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                ],
                if (u.stage == UpdateStage.downloading)
                  SecondaryButton(label: '取消下载', height: 44, fontSize: 15, onTap: u.cancel)
                else if (u.stage != UpdateStage.installing) ...[
                  PrimaryButton(label: '立即更新', icon: YIcons.download, height: 46, fontSize: 16, expand: true, onTap: u.downloadAndInstall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _TextButton('跳过此版本', () {
                          context.read<AppSettings>().skipUpdate(r.version);
                          Navigator.of(context).pop();
                        }),
                      ),
                      Expanded(child: _TextButton('发布页', () => launchUrl(Uri.parse(r.page), mode: LaunchMode.externalApplication))),
                      Expanded(child: _TextButton('稍后', () => Navigator.of(context).pop())),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TextButton extends StatelessWidget {
  const _TextButton(this.label, this.onTap);

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Pressable(
    onTap: onTap,
    child: SizedBox(
      height: 38,
      child: Center(
        child: Text(
          label,
          style: ts(14, weight: w500, color: Palette.of(context).text2),
        ),
      ),
    ),
  );
}

class _Bar extends StatelessWidget {
  const _Bar({required this.value});

  final double value;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        height: 6,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: p.text.withValues(alpha: 0.1))),
            AnimatedFractionallySizedBox(
              duration: const Duration(milliseconds: 200),
              widthFactor: value.clamp(0.0, 1.0),
              heightFactor: 1,
              alignment: Alignment.centerLeft,
              child: ColoredBox(color: p.accentText),
            ),
          ],
        ),
      ),
    );
  }
}
