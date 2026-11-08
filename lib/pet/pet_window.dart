import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'pet_host.dart';
import 'pet_rig.dart';
import 'pet_view.dart';

/// Android 悬浮窗里的桌宠（单独的 Flutter 引擎，入口见 main.dart 的 petOverlayMain）。
/// 触摸由原生一侧处理（拖动、点按、长按），这里只负责画。
const _overlayChannel = MethodChannel('yunyin/pet_view');

Future<void> runPetOverlay() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _PetStage(desktop: false));
}

/// 桌面端桌宠窗口的入口：无边框、透明、置顶、不显示在任务栏。
Future<void> runPetWindow(String arguments) async {
  final args = jsonDecode(arguments) as Map<String, dynamic>;
  await windowManager.ensureInitialized();
  if (Platform.isLinux) await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  await windowManager.setAsFrameless();
  await windowManager.setBackgroundColor(Colors.transparent);
  await windowManager.setTitle('云音桌宠');
  await windowManager.setSkipTaskbar(true);
  await windowManager.setAlwaysOnTop(true);
  await windowManager.setResizable(false);
  final size = petWindowSize(PetKind.tuantuan, 132, bubble: false);
  await windowManager.setSize(size);
  Offset? position;
  try {
    final p = jsonDecode('${args['position']}') as Map<String, dynamic>;
    position = Offset((p['x'] as num).toDouble(), (p['y'] as num).toDouble());
  } catch (_) {}
  if (position == null) {
    // 默认放在屏幕右下角。
    final display = ui.PlatformDispatcher.instance.displays.firstOrNull;
    if (display != null) {
      final screen = display.size / display.devicePixelRatio;
      position = Offset(screen.width - size.width - 40, screen.height - size.height - 90);
    }
  }
  if (position != null) await windowManager.setPosition(position);
  runApp(const _PetStage(desktop: true));
  await windowManager.show();
}

class _PetStage extends StatefulWidget {
  const _PetStage({required this.desktop});

  final bool desktop;

  @override
  State<_PetStage> createState() => _PetStageState();
}

class _PetStageState extends State<_PetStage> with WindowListener {
  PetKind _kind = PetKind.tuantuan;
  PetMood _mood = PetMood.idle;
  String _text = '';
  double _height = 132;
  bool _dragging = false;
  bool? _bubble;
  ui.Size? _size;
  Timer? _moved;
  final _pet = PetViewController();

  @override
  void initState() {
    super.initState();
    if (widget.desktop) {
      windowManager.addListener(this);
      petWindowChannel.setMethodCallHandler(_onCall);
      petWindowChannel.invokeMethod<Map>('ready').then((s) => s == null ? null : _apply(s)).catchError((Object e) => debugPrint('pet: $e'));
    } else {
      _overlayChannel.setMethodCallHandler(_onCall);
      _overlayChannel.invokeMethod<Map>('ready').then((s) => s == null ? null : _apply(s)).catchError((Object e) => debugPrint('pet: $e'));
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    switch (call.method) {
      case 'state':
        _apply(call.arguments as Map);
      case 'drag':
        final a = call.arguments as Map;
        _pet.dragVelocity = (a['vx'] as num?)?.toDouble() ?? 0;
        setState(() => _dragging = a['active'] == true);
      case 'poke':
        _pet.poke();
      case 'quit':
        Timer(Duration.zero, windowManager.destroy);
    }
    return null;
  }

  void _apply(Map<dynamic, dynamic> s) {
    final kind = PetKind.byName(s['kind'] as String?);
    if (!mounted || kind == null) return;
    setState(() {
      _kind = kind;
      _mood = PetMood.byName(s['mood'] as String?);
      _text = '${s['text'] ?? ''}';
      _height = (s['height'] as num?)?.toDouble() ?? 132;
    });
    unawaited(_fit());
  }

  /// 有气泡时窗口向上加高，没有时收回（透明区域也会挡住下面的点按，不能一直留着）。
  Future<void> _fit() async {
    final bubble = _text.isNotEmpty;
    final size = petWindowSize(_kind, _height, bubble: bubble);
    if (bubble == _bubble && size == _size) return;
    _bubble = bubble;
    _size = size;
    if (widget.desktop) {
      final b = await windowManager.getBounds();
      await windowManager.setBounds(Rect.fromLTWH(b.left + (b.width - size.width) / 2, b.bottom - size.height, size.width, size.height));
    } else {
      await _overlayChannel.invokeMethod<void>('size', {'w': size.width, 'h': size.height});
    }
  }

  @override
  void onWindowMoved() {
    // 桌面端拖动由系统完成：移动期间显示“被拎起来”，停下后保存位置。
    if (!_dragging) setState(() => _dragging = true);
    _moved?.cancel();
    _moved = Timer(const Duration(milliseconds: 350), () async {
      if (mounted) setState(() => _dragging = false);
      final p = await windowManager.getPosition();
      petWindowChannel.invokeMethod<void>('moved', {'x': p.dx, 'y': p.dy}).catchError((Object _) {});
    });
  }

  @override
  void dispose() {
    _moved?.cancel();
    if (widget.desktop) windowManager.removeListener(this);
    super.dispose();
  }

  void _tap() {
    _pet.poke();
    petWindowChannel.invokeMethod<void>('tap').catchError((Object e) => debugPrint('pet: $e'));
  }

  @override
  Widget build(BuildContext context) {
    Widget pet = PetView(
      kind: _kind,
      mood: _dragging ? PetMood.dragged : _mood,
      height: _height,
      bubble: _text,
      fps: 40,
      controller: _pet,
    );
    if (widget.desktop) {
      pet = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: _tap,
          // 右键打开云音主窗口。
          onSecondaryTap: () => petWindowChannel.invokeMethod<void>('open').catchError((Object _) {}),
          onPanStart: (_) => windowManager.startDragging(),
          child: Tooltip(message: '点我说话 · 拖动换位置 · 右键打开云音', waitDuration: const Duration(seconds: 1), child: pet),
        ),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(canvasColor: Colors.transparent, scaffoldBackgroundColor: Colors.transparent),
      home: Material(
        type: MaterialType.transparency,
        child: Align(alignment: Alignment.bottomCenter, child: pet),
      ),
    );
  }
}
