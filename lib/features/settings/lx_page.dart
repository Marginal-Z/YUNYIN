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
    final platforms = lx.platforms;
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
          '当前平台取不到完整播放地址（需要登录、会员或只有试听）时，用启用的音源获取同一首歌的地址。'
          '支持网易云（wy）、QQ 音乐（tx）、酷狗（kg）。音源脚本由你自行导入，请只使用可信来源的脚本。',
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
            child: StateView.empty(title: '还没有导入音源', message: '导入后在这里选择启用的音源。', icon: YIcons.source),
          )
        else
          CardList(
            indent: 56,
            children: [
              for (final s in lx.scripts)
                SettingsRow(
                  icon: YIcons.source,
                  tile: s.id == lx.active?.id ? TileColor.red : TileColor.graphite,
                  title: '${s.name}${s.version.isEmpty ? '' : '  v${s.version}'}',
                  value: s.id == lx.active?.id ? '已启用' : null,
                  height: 58,
                  onTap: () => lx.setActive(s.id == lx.active?.id ? null : s.id),
                  trailing: YIconButton(
                    YIcons.trash,
                    color: p.text2,
                    label: '删除${s.name}',
                    onTap: () async {
                      final ok = await showConfirm(context, title: '删除音源？', message: '删除“${s.name}”。', confirm: '删除');
                      if (ok) await lx.remove(s.id);
                    },
                  ),
                ),
            ],
          ),
        if (lx.active != null) ...[
          const SizedBox(height: 14),
          Text(
            lx.lastError != null
                ? '音源启动失败：${lx.lastError}'
                : platforms.isEmpty
                ? '音源会在第一次需要时启动。'
                : '支持：${platforms.entries.map((e) => '${LxSources.platformNames[e.key] ?? e.key}（${e.value.join(' / ')}）').join('、')}',
            style: ts(13, height: 1.5, color: lx.lastError != null ? p.danger : p.text2),
          ),
        ],
      ],
    );
  }
}

/// 设置页中的入口值：启用的音源名称。
String lxSummary(LxSources lx) => lx.active?.name ?? (lx.scripts.isEmpty ? '未导入' : '未启用');
