import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../core/lyrics_overlay.dart';
import '../../pet/pet_host.dart';
import '../../pet/pet_rig.dart';
import '../../pet/pet_view.dart';
import '../../voice/engines/local_engine.dart';
import '../../voice/tts_types.dart';
import '../../voice/voice_library.dart';
import '../../voice/voice_settings.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 桌宠：挑选团团 / 星月 / 阿曜，预览表情，打开后显示在桌面上（Android 悬浮窗 / 桌面端置顶小窗口）。
class PetPage extends StatefulWidget {
  const PetPage({super.key});

  @override
  State<PetPage> createState() => _PetPageState();
}

class _PetPageState extends State<PetPage> with WidgetsBindingObserver {
  late PetKind _preview = PetKind.byName(context.read<AssistantSettings>().pet) ?? PetKind.tuantuan;
  PetMood _mood = PetMood.idle;
  final _stage = PetViewController();
  bool? _canDraw;

  /// 各音色的中文离线声音是否已下载（没下载、也没配置云端引擎时，桌宠只能用系统朗读，几个桌宠声音都一样）。
  final _voiceInstalled = <String, bool>{};
  double? _voiceProgress;
  String? _voiceError;

  static LocalVoiceModel? _localModel(PetKind k) => LocalVoiceModels.byId(VoicePresets.byId(k.voiceId).binding('local')?.voices[VoiceLanguage.zh] ?? '');

  Future<void> _checkVoices() async {
    for (final k in PetKind.values) {
      final m = _localModel(k);
      if (m != null) _voiceInstalled[k.voiceId] = await LocalTtsEngine.isInstalled(m);
    }
    if (mounted) setState(() {});
  }

  Future<void> _downloadVoice(PetKind k) async {
    final binding = VoicePresets.byId(k.voiceId).binding('local');
    if (binding == null || _voiceProgress != null) return;
    setState(() {
      _voiceProgress = 0;
      _voiceError = null;
    });
    try {
      await LocalTtsEngine().prepare(binding, VoiceLanguage.zh, onProgress: (p) {
        if (mounted) setState(() => _voiceProgress = p);
      });
    } catch (e) {
      _voiceError = '下载失败：${'$e'.replaceFirst('Exception: ', '')}';
    }
    _voiceProgress = null;
    await _checkVoices();
  }

  static bool get _android => !kIsWeb && Platform.isAndroid;

  static const _greetings = {
    PetKind.tuantuan: '嗨嗨，我是团团！想听什么歌，戳戳我就好啦～',
    PetKind.xingyue: '你好呀，我是星月。今晚想听点什么呢？',
    PetKind.ayao: '哟，我是阿曜！点我一下，想听啥直接说。',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermission();
    _checkVoices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置授权回来后重新检查。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPermission();
  }

  Future<void> _checkPermission() async {
    final ok = await PetHost.canDraw();
    if (mounted) setState(() => _canDraw = ok);
  }

  void _pick(PetKind k) {
    setState(() {
      _preview = k;
      _mood = PetMood.speaking;
    });
    final speech = context.read<AssistantController>().speech;
    // 用桌宠自己的音色打个招呼，说完回到待机。
    speech?.say(_greetings[k]!, voice: VoicePresets.byId(k.voiceId)).whenComplete(() {
      if (mounted && _preview == k && _mood == PetMood.speaking) setState(() => _mood = PetMood.idle);
    });
    final s = context.read<AssistantSettings>();
    if (s.pet.isNotEmpty) _enable(k);
  }

