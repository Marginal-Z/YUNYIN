import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/assistant/assistant_settings.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/core/theme/palette.dart';
import 'package:yunyin/core/update/updater.dart';
import 'package:yunyin/data/cloud/cloud_drives.dart';
import 'package:yunyin/data/downloads.dart';
import 'package:yunyin/data/listen_stats.dart';
import 'package:yunyin/data/local_library.dart';
import 'package:yunyin/data/lx/lx_sources.dart';
import 'package:yunyin/player/player_controller.dart';
import 'package:yunyin/data/sources/kugou/kugou_source.dart';
import 'package:yunyin/data/sources/netease/netease_source.dart';
import 'package:yunyin/data/sources/qq/qq_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';
import 'package:yunyin/features/common/layout.dart';
import 'package:yunyin/features/desktop/desktop_dialogs.dart';
import 'package:yunyin/features/shell/nav.dart';

void main() {
  testWidgets('桌面端设置面板显示设置内容，子页面在面板内打开', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final sm = SourceManager([NeteaseSource(), QQMusicSource(), KugouSource()]);
    final settings = AppSettings();
    final player = PlayerController(sm, settings);
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: sm),
          ChangeNotifierProvider.value(value: player),
          ChangeNotifierProvider.value(value: DownloadManager(sm, settings)),
          ChangeNotifierProvider.value(value: LocalLibrary()),
          ChangeNotifierProvider.value(value: CloudDrives()),
          ChangeNotifierProvider.value(value: UpdateManager()),
          ChangeNotifierProvider.value(value: AssistantSettings()..voiceWake = false),
          ChangeNotifierProvider.value(value: LxSources()),
          ChangeNotifierProvider.value(value: ListenStats()),
          ChangeNotifierProvider.value(value: AppNav()),
        ],
        child: PaletteScope(
          palette: Palette.light(AccentColor.red),
          child: MaterialApp(
            home: LayoutScope(
              desktop: true,
              child: Material(
                child: Builder(builder: (context) => Center(child: TextButton(onPressed: () => showDesktopSettings(context), child: const Text('open')))),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    final subtitle = find.text('管理播放体验与应用偏好');
    expect(subtitle, findsOneWidget);
    // 面板中的页面按面板宽度排版，而不是按整个窗口（之前内容被挤成 40 像素宽，看起来一片空白）。
    expect(tester.getSize(subtitle).width, greaterThan(150));
  });
}
