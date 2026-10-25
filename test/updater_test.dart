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
}