  Future<void> _enable(PetKind k) async {
    if (_android && !(_canDraw ?? false)) {
      await LyricsOverlay.requestPermission();
      return;
    }
    final s = context.read<AssistantSettings>();
    s.setPet(k.name);
    // 桌宠用自己的音色说话，并常驻语音唤醒（后台也能叫它）。
    context.read<VoiceSettings>().setVoice(k.voiceId);
    if (!s.voiceWake) s.setVoiceWake(true);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AssistantSettings>();
    final on = s.pet.isNotEmpty;
    final needPermission = _android && _canDraw == false;
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 22,
      children: [
        const PageHeader('桌宠', subtitle: '在桌面上陪你听歌，点一下就能说话'),
        YCard(
          radius: 22,
          padding: const EdgeInsets.fromLTRB(12, 18, 12, 14),
          child: Column(
            children: [
              SizedBox(
                height: 300,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: GestureDetector(
                    onTap: _stage.poke,
                    child: PetView(
                      kind: _preview,
                      mood: _mood,
                      height: 200,
                      controller: _stage,
                      bubble: switch (_mood) {
                        PetMood.listening => '我在听…',
                        PetMood.speaking => _greetings[_preview]!,
                        _ => '',
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('${_preview.label} · ${_preview.style}', style: ts(17, weight: w600, color: p.text)),
              const SizedBox(height: 4),
              Text('${_preview.description} · 音色：${VoicePresets.byId(_preview.voiceId).name}', style: ts(13, color: p.text2)),
              _voiceHint(p),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                alignment: WrapAlignment.center,
                children: [
                  for (final m in PetMood.values.where((m) => m != PetMood.dragged))
                    YChip(m.label, height: 30, selected: _mood == m, onTap: () => setState(() => _mood = m)),
                ],
              ),
            ],
          ),
        ),
        const GroupLabel('选择桌宠'),
        Row(
          children: [
            for (final k in PetKind.values) ...[
              if (k != PetKind.values.first) const SizedBox(width: 10),
              Expanded(child: _PetCard(kind: k, selected: _preview == k, active: s.pet == k.name, onTap: () => _pick(k))),
            ],
          ],
        ),
        const SizedBox(height: 16),
        CardList(
          indent: 14,
          children: [
            SettingsRow(
              title: '显示桌宠',
              subtitle: needPermission
                  ? '需要“显示在其他应用上层”权限，点按开关去授权'
                  : on
                  ? '${PetKind.byName(s.pet)?.label ?? ''}已在桌面上 · 语音唤醒已打开'
                  : _android
                  ? '退到桌面后显示，云音在前台时自动收起'
                  : '在桌面上显示一个置顶的小窗口',
              height: 64,
              trailing: YSwitch(
                value: on,
                label: '显示桌宠',
                onChanged: (v) => v ? _enable(_preview) : s.setPet(''),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Row(
                children: [
                  Text('大小', style: ts(15, color: p.text)),
                  const SizedBox(width: 16),
                  Expanded(child: Segmented(labels: const ['小', '中', '大'], index: s.petSize, onChanged: s.setPetSize)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _android
              ? '点按桌宠开始说话，再点一下停下；长按打开云音；按住拖动换个位置。说“你好云音”也能随时叫它（语音唤醒，通知栏显示常驻通知）。'
                    '桌宠会跟着状态换表情：听你说话时眼睛亮晶晶，思考时冒泡泡，说话时张嘴，放歌时跟着摇摆，久了没人理会打瞌睡。'
              : '点按桌宠开始说话，再点一下停下；按住拖动换个位置；右键打开云音。说“你好云音”也能随时叫它。'
                    '桌宠会跟着状态换表情：听你说话时眼睛亮晶晶，思考时冒泡泡，说话时张嘴，放歌时跟着摇摆，久了没人理会打瞌睡。',
          style: ts(13, height: 1.55, color: p.text2),
        ),
      ],
    );
  }
}

extension on _PetPageState {
  /// 桌宠的音色还不能用时（没有离线声音，也没配置云端引擎）提示下载离线声音。
  Widget _voiceHint(Palette p) {
    final k = _preview;
    final cloud = const ['cosyvoice', 'elevenlabs', 'fish'].any((e) => context.read<VoiceSettings>().engine(e).usable);
    final m = _PetPageState._localModel(k);
    if (cloud || m == null || _voiceInstalled[k.voiceId] != false) return const SizedBox.shrink();
    final voice = VoicePresets.byId(k.voiceId).name;
    final progress = _voiceProgress;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          Text(
            _voiceError ?? '${k.label}的声音（$voice）还没有下载，现在说话用的是系统朗读。',
            textAlign: TextAlign.center,
            style: ts(12.5, color: _voiceError != null ? p.danger : p.text2),
          ),
          const SizedBox(height: 6),
          if (progress != null)
            SizedBox(
              width: 180,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(value: progress, minHeight: 4, color: k.color, backgroundColor: p.separator),
              ),
            )
          else
            Pressable(
              onTap: () => _downloadVoice(k),
              child: Text('下载$voice的离线声音（${m.sizeMb} MB）', style: ts(14, weight: w600, color: p.accentText)),
            ),
        ],
      ),
    );
  }
}

class _PetCard extends StatelessWidget {
  const _PetCard({required this.kind, required this.selected, required this.active, required this.onTap});

  final PetKind kind;
  final bool selected;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Pressable(
      onTap: onTap,
      child: YBox(
        radius: BorderRadius.circular(18),
        color: p.card,
        border: selected ? kind.color : p.separator,
        padding: const EdgeInsets.fromLTRB(6, 10, 6, 10),
        child: Column(
          children: [
            SizedBox(height: 104, child: Align(alignment: Alignment.bottomCenter, child: PetView(kind: kind, height: 84, fps: 30))),
            const SizedBox(height: 6),
            Text(kind.label, style: ts(15, weight: w600, color: p.text)),
            const SizedBox(height: 2),
            Text(active ? '使用中' : kind.style, style: ts(12, color: active ? kind.color : p.text2)),
          ],
        ),
      ),
    );
  }
}
