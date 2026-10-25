import 'package:flutter/material.dart';

/// 设计稿中的主题色（设置 → 外观 → 主题色）。
enum AccentColor {
  red('朱红', Color(0xFFDC1031), Color(0xFFFF5C75), Color(0xFFF2415B), Color(0xFFFF5A73)),
  blue('蓝', Color(0xFF2F7DE1), Color(0xFF7FB4FF), Color(0xFF4F95F0), Color(0xFF62A6FF)),
  teal('青绿', Color(0xFF14917F), Color(0xFF5ED6C0), Color(0xFF2AAE99), Color(0xFF3FCDB5)),
  orange('橙', Color(0xFFD9680A), Color(0xFFFFA346), Color(0xFFEE8526), Color(0xFFFFA346)),
  graphite('石墨', Color(0xFF636366), Color(0xFFC7C7CC), Color(0xFF7C7C80), Color(0xFF9A9AA0));

  const AccentColor(this.label, this.base, this.darkText, this.buttonTop, this.tileTop);

  final String label;

  /// 主色（浅色模式文字 / 填充渐变底色）。
  final Color base;

  /// 深色模式下提亮的强调文字色。
  final Color darkText;

  /// 主按钮渐变顶部色（#F2415B → #DC1031）。
  final Color buttonTop;

  /// 图标块渐变顶部色（#FF5A73 → #DC1031）。
  final Color tileTop;
}

/// 一组 CSS 风格的阴影参数，`blur` 与 CSS 的 blur 半径一致。
@immutable
class Shadow2 {
  const Shadow2(this.dx, this.dy, this.blur, this.color, {this.spread = 0});

  final double dx;
  final double dy;
  final double blur;
  final double spread;
  final Color color;

  Offset get offset => Offset(dx, dy);
}

/// 设计稿 token。字段命名对应设计规范页里的语义。
@immutable
class Palette {
  const Palette({
    required this.isDark,
    required this.accent,
    required this.bg,
    required this.glows,
    required this.playerBg,
    required this.playerGlows,
    required this.text,
    required this.text2,
    required this.text3,
    required this.text4,
    required this.muted,
    required this.danger,
    required this.separator,
    required this.card,
    required this.cardShadow,
    required this.chip,
    required this.chipShadow,
    required this.chipSelected,
    required this.chipSelectedText,
    required this.glass,
    required this.glassBorder,
    required this.glassInset,
    required this.glassShadow,
    required this.glassButtonShadow,
    required this.sidebar,
    required this.sidebarShadow,
    required this.sidebarActive,
    required this.navActive,
    required this.navActiveInset,
    required this.track,
    required this.trackFill,
    required this.playerText2,
    required this.lyricDim,
    required this.lyricActive,
    required this.primaryButton,
    required this.primaryButtonText,
    required this.segmentTrack,
    required this.segmentSelected,
    required this.field,
    required this.coverShadow,
    required this.secondaryShadow,
    required this.clearButton,
    required this.sheet,
    required this.skeleton,
    required this.dialog,
    required this.translucentButton,
    required this.lyricsCard,
    required this.scrim,
    required this.swatchRingInner,
    required this.swatchRingOuter,
    required this.dailyGradient,
    required this.dailyLabelBg,
    required this.dailyLabel,
    required this.dailyDesc,
    required this.highlightInset,
    required this.albumGradient,
    required this.albumLabel,
    required this.albumDesc,
    required this.artistGradient,
    required this.tagHot,
    required this.tagHotText,
    required this.tagNew,
    required this.tagNewText,
    required this.tagUp,
    required this.tagUpText,
    required this.tagPlain,
    required this.tagPlainText,
    required this.buttonInsetHighlight,
  });

  final bool isDark;
  final AccentColor accent;

  final Color bg;
  final List<Glow> glows;
  final Color playerBg;
  final List<Glow> playerGlows;

