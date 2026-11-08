import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'pet_painter.dart';
import 'pet_rig.dart';

/// 桌宠图片（解码一次，多处共用）。
abstract final class PetImages {
  static final _cache = <PetKind, Future<ui.Image>>{};

  static Future<ui.Image> load(PetKind kind) => _cache[kind] ??= () async {
    final data = await rootBundle.load(kind.rig.asset);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }();
}

/// 会动的桌宠：按 [mood] 换表情与动作，[bubble] 不为空时在头顶显示对话气泡。
///
/// 用计时器按 [fps] 刷新（悬浮窗与桌面窗口用较低的帧率省电）。
class PetView extends StatefulWidget {
  const PetView({super.key, required this.kind, this.mood = PetMood.idle, this.height = 140, this.bubble = '', this.fps = 60, this.controller});

  final PetKind kind;
  final PetMood mood;

  /// 桌宠本身的高度（画布还会在上方与两侧留出特效的空间）。
  final double height;
  final String bubble;
  final int fps;
  final PetViewController? controller;

  /// 气泡区域的高度。
  static const bubbleHeight = 64.0;

  @override
  State<PetView> createState() => _PetViewState();
}

/// 从外部触发桌宠的小反应（被戳、被拖动）。
class PetViewController {
  _PetViewState? _state;

  void poke() => _state?._animator.poke();

  set dragVelocity(double v) => _state?._animator.dragVelocity = v;
}

class _PetViewState extends State<PetView> with WidgetsBindingObserver {
  late PetAnimator _animator = PetAnimator(widget.kind)..setMood(widget.mood);
  final _time = ValueNotifier<double>(0);
  final _clock = Stopwatch()..start();
  ui.Image? _image;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    WidgetsBinding.instance.addObserver(this);
    _load();
    _start();
  }

  /// 看不见时（应用在后台、悬浮窗收起）停止计时，不耗电。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _timer?.cancel();
    }
  }

  void _load() {
    PetImages.load(widget.kind).then((img) {
      if (mounted) setState(() => _image = img);
    }).catchError((Object e) => debugPrint('pet image: $e'));
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(microseconds: 1000000 ~/ widget.fps), (_) => _time.value = _clock.elapsedMicroseconds / 1e6);
  }

  @override
  void didUpdateWidget(PetView old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.kind != widget.kind) {
      _animator = PetAnimator(widget.kind)..setMood(widget.mood);
      _image = null;
      _load();
    }
    _animator.setMood(widget.mood);
    if (old.fps != widget.fps) _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (widget.controller?._state == this) widget.controller?._state = null;
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = PetPainter.canvasSize(widget.kind, widget.height);
    final image = _image;
    final pet = SizedBox.fromSize(
      size: size,
      child: image == null
          ? null
          : RepaintBoundary(
              child: CustomPaint(
                painter: PetPainter(image: image, animator: _animator, time: _time, accent: widget.kind.color),
              ),
            ),
    );
    if (widget.bubble.isEmpty) return pet;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PetBubble(text: widget.bubble, color: widget.kind.color, width: size.width + 60),
        pet,
      ],
    );
  }
}

/// 头顶的对话气泡（白底、主题色描边，最多两行）。
class PetBubble extends StatelessWidget {
  const PetBubble({super.key, required this.text, required this.color, required this.width});

  final String text;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: PetView.bubbleHeight,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xF7FFFFFF),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.55), width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8, offset: Offset(0, 2))],
          ),
          child: Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            textDirection: TextDirection.ltr,
            style: const TextStyle(fontSize: 13, height: 1.3, color: Color(0xFF1F2333), decoration: TextDecoration.none),
          ),
        ),
      ),
    );
  }
}
