import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';

void main() {
  test('切换平台时切换并记住各平台的界面样式', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.init();
    s.initPlatform('netease');
    s.setAccent(AccentColor.orange);
    s.setPlayerStyle(PlayerStyle.vinyl);

    s.applyPlatform('qq');
    expect(s.accent, AccentColor.teal, reason: 'QQ 音乐默认绿色');
    expect(s.playerStyle, PlayerStyle.cardFlow);
    s.setPlayerStyle(PlayerStyle.wall);

    s.applyPlatform('kugou');
    expect(s.accent, AccentColor.blue);
    expect(s.playerStyle, PlayerStyle.coverFlow);

    s.applyPlatform('netease');
    expect(s.accent, AccentColor.orange, reason: '回到网易云恢复它自己的样式');
    expect(s.playerStyle, PlayerStyle.vinyl);
    s.applyPlatform('qq');
    expect(s.playerStyle, PlayerStyle.wall);

    // 重新启动后仍记得。
    final again = AppSettings();
    await again.init();
    again.initPlatform('qq');
    again.applyPlatform('netease');
    expect(again.playerStyle, PlayerStyle.vinyl);
  });
}
