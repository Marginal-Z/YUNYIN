import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../voice/engines/local_engine.dart';
import '../../voice/speech_output.dart';
import '../../voice/tts_types.dart';
import '../../voice/voice_library.dart';
import '../../voice/voice_settings.dart';

/// 音色中心的配色：浅色、白底、蓝色强调，不使用渐变与紫色。
abstract final class _C {
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF7F8FA);
  static const border = Color(0xFFE5E8EF);
  static const text = Color(0xFF0F172A);
  static const text2 = Color(0xFF64748B);
  static const accent = Color(0xFF2563EB);
  static const accentBg = Color(0xFFEEF4FF);
  static const danger = Color(0xFFDC2626);
}

/// 云端引擎的说明与申请密钥的页面。
const _engineInfo = {
  'cosyvoice': ('CosyVoice', '阿里云百炼的语音合成，中文自然、支持中英文。密钥与通义千问相同（DashScope API Key）。', 'https://bailian.console.aliyun.com/'),
  'elevenlabs': ('ElevenLabs', '表现力强的多语言语音，用中文朗读。', 'https://elevenlabs.io/app/settings/api-keys'),
  'fish': ('Fish Audio', '支持声音克隆。需要在音色的“高级”中填写你在 Fish Audio 选择或克隆的声音 ID。', 'https://fish.audio/app/api-keys/'),
};

/// 音色中心：试听、切换与设置默认音色；配置各个语音引擎。
class VoiceCenterPage extends StatefulWidget {
  const VoiceCenterPage({super.key});

  @override
  State<VoiceCenterPage> createState() => _VoiceCenterPageState();
}

class _VoiceCenterPageState extends State<VoiceCenterPage> {
  /// 云音助手只说中文。
  static const _lang = VoiceLanguage.zh;
  String? _previewing;
  String? _expanded;
  final Map<String, double> _downloads = {};
  final Map<String, bool> _installed = {};
  String? _message;

  @override
  void initState() {
    super.initState();
    _refreshInstalled();
  }

