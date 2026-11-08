import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../core/update/updater.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

const kRepoUrl = 'https://github.com/Marginal-Z/YUNYIN';

/// 反馈群组链接（Telegram）。为空时意见反馈页不显示这一项。
const kTelegramGroup = '';

/// 关于页中的二级页面。
enum AboutPage { privacy, agreement, permissions, feedback }

Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

/// 二级页面的通用外框：返回按钮 + 标题。
class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.children, this.subtitle});

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 22,
            children: [
        PageHeader(title, subtitle: subtitle),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 隐私政策正文（隐私政策页、首次启动的使用声明与登录页共用）。
const kPrivacySections = <Widget>[
  _Section('概述', ['云音是开源的第三方音乐客户端，没有自己的服务器，不收集、不上传、不出售任何个人信息，也没有统计、广告或崩溃上报。本政策说明云音在你的设备上保存哪些数据、会访问哪些网络服务，以及如何删除这些数据。']),
  _Section('保存在本机的数据', [
    '• 平台账号凭据：网易云音乐与 QQ 音乐登录后的 Cookie / 登录密钥，只用于向对应平台的官方接口发送请求，退出登录即删除。',
    '• 网盘配置：网盘地址、账号与密码保存在本机应用数据中，只发送给你填写的网盘服务器。',
    '• 洛雪音源：你导入的音源脚本保存在本机，可随时在“设置 → 洛雪音源”中删除。',
    '• 设置、搜索历史、播放队列、最近播放与听歌统计（每天的收听时长与最常听的歌曲）。',
    '• 本地音乐索引，以及从音频文件读取或联网匹配的封面与歌词。',
    '• 图片与页面数据缓存，可在“设置 → 清除缓存”中删除。',
    '• 云音助手：你填写的大模型接口地址、模型名称与密钥，以及离线语音模型。助手的对话记录只保存在内存中，关闭应用后清除。',
    '• 音色中心：你填写的云端语音引擎（CosyVoice、Fish Audio、ElevenLabs）的密钥、代理地址与声音 ID，下载的离线声音，以及最近合成的朗读语音缓存（最多约 60 MB，可在“设置 → 清除缓存”中删除）。',
  ]),
  _Section('云音助手与麦克风', [
    '• 麦克风只在你打开“语音唤醒”或点按麦克风按钮时使用。唤醒词检测与语音识别完全在本机离线完成，录音不会保存，也不会上传到任何服务器。',
    '• 打开语音唤醒后，Android 上会显示“语音唤醒已开启”的常驻通知，表示麦克风正在本机检测唤醒词；可在通知上或设置中随时关闭。',
    '• 你向助手说的话（识别后的文字）与必要的播放信息（正在播放的歌名、歌手、歌词与听歌统计摘要）只会发送到你在设置中填写的大模型接口，用于生成回答；不填写时这些内容不会离开你的设备。该服务如何处理数据适用其自身的隐私政策。',
    '• 朗读回答：只有在你于“音色中心”填写了云端语音引擎的密钥后，助手要朗读的文字才会发送到对应服务商合成语音——阿里云百炼 CosyVoice（dashscope.aliyuncs.com）、Fish Audio（api.fish.audio）或 ElevenLabs（api.elevenlabs.io），或你填写的代理地址；不填写时使用本机的离线声音或系统朗读，文字不会离开你的设备。各服务商如何处理数据适用其自身的隐私政策。',
    '• 桌宠：打开后在桌面上显示一个悬浮窗（需要“显示在其他应用上层”权限），只显示桌宠与助手的状态，不读取屏幕或其他应用的内容。',
  ]),
  _Section('访问的网络服务', [
    '• 当前平台模式的官方接口：网易云音乐（music.163.com 等）、QQ 音乐（y.qq.com、u.y.qq.com 等，扫码登录经 QQ 互联 ptlogin2.qq.com / graph.qq.com）、酷狗音乐（kugou.com 等），用于搜索、歌单、歌词与播放。各平台如何处理这些请求，适用其各自的隐私政策。',
    '• 本地歌曲联网补全封面与歌词时，会用歌名与歌手在上述平台中搜索。',
    '• 你挂载的网盘（WebDAV）服务器。',
    '• 你导入的洛雪音源脚本可能访问脚本作者指定的服务器以获取播放地址；云音只代为发送脚本发起的网络请求，脚本无法读取你的文件、账号或其他应用数据。请只导入可信来源的脚本。',
    '• GitHub（api.github.com、github.com）：检查与下载新版本，可在“设置 → 关于云音”中关闭自动检查。',
    '• 第一次打开语音功能时，从 sherpa-onnx 官方发布页（github.com，网络不畅时经 ghfast.top 加速或 hf-mirror.com 镜像）下载离线语音模型，下载后按官方文件的校验值核对；在音色中心下载离线声音时同样如此。',
    '• 你在音色中心填写了密钥的云端语音引擎（见上文“朗读回答”）。',
  ]),
  _Section('系统权限', ['云音申请的系统权限及用途见“权限管理”，每项权限只在对应功能需要时使用。']),
  _Section('删除数据', ['退出登录会删除对应平台的登录凭据；移除网盘或音源会删除其配置；卸载云音会删除它保存在应用目录中的全部数据。你自己的音乐文件不会被删除。']),
  _Section('联系', ['对本政策有疑问，可以在“意见反馈”中通过 GitHub 提交 Issue。']),
];

/// 用户协议正文。
const kAgreementSections = <Widget>[
  _Section('关于云音', ['云音是开源、免费的第三方音乐客户端，支持网易云音乐、QQ 音乐、酷狗音乐三种平台模式，以及本地音乐与网盘播放。云音与网易公司、腾讯公司、酷狗音乐及其关联公司没有任何关联，不提供、不存储、不分发任何音乐内容，仅供学习与交流使用。']),
  _Section('使用规则', [
    '• 请遵守各音乐平台的用户协议与相关法律法规，不得利用云音从事侵权或违法活动。',
    '• 歌曲、歌词、封面与评论等内容的著作权归各自权利人所有。播放与下载权限与你在各平台的账号一致，请支持正版。',
    '• 下载的歌曲仅供个人在本机收听，请勿传播或用于商业用途。',
    '• 网盘中的文件由你自行上传与管理，请确保你有权播放这些文件。',
  ]),
  _Section('第三方音源脚本', ['“洛雪音源”功能只提供脚本的运行环境，云音不提供、不推荐也不审核任何音源脚本。你导入与使用的脚本及其获取的内容由你自行负责，请遵守相关法律法规与平台规则；因使用第三方脚本产生的任何纠纷与损失，与云音及其开发者无关。']),
  _Section('免责声明', ['云音按“现状”提供，不保证服务不中断或没有错误。各平台接口的变化可能导致部分功能暂时不可用。因使用云音造成的任何直接或间接损失，开发者不承担责任。']),
  _Section('协议更新', ['本协议可能随版本更新而修改，修改后的内容会在应用内公布；继续使用即表示同意更新后的协议。']),
  _Section('开源', ['云音的源代码公开在 GitHub，你可以查看、学习与提出改进建议。第三方组件按各自的开源许可证使用，见“开源许可”。']),
];

/// 在弹窗中查看用户协议或隐私政策（首次启动的使用声明与登录页使用）。
Future<void> showDocument(BuildContext context, AboutPage page) {
  final title = page == AboutPage.privacy ? '隐私政策' : '用户协议';
  final sections = page == AboutPage.privacy ? kPrivacySections : kAgreementSections;
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '关闭',
    barrierColor: const Color.fromRGBO(0, 0, 0, 0.35),
    pageBuilder: (ctx, _, _) {
      final p = Palette.of(ctx);
      final size = MediaQuery.sizeOf(ctx);
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: size.height * 0.82),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: p.bg,
              borderRadius: BorderRadius.circular(26),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 8, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: ts(20, weight: w700, color: p.text),
                          ),
                        ),
                        YIconButton(YIcons.close, color: p.text2, label: '关闭', onTap: () => Navigator.of(ctx).pop()),
                      ],
                    ),
                  ),
                  Flexible(
                    child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 20), shrinkWrap: true, children: sections),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// 文档段落：小标题 + 若干段文字或要点。
