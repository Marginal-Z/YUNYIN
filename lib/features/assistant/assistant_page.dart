import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app.dart' show rootNavigatorKey;
import '../../assistant/assistant_controller.dart';
import '../../assistant/assistant_settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../player/player_controller.dart';
import '../common/layout.dart';
import '../common/song_cover.dart';
import '../desktop/desktop_dialogs.dart';
import '../shell/nav.dart';

/// 打开云音助手：手机为整页，桌面为弹出面板。[listen] 为 true 时打开后立即开始听（语音唤醒）。
void openAssistant(BuildContext context, {bool listen = false}) {
  if (_open) return;
  _open = true;
  final assistant = context.read<AssistantController>();
  if (listen && assistant.status != AssistantStatus.listening) unawaited(assistant.startListening());
  final Future<void> done;
  if (LayoutScope.isDesktop(context)) {
    done = showDesktopPanel<void>(context, width: 560, builder: (_) => const AssistantPage());
  } else {
    done = Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(builder: (_) => const AssistantPage()));
  }
  done.whenComplete(() => _open = false);
}

bool _open = false;

/// 语音唤醒时（应用在前台）自动打开助手面板。放在应用外壳中。
class AssistantWakeListener extends StatefulWidget {
  const AssistantWakeListener({super.key, required this.child});

  final Widget child;

  @override
  State<AssistantWakeListener> createState() => _AssistantWakeListenerState();
}