  Future<void> _refreshInstalled() async {
    for (final m in LocalVoiceModels.all) {
      _installed[m.id] = await LocalTtsEngine.isInstalled(m);
    }
    if (mounted) setState(() {});
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
      _message = null;
    });
    await out.say(v.preview(_lang), voice: v);
    if (!mounted) return;
    setState(() {
      _previewing = null;
      _message = out.lastError != null && out.lastEngine == null ? '试听失败：${out.lastError}' : (out.lastEngine == null ? null : '${v.name} · ${out.lastEngine}');
    });
  }

  Future<void> _download(VoiceProfile v) async {
    final id = v.binding('local')?.voices[_lang];
    final m = id == null ? null : LocalVoiceModels.byId(id);
    if (m == null || _downloads.containsKey(m.id)) return;
    setState(() => _downloads[m.id] = 0);
    try {
      await LocalTtsEngine().prepare(v.binding('local')!, _lang, onProgress: (p) {
        if (mounted) setState(() => _downloads[m.id] = p);
      }, cancel: CancelToken());
    } catch (e) {
      if (mounted) setState(() => _message = '下载失败：$e');
    }
    _downloads.remove(m.id);
    await _refreshInstalled();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<VoiceSettings>();
    final pad = MediaQuery.paddingOf(context);
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
            Text('为云音助手选择声音。每个音色都是独立的声音模型或供应商音色，不是同一个声音改变音调。', style: ts(13.5, height: 1.5, color: _C.text2)),
            if (_message != null) ...[const SizedBox(height: 10), Text(_message!, style: ts(13, color: _message!.startsWith('试听失败') || _message!.startsWith('下载失败') ? _C.danger : _C.text2))],
            const SizedBox(height: 14),
            for (final v in VoicePresets.all) ...[_voiceCard(v, s), const SizedBox(height: 12)],
            const SizedBox(height: 18),
            Text('朗读', style: ts(17, weight: w700, color: _C.text)),
            const SizedBox(height: 10),
            _Panel(
              children: [
                _Row(
                  title: '情绪表达',
                  subtitle: '按聊天内容调整语气、语速与停顿，音色不变',
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
                _Row(
                  title: '优先引擎',
                  subtitle: '不可用时自动换下一个：已配置的云端引擎 → 本地离线 → 系统朗读',
                  trailing: _EngineMenu(value: s.preferredEngine, onChanged: s.setPreferredEngine),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text('云端引擎', style: ts(17, weight: w700, color: _C.text)),
            const SizedBox(height: 6),
            Text('密钥只保存在本机，只发送给对应的服务；也可以填写自建代理地址，由你的服务器附加密钥，本机不保存密钥。', style: ts(13, height: 1.5, color: _C.text2)),
            const SizedBox(height: 10),
            for (final id in _engineInfo.keys) ...[_EngineCard(id: id), const SizedBox(height: 10)],
          ],
        ),
      ),
    );
  }

  Widget _voiceCard(VoiceProfile v, VoiceSettings s) {
    final selected = s.voiceId == v.id;
    final engines = context.read<SpeechOutput>().engines;
    final local = v.binding('local')?.voices[_lang];
    final model = local == null ? null : LocalVoiceModels.byId(local);
    final installed = model != null && (_installed[model.id] ?? false);
    final progress = model == null ? null : _downloads[model.id];
    final available = <String>[
      for (final e in engines.all.where((e) => !e.offline && e.configured))
        if ((engines.bindingFor(v, e).voices[_lang] ?? '').isNotEmpty && e.languages.contains(_lang)) e.name,
      if (installed) '本地离线',
    ];
    final previewing = _previewing == v.id;
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
                    Text('默认', style: ts(13, weight: w600, color: _C.accent)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(v.description, style: ts(14, height: 1.5, color: _C.text)),
          const SizedBox(height: 6),
          Text(v.traits.join(' · '), style: ts(12.5, color: _C.text2)),
          const SizedBox(height: 4),
          Text(
            available.isEmpty ? '可用：系统朗读（下载离线声音或配置云端引擎后使用这个音色）' : '可用：${available.join('、')}',
            style: ts(12.5, color: _C.text2),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Button(previewing ? '停止' : '试听', icon: previewing ? YIcons.pause : YIcons.play, primary: false, onTap: () => _preview(v)),
              const SizedBox(width: 10),
              if (!selected) _Button('设为默认', primary: true, onTap: () => s.setVoice(v.id)),
              const Spacer(),
              if (model != null && !installed)
                progress != null
                    ? Text('下载中 ${(progress * 100).round()}%', style: ts(13, color: _C.accent))
                    : Pressable(
                        onTap: () => _download(v),
                        child: Text('下载离线声音 ${model.sizeMb} MB', style: ts(13, weight: w600, color: _C.accent)),
                      ),
            ],
          ),
          const SizedBox(height: 8),
          Pressable(
            onTap: () => setState(() => _expanded = _expanded == v.id ? null : v.id),
            child: Text(_expanded == v.id ? '收起高级设置' : '高级：各引擎的声音 ID', style: ts(12.5, color: _C.text2)),
          ),
          if (_expanded == v.id) ...[
            const SizedBox(height: 8),
            for (final e in engines.all.where((e) => !e.offline))
              if (e.languages.contains(_lang))
                _VoiceIdField(
                  key: ValueKey('${v.id}/${e.id}/${_lang.name}'),
                  label: '${e.name}（${_lang.label}）',
                  initial: engines.bindingFor(v, e).voices[_lang] ?? '',
                  onChanged: (t) => s.setOverride(v.id, e.id, _lang, t == (v.binding(e.id)?.voices[_lang] ?? '') ? null : t),
                ),
            if (v.binding('local')?.note != null) Text(v.binding('local')!.note!, style: ts(12, color: _C.text2)),
          ],
        ],
      ),
    );
  }
}

class _EngineCard extends StatefulWidget {
  const _EngineCard({required this.id});

  final String id;

  @override
  State<_EngineCard> createState() => _EngineCardState();
}

class _EngineCardState extends State<_EngineCard> {
  late final VoiceSettings _s = context.read<VoiceSettings>();
  late final _key = TextEditingController(text: _s.engine(widget.id).apiKey);
  late final _proxy = TextEditingController(text: _s.engine(widget.id).proxy);
  late final _model = TextEditingController(text: _s.engine(widget.id).model);
  String? _result;
  bool _ok = false;
  bool _testing = false;

  @override
  void dispose() {
    _key.dispose();
    _proxy.dispose();
    _model.dispose();
    super.dispose();
  }

  void _save() => _s.setEngine(widget.id, EngineConfig(apiKey: _key.text.trim(), proxy: _proxy.text.trim(), model: _model.text.trim()));

