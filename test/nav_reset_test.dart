import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/features/shell/nav.dart';

void main() {
  test('切换平台后各标签只保留首页，当前标签保留正在看的页面', () {
    final nav = AppNav();
    nav.switchTab(1);
    nav.push(PlaylistRoute('123'));
    nav.push(ArtistRoute('a'));
    nav.switchTab(0);
    nav.push(SearchRoute());
    nav.push(ProfileRoute());
    nav.resetForPlatform();
    expect(nav.stacks[1].length, 1, reason: '发现标签回到首页');
    expect(nav.stacks[0].length, 2);
    expect(nav.top, isA<ProfileRoute>(), reason: '当前标签保留个人中心');
  });
}
