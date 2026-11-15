import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 均衡器（音效的二级页面）：开关、预设与 10 个频段的逐段调节。
///
/// 关闭时也能直接拖动频段或选预设，一调就自动打开。设备被记为“不支持”时提供“重新检测”。
class EqualizerPage extends StatelessWidget {
  const EqualizerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AppSettings>();
    final unsupported = context.select<PlayerController, bool>((c) => c.eqUnsupported);
    void enable() {
      if (!s.eqEnabled) s.setFlag('eqEnabled', true);
    }

    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 22,
      children: [
        const PageHeader('均衡器', subtitle: '选一个预设，或者逐段调节 10 个频段'),
        CardList(
          indent: 14,
          children: [
            SettingsRow(
              title: '均衡器',
              value: unsupported ? '当前设备不支持' : null,
              trailing: YSwitch(value: s.eqEnabled && !unsupported, label: '均衡器', onChanged: unsupported ? (_) {} : (v) => s.setFlag('eqEnabled', v)),
            ),
            if (unsupported) SettingsRow(title: '重新检测', subtitle: '播放引擎之前报告均衡器无法使用。重新检测会再试一次，真的不支持时会再次自动关闭。', onTap: () => context.read<PlayerController>().retryEq()),
          ],
        ),
        const GroupLabel('预设'),
        IgnorePointer(
          ignoring: unsupported,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in EqPreset.ordered)
                YChip(
                  preset.label,
                  selected: s.eqEnabled && s.eqPreset == preset,
                  onTap: () {
                    enable();
                    s.setEqPreset(preset);
                  },
                ),
            ],
          ),
        ),
        const GroupLabel('频段'),
        AnimatedOpacity(
          opacity: s.eqEnabled && !unsupported ? 1 : 0.55,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: unsupported,
            child: YCard(
              radius: 20,
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
              child: SizedBox(
                height: 300,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < kEqBands.length; i++)
                      Expanded(
                        child: _BandSlider(
                          label: kEqBands[i] >= 1000 ? '${kEqBands[i] ~/ 1000}k' : '${kEqBands[i]}',
                          value: s.eqGains[i],
                          onChanged: (v) {
                            enable();
                            s.setEqGain(i, v);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '上下拖动调节各频段（±12 dB），双击恢复为 0；均衡器关闭时，拖动频段或选预设会自动打开。'
          '提升的频段经过限幅器（Android 为系统音效链的限幅器，此时以浮点格式输出），响亮的歌曲也不会削波破音。',
          style: ts(12.5, height: 1.5, color: p.text2),
        ),
      ],
    );
  }
}

/// 均衡器的一个频段：竖向滑块，0 dB 在中间，填充从中线到当前值。
class _BandSlider extends StatelessWidget {
  const _BandSlider({required this.label, required this.value, required this.onChanged});

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  static const _range = 12.0;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      children: [
        Text(
          '${value > 0 ? '+' : ''}${value.round()}',
          style: ts(11, weight: w600, color: p.text2, tabular: true),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final h = c.maxHeight;
              void update(double dy) => onChanged(((0.5 - dy / h) * 2 * _range).clamp(-_range, _range).roundToDouble());
              final y = (0.5 - value / _range / 2) * h;
              // 触摸区域撑满这一列：没有子组件的 CustomPaint 在居中对齐的 Column 里宽度是 0，
              // 此前滑块画在列的左边缘、却没有可以按到的区域，频段完全拖不动。
              return SizedBox(
                width: c.maxWidth,
                height: h,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (d) => update(d.localPosition.dy),
                  onVerticalDragUpdate: (d) => update(d.localPosition.dy),
                  onTapDown: (d) => update(d.localPosition.dy),
                  onDoubleTap: () => onChanged(0),
                  child: Semantics(
                    label: '$label 赫兹',
                    value: '${value.round()} 分贝',
                    increasedValue: '${(value + 1).clamp(-_range, _range).round()} 分贝',
                    decreasedValue: '${(value - 1).clamp(-_range, _range).round()} 分贝',
                    onIncrease: () => onChanged((value + 1).clamp(-_range, _range)),
                    onDecrease: () => onChanged((value - 1).clamp(-_range, _range)),
                    child: CustomPaint(
                      painter: _BandPainter(y: y, track: p.track, fill: p.accentText),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: ts(11, color: p.text2)),
      ],
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter({required this.y, required this.track, required this.fill});

  final double y;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final mid = size.height / 2;
    final line = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), line..color = track);
    canvas.drawLine(Offset(x, mid), Offset(x, y.clamp(2, size.height - 2)), line..color = fill);
    canvas.drawCircle(Offset(x, y.clamp(7, size.height - 7)), 7, Paint()..color = fill);
    canvas.drawCircle(Offset(x, y.clamp(7, size.height - 7)), 3, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.y != y || old.fill != fill || old.track != track;
}