  Future<void> _test() async {
    _save();
    final out = context.read<SpeechOutput>();
    final engine = out.engines.byId(widget.id)!;
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final v = VoicePresets.byId(_s.voiceId);
      final b = out.engines.bindingFor(v, engine);
      final lang = b.voices.containsKey(VoiceLanguage.zh) ? VoiceLanguage.zh : b.voices.keys.firstOrNull;
      if (lang == null) throw TtsException('当前音色在这个引擎上没有声音 ID，请在音色的“高级”中填写');
      final audio = await engine.synthesize(b, TtsRequest('连接成功。', language: lang)).toList();
      _ok = audio.isNotEmpty;
      _result = '连接成功（${audio.fold<int>(0, (s, a) => s + a.bytes.length) ~/ 1024} KB 音频）';
    } catch (e) {
      _ok = false;
      _result = '$e';
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final (name, desc, url) = _engineInfo[widget.id]!;
    final configured = context.watch<VoiceSettings>().engine(widget.id).usable;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _C.bg, borderRadius: BorderRadius.circular(16), border: Border.all(color: _C.border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(name, style: ts(16, weight: w700, color: _C.text)),
              const SizedBox(width: 8),
              Text(configured ? '已配置' : '未配置', style: ts(12.5, color: configured ? _C.accent : _C.text2)),
              const Spacer(),
              Pressable(
                onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                child: Text('获取密钥', style: ts(13, weight: w600, color: _C.accent)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(desc, style: ts(12.5, height: 1.5, color: _C.text2)),
          const SizedBox(height: 10),
          _Field(label: '密钥', controller: _key, secret: true, onChanged: (_) => _save()),
          _Field(label: '代理地址', controller: _proxy, hint: '可选，自建代理时填写', onChanged: (_) => _save()),
          _Field(label: '模型', controller: _model, hint: '可选，留空使用默认模型', onChanged: (_) => _save()),
          const SizedBox(height: 10),
          Row(
            children: [
              _Button(_testing ? '测试中…' : '测试', primary: false, onTap: _testing || !configured ? null : _test),
              const SizedBox(width: 10),
              if (_result != null) Expanded(child: Text(_result!, style: ts(12.5, color: _ok ? _C.text2 : _C.danger), maxLines: 3, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ],
      ),
    );
  }
}

class _VoiceIdField extends StatefulWidget {
  const _VoiceIdField({super.key, required this.label, required this.initial, required this.onChanged});

  final String label;
  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_VoiceIdField> createState() => _VoiceIdFieldState();
}

class _VoiceIdFieldState extends State<_VoiceIdField> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _Field(label: widget.label, controller: _c, hint: '声音 / 音色 ID', onChanged: widget.onChanged, labelWidth: 150);
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.controller, this.hint, this.secret = false, this.onChanged, this.labelWidth = 72});

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool secret;
  final ValueChanged<String>? onChanged;
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: _C.surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
      child: Row(
        children: [
          SizedBox(width: labelWidth, child: Text(label, style: ts(13.5, color: _C.text2))),
          Expanded(
            child: TextField(
              controller: controller,
              obscureText: secret,
              onChanged: onChanged,
              style: ts(14, color: _C.text),
              cursorColor: _C.accent,
              decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: hint, hintStyle: ts(14, color: const Color(0xFFA0A9B8))),
            ),
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
  const _Button(this.label, {required this.primary, required this.onTap, this.icon});

  final String label;
  final bool primary;
  final VoidCallback? onTap;
  final YIconData? icon;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? Colors.white : _C.accent;
    return Pressable(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: primary ? _C.accent : _C.bg,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: _C.accent),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[YIcon(icon!, size: 14, color: fg), const SizedBox(width: 6)],
              Text(label, style: ts(13.5, weight: w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EngineMenu extends StatelessWidget {
  const _EngineMenu({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  static const _options = {'auto': '自动', 'cosyvoice': 'CosyVoice', 'elevenlabs': 'ElevenLabs', 'fish': 'Fish Audio', 'local': '本地离线', 'system': '系统朗读'};

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: () async {
        final keys = _options.keys.toList();
        final i = keys.indexOf(value);
        onChanged(keys[(i + 1) % keys.length]);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: _C.border)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_options[value] ?? '自动', style: ts(13.5, weight: w600, color: _C.accent)),
            const SizedBox(width: 4),
            const YIcon(YIcons.chevronRight, size: 14, color: _C.text2),
          ],
        ),
      ),
    );
  }
}
