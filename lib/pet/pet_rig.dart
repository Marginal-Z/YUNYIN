import 'dart:ui';

/// 桌宠的嘴型风格：团团是“ω”小猫嘴，另外两个是二次元的小嘴。
enum MouthStyle { cat, anime }

/// 一只眼睛在原图中的位置（像素）：椭圆中心与半径。眨眼、闭眼与笑眼都画在这个范围内。
class EyeRig {
  const EyeRig(this.cx, this.cy, this.rx, this.ry);

  final double cx, cy, rx, ry;
  Offset get center => Offset(cx, cy);
}

/// 桌宠的“骨架”：原图与五官的位置和颜色。表情由画笔在原图上绘制（眼皮、嘴型、腮红），
/// 不需要每个表情单独一张图。
class PetRig {
  const PetRig({
    required this.asset,
    required this.width,
    required this.height,
    required this.eyes,
    required this.skin,
    required this.line,
    required this.mouth,
    required this.mouthWidth,
    required this.mouthPatch,
    required this.mouthStyle,
    required this.blush,
    required this.head,
    required this.sweat,
  });

  final String asset;

  /// 原图尺寸（像素）。
  final double width, height;
  final List<EyeRig> eyes;

  /// 眼睛周围的皮肤颜色（眼皮）与线条颜色（睫毛、嘴的轮廓）。
  final Color skin, line;

  /// 嘴的中心、宽度，以及盖住原图嘴巴所需的皮肤色椭圆大小。
  final Offset mouth;
  final double mouthWidth;
  final Size mouthPatch;
  final MouthStyle mouthStyle;

  /// 两侧腮红（椭圆所在的矩形）。
  final List<Rect> blush;

  /// 头顶附近：音符、爱心、“Zzz”等特效从这里飘出。
  final Offset head;

  /// 尴尬 / 出错时的汗滴位置。
  final Offset sweat;
}

/// 三只桌宠：团团（可爱）、星月（美丽）、阿曜（帅气），各自使用一个音色。
enum PetKind {
  tuantuan('团团', '可爱', '软软的音乐云朵，戴着粉色耳机', 'xiaoyou', Color(0xFFFF6F91)),
  xingyue('星月', '美丽', '温柔的月光少女，说话轻轻的', 'wanxing', Color(0xFF8B7CF6)),
  ayao('阿曜', '帅气', '元气满满的少年，随时待命', 'qingchuan', Color(0xFF3B82F6));

  const PetKind(this.label, this.style, this.description, this.voiceId, this.color);

  final String label;
  final String style;
  final String description;

  /// 对应的音色（见 VoicePresets）。
  final String voiceId;

  /// 特效与气泡使用的主题色。
  final Color color;

  static PetKind? byName(String? name) => PetKind.values.asNameMap()[name];

  PetRig get rig => switch (this) {
    PetKind.tuantuan => const PetRig(
      asset: 'assets/pets/tuantuan.png',
      width: 560,
      height: 529,
      eyes: [EyeRig(174.5, 322.5, 27, 31), EyeRig(309, 333, 28, 33)],
      skin: Color(0xFFFAF8FB),
      line: Color(0xFF443D64),
      mouth: Offset(235, 362),
      mouthWidth: 46,
      mouthPatch: Size(62, 48),
      mouthStyle: MouthStyle.cat,
      blush: [Rect.fromLTWH(98, 340, 56, 38), Rect.fromLTWH(320, 357, 64, 40)],
      head: Offset(300, 150),
      sweat: Offset(425, 245),
    ),
    PetKind.xingyue => const PetRig(
      asset: 'assets/pets/xingyue.png',
      width: 555,
      height: 642,
      eyes: [EyeRig(203, 268, 40, 29), EyeRig(338, 240, 38, 33)],
      skin: Color(0xFFFEF3EC),
      line: Color(0xFF3A2F55),
      mouth: Offset(287, 309),
      mouthWidth: 22,
      mouthPatch: Size(28, 24),
      mouthStyle: MouthStyle.anime,
      blush: [Rect.fromLTWH(192, 300, 40, 16), Rect.fromLTWH(340, 270, 28, 14)],
      head: Offset(280, 70),
      sweat: Offset(400, 175),
    ),
    PetKind.ayao => const PetRig(
      asset: 'assets/pets/ayao.png',
      width: 481,
      height: 640,
      eyes: [EyeRig(180, 244, 38, 29), EyeRig(298, 221, 28, 30)],
      skin: Color(0xFFFEF2EA),
      line: Color(0xFF282A44),
      mouth: Offset(252, 283),
      mouthWidth: 30,
      mouthPatch: Size(42, 32),
      mouthStyle: MouthStyle.anime,
      blush: [Rect.fromLTWH(168, 274, 34, 14), Rect.fromLTWH(300, 245, 30, 12)],
      head: Offset(240, 60),
      sweat: Offset(360, 150),
    ),
  };
}

/// 桌宠此刻的状态（决定表情与动作）。
enum PetMood {
  idle('待机'),
  listening('倾听'),
  thinking('思考'),
  speaking('说话'),
  happy('开心'),
  dancing('跟着音乐摇摆'),
  sleepy('打瞌睡'),
  sad('委屈'),
  dragged('被拎起来');

  const PetMood(this.label);

  final String label;

  static PetMood byName(String? name) => PetMood.values.asNameMap()[name] ?? PetMood.idle;
}
