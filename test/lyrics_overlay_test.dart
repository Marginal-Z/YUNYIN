import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/lyrics_overlay.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/player/player_controller.dart';

void main() {
  test('桌面歌词跟随进度切换当前句与下一句，没有歌词时显示歌名', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings();
    await settings.init();
    settings.setFlag('desktopLyrics', true);
    final player = PlayerController(SourceManager(const []), settings)
      ..debugSetQueue([const Song(id: '1', sourceId: 'x', name: '晴天', artists: [ArtistRef('a', '周杰伦')])], 0);
    final overlay = LyricsOverlay.attach(player, settings);
    expect(overlay.line, '晴天');
    expect(overlay.next, '周杰伦');

    player.lyrics = const Lyrics([LyricLine(Duration(seconds: 2), '故事的小黄花'), LyricLine(Duration(seconds: 6), '从出生那年就飘着')]);
    player.notifyListeners();
    var changes = 0;
    overlay.addListener(() => changes++);
    player.position.value = const Duration(seconds: 3);
    expect(overlay.line, '故事的小黄花');
    expect(overlay.next, '从出生那年就飘着');
    player.position.value = const Duration(seconds: 4);
    expect(changes, 1, reason: '同一句内进度变化不重复通知');
    player.position.value = const Duration(seconds: 7);
    expect(overlay.line, '从出生那年就飘着');
    expect(overlay.next, '');
  });
}
