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

/// 账号与关于中的二级页面。
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
    final desktop = LayoutScope.isDesktop(context);
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 78,
      overlay: [
        Positioned(left: 16, top: 20, child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop())),
      ],
      children: [
        PageTitle(title, subtitle: subtitle, size: desktop ? 40 : 36),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 24),
      ],
    );
  }
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
              Text(title, style: ts(17, weight: w700, color: p.text)),
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
                      Expanded(child: Text(l.substring(2), style: ts(15, height: 1.6, color: p.text2))),
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
    return const _Frame(
      title: '隐私政策',
      subtitle: '更新于 2026 年 10 月',
      children: [
        _Section('概述', [
          '云音是开源的第三方客户端，不设服务器，不收集、不上传、不出售任何个人信息。本政策说明云音在你的设备上保存哪些数据、会访问哪些网络服务，以及如何删除这些数据。',
        ]),
        _Section('保存在本机的数据', [
          '• 登录凭据（网易云音乐 Cookie）：只用于向网易云音乐官方接口发送请求，退出登录即删除。',
          '• 设置、搜索历史、播放队列与最近播放。',
          '• 听歌统计：每天的收听时长与最常听的歌曲，只在本机计算与显示。',
          '• 本地音乐索引、从音频文件读取或联网补全的封面与歌词。',
          '• 图片与页面数据缓存，可在“设置 → 清除缓存”中删除。',
        ]),
        _Section('访问的网络服务', [
          '• 网易云音乐官方接口（music.163.com、interface.music.163.com 及其图片与音频服务器）：获取歌单、歌词、评论与播放地址，登录、收藏等操作也直接发送到这些接口。网易云音乐如何处理这些请求，适用其自身的隐私政策。',
          '• GitHub（api.github.com、github.com）：检查与下载新版本。可在“账号与关于 → 启动时检查更新”中关闭自动检查。',
          '云音没有统计、广告或崩溃上报等第三方服务。',
        ]),
        _Section('删除数据', [
          '退出登录会删除登录凭据；卸载云音会删除它保存在应用目录中的全部数据。你导入的本地音乐文件不会被删除。',
        ]),
        _Section('联系', ['对本政策有疑问，可以在“意见反馈”中通过 GitHub 提交 Issue。']),
      ],
    );
  }
}

class AgreementPage extends StatelessWidget {
  const AgreementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Frame(
      title: '用户协议',
      subtitle: '使用云音即表示你同意以下条款',
      children: [
        _Section('关于云音', [
          '云音是开源的第三方网易云音乐客户端，与网易公司及网易云音乐没有任何关联，仅供学习与交流使用，免费提供。',
        ]),
        _Section('使用规则', [
          '• 请遵守网易云音乐的用户协议与相关法律法规，不得利用云音从事侵权或违法活动。',
          '• 歌曲、歌词、封面与评论等内容的著作权归各自权利人所有。播放与下载权限与你的网易云音乐账号一致，请支持正版。',
          '• 下载的歌曲仅供个人在本机收听，请勿传播。',
        ]),
        _Section('免责声明', [
          '云音按“现状”提供，不保证服务不中断或没有错误。网易云音乐接口的变化可能导致部分功能暂时不可用。因使用云音造成的任何损失，开发者不承担责任。',
        ]),
        _Section('开源', ['云音的源代码公开在 GitHub，你可以查看、学习与提出改进建议。第三方组件按各自的开源许可证使用，见“开源许可”。']),
      ],
    );
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
                              Expanded(child: Text(title, style: ts(16, weight: w600, color: p.text))),
                              if (_status?[key] case final granted?)
                                Text(granted ? '已允许' : '未允许', style: ts(13, weight: w600, color: granted ? p.text2 : p.danger)),
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
          PrimaryButton(
            label: '打开系统设置',
            icon: YIcons.sliders,
            expand: true,
            onTap: () => _channel.invokeMethod<void>('openAppSettings'),
          ),
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
            SettingsRow(
              icon: YIcons.feedback,
              tile: TileColor.red,
              title: '报告问题',
              value: 'GitHub Issues',
              onTap: () => _open('$kRepoUrl/issues/new'),
            ),
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
                Text('反馈时请附上', style: ts(16, weight: w600, color: p.text)),
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
