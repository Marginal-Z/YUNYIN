import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../voice/engines/system_engine.dart';
import '../../voice/moss/moss_models.dart';
import '../../voice/speech_output.dart';
import '../../voice/tts_types.dart';
import '../../voice/voice_library.dart';
import '../../voice/voice_settings.dart';

/// 音色中心的配色：浅色、白底、蓝色强调，不使用渐变与紫色。
abstract final class _C {
  static const bg = Color(0xFFFFFFFF);
  static const border = Color(0xFFE5E8EF);
  static const text = Color(0xFF0F172A);
  static const text2 = Color(0xFF64748B);
  static const accent = Color(0xFF2563EB);
  static const accentBg = Color(0xFFEEF4FF);
  static const danger = Color(0xFFDC2626);
}

/// 音色中心：试听并选择云音助手的声音。
///
/// 首选本机语音（MOSS-TTS-Nano 的四个年轻中文声音，下载一次模型后离线合成）；没有下载或设备不支持时，
/// 用系统自带的语音引擎：女声 / 男声按音高自动选择，也可以指定系统里的某一个中文声音。
class VoiceCenterPage extends StatefulWidget {
  const VoiceCenterPage({super.key});

  @override
  State<VoiceCenterPage> createState() => _VoiceCenterPageState();
}

class _VoiceCenterPageState extends State<VoiceCenterPage> with WidgetsBindingObserver {
  static const _lang = VoiceLanguage.zh;
  String? _previewing;

  /// 每个声音卡片底部的一行状态（固定占一行，试听前后页面不跳动）。
  final Map<String, ({String text, bool error})> _status = {};

  /// 系统里的中文声音（Android）；为 null 表示还在读取。
  List<SystemVoice>? _system;