class _AssistantWakeListenerState extends State<AssistantWakeListener> {
  StreamSubscription<void>? _sub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sub ??= context.read<AssistantController>().wakeEvents.listen((_) {
      // 应用外壳在导航器之上：用根导航器的 context 打开面板。
      final nav = rootNavigatorKey.currentContext;
      if (!mounted || nav == null || !nav.mounted || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) return;
      openAssistant(nav);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 云音助手：对话记录、正在识别的话、快捷提问与输入框（文字 / 语音）。
class AssistantPage extends StatefulWidget {
  const AssistantPage({super.key});

  @override
  State<AssistantPage> createState() => _AssistantPageState();
}

class _AssistantPageState extends State<AssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _count = 0;
  int _lastLength = 0;

  static const _suggestions = ['来点适合跑步的歌', '这首歌讲了什么', '解读一下这句歌词', '推荐几首和这首类似的歌', '我最近常听什么', '30 分钟后停止播放'];

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = (text ?? _input.text).trim();
    if (t.isEmpty) return;
    _input.clear();
    context.read<AssistantController>().submit(t);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final a = context.watch<AssistantController>();
    final s = context.watch<AssistantSettings>();
    final pad = MediaQuery.paddingOf(context);
    // 新消息或者回答边生成边变长时，滚到最下面。
    final growing = a.messages.lastOrNull?.text.length ?? 0;
    if (a.messages.length != _count || growing != _lastLength) {
      _count = a.messages.length;
      _lastLength = growing;
      _scrollToEnd();
    }
    final waiting = a.status == AssistantStatus.thinking && !(a.messages.lastOrNull?.streaming ?? false);
    return Material(
      color: p.bg,
      child: Padding(
        padding: EdgeInsets.only(top: pad.top, bottom: MediaQuery.viewInsetsOf(context).bottom > 0 ? MediaQuery.viewInsetsOf(context).bottom : pad.bottom),
        child: Column(
          children: [
            // 标题栏。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Row(
                children: [
                  YIconButton(YIcons.back, size: 44, iconSize: 22, color: p.text, label: '返回', onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 4),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [p.accent.base, Color.lerp(p.accent.base, const Color(0xFF6A5CFF), 0.6)!])),
                    child: const Center(child: YIcon(YIcons.sparkle, size: 18, color: Colors.white)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('云音助手', style: ts(17, weight: w700, color: p.text)),
                        Text(
                          s.voiceWake ? '说“你好云音”随时唤醒' : (s.llmConfigured ? '已连接 ${s.model}' : '常用指令可直接使用'),
                          style: ts(12, color: p.text2),
                        ),
                      ],
                    ),
                  ),
                  if (a.messages.isNotEmpty) YIconButton(YIcons.trash, size: 40, iconSize: 20, color: p.text2, label: '清空对话', onTap: a.clear),
                  YIconButton(
                    YIcons.sliders,
                    size: 40,
                    iconSize: 20,
                    color: p.text2,
                    label: '云音助手设置',
                    onTap: () {
                      final nav = context.read<AppNav>();
                      Navigator.of(context).maybePop();
                      nav.push(AssistantSettingsRoute());
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: a.messages.isEmpty
                  ? _Welcome(onPick: _send, suggestions: _suggestions, configured: s.llmConfigured)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      itemCount: a.messages.length + (waiting ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == a.messages.length) return const _Bubble(fromUser: false, text: '思考中…', dim: true);
                        final m = a.messages[i];
                        // 大模型还没开始输出文字（或在调用函数）时显示“思考中”。
                        final pending = m.streaming && m.text.isEmpty;
                        return Column(
                          crossAxisAlignment: m.fromUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            _Bubble(fromUser: m.fromUser, text: pending ? '思考中…' : m.text, dim: pending),
                            if (m.songs.isNotEmpty) _SongList(songs: m.songs),
                          ],
                        );
                      },
                    ),
            ),
            if (a.voiceError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(a.voiceError!, style: ts(12.5, color: p.danger)),
              ),
            if (a.downloadProgress != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('正在下载离线语音模型（约 ${s.asrModel.sizeMb} MB，只需下载一次）…', style: ts(12.5, color: p.text2)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(value: a.downloadProgress, minHeight: 4, color: p.accent.base, backgroundColor: p.separator),
                    ),
                  ],
                ),
              ),
            if (a.status == AssistantStatus.listening)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                child: Row(
                  children: [
                    const _Pulse(),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.partial.isEmpty ? '正在听，请说…' : a.partial,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: ts(15, weight: w500, color: a.partial.isEmpty ? p.text2 : p.text),
                      ),
                    ),
                  ],
                ),
              ),
            // 输入栏。
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: YBox(
                      height: 48,
                      radius: BorderRadius.circular(24),
                      color: p.card,
                      shadows: p.cardShadow,
                      insets: p.cardInset,
                      padding: const EdgeInsets.fromLTRB(18, 0, 6, 0),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _input,
                              onSubmitted: (_) => _send(),
                              textInputAction: TextInputAction.send,
                              style: ts(15.5, color: p.text),
                              cursorColor: p.accentText,
                              decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: '想听什么，或者问点什么', hintStyle: ts(15.5, color: p.text2)),
                            ),
                          ),
                          YIconButton(YIcons.send, size: 40, iconSize: 20, color: p.accentText, label: '发送', onTap: _send),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Pressable(
                    onTap: a.startListening,
                    scale: 0.92,
                    semanticLabel: a.status == AssistantStatus.listening ? '停止' : '语音输入',
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: a.status == AssistantStatus.listening ? p.danger : p.accent.base),
                      child: Center(
                        child: YIcon(a.status == AssistantStatus.listening ? YIcons.close : YIcons.mic, size: 22, strokeWidth: 2.2, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({required this.onPick, required this.suggestions, required this.configured});

  final ValueChanged<String> onPick;
  final List<String> suggestions;
  final bool configured;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      children: [
        Text('想听什么？', style: ts(26, weight: w700, color: p.text)),
        const SizedBox(height: 8),
        Text(
          configured
              ? '可以直接点歌、按心情要歌单、问这首歌的故事或请我解读歌词，也可以控制播放、音量、音效和定时关闭。'
              : '播放控制、点歌（“播放晴天”“我想听周杰伦的歌”）、音量、音效与定时关闭可以直接说。按心情推荐、问答与歌词解读需要在设置中填写大模型接口。',
          style: ts(14, height: 1.55, color: p.text2),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in suggestions) YChip(s, onTap: () => onPick(s))],
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.text, this.dim = false});

  final bool fromUser;
  final String text;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 5),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78 > 460 ? 460 : MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: fromUser ? p.accent.base : p.card,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromUser ? 18 : 6),
            bottomRight: Radius.circular(fromUser ? 6 : 18),
          ),
        ),
        child: SelectableText(text, style: ts(15, height: 1.5, color: fromUser ? Colors.white : (dim ? p.text2 : p.text))),
      ),
    );
  }
}

/// 助手播放 / 推荐的歌曲，点按播放对应的那首。
class _SongList extends StatelessWidget {
  const _SongList({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final player = context.read<PlayerController>();
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      constraints: const BoxConstraints(maxWidth: 460),
      decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          for (final s in songs.take(8))
            Pressable(
              onTap: () => player.playSong(s, context: songs),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
                child: Row(
                  children: [
                    SongCover(s, size: 36, radius: 8),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, weight: w600, color: p.text)),
                          Text(s.artistText, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12, color: p.text2)),
                        ],
                      ),
                    ),
                    YIcon(YIcons.play, size: 16, color: p.text2),
                  ],
                ),
              ),
            ),
          if (songs.length > 8)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('等 ${songs.length} 首', style: ts(12, color: p.text2)),
            ),
        ],
      ),
    );
  }
}

/// 正在听时跳动的圆点。
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ScaleTransition(
      scale: Tween(begin: 0.7, end: 1.15).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
      child: Container(width: 14, height: 14, decoration: BoxDecoration(shape: BoxShape.circle, color: p.danger)),
    );
  }
}
