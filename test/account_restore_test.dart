import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('损坏的网易云凭据不会阻止应用启动', () async {
    SharedPreferences.setMockInitialValues({'netease.cookie': '{broken'});
    final source = NeteaseSource();
    await source.init();
    expect(source.user, isNull);
    expect((await SharedPreferences.getInstance()).getString('netease.cookie'), isNull);
  });

  test('损坏的账号资料不会阻止其他播放源初始化', () async {
    SharedPreferences.setMockInitialValues({'netease.cookie': '{"MUSIC_U":"test"}', 'netease.profile': '[broken'});
    final source = NeteaseSource();
    await source.init();
    expect(source.user, isNull);
    expect((await SharedPreferences.getInstance()).getString('netease.profile'), isNull);
  });
}