class _Section extends StatelessWidget {
  const _Section(this.title, this.lines);

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: YCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: ts(17, weight: w700, color: p.text),
              ),
              for (final l in lines) ...[
                const SizedBox(height: 8),
                if (l.startsWith('• '))
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8, right: 8),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(color: p.accentText, shape: BoxShape.circle),
                        ),
                      ),
                      Expanded(
                        child: Text(l.substring(2), style: ts(15, height: 1.6, color: p.text2)),
                      ),
                    ],
                  )
                else
                  Text(l, style: ts(15, height: 1.6, color: p.text2)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget buildAboutPage(AboutPage page) => switch (page) {
  AboutPage.privacy => const PrivacyPage(),
  AboutPage.agreement => const AgreementPage(),
  AboutPage.permissions => const PermissionsPage(),
  AboutPage.feedback => const FeedbackPage(),
};

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _Frame(title: '隐私政策', subtitle: '更新于 2026 年 11 月 · 适用于云音的所有版本', children: [...kPrivacySections]);
  }
}

class AgreementPage extends StatelessWidget {
  const AgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return _Frame(title: '用户协议', subtitle: '更新于 2026 年 11 月 · 使用云音即表示你同意以下条款', children: [...kAgreementSections]);
  }
}

/// 权限管理：说明每项权限的用途，Android 上显示授权状态并可打开系统设置。
class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> with WidgetsBindingObserver {
  static const _channel = MethodChannel('yunyin/system');
  Map<String, bool>? _status;

