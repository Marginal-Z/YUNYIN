import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/box.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/glow_background.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/models.dart';
import '../../data/sources/music_source.dart';
import '../../data/sources/source_manager.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  String _cc = '86';
  bool _agree = true;
  int _countdown = 0;
  Timer? _timer;
  bool _busy = false;

  MusicSource get _source => context.read<SourceManager>().current;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _done() {
    if (!mounted) return;
    Toast.show(context, '登录成功，欢迎回来');
    final nav = context.read<AppNav>();
    if (!nav.pop()) nav.switchTab(0);
  }

  bool _checkAgree() {
    if (_agree) return true;
    Toast.show(context, '请先阅读并同意用户协议与隐私政策', icon: YIcons.info);
    return false;
  }

  Future<void> _sendCode() async {
    if (_countdown > 0) return;
    final phone = _phone.text.trim();
    if (phone.length < 5) {
      Toast.show(context, '请输入正确的手机号', icon: YIcons.info);
      return;
    }
    try {
      await _source.sendSmsCode(phone, countryCode: _cc);
      if (!mounted) return;
      Toast.show(context, '验证码已发送');
      setState(() => _countdown = 60);
      _timer = Timer.periodic(const Duration(seconds: 1), (t) {
        if (!mounted || _countdown <= 1) {
          t.cancel();
          if (mounted) setState(() => _countdown = 0);
          return;
        }
        setState(() => _countdown--);
      });
    } catch (e) {
      if (mounted) Toast.show(context, errorText(e), icon: YIcons.info);
    }
  }

  Future<void> _login() async {
    if (!_checkAgree() || _busy) return;
    setState(() => _busy = true);
    try {
      await _source.loginWithSms(_phone.text.trim(), _code.text.trim(), countryCode: _cc);
      _done();
    } catch (e) {
      if (mounted) Toast.show(context, errorText(e), icon: YIcons.info);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickCountry() async {
    final v = await showOptions<String>(context, title: '选择国家和地区', selected: _cc, options: const [
      ('86', '中国大陆 +86'),
      ('852', '中国香港 +852'),
      ('853', '中国澳门 +853'),
      ('886', '中国台湾 +886'),
      ('1', '美国 / 加拿大 +1'),
      ('81', '日本 +81'),
      ('82', '韩国 +82'),
      ('44', '英国 +44'),
      ('65', '新加坡 +65'),
    ]);
    if (v != null) setState(() => _cc = v);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final pad = MediaQuery.paddingOf(context);
    final desktop = LayoutScope.isDesktop(context);
    final source = context.watch<SourceManager>().current;
    final canQr = source.supports(SourceFeature.qrLogin);
    final canPwd = source.supports(SourceFeature.passwordLogin);

    Widget field({required Widget child, double top = 0}) => Container(
          height: 52,
          margin: EdgeInsets.only(top: top),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(16)),
          child: child,
        );
    InputDecoration deco(String hint) => InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: ts(16, color: p.text2),
        );

    Widget content(double height) => SizedBox(
      width: 390,
      height: height,
      child: Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: 84,
          child: Column(children: [
            YBox(
              width: 84,
              height: 84,
              radius: BorderRadius.circular(19),
              clip: false,
              shadows: const [Shadow2(0, 16, 24, Color.fromRGBO(220, 16, 49, 0.35))],
              child: const AppLogo(size: 84, gradient: true),
            ),
            const SizedBox(height: 18),
            Text('云音', style: ts(34, weight: w700, em: -0.02, color: p.text)),
            const SizedBox(height: 6),
            Text(source.id == 'netease' ? '听见好音乐 · 使用网易云音乐账号登录' : '听见好音乐', style: ts(15, color: p.text2)),
          ]),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 300,
          child: YCard(
            radius: 30,
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              field(
                child: Row(children: [
                  Pressable(
                    onTap: _pickCountry,
                    pressedOpacity: 0.6,
                    semanticLabel: '选择区号',
                    child: Row(children: [
                      Text('+$_cc', style: ts(16, weight: w600, color: p.text)),
                      const SizedBox(width: 4),
                      YIcon(YIcons.chevronDown, size: 16, strokeWidth: 2, color: p.text),
                    ]),
                  ),
                  const SizedBox(width: 10),
                  Container(width: 1, height: 22, color: const Color.fromRGBO(60, 60, 67, 0.18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: ts(16, color: p.text),
                      cursorColor: p.accentText,
                      decoration: deco('请输入手机号'),
                    ),
                  ),
                ]),
              ),
              field(
                top: 12,
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _code,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: ts(16, color: p.text),
                      cursorColor: p.accentText,
                      decoration: deco('验证码'),
                      onSubmitted: (_) => _login(),
                    ),
                  ),
                  Pressable(
                    onTap: _countdown > 0 ? null : _sendCode,
                    pressedOpacity: 0.6,
                    child: Text(_countdown > 0 ? '${_countdown}s 后重发' : '获取验证码',
                        style: ts(15, weight: w600, color: _countdown > 0 ? p.text2 : p.accentText)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              PrimaryButton(label: _busy ? '登录中…' : '登录 / 注册', height: 52, fontSize: 17, onTap: _login),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Pressable(
                  onTap: () => setState(() => _agree = !_agree),
                  scale: 0.9,
                  semanticLabel: '同意用户协议与隐私政策',
                  child: Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(top: 1),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: _agree ? CssGradient.vertical(p.buttonGradient) : null,
                      border: _agree ? null : Border.all(color: p.muted, width: 1.5),
                    ),
                    alignment: Alignment.center,
                    child: _agree ? const YIcon(YIcons.check, size: 12, strokeWidth: 3, color: Colors.white) : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text.rich(
                    TextSpan(style: ts(12, height: 1.5, color: p.text2), children: [
                      const TextSpan(text: '我已阅读并同意'),
                      TextSpan(text: '《用户协议》', style: TextStyle(color: p.accentText)),
                      const TextSpan(text: '与'),
                      TextSpan(text: '《隐私政策》', style: TextStyle(color: p.accentText)),
                    ]),
                  ),
                ),
              ]),
            ]),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 612,
          child: Row(children: [
            Expanded(child: Container(height: 1, color: const Color.fromRGBO(60, 60, 67, 0.16))),
            const SizedBox(width: 12),
            Text('其他登录方式', style: ts(12, color: p.text2)),
            const SizedBox(width: 12),
            Expanded(child: Container(height: 1, color: const Color.fromRGBO(60, 60, 67, 0.16))),
          ]),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 646,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _OtherLogin(icon: YIcons.mail, label: '邮箱', onTap: canPwd ? () => _passwordLogin(email: true) : null),
            const SizedBox(width: 36),
            _OtherLogin(icon: YIcons.qr, label: '扫码', onTap: canQr ? _qrLogin : null),
            const SizedBox(width: 36),
            _OtherLogin(icon: YIcons.key, label: '密码', onTap: canPwd ? () => _passwordLogin(email: false) : null),
          ]),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 34,
          child: Center(
            child: Pressable(
              onTap: () {
                final nav = context.read<AppNav>();
                if (!nav.pop()) nav.switchTab(0);
              },
              pressedOpacity: 0.6,
              child: Text('先逛逛，稍后登录', style: ts(15, color: p.text2)),
            ),
          ),
        ),
      ]),
    );

    return GlowBackground.page(
      context,
      scale: desktop ? 2.4 : 1,
      child: LayoutBuilder(builder: (context, c) {
        final h = c.maxHeight - pad.top - pad.bottom;
        final boxH = math.max(h, 760.0);
        return Padding(
          padding: EdgeInsets.only(top: pad.top, bottom: pad.bottom),
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: math.min(390, c.maxWidth),
              height: h,
              child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.topCenter, child: content(boxH)),
            ),
          ),
        );
      }),
    );
  }

  Future<void> _passwordLogin({required bool email}) async {
    if (!_checkAgree()) return;
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.28),
      pageBuilder: (ctx, _, _) => _PasswordSheet(email: email, countryCode: _cc),
    );
    if (ok == true) _done();
  }

  Future<void> _qrLogin() async {
    if (!_checkAgree()) return;
    final ok = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭',
      barrierColor: const Color.fromRGBO(0, 0, 0, 0.28),
      pageBuilder: (ctx, _, _) => const _QrSheet(),
    );
    if (ok == true) _done();
  }
}