  static bool get _android => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    MossDownload.instance.addListener(_onDownload);
    _loadSystem();
    _loadMoss();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    MossDownload.instance.removeListener(_onDownload);
    super.dispose();
  }

  /// 从系统设置回来后重新读取（可能新装了声音）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadSystem();
  }

  /// 本机语音：设备是否支持、模型是否已下载（为 null 表示还在检查）。
  bool? _mossSupported;
  bool _mossReady = false;

  Future<void> _loadMoss() async {
    final supported = await MossModels.supported();
    final ready = supported && await MossModels.ready();
    if (!mounted) return;
    setState(() {
      _mossSupported = supported;
      _mossReady = ready;
    });
  }

  /// 下载进度变化时刷新；下载结束后重新检查模型。
  void _onDownload() {
    if (!mounted) return;
    setState(() {});
    if (!MossDownload.instance.running) _loadMoss();
  }

  Future<void> _deleteMoss() async {
    await context.read<SpeechOutput>().stop();
    await MossModels.delete();
    await _loadMoss();
  }

  Future<void> _loadSystem() async {
    final list = await SystemTtsEngine.voices();
    if (mounted) setState(() => _system = list);
  }

  Future<void> _preview(VoiceProfile v) async {
    final out = context.read<SpeechOutput>();
    if (_previewing == v.id) {
      await out.stop();
      setState(() => _previewing = null);
      return;
    }
    await out.stop();
    setState(() {
      _previewing = v.id;
      _status.remove(v.id);
    });
    await out.say(v.preview(_lang), voice: v);
    if (!mounted) return;
    setState(() {
      _previewing = null;
      if (out.lastError != null && out.lastEngine == null) _status[v.id] = (text: '试听失败：${out.lastError}', error: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<VoiceSettings>();
    final pad = MediaQuery.paddingOf(context);
    final system = _system;
    return ColoredBox(
      color: _C.bg,
      child: DefaultTextStyle(
        style: ts(15, color: _C.text),
        child: ListView(
          padding: EdgeInsets.fromLTRB(20, pad.top + 12, 20, pad.bottom + 40),
          children: [
            Row(
              children: [
                YIconButton(YIcons.back, size: 44, iconSize: 22, color: _C.text, label: '返回', onTap: () => Navigator.of(context).maybePop()),
                const SizedBox(width: 4),
                Expanded(child: Text('音色中心', style: ts(24, weight: w700, color: _C.text))),
              ],
            ),
            const SizedBox(height: 4),
            Text('首选本机语音：四个年轻的中文声音，在手机上离线合成，不联网。没有下载模型时，用系统自带的语音引擎。', style: ts(13.5, height: 1.5, color: _C.text2)),
            const SizedBox(height: 14),
            ..._mossSection(s),
            Text('自动', style: ts(17, weight: w700, color: _C.text)),
            const SizedBox(height: 10),
            for (final v in VoicePresets.all) ...[_voiceCard(v, s), const SizedBox(height: 12)],
            if (_android) ...[
              const SizedBox(height: 8),
              Text('本机的中文声音', style: ts(17, weight: w700, color: _C.text)),
              const SizedBox(height: 6),
              Text(
                system == null
                    ? '正在读取系统里的声音（第一次会逐个试读一句，判断是女声还是男声）…'
                    : (system.isEmpty ? '系统里没有可以离线使用的中文声音。请在系统的“文字转语音”设置中安装中文语音。' : '共 ${system.length} 个。想要更多声音（例如谷歌语音服务的中文声音），可以在系统的“文字转语音”设置中安装或切换语音引擎。'),
                style: ts(13, height: 1.5, color: _C.text2),
              ),
              const SizedBox(height: 10),
              for (final sv in system ?? const <SystemVoice>[]) ...[
                _voiceCard(VoicePresets.system(sv.name, label: sv.label, female: sv.female), s, detail: '${sv.name} · 音调约 ${sv.pitch.round()} Hz'),
                const SizedBox(height: 12),
              ],
              _Button('系统语音设置', icon: YIcons.sliders, primary: false, onTap: SystemTtsEngine.openSettings),
              const SizedBox(height: 18),
            ],
            Text('朗读', style: ts(17, weight: w700, color: _C.text)),
            const SizedBox(height: 10),
            _Panel(
              children: [
                _Row(
                  title: '情绪表达',
                  subtitle: '按聊天内容调整语速与停顿，声音不变',
                  trailing: _Toggle(value: s.expressive, onChanged: s.setExpressive),
                ),
                _Row(
                  title: '语速',
                  subtitle: '${s.rate.toStringAsFixed(1)} 倍',
                  trailing: SizedBox(
                    width: 160,
                    child: SliderTheme(
                      data: SliderThemeData(activeTrackColor: _C.accent, inactiveTrackColor: _C.border, thumbColor: _C.accent, overlayShape: SliderComponentShape.noOverlay, trackHeight: 3),
                      child: Slider(value: s.rate, min: 0.7, max: 1.4, divisions: 7, onChanged: s.setRate),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _mossSection(VoiceSettings s) {
    final supported = _mossSupported;
    if (supported == null) return const [];
    final dl = MossDownload.instance;
    final mb = (MossModels.totalBytes / (1 << 20)).round();
    return [
      Text('本机语音', style: ts(17, weight: w700, color: _C.text)),
      const SizedBox(height: 6),
      if (!supported)
        Text('本机语音需要内存 6 GB 以上的 Android 手机；这台设备使用系统朗读。', style: ts(13, height: 1.5, color: _C.text2))
      else if (!_mossReady)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('MOSS-TTS-Nano', style: ts(16, weight: w700, color: _C.text)),
              const SizedBox(height: 6),
              Text(
                '复旦大学 OpenMOSS 团队开源的语音合成模型（Apache-2.0）。灵语、悦雯两个女声，俊豪、志明两个男声，48 kHz 高清音质。'
                '需要下载一次模型（约 $mb MB，建议连接 Wi‑Fi），之后完全离线。',
                style: ts(13, height: 1.5, color: _C.text2),
              ),
              const SizedBox(height: 12),
              if (dl.running) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(value: dl.progress, minHeight: 6, color: _C.accent, backgroundColor: _C.border),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: Text('正在下载 ${((dl.progress ?? 0) * 100).toStringAsFixed(0)}%（约 $mb MB）', style: ts(13, color: _C.text2))),
                    _Button('暂停', primary: false, onTap: dl.cancel),
                  ],
                ),
              ] else ...[
                _Button('下载本机语音（约 $mb MB）', icon: YIcons.download, primary: true, onTap: dl.start),
                if (dl.error != null) ...[const SizedBox(height: 8), Text(dl.error!, maxLines: 3, style: ts(12.5, height: 1.4, color: _C.danger))],
              ],
            ],
          ),
        )
      else ...[
        for (final v in VoicePresets.moss) ...[_voiceCard(v, s), const SizedBox(height: 12)],
        Row(
          children: [
            Expanded(child: Text('模型约 $mb MB，第一次说话需要几秒加载。', style: ts(12.5, color: _C.text2))),
            _Button('删除模型', primary: false, onTap: _deleteMoss),
          ],
        ),
      ],
      const SizedBox(height: 18),
    ];
  }

  Widget _voiceCard(VoiceProfile v, VoiceSettings s, {String? detail}) {
    final selected = s.voiceId == v.id;
    final previewing = _previewing == v.id;
    // 合成第一句要一点时间：还没出声时显示“合成中”，出声后才显示“停止”。
    final audible = previewing && context.select<SpeechOutput, bool>((o) => o.audible);
    final status = _status[v.id];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: selected ? _C.accentBg : _C.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? _C.accent : _C.border, width: selected ? 1.6 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(v.name, style: ts(19, weight: w700, color: _C.text)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), border: Border.all(color: _C.accent)),
                child: Text(v.style, style: ts(12, weight: w600, color: _C.accent)),
              ),
              const Spacer(),
              if (selected)
                Row(
                  children: [
                    const YIcon(YIcons.check, size: 16, strokeWidth: 2.6, color: _C.accent),
                    const SizedBox(width: 4),
                    Text('正在使用', style: ts(13, weight: w600, color: _C.accent)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(detail ?? v.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13, height: 1.45, color: _C.text2)),
          const SizedBox(height: 12),
          Row(
            children: [
              _Button(
                previewing ? (audible ? '停止' : '合成中') : '试听',
                icon: previewing ? (audible ? YIcons.pause : null) : YIcons.play,
                busy: previewing && !audible,
                primary: false,
                onTap: () => _preview(v),
              ),
              const SizedBox(width: 10),
              if (!selected) _Button('使用这个声音', primary: true, onTap: () => s.setVoice(v.id)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 18,
            child: Text(status?.text ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, color: status?.error == true ? _C.danger : _C.text2)),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: _C.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border)),
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, color: _C.border, indent: 16),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, required this.trailing});

  final String title;
  final String? subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: ts(15, color: _C.text)),
                if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: ts(12.5, height: 1.4, color: _C.text2))],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }
}