  final Color text;
  final Color text2;
  final Color text3;
  final Color text4;
  final Color muted;
  final Color danger;
  final Color separator;

  final Color card;
  final List<Shadow2> cardShadow;
  final Color chip;
  final List<Shadow2> chipShadow;
  final Color chipSelected;
  final Color chipSelectedText;

  final Color glass;
  final Color glassBorder;
  final List<Shadow2> glassInset;
  final List<Shadow2> glassShadow;
  final List<Shadow2> glassButtonShadow;
  final Color sidebar;
  final List<Shadow2> sidebarShadow;
  final Color sidebarActive;
  final Color navActive;
  final Color navActiveInset;

  final Color track;
  final Color trackFill;
  final Color playerText2;
  final Color lyricDim;
  final Color lyricActive;
  final Color primaryButton;
  final Color primaryButtonText;

  final Color segmentTrack;
  final Color segmentSelected;
  final Color field;
  final List<Shadow2> coverShadow;
  final List<Shadow2> secondaryShadow;
  final Color clearButton;
  final Color sheet;
  final Color skeleton;
  final Color dialog;
  final Color translucentButton;
  final Color lyricsCard;
  final Color scrim;
  final Color swatchRingInner;
  final Color swatchRingOuter;

  final List<Color> dailyGradient;
  final Color dailyLabelBg;
  final Color dailyLabel;
  final Color dailyDesc;
  final Color highlightInset;
  final List<Color> albumGradient;
  final Color albumLabel;
  final Color albumDesc;
  final List<Color> artistGradient;

  final Color tagHot;
  final Color tagHotText;
  final Color tagNew;
  final Color tagNewText;
  final Color tagUp;
  final Color tagUpText;
  final Color tagPlain;
  final Color tagPlainText;
  final Color buttonInsetHighlight;

  static Palette of(BuildContext context) => PaletteScope.of(context);

  /// 播放页使用封面取色时，替换与播放页相关的颜色。
  Palette withPlayer({Color? playerBg, List<Glow>? playerGlows, Color? playerText2, Color? lyricDim, Color? lyricActive}) => Palette(
    isDark: isDark,
    accent: accent,
    bg: bg,
    glows: glows,
    playerBg: playerBg ?? this.playerBg,
    playerGlows: playerGlows ?? this.playerGlows,
    text: text,
    text2: text2,
    text3: text3,
    text4: text4,
    muted: muted,
    danger: danger,
    separator: separator,
    card: card,
    cardShadow: cardShadow,
    chip: chip,
    chipShadow: chipShadow,
    chipSelected: chipSelected,
    chipSelectedText: chipSelectedText,
    glass: glass,
    glassBorder: glassBorder,
    glassInset: glassInset,
    glassShadow: glassShadow,
    glassButtonShadow: glassButtonShadow,
    sidebar: sidebar,
    sidebarShadow: sidebarShadow,
    sidebarActive: sidebarActive,
    navActive: navActive,
    navActiveInset: navActiveInset,
    track: track,
    trackFill: trackFill,
    playerText2: playerText2 ?? this.playerText2,
    lyricDim: lyricDim ?? this.lyricDim,
    lyricActive: lyricActive ?? this.lyricActive,
    primaryButton: primaryButton,
    primaryButtonText: primaryButtonText,
    segmentTrack: segmentTrack,
    segmentSelected: segmentSelected,
    field: field,
    coverShadow: coverShadow,
    secondaryShadow: secondaryShadow,
    clearButton: clearButton,
    sheet: sheet,
    skeleton: skeleton,
    dialog: dialog,
    translucentButton: translucentButton,
    lyricsCard: lyricsCard,
    scrim: scrim,
    swatchRingInner: swatchRingInner,
    swatchRingOuter: swatchRingOuter,
    dailyGradient: dailyGradient,
    dailyLabelBg: dailyLabelBg,
    dailyLabel: dailyLabel,
    dailyDesc: dailyDesc,
    highlightInset: highlightInset,
    albumGradient: albumGradient,
    albumLabel: albumLabel,
    albumDesc: albumDesc,
    artistGradient: artistGradient,
    tagHot: tagHot,
    tagHotText: tagHotText,
    tagNew: tagNew,
    tagNewText: tagNewText,
    tagUp: tagUp,
    tagUpText: tagUpText,
    tagPlain: tagPlain,
    tagPlainText: tagPlainText,
    buttonInsetHighlight: buttonInsetHighlight,
  );

