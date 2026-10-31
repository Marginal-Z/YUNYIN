import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/palette.dart';
import '../../core/ui/feedback.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../data/cloud/cloud_drives.dart';
import '../../data/sources/cloud/cloud_source.dart';
import '../common/actions.dart';
import '../common/layout.dart';
import '../common/song_row.dart';
import '../shell/nav.dart';

/// 二级页面外框：移动端左上角返回按钮 + 标题。
class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.children, this.subtitle, this.chrome = Chrome.full});

  final String title;
  final String? subtitle;
  final Chrome chrome;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final desktop = LayoutScope.isDesktop(context);
    return AdaptivePage(
      chrome: chrome,
      mobileTop: 78,
      overlay: [
        Positioned(
          left: 16,
          top: 20,
          child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
        ),
      ],
      children: [
        PageTitle(title, subtitle: subtitle, size: desktop ? 40 : 36),
        const SizedBox(height: 18),
        ...children,
        const SizedBox(height: 24),
      ],
    );
  }
}

/// 网盘页（桌面端侧边栏“网盘”）。
class CloudDrivesPage extends StatelessWidget {
  const CloudDrivesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Frame(title: '网盘', subtitle: '挂载网盘，直接播放其中的音乐', children: [CloudDriveList()]);
  }
}

/// 已挂载的网盘列表 + 添加按钮 + 支持的网盘说明（乐库“网盘”标签也使用）。
class CloudDriveList extends StatelessWidget {
  const CloudDriveList({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final drives = context.watch<CloudDrives>().drives;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (drives.isEmpty)
          YCard(
            child: StateView.empty(
              title: '还没有挂载网盘',
              message: '通过 WebDAV 挂载网盘或 NAS，在线播放其中的 MP3、FLAC、M4A 等音乐文件。',
              icon: YIcons.cloud,
              action: '添加网盘',
              onAction: () => go(context, CloudEditRoute()),
            ),
          )
        else ...[
          CardList(
            indent: 56,
            children: [
              for (final d in drives)
                SettingsRow(
                  icon: YIcons.cloud,
                  tile: TileColor.blue,
                  title: d.name,
                  height: 58,
                  onTap: () => go(context, CloudBrowseRoute(d.id, title: d.name)),
                  trailing: Pressable(
                    onTap: () => go(context, CloudEditRoute(d.id)),
                    pressedOpacity: 0.6,
                    semanticLabel: '编辑${d.name}',
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: YIcon(YIcons.more, size: 20, color: p.text2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          SecondaryButton(label: '添加网盘', icon: YIcons.plus, iconSize: 18, height: 46, fontSize: 15, onTap: () => go(context, CloudEditRoute())),
        ],
        const SizedBox(height: 22),
        Text(
          '支持的网盘',
          style: ts(17, weight: w700, color: p.text),
        ),
        const SizedBox(height: 8),
        Text(
          '坚果云、Nextcloud / ownCloud、群晖等 NAS、pCloud、Box 以及任何 WebDAV 服务可以直接添加。\n'
          '阿里云盘、百度网盘、夸克网盘、115、天翼云盘、123 云盘、OneDrive、Google Drive、Dropbox 等，'
          '先用 Alist / OpenList 挂载，再添加它的 WebDAV 地址（http://地址:5244/dav）。',
          style: ts(14, height: 1.6, color: p.text2),
        ),
      ],
    );
  }
}

/// 添加或编辑网盘。
class CloudEditPage extends StatefulWidget {
  const CloudEditPage({super.key, this.driveId});

  final String? driveId;

  @override
  State<CloudEditPage> createState() => _CloudEditPageState();
}

class _CloudEditPageState extends State<CloudEditPage> {
  late CloudKind _kind;
  late final TextEditingController _name, _url, _user, _pass;
  bool _testing = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    final d = widget.driveId == null ? null : context.read<CloudDrives>().byId(widget.driveId!);
    _kind = d?.kind ?? CloudKind.alist;
    _name = TextEditingController(text: d?.name ?? '');
    _url = TextEditingController(text: d?.url ?? _kind.defaultUrl);
    _user = TextEditingController(text: d?.username ?? '');
    _pass = TextEditingController(text: d?.password ?? '');
  }

  @override
  void dispose() {
    for (final c in [_name, _url, _user, _pass]) {
      c.dispose();
    }
    super.dispose();
  }

  void _pickKind(CloudKind k) {
    setState(() {
      // 地址还是上一个类型的默认地址（或为空）时换成新类型的默认地址。
      if (_url.text.trim().isEmpty || _url.text == _kind.defaultUrl) _url.text = k.defaultUrl;
      _kind = k;
    });
  }

  CloudDrive? _draft() {
    var url = _url.text.trim();
    if (url.isEmpty) {
      Toast.show(context, '请填写 WebDAV 地址', icon: YIcons.info);
      return null;
    }
    if (!url.startsWith(RegExp('https?://'))) url = 'https://$url';
    if (Uri.tryParse(url)?.host.isEmpty ?? true) {
      Toast.show(context, '地址格式不正确', icon: YIcons.info);
      return null;
    }
    final name = _name.text.trim();
    return CloudDrive(
      id: widget.driveId ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      kind: _kind,
      name: name.isEmpty ? (_kind == CloudKind.webdav ? Uri.parse(url).host : _kind.label) : name,
      url: url,
      username: _user.text.trim(),
      password: _pass.text,
    );
  }

  Future<void> _test() async {
    final d = _draft();
    if (d == null) return;
    setState(() => _testing = true);
    try {
      final items = await context.read<CloudDrives>().list(d);
      if (mounted) Toast.show(context, '连接成功，根目录有 ${items.length} 项');
    } catch (e) {
      if (mounted) Toast.show(context, '连接失败：${errorText(e)}', icon: YIcons.info);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  void _save() {
    final d = _draft();
    if (d == null) return;
    context.read<CloudDrives>().upsert(d);
    context.read<AppNav>().pop();
    Toast.show(context, '已保存${d.name}');
  }

  Future<void> _delete() async {
    final drives = context.read<CloudDrives>();
    final ok = await showConfirm(context, title: '移除网盘？', message: '只会移除云音中的挂载信息，不会删除网盘中的文件。', confirm: '移除');
    if (!ok || !mounted) return;
    drives.remove(widget.driveId!);
    context.read<AppNav>().pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
      child: Text(
        text,
        style: ts(13, weight: w600, color: p.text2),
      ),
    );
    Widget field(TextEditingController c, String hint, {bool password = false, TextInputType? type}) => Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: p.field, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: c,
              obscureText: password && _obscure,
              keyboardType: type,
              autocorrect: false,
              enableSuggestions: !password,
              style: ts(16, color: p.text),
              cursorColor: p.accentText,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: ts(16, color: p.text3),
              ),
            ),
          ),
          if (password)
            Pressable(
              onTap: () => setState(() => _obscure = !_obscure),
              pressedOpacity: 0.6,
              child: Text(
                _obscure ? '显示' : '隐藏',
                style: ts(14, weight: w600, color: p.accentText),
              ),
            ),
        ],
      ),
    );
    return _Frame(
      title: widget.driveId == null ? '添加网盘' : '编辑网盘',
      subtitle: '通过 WebDAV 挂载',
      chrome: Chrome.navOnly,
      children: [
        ChipBar(labels: [for (final k in CloudKind.values) k.label], index: _kind.index, scroll: true, onChanged: (i) => _pickKind(CloudKind.values[i])),
        const SizedBox(height: 12),
        Text(_kind.hint, style: ts(14, height: 1.5, color: p.text2)),
        YCard(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              label('名称'),
              field(_name, _kind == CloudKind.webdav ? '我的网盘' : _kind.label),
              label('WebDAV 地址'),
              field(_url, 'https://', type: TextInputType.url),
              label('账号'),
              field(_user, '用户名或邮箱'),
              label('密码'),
              field(_pass, '密码或应用密码', password: true),
            ],
          ),
        ).withTop(14),
        const SizedBox(height: 8),
        Text('账号与密码只保存在本机，仅发送给你填写的网盘服务器。', style: ts(13, color: p.text3)),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: _testing ? '正在连接…' : '测试连接',
                icon: YIcons.wifi,
                iconSize: 18,
                height: 48,
                fontSize: 15,
                onTap: _testing ? null : _test,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(label: '保存', icon: YIcons.check, iconSize: 18, height: 48, fontSize: 15, expand: true, onTap: _save),
            ),
          ],
        ),
        if (widget.driveId != null) ...[
          const SizedBox(height: 18),
          Center(
            child: Pressable(
              onTap: _delete,
              pressedOpacity: 0.6,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '移除网盘',
                  style: ts(15, weight: w600, color: const Color(0xFFFF3B30)),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

extension on Widget {
  Widget withTop(double top) => Padding(
    padding: EdgeInsets.only(top: top),
    child: this,
  );
}

/// 浏览网盘文件夹：子文件夹 + 音乐文件，可以播放全部。
class CloudBrowsePage extends StatelessWidget {
  const CloudBrowsePage({super.key, required this.route});

  final CloudBrowseRoute route;

  @override
  Widget build(BuildContext context) {
    final drives = context.watch<CloudDrives>();
    final d = drives.byId(route.driveId);
    if (d == null) {
      return _Frame(
        title: route.title ?? '网盘',
        children: [
          YCard(
            child: StateView.empty(title: '网盘已移除', message: '这个网盘已经从云音中移除。', icon: YIcons.folder),
          ),
        ],
      );
    }
    return _Frame(
      title: route.title ?? d.name,
      subtitle: route.href.isEmpty ? d.kind.label : d.name,
      children: [
        AsyncView<List<CloudEntry>>(
          keyValue: '${d.url}|${route.href}',
          load: () => drives.list(d, route.href),
          builder: (context, items, reload) => _Listing(drive: d, items: items, title: route.title ?? d.name),
        ),
      ],
    );
  }
}

class _Listing extends StatelessWidget {
  const _Listing({required this.drive, required this.items, required this.title});

  final CloudDrive drive;
  final List<CloudEntry> items;
  final String title;

  @override
  Widget build(BuildContext context) {
    final folders = [
      for (final e in items)
        if (e.isDir) e,
    ];
    final songs = [
      for (final e in items)
        if (e.isAudio) CloudSource.songOf(drive, e),
    ];
    if (folders.isEmpty && songs.isEmpty) {
      return YCard(
        child: StateView.empty(title: '这里没有音乐', message: '这个文件夹中没有子文件夹或音乐文件。', icon: YIcons.folder),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (folders.isNotEmpty) ...[
          SectionHeader('文件夹 · ${folders.length}', top: 0),
          CardList(
            indent: 56,
            children: [
              for (final f in folders)
                SettingsRow(
                  icon: YIcons.folder,
                  tile: TileColor.orange,
                  title: f.name,
                  onTap: () => go(context, CloudBrowseRoute(drive.id, href: f.href, title: f.name)),
                ),
            ],
          ),
        ],
        if (songs.isNotEmpty) ...[
          SectionHeader(
            '音乐 · ${songs.length} 首',
            top: folders.isEmpty ? 0 : 28,
            action: '播放全部',
            onAction: () => playAll(context, songs, title: title),
          ),
          CardList(
            indent: 70,
            children: [
              for (var i = 0; i < songs.length; i++)
                SongRow(
                  song: songs[i],
                  trailing: SongTrailing.none,
                  onTap: () => playAll(context, songs, start: i, title: title),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
