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

/// 本地离线声音模型的标识（见 [LocalVoiceModels]）。
abstract final class LocalVoiceIds {
  static const huayan = 'piper-zh-huayan';
  static const xiaoya = 'piper-zh-xiaoya';
  static const chaowen = 'piper-zh-chaowen';
  static const baker = 'matcha-zh-baker';
  static const laozhe = 'vits-zh-laozhe';
}

/// 首批预设的五个音色。
///
/// 云音助手只说中文。
/// - 本地离线：每个音色都是独立的中文声音模型。
/// - CosyVoice（阿里云百炼）：cosyvoice-v2 的系统音色。
/// - ElevenLabs：官方预置音色（多语言模型说中文）。
/// - Fish Audio：没有可以预置的官方音色 ID，需要在音色中心填写你在 Fish Audio 选择或克隆的声音（reference_id）。
abstract final class VoicePresets {
  static const yunxi = VoiceProfile(
    id: 'yunxi',
    name: '云汐',
    style: '温柔知性',
    description: '温暖柔和的青年女声，语气从容，适合陪伴聊天、讲歌曲背后的故事。',
    traits: ['女声', '青年', '温暖柔和'],
    previewText: {
      VoiceLanguage.zh: '你好，我是云汐。今天想听点什么？我陪你慢慢挑。',
    },
    bindings: [
      EngineVoice('cosyvoice', {VoiceLanguage.zh: 'longxiaochun_v2'}, model: 'cosyvoice-v2'),
      EngineVoice('elevenlabs', {VoiceLanguage.zh: 'XB0fDUnXU5powFXDhCwa'}, model: 'eleven_multilingual_v2'),
      EngineVoice('fish', {}),
      EngineVoice('local', {VoiceLanguage.zh: LocalVoiceIds.huayan}),
      EngineVoice('system', {VoiceLanguage.zh: 'female'}, note: '系统朗读只区分男声 / 女声'),
    ],
  );

  static const xiaoyou = VoiceProfile(
    id: 'xiaoyou',
    name: '小柚',
    style: '元气活泼',
    description: '明亮清甜的少女声，语速轻快、带着笑意，适合推荐新歌和日常聊天。',
    traits: ['女声', '少女', '明亮清甜'],
    previewText: {
      VoiceLanguage.zh: '嗨嗨，我是小柚！今天的推荐我都替你挑好啦，要不要听听？',
    },
    bindings: [
      EngineVoice('cosyvoice', {VoiceLanguage.zh: 'longhua_v2'}, model: 'cosyvoice-v2'),
      EngineVoice('elevenlabs', {VoiceLanguage.zh: 'jBpfuIE2acCO8z3wKNLl'}, model: 'eleven_multilingual_v2'),
      EngineVoice('fish', {}),
      EngineVoice('local', {VoiceLanguage.zh: LocalVoiceIds.xiaoya}),
      EngineVoice('system', {VoiceLanguage.zh: 'female'}, note: '系统朗读只区分男声 / 女声'),
    ],
  );

  static const wanxing = VoiceProfile(
    id: 'wanxing',
    name: '晚星',
    style: '轻柔夜语',
    description: '轻柔安静的女声，像深夜电台主播，语速舒缓、停顿从容，适合夜晚与助眠。',
    traits: ['女声', '青年', '轻柔舒缓'],
    previewText: {
      VoiceLanguage.zh: '晚上好，我是晚星。夜深了，为你放一首安静的歌吧。',
    },
    bindings: [
      EngineVoice('cosyvoice', {VoiceLanguage.zh: 'longyue_v2'}, model: 'cosyvoice-v2'),
      EngineVoice('elevenlabs', {VoiceLanguage.zh: '21m00Tcm4TlvDq8ikWAM'}, model: 'eleven_multilingual_v2'),
      EngineVoice('fish', {}),
      EngineVoice('local', {VoiceLanguage.zh: LocalVoiceIds.baker}),
      EngineVoice('system', {VoiceLanguage.zh: 'female'}, note: '系统朗读只区分男声 / 女声'),
    ],
  );

  static const qingchuan = VoiceProfile(
    id: 'qingchuan',
    name: '清川',
    style: '清朗少年',
    description: '干净明亮的青年男声，咬字清楚、节奏利落，适合播报与快速操作。',
    traits: ['男声', '青年', '干净明亮'],
    previewText: {
      VoiceLanguage.zh: '我是清川。想燃一点？交给我，节奏马上到位。',
    },
    bindings: [
      EngineVoice('cosyvoice', {VoiceLanguage.zh: 'longcheng_v2'}, model: 'cosyvoice-v2'),
      EngineVoice('elevenlabs', {VoiceLanguage.zh: 'TxGEqnHWrfWFTfGW9XjX'}, model: 'eleven_multilingual_v2'),
      EngineVoice('fish', {}),
      EngineVoice('local', {VoiceLanguage.zh: LocalVoiceIds.chaowen}),
      EngineVoice('system', {VoiceLanguage.zh: 'male'}, note: '系统朗读只区分男声 / 女声'),
    ],
  );

  static const muyan = VoiceProfile(
    id: 'muyan',
    name: '暮言',
    style: '沉稳磁性',
    description: '低沉有磁性的成熟男声，语气沉稳，适合讲解、长篇解读与夜晚聊天。',
    traits: ['男声', '成熟', '低沉磁性'],
    previewText: {
      VoiceLanguage.zh: '我是暮言。好的音乐，值得慢慢听。今晚想聊哪首歌？',
    },
    bindings: [
      EngineVoice('cosyvoice', {VoiceLanguage.zh: 'longxiaocheng_v2'}, model: 'cosyvoice-v2'),
      EngineVoice('elevenlabs', {VoiceLanguage.zh: 'nPczCjzI2devNBz1zQrb'}, model: 'eleven_multilingual_v2'),
      EngineVoice('fish', {}),
      EngineVoice('local', {VoiceLanguage.zh: LocalVoiceIds.laozhe}),
      EngineVoice('system', {VoiceLanguage.zh: 'male'}, note: '系统朗读只区分男声 / 女声'),
    ],
  );

  static const all = [yunxi, xiaoyou, wanxing, qingchuan, muyan];

  static VoiceProfile byId(String? id) => all.where((v) => v.id == id).firstOrNull ?? yunxi;
}
