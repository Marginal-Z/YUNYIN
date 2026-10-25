import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub Releases 上的一个版本。
class ReleaseInfo {
  const ReleaseInfo({required this.version, required this.notes, required this.page, required this.assets, this.date});

  final String version;
  final String notes;
  final String page;
  final DateTime? date;

  /// 文件名 → (下载地址, 大小)。
  final Map<String, (String, int)> assets;
}

/// 当前安装方式，决定下载哪个安装包以及如何覆盖安装。
enum InstallKind { androidApk, windowsInstaller, windowsPortable, linuxDeb, linuxAppImage, linuxTar, macosApp, unsupported }

enum UpdateStage { idle, checking, upToDate, available, downloading, installing, failed }

/// 应用内更新：从 GitHub Releases 获取最新版本，下载与当前平台、架构、安装方式对应的安装包，并以高版本覆盖当前版本。
class UpdateManager extends ChangeNotifier {
  UpdateManager({Dio? dio}) : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), headers: {'User-Agent': 'YunYin-Updater'}));

  static const repo = 'Marginal-Z/YUNYIN';
  static const _channel = MethodChannel('yunyin/update');

  final Dio _dio;
  CancelToken? _cancel;

  UpdateStage stage = UpdateStage.idle;
  String current = '';
  int build = 0;
  ReleaseInfo? latest;
  double progress = 0;
  String? error;
  InstallKind kind = InstallKind.unsupported;

  bool get hasUpdate => latest != null && compareVersions(latest!.version, current) > 0;

  Future<void> init() async {
    final info = await PackageInfo.fromPlatform();
    current = info.version;
    build = int.tryParse(info.buildNumber) ?? 0;
    kind = _detectKind();
  }

  void _set(UpdateStage s, {String? err}) {
    stage = s;
    error = err;
    notifyListeners();
  }

  /// 检查最新版本。返回是否有更新。
  Future<bool> check() async {
    if (stage == UpdateStage.checking || stage == UpdateStage.downloading || stage == UpdateStage.installing) return hasUpdate;
    if (current.isEmpty) await init();
    _set(UpdateStage.checking);
    try {
      final r = await _dio.get<Map<String, dynamic>>(
        'https://api.github.com/repos/$repo/releases/latest',
        options: Options(headers: {'Accept': 'application/vnd.github+json'}),
      );
      final j = r.data!;
      latest = ReleaseInfo(
        version: (j['tag_name'] as String).replaceFirst(RegExp('^v'), ''),
        notes: (j['body'] as String? ?? '').trim(),
        page: j['html_url'] as String? ?? 'https://github.com/$repo/releases',
        date: DateTime.tryParse(j['published_at'] as String? ?? ''),
        assets: {
          for (final a in (j['assets'] as List).cast<Map<String, dynamic>>())
            a['name'] as String: (a['browser_download_url'] as String, (a['size'] as num?)?.toInt() ?? 0),
        },
      );
      _set(hasUpdate ? UpdateStage.available : UpdateStage.upToDate);
      return hasUpdate;
    } catch (e) {
      _set(UpdateStage.failed, err: '检查更新失败：${_describe(e)}');
      return false;
    }
  }

  /// 安装方式的说明，显示在更新弹窗中。
  String get kindLabel => switch (kind) {
    InstallKind.androidApk => 'Android 安装包',
    InstallKind.windowsInstaller => 'Windows 安装程序',
    InstallKind.windowsPortable => 'Windows 便携版',
    InstallKind.linuxDeb => 'deb 软件包',
    InstallKind.linuxAppImage => 'AppImage',
    InstallKind.linuxTar => 'Linux 便携版',
    InstallKind.macosApp => 'macOS 应用',
    InstallKind.unsupported => '当前平台',
  };

  /// 与当前安装方式匹配的安装包文件名。
  Future<String?> assetName(ReleaseInfo r) async {
    final v = r.version;
    final base = 'YunYin-$v';
    switch (kind) {
      case InstallKind.androidApk:
        // 分 ABI 的安装包版本号为 ABI × 1000 + 版本号，通用包没有前缀，因此必须继续使用同一种包才能覆盖安装。
        final abi = switch (build ~/ 1000) {
          1 => 'armeabi-v7a',
          2 => 'arm64-v8a',
          4 => 'x86_64',
          _ => null,
        };
        return abi == null ? '$base-android-universal.apk' : '$base-android-$abi.apk';
      case InstallKind.windowsInstaller:
        return '$base-windows-x64-setup.exe';
      case InstallKind.windowsPortable:
        return '$base-windows-x64.zip';
      case InstallKind.linuxDeb:
        return '$base-linux-${await _linuxArch()}.deb';
      case InstallKind.linuxAppImage:
        return '$base-linux-${await _linuxArch()}.AppImage';
      case InstallKind.linuxTar:
        return '$base-linux-${await _linuxArch()}.tar.gz';
      case InstallKind.macosApp:
        return '$base-macos-universal.zip';
      case InstallKind.unsupported:
        return null;
    }
  }

  /// 下载并安装。成功时桌面端会退出并由安装脚本重新启动应用。
  Future<void> downloadAndInstall() async {
    final r = latest;
    if (r == null || !hasUpdate) return;
    final name = await assetName(r);
    final asset = name == null ? null : r.assets[name];
    if (asset == null) {
      _set(UpdateStage.failed, err: '这个版本没有提供$kindLabel，请前往发布页手动下载');
      return;
    }
    final dir = Directory('${(await getTemporaryDirectory()).path}/yunyin-update');
    await dir.create(recursive: true);
    final file = File('${dir.path}/$name');
    progress = 0;
    _set(UpdateStage.downloading);
    try {
      if (!(await file.exists() && await file.length() == asset.$2)) {
        _cancel = CancelToken();
        await _dio.download(
          asset.$1,
          '${file.path}.part',
          cancelToken: _cancel,
          options: Options(receiveTimeout: const Duration(minutes: 30)),
          onReceiveProgress: (got, total) {
            final t = total > 0 ? total : asset.$2;
            if (t <= 0) return;
            progress = got / t;
            notifyListeners();
          },
        );
        await File('${file.path}.part').rename(file.path);
      }
      progress = 1;
      _set(UpdateStage.installing);
      await _install(file);
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        _set(UpdateStage.available);
      } else {
        _set(UpdateStage.failed, err: '下载失败：${_describe(e)}');
      }
    } catch (e) {
      _set(UpdateStage.failed, err: '安装失败：${_describe(e)}');
    }
  }

  void cancel() => _cancel?.cancel();

  Future<void> _install(File pkg) async {
    final exe = File(Platform.resolvedExecutable);
    switch (kind) {
      case InstallKind.androidApk:
        final r = await _channel.invokeMethod<String>('installApk', {'path': pkg.path});
        // 系统安装界面接管后续步骤；需要授权“安装未知应用”时先打开系统设置。
        _set(UpdateStage.available, err: r == 'permission' ? '请允许云音安装应用，然后再点一次“立即更新”' : null);
        return;
      case InstallKind.windowsInstaller:
        // 安装程序使用固定的 AppId，覆盖安装到原目录，完成后重新启动云音。
        await Process.start(pkg.path, ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS'], mode: ProcessStartMode.detached);
        exit(0);
      case InstallKind.windowsPortable:
        final script = File('${pkg.parent.path}\\update.ps1');
        await script.writeAsString('''
\$ErrorActionPreference = 'Stop'
Wait-Process -Id $pid -ErrorAction SilentlyContinue
Expand-Archive -LiteralPath '${pkg.path}' -DestinationPath '${exe.parent.path}' -Force
Start-Process -FilePath '${exe.path}'
''');
        await Process.start('powershell', [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-WindowStyle',
          'Hidden',
          '-File',
          script.path,
        ], mode: ProcessStartMode.detached);
        exit(0);
      case InstallKind.linuxDeb:
        final apt = await _which('apt-get');
        final args = apt != null ? [apt, 'install', '-y', pkg.path] : ['dpkg', '-i', pkg.path];
        final r = await Process.run('pkexec', args);
        if (r.exitCode != 0) {
          final msg = '${r.stderr}'.trim();
          throw Exception(r.exitCode == 126 || r.exitCode == 127 ? '已取消授权' : (msg.isEmpty ? '退出码 ${r.exitCode}' : msg.split('\n').last));
        }
        await Process.start(exe.path, [], mode: ProcessStartMode.detached);
        exit(0);
      case InstallKind.linuxAppImage:
        final target = Platform.environment['APPIMAGE']!;
        final tmp = '$target.new';
        await pkg.copy(tmp);
        await Process.run('chmod', ['755', tmp]);
        // 同一目录内重命名是原子操作，正在运行的旧文件不受影响。
        await File(tmp).rename(target);
        await Process.start(target, [], mode: ProcessStartMode.detached);
        exit(0);
      case InstallKind.linuxTar:
        await _runAfterExit('''
tar -xzf '${pkg.path}' -C '${exe.parent.path}'
exec '${exe.path}'
''');
      case InstallKind.macosApp:
        final app = exe.parent.parent.parent.path;
        await _runAfterExit('''
rm -rf '${pkg.parent.path}/unpacked'
ditto -x -k '${pkg.path}' '${pkg.parent.path}/unpacked'
new=\$(ls -d '${pkg.parent.path}'/unpacked/*.app | head -n1)
rm -rf '$app'
mv "\$new" '$app'
open '$app'
''');
      case InstallKind.unsupported:
        throw Exception('当前平台不支持应用内更新');
    }
  }

  /// 在应用退出后执行 shell 脚本（替换正在运行的文件）。
  Future<Never> _runAfterExit(String body) async {
    final dir = (await getTemporaryDirectory()).path;
    final script = File('$dir/yunyin-update/update.sh');
    await script.writeAsString('#!/bin/sh\nwhile kill -0 $pid 2>/dev/null; do sleep 0.3; done\nset -e\n$body');
    await Process.start('/bin/sh', [script.path], mode: ProcessStartMode.detached);
    exit(0);
  }

  static InstallKind _detectKind() {
    if (kIsWeb) return InstallKind.unsupported;
    if (Platform.isAndroid) return InstallKind.androidApk;
    final dir = File(Platform.resolvedExecutable).parent;
    if (Platform.isWindows) {
      return File('${dir.path}\\unins000.exe').existsSync() ? InstallKind.windowsInstaller : InstallKind.windowsPortable;
    }
    if (Platform.isLinux) {
      if ((Platform.environment['APPIMAGE'] ?? '').isNotEmpty) return InstallKind.linuxAppImage;
      if (dir.path.startsWith('/opt/yunyin')) return InstallKind.linuxDeb;
      return InstallKind.linuxTar;
    }
    if (Platform.isMacOS) return InstallKind.macosApp;
    return InstallKind.unsupported;
  }

  static Future<String> _linuxArch() async {
    final r = await Process.run('uname', ['-m']);
    return '${r.stdout}'.trim() == 'aarch64' ? 'arm64' : 'x64';
  }

  static Future<String?> _which(String cmd) async {
    final r = await Process.run('which', [cmd]);
    return r.exitCode == 0 ? '${r.stdout}'.trim() : null;
  }

  static String _describe(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 403) return 'GitHub 请求过于频繁，请稍后再试';
      if (code == 404) return '还没有发布版本';
      if (code != null) return 'HTTP $code';
      return '网络连接失败';
    }
    return '$e'.replaceFirst('Exception: ', '');
  }
}

/// 比较形如 1.2.10 的版本号。
int compareVersions(String a, String b) {
  List<int> parts(String v) => v.split(RegExp(r'[.+-]')).take(3).map((x) => int.tryParse(x) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}
