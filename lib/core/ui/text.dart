import 'package:flutter/widgets.dart';

/// 字体栈：-apple-system, SF Pro, Inter, PingFang SC, Noto Sans SC。
const String kFontFamily = 'Inter';
const List<String> kFontFallback = [
  'PingFang SC',
  'Noto Sans SC',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'sans-serif',
];

/// 按设计稿参数构造文字样式：字号 / 字重 / 字距(em) / 行高。
TextStyle ts(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color? color,
  double em = 0,
  double? height,
  bool tabular = false,
}) {
  return TextStyle(
    fontFamily: kFontFamily,
    fontFamilyFallback: kFontFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: em == 0 ? null : em * size,
    height: height,
    leadingDistribution: TextLeadingDistribution.even,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

const FontWeight w400 = FontWeight.w400;
const FontWeight w500 = FontWeight.w500;
const FontWeight w600 = FontWeight.w600;
const FontWeight w700 = FontWeight.w700;
