import 'dart:async';

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

/// 问题诊断：设备与运行状态、最近的日志，以及导出日志（附在反馈里）。
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  final _d = Diagnostics.instance;
  String _summary = '';
  bool _exporting = false;

  /// 每 2 秒刷新一次状态与日志。
  Timer? _refresh;

  @override
  void initState() {
    super.initState();
    _load();
    _refresh = Timer.periodic(const Duration(seconds: 2), (_) => _load());
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final s = await _d.summary();
    if (mounted) setState(() => _summary = s);
  }

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      final tip = await _d.export();
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
    final lines = _d.recent.reversed.take(60).toList();
    final slowRate = _d.frames == 0 ? 0.0 : _d.slowFrames * 100 / _d.frames;
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 22,
      children: [
        const PageHeader('问题诊断', subtitle: '遇到问题时导出日志，附在反馈里'),
        const GroupLabel('运行状态'),
        CardList(
          indent: 14,
          children: [
            SettingsRow(title: '流畅度', value: _d.frames == 0 ? '暂无数据' : '慢帧 ${slowRate.toStringAsFixed(1)}% · 最慢 ${_d.worstFrameMs.toStringAsFixed(0)} ms'),
            SettingsRow(title: '错误', value: _d.errors == 0 ? '无' : '${_d.errors} 次'),
          ],
        ),
        const SizedBox(height: 12),
        YCard(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Text(_summary.trim(), style: ts(13, height: 1.6, color: p.text2)),
        ),
        const SizedBox(height: 18),
        PrimaryButton(label: _exporting ? '正在导出…' : '导出日志', icon: YIcons.share, expand: true, onTap: _export),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: '复制摘要',
                icon: YIcons.document,
                iconSize: 16,
                height: 44,
                fontSize: 14,
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _summary));
                  Toast.show(context, '已复制');
                },
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SecondaryButton(
                label: '清空日志',
                icon: YIcons.trashSimple,
                iconSize: 16,
                height: 44,
                fontSize: 14,
                onTap: () async {
                  await _d.clear();
                  await _load();
                  if (context.mounted) Toast.show(context, '已清空');
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '日志只保存在本机，不会自动上传。导出的文件包含设备型号、系统版本、运行状态、卡顿与错误记录，以及最近的退出原因，'
          '已去掉 Cookie、密钥等登录凭据；你可以先查看内容，再决定发给谁。',
          style: ts(12.5, height: 1.55, color: p.text3),
        ),
        const GroupLabel('最近日志'),
        YCard(
          radius: 18,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: lines.isEmpty
              ? Text('暂无日志', style: ts(13, color: p.text3))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final l in lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          // 只显示时分秒，日期在导出的文件里。
                          l.length > 11 ? l.substring(11) : l,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: ts(
                            11.5,
                            height: 1.4,
                            color: switch (l.length > 24 ? l[24] : '') {
                              'E' => p.danger,
                              'W' => p.text,
                              _ => p.text2,
                            },
                          ),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}
