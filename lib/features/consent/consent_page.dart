import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../settings/about_pages.dart';

/// 首次启动的使用声明：阅读并同意用户协议与隐私政策后才能进入应用，同意后申请通知权限。
class ConsentPage extends StatefulWidget {
  const ConsentPage({super.key});

  @override
  State<ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<ConsentPage> {
  bool _checked = false;

  static const _system = MethodChannel('yunyin/system');

  Future<void> _accept() async {
    context.read<AppSettings>().acceptConsent();
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await _system.invokeMethod<void>('requestNotifications');
      } catch (_) {}
    }
  }

  void _decline() {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      SystemNavigator.pop();
    } else {
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    TextSpan link(String text, AboutPage page) => TextSpan(
      text: text,
      style: TextStyle(color: p.accentText, fontWeight: FontWeight.w600),
      recognizer: TapGestureRecognizer()..onTap = () => showDocument(context, page),
    );
    return ColoredBox(
      color: const Color(0x8C000000),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: YBox(
                radius: BorderRadius.circular(28),
                color: p.bg,
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const AppLogo(size: 44, gradient: true),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '欢迎使用云音',
                            style: ts(22, weight: w700, color: p.text),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Text.rich(
                          TextSpan(
                            style: ts(14, height: 1.65, color: p.text2),
                            children: [
                              const TextSpan(
                                text:
                                    '云音是开源、免费的第三方音乐客户端，与网易云音乐、QQ 音乐、酷狗音乐及其关联公司没有任何关联，'
                                    '不提供、不存储、不分发任何音乐内容，仅供学习与交流使用。\n\n'
                                    '云音没有服务器，不收集、不上传任何个人信息；账号凭据、网盘配置与音源脚本只保存在你的设备上。'
                                    '为了在通知栏与锁屏显示播放控制，云音会在你同意后申请通知权限；扫描本机歌曲、桌面歌词等功能会在使用时再单独申请权限。\n\n'
                                    '请仔细阅读',
                              ),
                              link('《用户协议》', AboutPage.agreement),
                              const TextSpan(text: '与'),
                              link('《隐私政策》', AboutPage.privacy),
                              const TextSpan(text: '，同意后即可开始使用。'),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Pressable(
                      onTap: () => setState(() => _checked = !_checked),
                      scale: 1,
                      semanticLabel: '我已阅读并同意用户协议与隐私政策',
                      child: Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _checked ? p.accentText : null,
                              border: _checked ? null : Border.all(color: p.muted, width: 1.5),
                            ),
                            alignment: Alignment.center,
                            child: _checked ? const YIcon(YIcons.check, size: 13, strokeWidth: 3, color: Colors.white) : null,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('我已阅读并同意用户协议与隐私政策', style: ts(14, color: p.text)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    PrimaryButton(label: '同意并进入', height: 48, fontSize: 16, expand: true, enabled: _checked, onTap: _accept),
                    const SizedBox(height: 6),
                    Center(
                      child: Pressable(
                        onTap: _decline,
                        pressedOpacity: 0.6,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text('不同意并退出', style: ts(14, color: p.text2)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