  bool get _android => !kIsWeb && Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 从系统设置返回后刷新状态。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!_android) return;
    try {
      final m = await _channel.invokeMapMethod<String, bool>('permissionStatus');
      if (mounted) setState(() => _status = m);
    } catch (e) {
      debugPrint('permission status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final items = _android
        ? const [
            ('network', YIcons.wifi, TileColor.blue, '网络', '获取歌单、歌词、评论与播放音乐。安装时自动授予。'),
            ('notifications', YIcons.bell, TileColor.red, '通知', '在通知栏与锁屏显示播放控制。关闭后仍可后台播放，但看不到媒体通知。'),
            ('audio', YIcons.library, TileColor.teal, '音乐与音频', '“扫描本机歌曲”读取设备中的音乐文件。不扫描时不需要。'),
            ('install', YIcons.download, TileColor.orange, '安装未知应用', '应用内更新时安装新版本。只在你确认更新后使用。'),
            ('overlay', YIcons.lyrics, TileColor.red, '显示在其他应用上层', '桌面歌词、状态栏歌词与桌宠的悬浮窗。只在你开启这些功能时需要。'),
            ('microphone', YIcons.mic, TileColor.blue, '麦克风', '云音助手的语音唤醒与语音指令，只在本机识别、不上传。只在你打开语音功能时需要。'),
            ('background', YIcons.play, TileColor.graphite, '后台播放', '前台服务与唤醒锁，保证锁屏与切到后台时继续播放。安装时自动授予。'),
          ]
        : const [
            ('network', YIcons.wifi, TileColor.blue, '网络', '获取歌单、歌词、评论与播放音乐。'),
            ('files', YIcons.folder, TileColor.teal, '文件', '导入或扫描本地音乐、选择下载目录与背景图片时，只读取你选择或“音乐”“下载”目录中的文件。'),
          ];
    return _Frame(
      title: '权限管理',
      subtitle: '云音只申请播放与下载必需的权限',
      children: [
        CardList(
          indent: 56,
          children: [
            for (final (key, icon, tile, title, desc) in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IconTile(icon, tile),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: ts(16, weight: w600, color: p.text),
                                ),
                              ),
                              if (_status?[key] case final granted?)
                                Text(
                                  granted ? '已允许' : '未允许',
                                  style: ts(13, weight: w600, color: granted ? p.text2 : p.danger),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(desc, style: ts(13, height: 1.5, color: p.text2)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (_android) ...[
          const SizedBox(height: 18),
          PrimaryButton(label: '打开系统设置', icon: YIcons.sliders, expand: true, onTap: () => _channel.invokeMethod<void>('openAppSettings')),
        ],
      ],
    );
  }
}

class FeedbackPage extends StatelessWidget {
  const FeedbackPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final version = context.watch<UpdateManager>().current;
    final platform = kIsWeb ? 'Web' : '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
    return _Frame(
      title: '意见反馈',
      subtitle: '遇到问题或有好点子，欢迎告诉我们',
      children: [
        CardList(
          indent: 56,
          children: [
            SettingsRow(icon: YIcons.feedback, tile: TileColor.red, title: '报告问题', value: 'GitHub Issues', onTap: () => _open('$kRepoUrl/issues/new')),
            SettingsRow(icon: YIcons.sparkle, tile: TileColor.blue, title: '功能建议', value: 'GitHub', onTap: () => _open('$kRepoUrl/issues')),
            if (kTelegramGroup.isNotEmpty)
              SettingsRow(icon: YIcons.send, tile: TileColor.teal, title: 'Telegram 交流群', value: '加入群组', onTap: () => _open(kTelegramGroup)),
          ],
        ),
        const SizedBox(height: 18),
        YCard(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '反馈时请附上',
                  style: ts(16, weight: w600, color: p.text),
                ),
                const SizedBox(height: 6),
                Text('云音 v$version · $platform', style: ts(13, color: p.text2)),
                const SizedBox(height: 4),
                Text('以及问题出现的步骤、截图或录屏，能帮我们更快定位问题。', style: ts(13, height: 1.5, color: p.text2)),
                const SizedBox(height: 12),
                SecondaryButton(
                  label: '复制设备信息',
                  icon: YIcons.document,
                  height: 42,
                  fontSize: 15,
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: '云音 v$version\n$platform'));
                    Toast.show(context, '已复制设备信息');
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
