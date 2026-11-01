import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/text_decode.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/lx/lx_sources.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 洛雪音源：导入自定义音源脚本（链接或文件），选择启用的音源。
class LxSourcesPage extends StatefulWidget {
  const LxSourcesPage({super.key});

  @override
  State<LxSourcesPage> createState() => _LxSourcesPageState();
}

class _LxSourcesPageState extends State<LxSourcesPage> {
  final _url = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _run(Future<LxScript> Function() job) async {
    setState(() => _busy = true);
    try {
      final s = await job();
      if (mounted) Toast.show(context, '已导入并启用：${s.name}');
      _url.clear();
    } catch (e) {
      if (mounted) Toast.show(context, '导入失败：${errorText(e)}', icon: YIcons.info);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _importFile() async {
    final files = await FilePicker.pickFiles(dialogTitle: '选择洛雪音源脚本', type: FileType.custom, allowedExtensions: const ['js']);
    final f = files.firstOrNull;
    if (f == null || !mounted) return;
    final bytes = <int>[];
    await for (final chunk in f.readAsByteStream()) {
      bytes.addAll(chunk);
    }
    if (!mounted) return;
    final lx = context.read<LxSources>();
    await _run(() => lx.importText(decodeText(bytes)));
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final lx = context.watch<LxSources>();
    final desktop = LayoutScope.isDesktop(context);
    return AdaptivePage(
      chrome: Chrome.none,
      mobileTop: 78,
      overlay: [
        Positioned(
          left: 16,
          top: 20,
          child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
        ),
      ],
      children: [
        PageTitle('洛雪音源', subtitle: '导入洛雪音乐格式的自定义音源', size: desktop ? 40 : 36),
        const SizedBox(height: 10),
        Text(
          '洛雪曲库是独立的平台模式（在个人中心切换）：曲库来自酷我，播放时按顺序用这里启用的音源获取地址（需要支持酷我 kw，可同时启用多个）。'
          '网易云、QQ 音乐、酷狗只播放各自官方接口的歌曲，不使用洛雪音源。音源脚本由你自行导入，请只使用可信来源的脚本。',
          style: ts(13, height: 1.55, color: p.text2),
        ),
        const SizedBox(height: 16),
        Container(
          height: 50,
          padding: const EdgeInsets.only(left: 16, right: 6),
          decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  style: ts(15, color: p.text),
                  cursorColor: p.accentText,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: '音源脚本链接（https://…/xxx.js）',
                    hintStyle: ts(15, color: p.text3),
                  ),
                ),
              ),
              PrimaryButton(
                label: _busy ? '导入中…' : '导入',
                height: 38,
                fontSize: 14,
                enabled: !_busy,
                onTap: () {
                  final url = _url.text.trim();
                  if (!url.startsWith('http')) {
                    Toast.show(context, '请输入以 http 开头的链接', icon: YIcons.info);
                    return;
                  }
                  _run(() => lx.importUrl(url));
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SecondaryButton(label: '从文件导入（.js）', icon: YIcons.folder, iconSize: 18, height: 46, fontSize: 15, onTap: _busy ? null : _importFile),
        const SizedBox(height: 22),
        if (lx.scripts.isEmpty)
          YCard(
            child: StateView.empty(title: '还没有导入音源', message: '可以导入多个音源，按顺序依次尝试，第一个成功的生效。', icon: YIcons.source),
          )
        else ...[
          CardList(
            indent: 14,
            children: [for (var i = 0; i < lx.scripts.length; i++) _ScriptRow(script: lx.scripts[i], index: i, lx: lx)],
          ),
          const SizedBox(height: 10),
          Text('启用的音源按列表顺序依次尝试；点按“↑”调整优先级。', style: ts(13, height: 1.5, color: p.text2)),
        ],
      ],
    );
  }
}

class _ScriptRow extends StatelessWidget {
  const _ScriptRow({required this.script, required this.index, required this.lx});

  final LxScript script;
  final int index;
  final LxSources lx;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final platforms = lx.platformsOf(script.id);
    final error = lx.errors[script.id];
    final failure = lx.lastFailures[script.id];
    final detail = error != null
        ? '启动失败：${error.replaceFirst('Exception: ', '')}'
        : failure != null
        ? '最近一次取地址失败：$failure（音源的服务器可能无法访问）'
        : platforms.isEmpty
        ? (script.enabled ? '第一次需要时启动' : '未启用')
        : platforms.entries.map((e) => '${LxSources.platformNames[e.key] ?? e.key}（${e.value.join('/')}）').join('、');
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '${index + 1}',
              style: ts(15, weight: w700, color: script.enabled ? p.accentText : p.text3, tabular: true),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // 版本号本身可能已经带有 v。
                  '${script.name}${script.version.isEmpty ? '' : '  v${script.version.replaceFirst(RegExp('^[vV]'), '')}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: ts(16, weight: w600, color: p.text),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: ts(12, color: error != null || failure != null ? p.danger : p.text2),
                ),
              ],
            ),
          ),
          if (index > 0)
            YIconButton(YIcons.chevronDown, size: 34, iconSize: 18, color: p.text2, label: '上移${script.name}', onTap: () => lx.moveUp(script.id)).flipped(),
          YIconButton(
            YIcons.trash,
            size: 34,
            iconSize: 18,
            color: p.text2,
            label: '删除${script.name}',
            onTap: () async {
              final ok = await showConfirm(context, title: '删除音源？', message: '删除“${script.name}”。', confirm: '删除');
              if (ok) await lx.remove(script.id);
            },
          ),
          YSwitch(value: script.enabled, label: '启用${script.name}', onChanged: (v) => lx.setEnabled(script.id, v)),
        ],
      ),
    );
  }
}

extension on Widget {
  /// 向下箭头翻转为向上箭头。
  Widget flipped() => Transform.flip(flipY: true, child: this);
}

/// 设置页中的入口值：启用的音源名称。
String lxSummary(LxSources lx) => lx.scripts.isEmpty ? '未导入' : (lx.enabled.isEmpty ? '未启用' : '已启用 ${lx.enabled.length} 个');