class _OtherLogin extends StatelessWidget {
  const _OtherLogin({required this.icon, required this.label, this.onTap});

  final YIconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        CircleButton(icon, size: 56, iconSize: 24, label: label, onTap: onTap ?? () {}),
        const SizedBox(height: 8),
        Text(label, style: ts(12, color: p.text3)),
      ]),
    );
  }
}

class _Dialog extends StatelessWidget {
  const _Dialog({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 350),
          child: YBox(
            radius: BorderRadius.circular(30),
            color: p.sheet,
            shadows: const [Shadow2(0, 24, 50, Color.fromRGBO(28, 44, 92, 0.22))],
            padding: const EdgeInsets.all(20),
            child: Material(
              type: MaterialType.transparency,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  Expanded(child: Text(title, style: ts(20, weight: w700, em: -0.01, color: p.text))),
                  YIconButton(YIcons.close, size: 36, iconSize: 14, color: p.text2, label: '关闭', onTap: () => Navigator.of(context).pop()),
                ]),
                const SizedBox(height: 12),
                child,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({required this.email, required this.countryCode});

  final bool email;
  final String countryCode;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _account = TextEditingController();
  final _pwd = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _account.dispose();
    _pwd.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<SourceManager>().current.loginWithPassword(_account.text.trim(), _pwd.text, countryCode: widget.countryCode);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) Toast.show(context, errorText(e), icon: YIcons.info);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget input(TextEditingController c, String hint, {bool obscure = false, TextInputType? type}) => Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(16)),
          alignment: Alignment.centerLeft,
          child: TextField(
            controller: c,
            obscureText: obscure,
            keyboardType: type,
            style: ts(16, color: p.text),
            cursorColor: p.accentText,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: hint, hintStyle: ts(16, color: p.text2)),
          ),
        );
    return _Dialog(
      title: widget.email ? '邮箱登录' : '密码登录',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        input(_account, widget.email ? '网易邮箱账号' : '手机号', type: widget.email ? TextInputType.emailAddress : TextInputType.phone),
        const SizedBox(height: 12),
        input(_pwd, '密码', obscure: true),
        const SizedBox(height: 16),
        PrimaryButton(label: _busy ? '登录中…' : '登录', height: 52, fontSize: 17, onTap: _submit),
        const SizedBox(height: 10),
        Text('若提示需要安全验证，请改用验证码或扫码登录。', style: ts(12, height: 1.5, color: p.text2), textAlign: TextAlign.center),
      ]),
    );
  }
}

