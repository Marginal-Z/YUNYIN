import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/diagnostics.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../common/layout.dart';
import '../shell/nav.dart';
import 'diagnostics_checks.dart';

/// 问题诊断：点“开始诊断”后逐项检查设备、流畅度、网络、账号、播放、语音、存储、权限与退出记录，
/// 结果可以复制或导出（附带最近的应用日志）。只在手动开始时检查，平时不在后台运行。
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> with SingleTickerProviderStateMixin {
  final _results = <String, CheckResult>{};
  String? _running;
  bool _exporting = false;

  /// 流畅度测试期间播放的动画（让屏幕持续出帧）。
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  bool _animating = false;

  bool get _busy => _running != null;
  bool get _done => !_busy && _results.length == diagnosticChecks.length;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_busy) return;
    setState(_results.clear);
    final hooks = DiagnosticsHooks(
      setAnimating: (on) {
        if (!mounted) return;
        setState(() => _animating = on);
        on ? _spin.repeat() : _spin.stop();
      },
    );
    for (final check in diagnosticChecks) {
      if (!mounted) return;
      setState(() => _running = check.title);
      CheckResult r;
      try {
        r = await check.run(context, hooks);
      } catch (e) {
        r = CheckResult(CheckStatus.fail, '检查出错', ['$e']);
      }
      if (!mounted) return;
      setState(() => _results[check.title] = r);
    }
    if (mounted) setState(() => _running = null);
  }

  String _text() {
    final b = StringBuffer();
    for (final c in diagnosticChecks) {
      final r = _results[c.title];
      if (r == null) continue;
      b.writeln('【${c.title}】${_label(r.status)}：${r.summary}');
      for (final d in r.details) {
        b.writeln('  · $d');
      }
    }
    return b.toString();
  }

  static String _label(CheckStatus s) => switch (s) {
    CheckStatus.ok => '正常',
    CheckStatus.warn => '注意',
    CheckStatus.fail => '异常',
    CheckStatus.info => '信息',
  };

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final tip = await Diagnostics.instance.export(_text());
      if (mounted && tip.isNotEmpty) Toast.show(context, tip);
    } catch (e) {
      if (mounted) Toast.show(context, '$e'.replaceFirst('Exception: ', ''), icon: YIcons.info);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final counts = {for (final s in CheckStatus.values) s: _results.values.where((r) => r.status == s).length};
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 22,
      children: [
        const PageHeader('问题诊断', subtitle: '逐项检查云音的运行状况，结果可以导出附在反馈里'),
        const SizedBox(height: 6),
        PrimaryButton(
          label: _busy ? '正在检查：$_running' : (_results.isEmpty ? '开始诊断' : '重新诊断'),
          icon: YIcons.stats,
          expand: true,
          enabled: !_busy,
          onTap: _start,
        ),
        const SizedBox(height: 8),
        Text(
          _done
              ? '检查完成：${counts[CheckStatus.ok]} 项正常，${counts[CheckStatus.warn]} 项需要注意，${counts[CheckStatus.fail]} 项异常。'
              : '大约需要 10 秒。检查流畅度时会播放一段 3 秒的动画；检查语音合成时会在后台合成一句话（不会出声）。',
          style: ts(12.5, height: 1.5, color: p.text2),
        ),
        if (_animating) ...[
          const SizedBox(height: 12),
          _FrameTestAnimation(controller: _spin),
        ],
        const SizedBox(height: 14),
        for (final c in diagnosticChecks) ...[
          _CheckCard(title: c.title, result: _results[c.title], running: _running == c.title),
          const SizedBox(height: 10),
        ],
        if (_done) ...[
          const SizedBox(height: 6),
          PrimaryButton(label: _exporting ? '正在导出…' : '导出诊断报告', icon: YIcons.share, expand: true, onTap: _export),
          const SizedBox(height: 10),
          SecondaryButton(
            label: '复制检查结果',
            icon: YIcons.document,
            iconSize: 16,
            height: 44,
            fontSize: 14,
            onTap: () {
              Clipboard.setData(ClipboardData(text: _text()));
              Toast.show(context, '已复制');
            },
          ),
          const SizedBox(height: 10),
          Text(
            '诊断报告只在你点“导出”时生成，包含检查结果、设备型号、系统版本、最近的退出原因与最近的应用日志，'
            '已去掉 Cookie、密钥等登录凭据；你可以先查看内容，再决定发给谁。',
            style: ts(12.5, height: 1.55, color: p.text3),
          ),
        ],
      ],
    );
  }
}

class _CheckCard extends StatelessWidget {
  const _CheckCard({required this.title, required this.result, required this.running});

  final String title;
  final CheckResult? result;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final r = result;
    final color = switch (r?.status) {
      CheckStatus.ok => const Color(0xFF2BB673),
      CheckStatus.warn => const Color(0xFFF5A524),
      CheckStatus.fail => p.danger,
      _ => p.text3,
    };
    return YCard(
      radius: 16,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: running
                    ? CircularProgressIndicator(strokeWidth: 2, color: p.accentText)
                    : Center(
                        child: Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: ts(15, weight: w600, color: p.text))),
              if (r != null)
                Text(
                  switch (r.status) {
                    CheckStatus.ok => '正常',
                    CheckStatus.warn => '注意',
                    CheckStatus.fail => '异常',
                    CheckStatus.info => '',
                  },
                  style: ts(13, weight: w600, color: color),
                ),
            ],
          ),
          if (r != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.summary, style: ts(13.5, height: 1.45, color: p.text)),
                  for (final d in r.details) Text(d, style: ts(12.5, height: 1.5, color: p.text2)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 流畅度测试的动画：一排圆点来回移动、一个进度条，每一帧都要重新绘制。
class _FrameTestAnimation extends StatelessWidget {
  const _FrameTestAnimation({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return SizedBox(
      height: 44,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final t = controller.value;
          return Stack(
            children: [
              for (var i = 0; i < 8; i++)
                Align(
                  alignment: Alignment(-1 + 2 * ((t + i / 8) % 1), 0),
                  child: Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: p.accentText.withValues(alpha: 0.35 + 0.08 * i))),
                ),
              Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: t, minHeight: 3, color: p.accentText, backgroundColor: p.separator)),
            ],
          );
        },
      ),
    );
  }
}