  /// 强调文字色（链接、激活态）。深色下使用提亮色。
  Color get accentText => isDark ? accent.darkText : accent.base;

  /// 主按钮的红色渐变。深浅色一致。
  List<Color> get buttonGradient => [accent.buttonTop, accent.base];

  /// 主按钮的辉光阴影。
  List<Shadow2> get buttonShadow => [Shadow2(0, 10, 22, accent.base.withValues(alpha: 0.32))];

  factory Palette.light(AccentColor accent) => Palette(
    isDark: false,
    accent: accent,
    bg: const Color(0xFFF5F7FC),
    glows: const [
      Glow(0, 0, 380, 300, Color.fromRGBO(96, 165, 255, 0.28)),
      Glow(1, 0.04, 340, 300, Color.fromRGBO(255, 170, 140, 0.28)),
      Glow(0.55, 1, 420, 360, Color.fromRGBO(120, 214, 190, 0.2)),
    ],
    playerBg: const Color(0xFFE7F5F1),
    playerGlows: const [
      Glow(0.08, 0, 380, 320, Color.fromRGBO(70, 200, 170, 0.38)),
      Glow(1, 0.08, 340, 300, Color.fromRGBO(255, 214, 110, 0.34)),
      Glow(0.5, 1, 420, 380, Color.fromRGBO(120, 190, 255, 0.22)),
    ],
    text: const Color(0xFF1D1D1F),
    text2: const Color(0xFF6E6E73),
    text3: const Color(0xFF3C3C43),
    text4: const Color(0xFF48484A),
    muted: const Color(0xFF8E8E93),
    danger: const Color(0xFFC40F2D),
    separator: const Color.fromRGBO(60, 60, 67, 0.12),
    card: Colors.white,
    cardShadow: const [Shadow2(0, 14, 34, Color.fromRGBO(28, 44, 92, 0.07)), Shadow2(0, 1, 3, Color.fromRGBO(28, 44, 92, 0.05))],
    chip: Colors.white,
    chipShadow: const [Shadow2(0, 6, 14, Color.fromRGBO(28, 44, 92, 0.07)), Shadow2(0, 0, 0, Color.fromRGBO(255, 255, 255, 0.9), spread: 1)],
    chipSelected: const Color(0xFF1D1D1F),
    chipSelectedText: Colors.white,
    glass: const Color.fromRGBO(255, 255, 255, 0.6),
    glassBorder: const Color.fromRGBO(255, 255, 255, 0.7),
    glassInset: const [
      Shadow2(0, 1, 1, Color.fromRGBO(255, 255, 255, 0.95)),
      Shadow2(0, -1, 1, Color.fromRGBO(0, 0, 0, 0.04)),
      Shadow2(0, 0, 14, Color.fromRGBO(255, 255, 255, 0.35)),
    ],
    glassShadow: const [Shadow2(0, 10, 30, Color.fromRGBO(0, 0, 0, 0.14)), Shadow2(0, 1, 3, Color.fromRGBO(0, 0, 0, 0.08))],
    glassButtonShadow: const [Shadow2(0, 6, 18, Color.fromRGBO(0, 0, 0, 0.1)), Shadow2(0, 1, 3, Color.fromRGBO(0, 0, 0, 0.08))],
    sidebar: const Color.fromRGBO(255, 255, 255, 0.72),
    sidebarShadow: const [Shadow2(0, 10, 30, Color.fromRGBO(0, 0, 0, 0.1)), Shadow2(0, 1, 3, Color.fromRGBO(0, 0, 0, 0.06))],
    sidebarActive: const Color.fromRGBO(120, 120, 128, 0.16),
    navActive: const Color.fromRGBO(120, 120, 128, 0.18),
    navActiveInset: const Color.fromRGBO(255, 255, 255, 0.7),
    track: const Color.fromRGBO(0, 0, 0, 0.14),
    trackFill: const Color(0xFF1D1D1F),
    playerText2: const Color(0xFF3F5F58),
    lyricDim: const Color(0xFF4F6F68),
    lyricActive: const Color(0xFF0F1413),
    primaryButton: const Color(0xFF1D1D1F),
    primaryButtonText: Colors.white,
    segmentTrack: const Color.fromRGBO(118, 118, 128, 0.12),
    segmentSelected: Colors.white,
    field: const Color(0xFFF1F2F7),
    coverShadow: const [Shadow2(0, 10, 24, Color.fromRGBO(28, 44, 92, 0.16))],
    secondaryShadow: const [Shadow2(0, 8, 18, Color.fromRGBO(28, 44, 92, 0.09))],
    clearButton: const Color.fromRGBO(60, 60, 67, 0.3),
    sheet: Colors.white,
    skeleton: const Color(0xFFE9EBF2),
    dialog: const Color.fromRGBO(255, 255, 255, 0.86),
    translucentButton: const Color.fromRGBO(255, 255, 255, 0.7),
    lyricsCard: const Color.fromRGBO(255, 255, 255, 0.72),
    scrim: const Color.fromRGBO(15, 24, 22, 0.34),
    swatchRingInner: Colors.white,
    swatchRingOuter: const Color(0xFF1D1D1F),
    dailyGradient: const [Color(0xFFFFF2EC), Color(0xFFFFD6CA)],
    dailyLabelBg: const Color.fromRGBO(255, 255, 255, 0.72),
    dailyLabel: const Color(0xFFB3261E),
    dailyDesc: const Color(0xFF5C4A47),
    highlightInset: const Color.fromRGBO(255, 255, 255, 0.8),
    albumGradient: const [Color(0xFFECFAF6), Color(0xFFC3EADF)],
    albumLabel: const Color(0xFF0E6B5C),
    albumDesc: const Color(0xFF2F5A53),
    artistGradient: const [Color(0xFFFFEBC9), Color(0xFFFFC8A6)],
    tagHot: const Color.fromRGBO(220, 16, 49, 0.10),
    tagHotText: const Color(0xFFC40F2D),
    tagNew: const Color.fromRGBO(47, 125, 225, 0.12),
    tagNewText: const Color(0xFF1F66C7),
    tagUp: const Color.fromRGBO(20, 145, 127, 0.12),
    tagUpText: const Color(0xFF0E7A6A),
    tagPlain: const Color(0xFFEEEEF2),
    tagPlainText: const Color(0xFF48484A),
    buttonInsetHighlight: const Color.fromRGBO(255, 255, 255, 0.35),
  );