class _QrSheet extends StatefulWidget {
  const _QrSheet();

  @override
  State<_QrSheet> createState() => _QrSheetState();
}

class _QrSheetState extends State<_QrSheet> {
  QrTicket? _ticket;
  QrState _state = QrState.waiting;
  Object? _error;
  Timer? _poll;
  int _failures = 0;

  @override
  void initState() {
    super.initState();
    _create();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _create() async {
    _poll?.cancel();
    setState(() {
      _ticket = null;
      _error = null;
      _state = QrState.waiting;
    });
    try {
      final source = context.read<SourceManager>().current;
      final t = await source.createQrLogin();
      if (!mounted) return;
      setState(() => _ticket = t);
      _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final s = await source.checkQrLogin(t);
          if (!mounted) return;
          setState(() => _state = s);
          if (s == QrState.confirmed) {
            _poll?.cancel();
            Navigator.of(context).pop(true);
          } else if (s == QrState.expired) {
            _poll?.cancel();
          }
          _failures = 0;
        } catch (e) {
          // 连续失败（例如触发风控）时把原因展示出来，而不是一直停在“等待扫码”。
          if (!mounted) return;
          if (++_failures >= 3) {
            _poll?.cancel();
            setState(() => _error = e);
          }
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final status = switch (_state) {
      QrState.waiting => '使用网易云音乐 App 扫码登录',
      QrState.scanned => '已扫码，请在手机上确认',
      QrState.confirmed => '登录成功',
      QrState.expired => '二维码已过期',
    };
    return _Dialog(
      title: '扫码登录',
      child: Column(children: [
        Container(
          width: 220,
          height: 220,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: _error != null
              ? Center(child: Text(errorText(_error), style: ts(13, color: const Color(0xFF6E6E73)), textAlign: TextAlign.center))
              : _ticket == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : Opacity(
                      opacity: _state == QrState.expired ? 0.2 : 1,
                      child: QrImageView(
                        data: _ticket!.content,
                        padding: EdgeInsets.zero,
                        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF1D1D1F)),
                        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF1D1D1F)),
                      ),
                    ),
        ),
        const SizedBox(height: 14),
        Text(status, style: ts(15, weight: w600, color: p.text)),
        const SizedBox(height: 14),
        if (_state == QrState.expired || _error != null)
          PrimaryButton(label: '刷新二维码', icon: YIcons.refresh, height: 44, fontSize: 15, iconSize: 18, onTap: _create),
      ]),
    );
  }
}
