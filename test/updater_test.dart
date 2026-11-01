import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/update/updater.dart';

void main() {
  test('版本号比较', () {
    expect(compareVersions('1.1.0', '1.0.2'), 1);
    expect(compareVersions('1.0.10', '1.0.9'), 1);
    expect(compareVersions('1.0.2', '1.0.2+3'), 0);
    expect(compareVersions('1.0.2', '1.1'), -1);
    expect(compareVersions('2.0.0', '1.99.99'), 1);
  });

  test('Android 按安装的 ABI 选择安装包', () async {
    const release = ReleaseInfo(version: '1.2.0', notes: '', page: '', assets: {});
    final u = UpdateManager()..kind = InstallKind.androidApk;
    u.build = 2004;
    expect(await u.assetName(release), 'YunYin-1.2.0-android-arm64-v8a.apk');
    u.build = 1004;
    expect(await u.assetName(release), 'YunYin-1.2.0-android-armeabi-v7a.apk');
    u.build = 4;
    expect(await u.assetName(release), 'YunYin-1.2.0-android-universal.apk');
    u.kind = InstallKind.windowsInstaller;
    expect(await u.assetName(release), 'YunYin-1.2.0-windows-x64-setup.exe');
  });

  test('拒绝路径穿越或带命令的版本号', () async {
    final updater = UpdateManager()..kind = InstallKind.windowsPortable;
    for (final version in ['../../other', "1.2.0'; touch injected", '1/2/3']) {
      await expectLater(updater.assetName(ReleaseInfo(version: version, notes: '', page: '', assets: const {})), throwsFormatException);
    }
  });

  test('更新包同时校验大小与 SHA256，包括已缓存的同大小坏文件', () async {
    final directory = await Directory.systemTemp.createTemp('yunyin-update');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/package');
    await file.writeAsBytes([1, 2, 3]);
    final digest = 'sha256:${sha256.convert([1, 2, 3])}';
    expect(await verifyUpdateFile(file, 3, digest), isTrue);
    expect(await verifyUpdateFile(file, 4, digest), isFalse);
    await file.writeAsBytes([3, 2, 1]);
    expect(await verifyUpdateFile(file, 3, digest), isFalse);
    expect(await verifyUpdateFile(file, 3, 'unknown:hash'), isFalse);
    expect(await verifyUpdateFile(file, 0, null), isFalse);
    expect(await verifyUpdateFile(file, 3, null), isTrue);
  });

  test('更新脚本安全处理空格、单引号和 shell 字符', () async {
    const path = "/tmp/it's a file; \$(echo injected) & music";
    expect(quotePowerShellArgument(path), "'/tmp/it''s a file; \$(echo injected) & music'");
    if (Platform.isWindows) return;
    final result = await Process.run('/bin/sh', ['-c', 'printf %s ${quoteShellArgument(path)}']);
    expect(result.exitCode, 0);
    expect(result.stdout, path);
  });
}
