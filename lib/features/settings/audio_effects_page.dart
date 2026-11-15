import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/settings.dart';
import '../../core/theme/palette.dart';
import '../../core/ui/text.dart';
import '../../core/ui/widgets.dart';
import '../../player/player_controller.dart';
import '../common/actions.dart';
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
    final smartBoost = context.select<PlayerController, bool>((c) => c.smartBoost);
    final spatialUnsupported = context.select<PlayerController, bool>((c) => c.spatialUnsupported);
    final bassUnsupported = context.select<PlayerController, bool>((c) => c.bassUnsupported);
    final android = !kIsWeb && Platform.isAndroid;
    return AdaptivePage(
      chrome: Chrome.navOnly,
      mobileTop: 22,
            children: [
        PageHeader('音效', subtitle: '音质引擎、均衡器与音量'),
        const GroupLabel('音质引擎'),
        CardList(
          indent: 14,
          children: [
            SettingsRow(
              title: '高保真引擎',
              trailing: YSwitch(value: s.hifiEngine, label: '高保真引擎', onChanged: (v) => s.setFlag('hifiEngine', v)),
            ),
            SettingsRow(title: '播放音质', value: s.quality.label),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '高保真引擎使用更高精度的重采样滤镜与三角高通抖动，减少采样率转换与 16 位输出时的失真，是细节上的改善，并不改变音色；想明显改变声音请使用下面的均衡器、空间音效与低频增强。播放音质优先取平台的最高音质（Hi-Res / 无损），没有时逐级降低（未登录或没有会员时平台只给标准音质）。',
          style: ts(13, height: 1.5, color: p.text2),
        ),
        const GroupLabel('均衡器'),
        CardList(
          indent: 14,
          children: [
            SettingsRow(
              title: '均衡器',
              value: unsupported ? '当前设备不支持' : (s.eqEnabled ? s.eqPreset.label : '关闭'),
              onTap: () => go(context, EqualizerRoute()),
            ),
          ],
        ),
        ...[
          const GroupLabel('空间与低频'),
          CardList(
            indent: 14,
            children: [
              _SliderRow(
                title: '空间音效',
                value: s.spatial,
                text: spatialUnsupported ? '不支持' : (s.spatial == 0 ? '关闭' : '${(s.spatial * 100).round()}%'),
                onChanged: s.setSpatial,
              ),
              _SliderRow(
                title: '低频增强',
                value: s.bassEnhance,
                text: bassUnsupported ? '不支持' : (s.bassEnhance == 0 ? '关闭' : '${(s.bassEnhance * 100).round()}%'),
                onChanged: s.setBassEnhance,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            android
                ? '空间音效使用系统的虚拟环绕（按耳机或外放选择模式），并加一条声场曲线让高频更通透；低频增强在播放器中提升 30–120 Hz 的鼓点与贝斯，所有设备都有效，与均衡器可以叠加。'
                : '空间音效加一条声场曲线：中频略收、高频更通透，听感更开阔；低频增强提升 30–120 Hz 的鼓点与贝斯。两者与均衡器可以叠加。',
            style: ts(13, height: 1.5, color: p.text2),
          ),
        ],
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
              value: s.volumeBoost / AppSettings.maxVolumeBoost,
              text: s.volumeBoost == 0 ? '关闭' : '+${s.volumeBoost} dB',
              divisions: AppSettings.maxVolumeBoost,
              onChanged: (v) => s.setVolumeBoost((v * AppSettings.maxVolumeBoost).round()),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          smartBoost
              ? '音量均衡按平台提供的响度信息让不同歌曲音量接近。当前设备的播放引擎没有限幅器，音量增强改为按平台提供的峰值智能提升：每首歌最多提升到接近满幅，不会削波破音；已经很响的歌曲提升较少，没有峰值信息的歌曲保持原音量。'
              : '音量均衡按平台提供的响度信息让不同歌曲音量接近。音量增强先提升增益，再经过限幅器压住峰值，响亮的歌曲也不会削波破音。',
          style: ts(13, height: 1.5, color: p.text2),
        ),
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
          // 标题列留足四个字的宽度，滑块两侧各缩进一个滑块半径：值为 0 时滑块的圆点不会压到标题上。
          SizedBox(
            width: 84,
            child: Text(title, maxLines: 1, softWrap: false, overflow: TextOverflow.fade, style: ts(16, color: p.text)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SeekBar(value: value, height: 28, onSeek: (v) => onChanged(divisions == null ? v : (v * divisions!).round() / divisions!)),
            ),
          ),
          SizedBox(
            width: 56,
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
