import 'tts_types.dart';

/// 音色库中的一个音色：名称、风格、描述、声音特征、支持的语言，以及在各个引擎上对应的真实声音
/// （不同的声音模型、供应商音色 ID）。同一个音色在不同引擎上声音不完全相同，但都是同一类气质的独立声音，
/// 绝不通过改变同一个声音的音调或语速来“冒充”另一个音色。
class VoiceProfile {
  const VoiceProfile({
    required this.id,
    required this.name,
    required this.style,
    required this.description,
    required this.traits,
    required this.bindings,
    this.previewText = const {},
  });

  final String id;
  final String name;

  /// 一两个词的风格标签。
  final String style;
  final String description;

  /// 声音特征（性别、年龄感、音色）。
  final List<String> traits;

  /// 各引擎上的声音，按推荐顺序排列。
  final List<EngineVoice> bindings;

  /// 试听文本。
  final Map<VoiceLanguage, String> previewText;

  /// 至少有一个引擎支持的语言。
  Set<VoiceLanguage> get languages => {for (final b in bindings) ...b.voices.keys};

  EngineVoice? binding(String engine) => bindings.where((b) => b.engine == engine).firstOrNull;

  String preview(VoiceLanguage lang) => previewText[lang] ?? previewText[VoiceLanguage.zh] ?? '你好，我是$name。';
}

/// 云音助手的声音。
///
/// 首选本机语音 MOSS-TTS-Nano（OpenMOSS 开源，Apache-2.0）：四个年轻的中文声音（灵语、悦雯、俊豪、志明），
/// 在手机上离线合成，48 kHz，需要在音色中心下载一次模型（约 720 MB，只支持 Android）。模型没有下载、设备不支持
/// （桌面端、内存不足 6 GB）或合成失败时，自动换成系统自带的语音引擎里同性别的声音。
/// 女声 / 男声：本机语音的灵语 / 俊豪，退回系统里音调最高 / 最低的中文声音；也可以指定系统里的某一个声音（`sys:声音名称`）。
///
/// 此前的五个本机开源语音音色（云汐、小柚、晚星、清川、暮言）与云端引擎都已去掉；保存过的旧音色按性别换成女声或男声。
abstract final class VoicePresets {
  static const female = VoiceProfile(
    id: 'female',
    name: '女声',
    style: '自动',
    description: '本机语音“灵语”；没有下载模型时用系统里音调最高的中文声音。',
    traits: ['女声'],
    previewText: {VoiceLanguage.zh: '你好，我是云音助手。今天想听点什么？我给你挑几首合适的歌。'},
    bindings: [
      EngineVoice('moss', {VoiceLanguage.zh: 'Lingyu'}),
      EngineVoice('system', {VoiceLanguage.zh: 'female'}),
    ],
  );

  static const male = VoiceProfile(
    id: 'male',
    name: '男声',
    style: '自动',
    description: '本机语音“俊豪”；没有下载模型时用系统里音调最低的中文声音。',
    traits: ['男声'],
    previewText: {VoiceLanguage.zh: '你好，我是云音助手。想听什么歌，直接告诉我就好。'},
    bindings: [
      EngineVoice('moss', {VoiceLanguage.zh: 'Junhao'}),
      EngineVoice('system', {VoiceLanguage.zh: 'male'}),
    ],
  );

  static const all = [female, male];

  /// 本机语音（MOSS-TTS-Nano）的四个中文声音。官方内置的其余中文声音没有收录：“说书”偏年长，“明星”是模仿某位公众人物的声音。
  static const mossPrefix = 'moss:';

  static VoiceProfile _moss(String speaker, String name, String style, String description, {required bool female}) => VoiceProfile(
    id: '$mossPrefix$speaker',
    name: name,
    style: style,
    description: description,
    traits: [female ? '女声' : '男声', '年轻'],
    previewText: const {VoiceLanguage.zh: '你好，我是云音助手。这是我的声音，想听什么歌，直接告诉我就好。'},
    bindings: [
      EngineVoice('moss', {VoiceLanguage.zh: speaker}),
      EngineVoice('system', {VoiceLanguage.zh: female ? 'female' : 'male'}),
    ],
  );

  static final moss = [
    _moss('Lingyu', '灵语', '温柔', '年轻女声，轻柔、放松，像深夜电台。', female: true),
    _moss('Yuewen', '悦雯', '活泼', '年轻女声，明快俏皮，略带台湾口音。', female: true),
    _moss('Junhao', '俊豪', '清朗', '年轻男声，标准普通话，干净明亮。', female: false),
    _moss('Zhiming', '志明', '随和', '年轻男声，京味口音，聊天感强。', female: false),
  ];

  /// 指定系统声音的 ID 前缀。
  static const systemPrefix = 'sys:';

  /// 指定的系统声音：[label] 为显示的名称（例如“女声 2”）。
  static VoiceProfile system(String name, {String? label, bool? female}) => VoiceProfile(
    id: '$systemPrefix$name',
    name: label ?? name,
    style: '系统声音',
    description: name,
    traits: [if (female != null) female ? '女声' : '男声'],
    previewText: const {VoiceLanguage.zh: '你好，我是云音助手。这是我的声音，听起来怎么样？'},
    bindings: [EngineVoice('system', {VoiceLanguage.zh: 'voice:$name'})],
  );

  /// 旧版本保存的音色 ID 按性别换成新的声音。
  static const _legacy = {'yunxi': 'female', 'xiaoyou': 'female', 'wanxing': 'female', 'qingchuan': 'male', 'muyan': 'male'};

  static VoiceProfile byId(String? id) {
    if (id != null && id.startsWith(mossPrefix)) return moss.where((v) => v.id == id).firstOrNull ?? female;
    if (id != null && id.startsWith(systemPrefix)) return system(id.substring(systemPrefix.length), label: systemLabels[id.substring(systemPrefix.length)]);
    final key = _legacy[id] ?? id;
    return all.where((v) => v.id == key).firstOrNull ?? female;
  }

  /// 系统声音的显示名称（由 SystemTtsEngine 测出音高后填写，例如“女声 1”“男声 2”）。
  static final Map<String, String> systemLabels = {};

  /// 按名称查找（语音指令“换成男声”）；也接受“女生 / 男生”与旧音色名。
  static VoiceProfile? byName(String name) {
    final n = const {'女生': '女声', '男生': '男声', '云汐': '女声', '小柚': '女声', '晚星': '女声', '清川': '男声', '暮言': '男声'}[name] ?? name;
    return [...all, ...moss].where((v) => v.name == n).firstOrNull;
  }
}