  factory Palette.dark(AccentColor accent) => Palette(
    isDark: true,
    accent: accent,
    bg: const Color(0xFF0B0C10),
    glows: const [
      Glow(0, 0, 380, 300, Color.fromRGBO(60, 120, 230, 0.34)),
      Glow(1, 0.04, 340, 300, Color.fromRGBO(255, 110, 90, 0.2)),
      Glow(0.55, 1, 420, 360, Color.fromRGBO(40, 170, 150, 0.2)),
    ],
    playerBg: const Color(0xFF08130F),
    playerGlows: const [
      Glow(0.08, 0, 380, 320, Color.fromRGBO(40, 190, 160, 0.36)),
      Glow(1, 0.08, 340, 300, Color.fromRGBO(255, 190, 80, 0.16)),
      Glow(0.5, 1, 420, 380, Color.fromRGBO(60, 120, 230, 0.22)),
    ],
    text: const Color(0xFFF5F5F7),
    text2: const Color(0xFFA1A1A6),
    text3: const Color(0xFFD1D1D6),
    text4: const Color(0xFFC7C7CC),
    muted: const Color(0xFF8E8E93),
    danger: const Color(0xFFFF8A9B),
    separator: const Color.fromRGBO(255, 255, 255, 0.10),
    card: const Color.fromRGBO(255, 255, 255, 0.08),
    cardShadow: const [Shadow2(0, 14, 34, Color.fromRGBO(0, 0, 0, 0.38))],
    chip: const Color.fromRGBO(255, 255, 255, 0.08),
    chipShadow: const [Shadow2(0, 6, 14, Color.fromRGBO(0, 0, 0, 0.3))],
    chipSelected: const Color(0xFFF5F5F7),
    chipSelectedText: const Color(0xFF1D1D1F),
    glass: const Color.fromRGBO(48, 48, 54, 0.55),
    glassBorder: const Color.fromRGBO(255, 255, 255, 0.14),
    glassInset: const [
      Shadow2(0, 1, 1, Color.fromRGBO(255, 255, 255, 0.24)),
      Shadow2(0, -1, 1, Color.fromRGBO(0, 0, 0, 0.35)),
      Shadow2(0, 0, 14, Color.fromRGBO(255, 255, 255, 0.05)),
    ],
    glassShadow: const [Shadow2(0, 10, 30, Color.fromRGBO(0, 0, 0, 0.5)), Shadow2(0, 1, 3, Color.fromRGBO(0, 0, 0, 0.4))],
    glassButtonShadow: const [Shadow2(0, 6, 18, Color.fromRGBO(0, 0, 0, 0.4)), Shadow2(0, 1, 3, Color.fromRGBO(0, 0, 0, 0.3))],
    sidebar: const Color.fromRGBO(34, 34, 38, 0.62),
    sidebarShadow: const [Shadow2(0, 10, 30, Color.fromRGBO(0, 0, 0, 0.5)), Shadow2(0, 1, 3, Color.fromRGBO(0, 0, 0, 0.4))],
    sidebarActive: const Color.fromRGBO(255, 255, 255, 0.12),
    navActive: const Color.fromRGBO(255, 255, 255, 0.14),
    navActiveInset: const Color.fromRGBO(255, 255, 255, 0.14),
    track: const Color.fromRGBO(255, 255, 255, 0.18),
    trackFill: const Color(0xFFF5F5F7),
    playerText2: const Color(0xFFA8CFC6),
    lyricDim: const Color(0xFF8FB5AC),
    lyricActive: const Color(0xFFF2FFFC),
    primaryButton: const Color(0xFFF5F5F7),
    primaryButtonText: const Color(0xFF1D1D1F),
    segmentTrack: const Color.fromRGBO(118, 118, 128, 0.28),
    segmentSelected: const Color(0xFF636366),
    field: const Color.fromRGBO(255, 255, 255, 0.08),
    coverShadow: const [Shadow2(0, 10, 24, Color.fromRGBO(0, 0, 0, 0.45))],
    secondaryShadow: const [Shadow2(0, 8, 18, Color.fromRGBO(0, 0, 0, 0.3))],
    clearButton: const Color.fromRGBO(235, 235, 245, 0.3),
    sheet: const Color(0xFF1C1D21),
    skeleton: const Color.fromRGBO(255, 255, 255, 0.08),
    dialog: const Color.fromRGBO(44, 44, 48, 0.9),
    translucentButton: const Color.fromRGBO(255, 255, 255, 0.14),
    lyricsCard: const Color.fromRGBO(255, 255, 255, 0.10),
    scrim: const Color.fromRGBO(15, 24, 22, 0.34),
    swatchRingInner: const Color(0xFF1C1C1E),
    swatchRingOuter: const Color(0xFFF5F5F7),
    dailyGradient: const [Color(0xFF5E2C27), Color(0xFF3B1D1D)],
    dailyLabelBg: const Color.fromRGBO(255, 255, 255, 0.14),
    dailyLabel: const Color(0xFFFFB4A8),
    dailyDesc: const Color(0xFFFFD9D0),
    highlightInset: const Color.fromRGBO(255, 255, 255, 0.14),
    albumGradient: const [Color(0xFF1B4A42), Color(0xFF12302F)],
    albumLabel: const Color(0xFF7FE0CC),
    albumDesc: const Color(0xFFBDEBE0),
    artistGradient: const [Color(0xFF5A4224), Color(0xFF3E2A22)],
    tagHot: const Color.fromRGBO(220, 16, 49, 0.22),
    tagHotText: const Color(0xFFFF8A9B),
    tagNew: const Color.fromRGBO(47, 125, 225, 0.22),
    tagNewText: const Color(0xFF7FB4FF),
    tagUp: const Color.fromRGBO(20, 145, 127, 0.22),
    tagUpText: const Color(0xFF5ED6C0),
    tagPlain: const Color.fromRGBO(255, 255, 255, 0.10),
    tagPlainText: const Color(0xFFC7C7CC),
    buttonInsetHighlight: const Color.fromRGBO(255, 255, 255, 0.05),
  );