/// 扁平的开关（不使用 Material 开关）。
class _Toggle extends StatelessWidget {
  const _Toggle({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () => onChanged(!value),
      semanticLabel: value ? '已开启' : '已关闭',
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 26,
        padding: const EdgeInsets.all(3),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        decoration: BoxDecoration(color: value ? _C.accent : _C.border, borderRadius: BorderRadius.circular(13)),
        child: Container(width: 20, height: 20, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
      ),
    );
  }
}
class _Button extends StatelessWidget {
  const _Button(this.label, {required this.primary, required this.onTap, this.icon, this.busy = false});

  final String label;
  final bool primary;
  final VoidCallback? onTap;
  final YIconData? icon;

  /// 显示转圈（正在合成）。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : _C.accent;
    return Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          height: 34,
          // 最小宽度固定：“试听 / 合成中 / 停止”切换时按钮不变宽变窄，旁边的按钮不会跟着挪动。
          constraints: const BoxConstraints(minWidth: 88),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: primary ? _C.accent : _C.bg,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: _C.accent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy) ...[SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.6, color: fg)), const SizedBox(width: 6)],
              if (icon != null && !busy) ...[YIcon(icon!, size: 14, color: fg), const SizedBox(width: 6)],
              Text(label, style: ts(13.5, weight: w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
