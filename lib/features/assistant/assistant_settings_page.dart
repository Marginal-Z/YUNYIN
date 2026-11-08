import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_settings.dart';
import '../../assistant/voice_engine.dart';
import '../../core/theme/palette.dart';
import '../../pet/pet_rig.dart';
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
            Builder(
              builder: (context) {
                final pet = PetKind.byName(s.pet);
                return SettingsRow(
                  title: '桌宠',
                  subtitle: pet == null ? '团团、星月、阿曜 · 在桌面上陪你听歌，点一下就能说话' : '${pet.label}（${pet.style}）已在桌面上',
                  height: 64,
                  chevron: true,
                  onTap: () => context.read<AppNav>().push(PetRoute()),
                );
              },
            ),
            const _WakeWordRow(),
            SettingsRow(
              title: '识别模型',
              subtitle: '${s.asrModel.label}（约 ${s.asrModel.sizeMb} MB）· 点按切换${s.asrModel == AsrModel.senseVoice ? '，支持中英文混说' : '，体积更小'}',
              height: 64,
              chevron: true,
              onTap: () => s.setAsrModel(AsrModel.values[(s.asrModel.index + 1) % AsrModel.values.length]),
            ),
            SettingsRow(
              title: '朗读回答',
              subtitle: '语音提问时用所选音色读出回答，边生成边读',
              height: 64,
              trailing: YSwitch(value: s.speakReplies, label: '朗读回答', onChanged: s.setSpeakReplies),
            ),
            SettingsRow(
              title: '连续对话',
              subtitle: '回答完自动继续听，不用每句都说唤醒词；几秒不说话就结束',
              height: 64,
              trailing: YSwitch(value: s.continuous, label: '连续对话', onChanged: s.setContinuous),
            ),
            SettingsRow(
              title: '开口打断',
              subtitle: '戴耳机时，朗读中直接说话就能打断；外放时说唤醒词或点按打断（外放的朗读声会被麦克风收到）',
              height: 64,
              trailing: YSwitch(value: s.bargeIn, label: '开口打断', onChanged: s.setBargeIn),
            ),
          ],
        ),
        if (a.downloadProgress != null) ...[
          const SizedBox(height: 10),
          Text('正在下载离线语音模型（${s.asrModel.label}约 ${s.asrModel.sizeMb} MB，只需下载一次）…', style: ts(13, color: p.text2)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: a.downloadProgress, minHeight: 4, color: p.accent.base, backgroundColor: p.separator),
          ),
        ],
        if (a.voiceError != null) ...[const SizedBox(height: 8), Text(a.voiceError!, style: ts(13, color: p.danger))],
        const SizedBox(height: 8),
        Text(
          '唤醒词与语音识别完全在本机离线完成，录音不会上传。第一次打开语音功能时下载离线模型（高精度约 ${AsrModel.senseVoice.sizeMb} MB，标准约 ${AsrModel.paraformer.sizeMb} MB）。'
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

/// 唤醒词：显示当前的唤醒词，点按后在弹窗中修改。
class _WakeWordRow extends StatelessWidget {
  const _WakeWordRow();

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AssistantSettings>();
    return SettingsRow(
      title: '唤醒词',
      subtitle: s.wakeWord.isEmpty ? '你好云音（也可以说“嗨云音”“云音云音”）· 点按自定义' : '${s.wakeWord}（“你好云音”仍然有效）· 点按修改',
      height: 64,
      chevron: true,
      onTap: () => _editWakeWord(context),
    );
  }
}

/// 修改唤醒词的弹窗：输入 3–6 个汉字，保存时转换为拼音并校验唤醒模型能否检测。
Future<void> _editWakeWord(BuildContext context) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: '取消',
  barrierColor: const Color.fromRGBO(0, 0, 0, 0.25),
  transitionDuration: const Duration(milliseconds: 220),
  pageBuilder: (ctx, _, _) => const _WakeWordDialog(),
  transitionBuilder: (ctx, a, _, child) => FadeTransition(
    opacity: a,
    child: ScaleTransition(scale: Tween(begin: 1.06, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOut)), child: child),
  ),
);

class _WakeWordDialog extends StatefulWidget {
  const _WakeWordDialog();

  @override
  State<_WakeWordDialog> createState() => _WakeWordDialogState();
}

class _WakeWordDialogState extends State<_WakeWordDialog> {
  late final _c = TextEditingController(text: context.read<AssistantSettings>().wakeWord);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Future<void> _save(String word) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final e = await context.read<AssistantController>().setWakeWord(word);
    if (!mounted) return;
    if (e == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = e;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final a = context.watch<AssistantController>();
    final custom = context.watch<AssistantSettings>().wakeWord.isNotEmpty;
    Widget button(String label, VoidCallback? onTap, {bool primary = false}) => Expanded(
      child: Pressable(
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Center(child: Text(label, style: ts(16, weight: primary ? w700 : FontWeight.w400, color: onTap == null ? p.text3 : (primary ? p.accentText : p.text)))),
        ),
      ),
    );
    final divider = Container(width: 1, height: 46, color: const Color.fromRGBO(60, 60, 67, 0.16));
    return Center(
      child: SizedBox(
        width: 300,
        child: YBox(
          radius: BorderRadius.circular(22),
          color: p.dialog,
          blur: true,
          shadows: const [Shadow2(0, 24, 50, Color.fromRGBO(28, 44, 92, 0.22))],
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('自定义唤醒词', textAlign: TextAlign.center, style: ts(17, weight: w700, color: p.text)),
                      const SizedBox(height: 6),
                      Text('用 3–6 个汉字，读音清楚、不常在聊天里出现的词更不容易误唤醒。“你好云音”始终有效。', textAlign: TextAlign.center, style: ts(13, height: 1.45, color: p.text2)),
                      const SizedBox(height: 14),
                      YBox(
                        radius: BorderRadius.circular(12),
                        color: p.card,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: TextField(
                          controller: _c,
                          autofocus: true,
                          enabled: !_saving,
                          maxLength: 6,
                          onSubmitted: (v) => _save(v),
                          textAlign: TextAlign.center,
                          style: ts(17, weight: w600, color: p.text),
                          cursorColor: p.accentText,
                          decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, counterText: '', hintText: '例如：小云小云', hintStyle: ts(17, color: p.text3)),
                        ),
                      ),
                      if (_saving || a.downloadProgress != null || _error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error ?? (a.downloadProgress != null ? '正在下载唤醒模型（${((a.downloadProgress ?? 0) * 100).round()}%）…' : '正在校验读音…'),
                          textAlign: TextAlign.center,
                          style: ts(12.5, height: 1.4, color: _error != null ? p.danger : p.text2),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(height: 1, color: const Color.fromRGBO(60, 60, 67, 0.16)),
                Row(
                  children: [
                    if (custom) ...[button('恢复默认', _saving ? null : () => _save('')), divider],
                    button('取消', () => Navigator.of(context).pop()),
                    divider,
                    button('保存', _saving ? null : () => _save(_c.text), primary: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
