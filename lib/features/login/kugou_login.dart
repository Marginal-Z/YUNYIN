import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/sources/kugou/kugou_source.dart';
import '../../data/sources/source_manager.dart';

/// 应用内网页登录只在有系统 WebView 的平台上提供（Android、iOS、macOS）。
bool get kugouWebLoginSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

/// 酷狗登录方式：官方登录页（应用内网页）或粘贴浏览器中的 Cookie。登录成功返回 true。
class KugouLoginCard extends StatelessWidget {
  const KugouLoginCard({super.key, required this.onDone});

  final VoidCallback onDone;

  Future<void> _paste(BuildContext context) async {
    final source = context.read<SourceManager>().current;
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final p = Palette.of(ctx);
        return AlertDialog(
          backgroundColor: p.bg,
          title: Text(
            '粘贴酷狗 Cookie',
            style: ts(18, weight: w700, color: p.text),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '在电脑浏览器中打开 www.kugou.com 并登录，按 F12 打开开发者工具 → 网络（Network），刷新页面后点任一请求，复制请求头中的 Cookie（需要包含 KuGoo=…）。',
                  style: ts(13, height: 1.5, color: p.text2),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(14)),
                  child: TextField(
                    controller: ctl,
                    maxLines: 5,
                    minLines: 3,
                    autocorrect: false,
                    style: ts(13, color: p.text),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'KuGoo=KugooID=…&t=…',
                      hintStyle: ts(13, color: p.text3),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('登录')),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;
    try {
      await source.loginWithCookie(ctl.text);
      onDone();
    } catch (e) {
      if (context.mounted) Toast.show(context, errorText(e), icon: YIcons.info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          kugouWebLoginSupported ? '在酷狗官方登录页中登录（支持酷狗 App 扫码与账号密码），登录后自动返回云音。' : '在浏览器中登录 kugou.com 后，把登录信息（Cookie）粘贴到云音。',
          style: ts(14, height: 1.5, color: p.text2),
        ),
        const SizedBox(height: 16),
        if (kugouWebLoginSupported)
          PrimaryButton(
            label: '打开酷狗官方登录页',
            icon: YIcons.user,
            height: 52,
            fontSize: 17,
            expand: true,
            onTap: () async {
              final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const KugouWebLogin()));
              if (ok == true) onDone();
            },
          )
        else
          PrimaryButton(
            label: '在浏览器中打开 kugou.com',
            icon: YIcons.share,
            height: 52,
            fontSize: 17,
            expand: true,
            onTap: () => launchUrl(Uri.parse('https://www.kugou.com/'), mode: LaunchMode.externalApplication),
          ),
        const SizedBox(height: 10),
        SecondaryButton(label: '粘贴 Cookie 登录', icon: YIcons.key, iconSize: 18, height: 46, fontSize: 15, onTap: () => _paste(context)),
      ],
    );
  }
}

/// 应用内打开酷狗官网登录：每秒检查一次页面 Cookie，出现登录信息后保存并返回。
class KugouWebLogin extends StatefulWidget {
  const KugouWebLogin({super.key});

  @override
  State<KugouWebLogin> createState() => _KugouWebLoginState();
}

class _KugouWebLoginState extends State<KugouWebLogin> {
  late final WebViewController _web;
  Timer? _poll;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // 使用电脑版页面：移动版没有登录入口。
      ..setUserAgent('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36')
      ..loadRequest(Uri.parse('https://www.kugou.com/'));
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  Future<void> _check() async {
    if (_done) return;
    try {
      final r = await _web.runJavaScriptReturningResult('document.cookie');
      final cookie = '$r'.replaceAll('"', '');
      if (KugouSource.parseKugooCookie(cookie) == null || !mounted) return;
      _done = true;
      _poll?.cancel();
      await context.read<SourceManager>().current.loginWithCookie(cookie);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('kugou web login: $e');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Scaffold(
      backgroundColor: p.bg,
      appBar: AppBar(
        backgroundColor: p.bg,
        foregroundColor: p.text,
        title: Text(
          '登录酷狗',
          style: ts(17, weight: w600, color: p.text),
        ),
        actions: [IconButton(onPressed: () => _web.reload(), icon: const Icon(Icons.refresh), tooltip: '刷新')],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: p.field,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Text('点按页面右上角“登录”，用酷狗 App 扫码或输入账号密码。登录成功后会自动返回。', style: ts(13, height: 1.4, color: p.text2)),
          ),
          Expanded(child: WebViewWidget(controller: _web)),
        ],
      ),
    );
  }
}
