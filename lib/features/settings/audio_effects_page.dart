import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/icons.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/layout.dart';
import '../shell/nav.dart';

/// 音效：10 段均衡器（预设与逐段调节）、音量均衡强度与音量增强。
class AudioEffectsPage extends StatelessWidget {
  const AudioEffectsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final s = context.watch<AppSettings>();
    final unsupported = context.select<PlayerController, bool>((c) => c.eqUnsupported);
    final desktop = LayoutScope.isDesktop(context);
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 78,
      overlay: [
        Positioned(
          left: 16,
          top: 20,
          child: GlassButton(YIcons.back, label: '返回', onTap: () => context.read<AppNav>().pop()),
        ),
      ],
      children: [
        PageTitle('音效', subtitle: '均衡器与音量', size: desktop ? 40 : 36),
        const GroupLabel('均衡器'),
        CardList(
          indent: 14,
          children: [
            SettingsRow(
              title: '均衡器',
              value: unsupported ? '当前设备不支持' : null,
              trailing: YSwitch(value: s.eqEnabled && !unsupported, label: '均衡器', onChanged: unsupported ? (_) {} : (v) => s.setFlag('eqEnabled', v)),
            ),
            AnimatedOpacity(
              opacity: s.eqEnabled && !unsupported ? 1 : 0.4,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !s.eqEnabled || unsupported,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final preset in EqPreset.values) ...[
                              YChip(preset.label, selected: s.eqPreset == preset, onTap: () => s.setEqPreset(preset)),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 220,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < kEqBands.length; i++)
                              Expanded(
                                child: _BandSlider(
                                  label: kEqBands[i] >= 1000 ? '${kEqBands[i] ~/ 1000}k' : '${kEqBands[i]}',
                                  value: s.eqGains[i],
                                  onChanged: (v) => s.setEqGain(i, v),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('上下拖动调节各频段（±12 dB），双击恢复为 0。', style: ts(12, color: p.text2)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const GroupLabel('音量'),
        CardList(
          indent: 14,
          children: [
            SettingsRow(
              title: '音量均衡',
              trailing: YSwitch(value: s.normalize, label: '音量均衡', onChanged: (v) => s.setFlag('normalize', v)),
            ),
            if (s.normalize)
              _SliderRow(title: '均衡强度', value: s.normalizeStrength, text: '${(s.normalizeStrength * 100).round()}%', onChanged: s.setNormalizeStrength),
            _SliderRow(
              title: '音量增强',
              value: s.volumeBoost / 6,
              text: s.volumeBoost == 0 ? '关闭' : '+${s.volumeBoost} dB',
              divisions: 6,
              onChanged: (v) => s.setVolumeBoost((v * 6).round()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('音量均衡按平台提供的响度信息让不同歌曲音量接近；强度越低，响的歌曲被压低得越少。音量增强过高时，响亮的歌曲可能失真。', style: ts(13, height: 1.5, color: p.text2)),
      ],
    );
  }
}

/// 一行标题 + 横向滑块 + 数值。
class _SliderRow extends StatelessWidget {
  const _SliderRow({required this.title, required this.value, required this.text, required this.onChanged, this.divisions});

  final String title;
  final double value;
  final String text;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(title, style: ts(16, color: p.text)),
          ),
          Expanded(
            child: SeekBar(value: value, height: 28, onSeek: (v) => onChanged(divisions == null ? v : (v * divisions!).round() / divisions!)),
          ),
          SizedBox(
            width: 64,
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: ts(14, color: p.text2, tabular: true),
            ),
          ),
        ],
      ),
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
              return GestureDetector(
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
