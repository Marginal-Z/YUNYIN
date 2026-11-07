import 'dart:async';

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
import '../../data/sources/lx/lx_library_source.dart';
import '../../data/sources/source_manager.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 洛雪音源：导入自定义音源脚本（链接或文件），选择启用的音源与洛雪曲库浏览的平台，实时检测音源是否可用。
class LxSourcesPage extends StatefulWidget {
  const LxSourcesPage({super.key});

  @override
  State<LxSourcesPage> createState() => _LxSourcesPageState();
}

class _LxSourcesPageState extends State<LxSourcesPage> {
  final _url = TextEditingController();
  bool _busy = false;
  bool _checking = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // 打开页面时检测一次，停留期间每两分钟重新检测。
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _check());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _url.dispose();
    super.dispose();
  }

  /// 用当前曲库飙升榜的第一首歌检测启用的音源能否取到可以访问的地址。
  Future<void> _check({bool manual = false}) async {
    if (_checking || !mounted) return;
    final lx = context.read<LxSources>();
    if (lx.enabled.isEmpty) return;
    final library = context.read<SourceManager>().sources.whereType<LxLibrarySource>().firstOrNull;
    if (library == null) return;
    setState(() => _checking = true);
    try {
      final sample = await library.sample();
      if (sample == null) throw Exception('没有取到用于检测的歌曲');
      await lx.check(sample.$2, sample.$1);
    } catch (e) {
      if (mounted && manual) Toast.show(context, '检测失败：${errorText(e)}', icon: YIcons.info);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _run(Future<LxScript> Function() job) async {
    setState(() => _busy = true);
    try {
      final s = await job();
      if (mounted) Toast.show(context, '已导入并启用：${s.name}');
      _url.clear();
      unawaited(_check());
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
    return AdaptivePage(
      chrome: Chrome.none,
      mobileTop: 22,
            children: [
        PageHeader('洛雪音源', subtitle: '导入洛雪音乐格式的自定义音源'),
        const SizedBox(height: 10),
        Text(
          '洛雪曲库是独立的平台模式（在个人中心切换）：可以浏览启用的音源所支持平台的曲库，播放时按顺序用这里启用的音源获取地址（可同时启用多个）。'
          '网易云、QQ 音乐、酷狗只播放各自官方接口的歌曲，不使用洛雪音源。音源脚本由你自行导入，请只使用可信来源的脚本。',
          style: ts(13, height: 1.55, color: p.text2),
        ),
        const SizedBox(height: 18),
        Text('洛雪曲库', style: ts(15, weight: w700, color: p.text)),
        const SizedBox(height: 8),
        if (lx.availableCatalogs.isEmpty)
          Text('导入并启用音源后，可以在这里选择浏览哪个平台的曲库（由音源支持的平台决定）。目前浏览酷我曲库。', style: ts(13, height: 1.5, color: p.text2))
        else ...[
          ChipBar(
            labels: [for (final k in lx.availableCatalogs) LxSources.platformNames[k]!],
            index: lx.availableCatalogs.indexOf(lx.catalog).clamp(0, lx.availableCatalogs.length - 1),
            scroll: true,
            onChanged: (i) async {
              await lx.setCatalog(lx.availableCatalogs[i]);
              unawaited(_check());
            },
          ),
          const SizedBox(height: 6),
          Text(
            '搜索、排行榜与歌词来自${LxSources.platformNames[lx.catalog]}的公开接口，播放只使用支持${LxSources.platformNames[lx.catalog]}（${lx.catalog}）的音源。',
            style: ts(13, height: 1.5, color: p.text2),
          ),
        ],
        const SizedBox(height: 18),
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
          Row(
            children: [
              Expanded(
                child: Text('启用的音源按列表顺序依次尝试；点按“↑”调整优先级。状态每两分钟自动检测一次。', style: ts(13, height: 1.5, color: p.text2)),
              ),
              const SizedBox(width: 10),
              SecondaryButton(
                label: _checking ? '检测中…' : '检测可用性',
                icon: YIcons.refresh,
                iconSize: 16,
                height: 36,
                fontSize: 13,
                onTap: _checking || lx.enabled.isEmpty ? null : () => _check(manual: true),
              ),
            ],
          ),
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
    final health = lx.health[script.id];
    final platformText = platforms.isEmpty
        ? (script.platforms.isEmpty ? '' : script.platforms.map((k) => LxSources.platformNames[k] ?? k).join('、'))
        : platforms.entries.map((e) => '${LxSources.platformNames[e.key] ?? e.key}（${e.value.join('/')}）').join('、');
    final detail = error != null
        ? '启动失败：${error.replaceFirst('Exception: ', '')}'
        : failure != null
        ? '最近一次取地址失败：$failure（音源的服务器可能无法访问）'
        : platformText.isEmpty
        ? (script.enabled ? '第一次需要时启动' : '未启用')
        : platformText;
    final (statusText, statusColor) = !script.enabled
        ? ('未启用', p.text3)
        : health == null
        ? ('未检测', p.text3)
        : health.checking && health.ok == null
        ? ('检测中…', p.text2)
        : health.ok == true
        ? ('可用${health.latency == null ? '' : ' · ${health.latency!.inMilliseconds} ms'}${health.checking ? '（检测中…）' : ''}', const Color(0xFF2FA84F))
        : ('不可用${health.message == null ? '' : '：${health.message}'}${health.checking ? '（检测中…）' : ''}', p.danger);
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
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        statusText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(12, weight: w600, color: statusColor),
                      ),
                    ),
                  ],
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
