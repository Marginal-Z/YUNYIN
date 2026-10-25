import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 设计稿图标：24 网格，描边 1.75，圆角端点。
class YIconData {
  const YIconData(this.body, {this.stroke = true, this.strokeWidth = 1.75, this.cap = true, this.join = true});

  final String body;
  final bool stroke;
  final double strokeWidth;
  final bool cap;
  final bool join;

  String svg({double? strokeWidth}) {
    final attrs = stroke
        ? 'fill="none" stroke="currentColor" stroke-width="${strokeWidth ?? this.strokeWidth}"'
              '${cap ? ' stroke-linecap="round"' : ''}${join ? ' stroke-linejoin="round"' : ''}'
        : 'fill="currentColor"';
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" $attrs>$body</svg>';
  }
}

abstract final class YIcons {
  static const back = YIconData('<path d="m15 6-6 6 6 6"/>');
  static const forward = YIconData('<path d="m9 6 6 6-6 6"/>');
  static const chevronDown = YIconData('<path d="m6 9 6 6 6-6"/>');
  static const chevronRight = YIconData('<path d="m9 5 7 7-7 7"/>', strokeWidth: 2.2);
  static const more = YIconData('<circle cx="5" cy="12" r="1.6"/><circle cx="12" cy="12" r="1.6"/><circle cx="19" cy="12" r="1.6"/>', stroke: false);
  static const plus = YIconData('<path d="M12 5v14M5 12h14"/>');
  static const play = YIconData('<path d="M8 5.5v13l11-6.5z"/>', stroke: false);
  static const playOutline = YIconData('<path d="M8 5.5v13l11-6.5z"/>', cap: false);
  static const pause = YIconData('<rect x="6.5" y="5" width="4" height="14" rx="1.2"/><rect x="13.5" y="5" width="4" height="14" rx="1.2"/>', stroke: false);
  static const pauseLarge = YIconData(
    '<rect x="6" y="5" width="4.2" height="14" rx="1.3"/><rect x="13.8" y="5" width="4.2" height="14" rx="1.3"/>',
    stroke: false,
  );
  static const next = YIconData('<path d="M5 6v12l9-6z"/><rect x="16" y="6" width="2.8" height="12" rx="1.2"/>', stroke: false);
  static const prev = YIconData('<path d="M19 6v12l-9-6z"/><rect x="5.2" y="6" width="2.8" height="12" rx="1.2"/>', stroke: false);
  static const home = YIconData('<path d="M4 11.5 12 5l8 6.5V19a1 1 0 0 1-1 1h-4v-5.5h-6V20H5a1 1 0 0 1-1-1z"/>');
  static const discover = YIconData('<circle cx="12" cy="12" r="8.5"/><path d="m15.5 8.5-2 5-5 2 2-5z"/>');
  static const library = YIconData('<path d="M10 17.5V6l9-2v11.5"/><circle cx="7.5" cy="17.5" r="2.5"/><circle cx="16.5" cy="15.5" r="2.5"/>');
  static const search = YIconData('<circle cx="11" cy="11" r="6.5"/><path d="m20 20-4.2-4.2"/>');
  static const user = YIconData('<circle cx="12" cy="9" r="3.5"/><path d="M5 20c.8-3.6 3.6-5.5 7-5.5s6.2 1.9 7 5.5"/>');
  static const share = YIconData('<path d="M12 15V4m0 0L8 8m4-4 4 4M6 12v7h12v-7"/>');
  static const heart = YIconData('<path d="M12 20s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.2 4.3 4.3 0 0 1 19.5 10c0 5.4-7.5 10-7.5 10z"/>', stroke: false);
  static const heartOutline = YIconData('<path d="M12 20s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.2 4.3 4.3 0 0 1 19.5 10c0 5.4-7.5 10-7.5 10z"/>');
  static const send = YIconData('<path d="M5 12 19 5l-4 14-3-6z"/>');
  static const clock = YIconData('<circle cx="12" cy="12" r="8"/><path d="M12 7.5V12l3 2"/>');
  static const timer = YIconData('<circle cx="12" cy="12" r="8"/><path d="M12 8v4l3 2"/>');
  static const download = YIconData('<path d="M12 4v11m0 0-4-4m4 4 4-4M5 20h14"/>');
  static const bell = YIconData('<path d="M6 17v-6a6 6 0 0 1 12 0v6l1.5 2h-15zM10 21h4"/>');
  static const lock = YIconData('<rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>');
  static const radio = YIconData(
    '<circle cx="12" cy="12" r="2"/><path d="M8 8a5.5 5.5 0 0 0 0 8M16 8a5.5 5.5 0 0 1 0 8M5 5a9.5 9.5 0 0 0 0 14M19 5a9.5 9.5 0 0 1 0 14"/>',
  );
  static const sliders = YIconData('<path d="M4 7h9M19 7h1M4 17h1M11 17h9"/><circle cx="16" cy="7" r="2.5"/><circle cx="8" cy="17" r="2.5"/>', join: false);
  static const shuffle = YIconData(
    '<path d="M4 7h3.5c5 0 5 10 10 10H20M4 17h3.5c1.6 0 2.7-.7 3.6-1.8M20 7h-2.5c-1.6 0-2.7.7-3.6 1.8"/>'
    '<path d="m17.5 14.5 2.5 2.5-2.5 2.5M17.5 4.5 20 7l-2.5 2.5"/>',
  );
  static const repeat = YIconData(
    '<path d="M5 11V9.5A2.5 2.5 0 0 1 7.5 7H19M19 7l-2.5-2.5M19 7l-2.5 2.5M19 13v1.5a2.5 2.5 0 0 1-2.5 2.5H5M5 17l2.5-2.5M5 17l2.5 2.5"/>',
  );
  static const repeatOne = YIconData(
    '<path d="M5 11V9.5A2.5 2.5 0 0 1 7.5 7H19M19 7l-2.5-2.5M19 7l-2.5 2.5M19 13v1.5a2.5 2.5 0 0 1-2.5 2.5H5M5 17l2.5-2.5M5 17l2.5 2.5"/>'
    '<path d="M11.2 10.6 12.4 10v4"/>',
  );
  static const lyrics = YIconData('<path d="M5 7h10M5 12h14M5 17h8"/>');
  static const queue = YIconData('<path d="M4 7h12M4 12h12M4 17h7M19 14v5M16.5 16.5 19 14l2.5 2.5"/>');
  static const volume = YIconData('<path d="M5 10v4h3l4 3V7l-4 3z"/><path d="M16 9a4 4 0 0 1 0 6"/>');
  static const volumeMute = YIconData('<path d="M5 10v4h3l4 3V7l-4 3z"/><path d="m16 10 4 4M20 10l-4 4"/>');
  static const comment = YIconData('<path d="M5 6h14v10h-8.5L6 19v-3H5z"/>');
  static const trash = YIconData('<path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12M10 11v5M14 11v5"/>');
  static const trashSimple = YIconData('<path d="M5 7h14M10 7V5h4v2M7 7l1 12h8l1-12"/>');
  static const drag = YIconData('<path d="M5 9h14M5 15h14"/>');
  static const close = YIconData('<path d="m7 7 10 10M17 7 7 17"/>', strokeWidth: 3);
  static const check = YIconData('<path d="m5 12.5 4.5 4.5L19 7"/>', strokeWidth: 2);
  static const bookmark = YIconData('<path d="M6 4h12v16l-6-4-6 4z"/>');
  static const equalizer = YIconData('<path d="M4 12h2M8 8v8M12 5v14M16 8v8M20 12h-2"/>');
  static const crossfade = YIconData('<circle cx="9" cy="12" r="5"/><circle cx="15" cy="12" r="5"/>');
  static const target = YIconData('<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="2.5"/>');
  static const wifi = YIconData('<path d="M4 10a12 12 0 0 1 16 0M7 13.5a8 8 0 0 1 10 0M10 17a4 4 0 0 1 4 0"/>');
  static const wifiOff = YIconData(
    '<path d="M2.5 9a15 15 0 0 1 19 0M5.5 12.5a10 10 0 0 1 13 0M8.8 16a5 5 0 0 1 6.4 0M4 4l16 16"/>'
    '<circle cx="12" cy="19.5" r="1" fill="currentColor"/>',
  );
  static const refresh = YIconData('<path d="M19 12a7 7 0 1 1-2.1-5M19 5v4.5h-4.5"/>');
  static const sparkle = YIconData('<path d="M12 4l1.8 5.2L19 11l-5.2 1.8L12 18l-1.8-5.2L5 11l5.2-1.8z"/>');
  static const shield = YIconData('<path d="M12 3l7 3v5c0 5-3 8-7 10-4-2-7-5-7-10V6z"/><path d="m9 12 2.2 2.2L15.5 10"/>');
  static const info = YIconData('<circle cx="12" cy="12" r="9"/><path d="M12 11v5"/><circle cx="12" cy="8" r="1" fill="currentColor"/>');
  static const document = YIconData('<path d="M7 3h7l4 4v14H7zM14 3v4h4M10 12h5M10 16h5"/>');
  static const code = YIconData('<path d="m9 8-4 4 4 4M15 8l4 4-4 4"/>');
  static const feedback = YIconData('<path d="M5 5h14a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1h-7l-4 4v-4H5a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z"/>');
  static const mail = YIconData('<rect x="3" y="6" width="18" height="12" rx="2"/><path d="m4 8 8 6 8-6"/>');
  static const qr = YIconData(
    '<rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/>'
    '<rect x="4" y="14" width="6" height="6" rx="1"/><path d="M14 14h2v2h-2zM18 14h2v6h-4M14 18v2"/>',
  );
  static const key = YIconData('<circle cx="8" cy="15" r="4"/><path d="m11 12 8-8M16 7l2.5 2.5"/>');
  static const source = YIconData(
    '<path d="M4 7h16M4 12h16M4 17h16"/><circle cx="8" cy="7" r="1.6" fill="currentColor"/>'
    '<circle cx="15" cy="12" r="1.6" fill="currentColor"/><circle cx="10" cy="17" r="1.6" fill="currentColor"/>',
  );
  static const folder = YIconData('<path d="M4 7a1 1 0 0 1 1-1h5l2 2h7a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1z"/>');
  static const miniMode = YIconData('<rect x="4" y="6" width="16" height="12" rx="2"/><rect x="11" y="12" width="7" height="4" rx="1"/>');
}

/// 渲染 [YIconData]，颜色默认继承 [DefaultTextStyle]/[IconTheme] 的颜色。
class YIcon extends StatelessWidget {
  const YIcon(this.icon, {super.key, this.size = 22, this.color, this.strokeWidth});

  final YIconData icon;
  final double size;
  final Color? color;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final c = color ?? IconTheme.of(context).color ?? DefaultTextStyle.of(context).style.color!;
    return SvgPicture.string(
      icon.svg(strokeWidth: strokeWidth),
      width: size,
      height: size,
      theme: SvgTheme(currentColor: c),
    );
  }
}
