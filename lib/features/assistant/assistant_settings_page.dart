import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_settings.dart';
import '../../assistant/voice_engine.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../voice/voice_library.dart';
import '../../voice/voice_settings.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 云音助手设置：语音唤醒（离线）、朗读回答与大模型接口（用户自己的密钥）。
class AssistantSettingsPage extends StatefulWidget {
  const AssistantSettingsPage({super.key});

  @override
  State<AssistantSettingsPage> createState() => _AssistantSettingsPageState();
}

class _AssistantSettingsPageState extends State<AssistantSettingsPage> {
  late final AssistantSettings _s = context.read<AssistantSettings>();
  late final _url = TextEditingController(text: _s.baseUrl);
  late final _model = TextEditingController(text: _s.model);
  late final _key = TextEditingController(text: _s.apiKey);
  bool _testing = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  void _save() => _s.setLlm(baseUrl: _url.text, model: _model.text, apiKey: _key.text);

  Future<void> _test() async {
    _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final r = await context.read<AssistantController>().testLlm();
      _testOk = true;
      _testResult = '连接成功：$r';
    } catch (e) {
      _testOk = false;
      _testResult = '$e';
    }
    if (mounted) setState(() => _testing = false);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AssistantSettings>();
    final a = context.watch<AssistantController>();
    final android = !kIsWeb && Platform.isAndroid;
    Widget field(String label, TextEditingController c, {String? hint, bool secret = false}) => Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          SizedBox(width: 76, child: Text(label, style: ts(15, color: p.text))),
          Expanded(
            child: TextField(
              controller: c,
              obscureText: secret,
              onChanged: (_) => _save(),
              style: ts(15, color: p.text),
              cursorColor: p.accentText,
              decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: hint, hintStyle: ts(15, color: p.text3)),
            ),
          ),
        ],
      ),
    );
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 22,
      children: [
        const PageHeader('云音助手', subtitle: '语音唤醒、语音控制与大模型'),
        const GroupLabel('语音'),
        CardList(
          indent: 14,
          children: [
            SettingsRow(
              title: '语音唤醒',
              subtitle: android ? '说“你好云音”唤醒，后台也能用（显示常驻通知）' : '说“你好云音”唤醒，窗口最小化时也能用',
              height: 64,
              trailing: YSwitch(value: s.voiceWake, label: '语音唤醒', onChanged: s.setVoiceWake),
            ),
            Builder(
              builder: (context) {
                final v = context.watch<VoiceSettings>();
                return SettingsRow(
                  title: '音色中心',
                  subtitle: '当前音色：${VoicePresets.byId(v.voiceId).name} · 试听、切换与语音引擎',
                  height: 64,
                  chevron: true,
                  onTap: () => context.read<AppNav>().push(VoiceCenterRoute()),
                );
              },
            ),
            _WakeWordRow(),
            SettingsRow(
              title: '识别模型',
              subtitle: '${s.asrModel.label}（约 ${s.asrModel.sizeMb} MB）· 点按切换${s.asrModel == AsrModel.senseVoice ? '，支持中英文混说' : '，体积更小'}',
              height: 64,
              chevron: true,
              onTap: () => s.setAsrModel(AsrModel.values[(s.asrModel.index + 1) % AsrModel.values.length]),
            ),
            SettingsRow(
              title: '朗读回答',
              subtitle: '语音提问时用系统语音读出回答',
              height: 64,
              trailing: YSwitch(value: s.speakReplies, label: '朗读回答', onChanged: s.setSpeakReplies),
            ),
          ],
        ),
        if (a.downloadProgress != null) ...[
          const SizedBox(height: 10),
          Text('正在下载离线语音模型（约 31 MB，只需下载一次）…', style: ts(13, color: p.text2)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: a.downloadProgress, minHeight: 4, color: p.accent.base, backgroundColor: p.separator),
          ),
        ],
        if (a.voiceError != null) ...[const SizedBox(height: 8), Text(a.voiceError!, style: ts(13, color: p.danger))],
        const SizedBox(height: 8),
        Text(
          '唤醒词与语音识别完全在本机离线完成，录音不会上传。第一次打开语音功能时下载离线模型（高精度约 260 MB，标准约 110 MB）。'
          '可以直接说：“播放晴天”“我想听周杰伦的歌”“下一首”“暂停”“音量调到五十”“三十分钟后停止播放”“切换到摇滚音效”“收藏这首歌”。',
          style: ts(13, height: 1.55, color: p.text2),
        ),
        const GroupLabel('大模型'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final provider in AiProvider.presets)
              YChip(
                provider.name,
                selected: s.baseUrl == provider.baseUrl,
                onTap: () {
                  _url.text = provider.baseUrl;
                  _model.text = provider.model;
                  _save();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        CardList(
          indent: 14,
          children: [
            field('接口地址', _url, hint: 'https://api.deepseek.com/v1'),
            field('模型', _model, hint: 'deepseek-chat'),
            field('密钥', _key, hint: 'sk-…', secret: true),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            PrimaryButton(label: _testing ? '测试中…' : '测试连接', height: 40, fontSize: 15, onTap: _testing || !s.llmConfigured ? null : _test),
            const SizedBox(width: 12),
            Pressable(
              onTap: () {
                final provider = AiProvider.presets.where((e) => e.baseUrl == s.baseUrl).firstOrNull ?? AiProvider.presets.first;
                launchUrl(Uri.parse(provider.keyUrl), mode: LaunchMode.externalApplication);
              },
              child: Text('获取密钥', style: ts(15, weight: w600, color: p.accentText)),
            ),
          ],
        ),
        if (_testResult != null) ...[const SizedBox(height: 10), Text(_testResult!, style: ts(13, height: 1.5, color: _testOk ? p.text2 : p.danger))],
        const SizedBox(height: 10),
        Text(
          '填写任意兼容 OpenAI 接口的大模型服务（DeepSeek、通义千问、Kimi、智谱、OpenAI 等）与你自己的密钥后，助手可以按心情或场景生成歌单、推荐相似歌曲、讲解歌曲背景与歌词、点评你的听歌习惯。'
          '密钥只保存在本机，对话内容只发送到你填写的接口地址，费用由该服务按其价格收取。不填写时常用语音指令照常可用。',
          style: ts(13, height: 1.55, color: p.text2),
        ),
        const SizedBox(height: 16),
        YBox(
          radius: BorderRadius.circular(18),
          color: p.card,
          padding: const EdgeInsets.all(14),
          child: Text(
            '试试说：“来点适合深夜一个人听的歌”“这首歌讲了什么”“解读一下这句歌词”“推荐几首和这首类似的歌”“我最近常听什么”。',
            style: ts(13.5, height: 1.55, color: p.text),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

/// 自定义唤醒词：输入 3–6 个汉字，保存时转换为拼音并校验唤醒模型能否检测。
class _WakeWordRow extends StatefulWidget {
  const _WakeWordRow();

  @override
  State<_WakeWordRow> createState() => _WakeWordRowState();
}

class _WakeWordRowState extends State<_WakeWordRow> {
  late final _c = TextEditingController(text: context.read<AssistantSettings>().wakeWord);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final e = await context.read<AssistantController>().setWakeWord(_c.text);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _error = e;
    });
    if (e == null) FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AssistantSettings>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('唤醒词', style: ts(15, color: p.text)),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _c,
                  onSubmitted: (_) => _save(),
                  style: ts(15, color: p.text),
                  cursorColor: p.accentText,
                  decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: '默认“你好云音”，可自定义 3–6 个汉字', hintStyle: ts(14, color: p.text3)),
                ),
              ),
              Pressable(onTap: _saving ? null : _save, child: Text(_saving ? '校验中…' : '保存', style: ts(14, weight: w600, color: p.accentText))),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _error ?? (s.wakeWord.isEmpty ? '当前：你好云音 / 嗨云音 / 云音云音' : '当前：${s.wakeWord}（“你好云音”仍然有效）'),
            style: ts(12.5, color: _error != null ? p.danger : p.text2),
          ),
        ],
      ),
    );
  }
}
