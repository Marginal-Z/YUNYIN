import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';

void main() {
  const cookie =
      'kg_mid=abc; kg_dfid=xyz; KuGoo=KugooID=123456789&KugooPwd=ABCDEF&NickName=%u4e91%u97f3%u7528%u6237&Pic=http://imge.kugou.com/kugouicon/165/a.jpg&RegState=1&RegFrom=&t=tok123&a_id=1014&ct=1700000000&UserName=%u4e91%u97f3; kg_mid_temp=1';

  test('解析酷狗 KuGoo Cookie（整段 Cookie 或只有 KuGoo 的值）', () {
    final a = KugouSource.parseKugooCookie(cookie)!;
    expect(a['KugooID'], '123456789');
    expect(a['t'], 'tok123');
    expect(a['NickName'], '云音用户');
    expect(a['_raw'], startsWith('KugooID=123456789&'));
    expect(KugouSource.parseKugooCookie('KugooID=1&t=x&NickName=a')!['KugooID'], '1');
    expect(KugouSource.parseKugooCookie('kg_mid=abc'), isNull, reason: '没有登录信息');
    expect(KugouSource.parseKugooCookie('KuGoo=KugooID=0&t='), isNull, reason: '未登录的游客 Cookie');
  });

  test('Cookie 登录后保存账号，重新启动仍为登录状态，退出后清除', () async {
    SharedPreferences.setMockInitialValues({});
    final kg = KugouSource();
    await kg.loginWithCookie(cookie);
    expect(kg.user?.nickname, '云音用户');
    expect(kg.user?.avatar, startsWith('https://'));
    final again = KugouSource();
    await again.init();
    expect(again.loggedIn, isTrue);
    expect((await again.membership())?.title, '已登录');
    await again.logout();
    final third = KugouSource();
    await third.init();
    expect(third.loggedIn, isFalse);
    await expectLater(kg.loginWithCookie('kg_mid=1'), throwsA(isA<Exception>()));
  });
}