  /// 卡片的内描边（深色模式：inset 0 0 0 1px rgba(255,255,255,0.07)）。
  List<Shadow2> get cardInset => isDark ? const [Shadow2(0, 0, 0, Color.fromRGBO(255, 255, 255, 0.07), spread: 1)] : const [];

  /// 胶囊/圆形白色按钮的内描边（深色模式）。
  List<Shadow2> get chipInset => isDark ? const [Shadow2(0, 0, 0, Color.fromRGBO(255, 255, 255, 0.08), spread: 1)] : const [];

  /// 玻璃小按钮（44px 圆）的内阴影：没有 14px 的内发光。
  List<Shadow2> get glassButtonInset => glassInset.take(2).toList();
}

/// 背景光晕：CSS `radial-gradient(rx ry at cx cy, color, transparent 72%)`。
@immutable
class Glow {
  const Glow(this.cx, this.cy, this.rx, this.ry, this.color);

  /// 圆心位置（相对容器宽高的比例）。
  final double cx;
  final double cy;
  final double rx;
  final double ry;
  final Color color;

  Glow scaled(double s) => Glow(cx, cy, rx * s, ry * s, color);
}

/// 图标块的五种渐变（设计规范：品牌红 / 蓝 / 青绿 / 橙 / 石墨）。
enum TileColor {
  red(Color(0xFFFF5A73), Color(0xFFDC1031), Color.fromRGBO(220, 16, 49, 0.34)),
  blue(Color(0xFF62A6FF), Color(0xFF2F7DE1), Color.fromRGBO(47, 125, 225, 0.34)),
  teal(Color(0xFF3FCDB5), Color(0xFF14917F), Color.fromRGBO(20, 145, 127, 0.34)),
  orange(Color(0xFFFFA346), Color(0xFFD9680A), Color.fromRGBO(232, 115, 10, 0.34)),
  graphite(Color(0xFF9A9AA0), Color(0xFF636366), Color.fromRGBO(99, 99, 102, 0.34));

  const TileColor(this.top, this.bottom, this.glow);

  final Color top;
  final Color bottom;
  final Color glow;

  /// 扁平图标块使用的纯色（渐变两端之间偏深的一点）。
  Color get flat => Color.lerp(top, bottom, 0.6)!;
}

/// 向下提供当前的 [Palette]。
class PaletteScope extends InheritedWidget {
  const PaletteScope({super.key, required this.palette, required super.child});

  final Palette palette;

  static Palette of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PaletteScope>()!.palette;

  @override
  bool updateShouldNotify(PaletteScope old) => old.palette != palette;
}
