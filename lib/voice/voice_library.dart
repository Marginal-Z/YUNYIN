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

/// 云音助手的声音：女声与男声。
///
/// 默认使用系统自带的语音引擎（Android 为系统朗读引擎，例如三星、谷歌的中文语音；桌面端为系统语音），
/// 不需要下载模型，声音清楚自然；系统里有多个中文声音时，按实测音高选出女声与男声。
/// 在音色中心填写了云端引擎的密钥后，改用对应引擎里同性别的声音（CosyVoice、ElevenLabs、Fish Audio）。
///
/// 此前的五个音色（云汐、小柚、晚星、清川、暮言）使用本机的开源语音模型合成，听感不自然，已经去掉；
/// 保存过的旧音色按性别换成女声或男声（见 [byId]）。
abstract final class VoicePresets {
  static const female = VoiceProfile(
    id: 'female',
    name: '女声',
    style: '清楚自然',
    description: '中文女声，咬字清楚，适合日常聊天、推荐歌曲与讲解。',
    traits: ['女声'],
    previewText: {VoiceLanguage.zh: '你好，我是云音助手。今天想听点什么？我给你挑几首合适的歌。'},
    bindings: [
      EngineVoice('cosyvoice', {VoiceLanguage.zh: 'longanwen_v3'}, model: 'cosyvoice-v3-flash'),
      EngineVoice('elevenlabs', {VoiceLanguage.zh: 'XB0fDUnXU5powFXDhCwa'}, model: 'eleven_multilingual_v2'),
      EngineVoice('fish', {}),
      EngineVoice('system', {VoiceLanguage.zh: 'female'}),
    ],
  );

  static const male = VoiceProfile(
    id: 'male',
    name: '男声',
    style: '沉稳清晰',
    description: '中文男声，语气沉稳，适合播报与讲解。',
    traits: ['男声'],
    previewText: {VoiceLanguage.zh: '你好，我是云音助手。想听什么歌，直接告诉我就好。'},
    bindings: [
      EngineVoice('cosyvoice', {VoiceLanguage.zh: 'longanyang'}, model: 'cosyvoice-v3-flash'),
      EngineVoice('elevenlabs', {VoiceLanguage.zh: 'TxGEqnHWrfWFTfGW9XjX'}, model: 'eleven_multilingual_v2'),
      EngineVoice('fish', {}),
      EngineVoice('system', {VoiceLanguage.zh: 'male'}),
    ],
  );

  static const all = [female, male];

  /// 旧版本保存的音色 ID 按性别换成新的声音。
  static const _legacy = {'yunxi': 'female', 'xiaoyou': 'female', 'wanxing': 'female', 'qingchuan': 'male', 'muyan': 'male'};

  static VoiceProfile byId(String? id) {
    final key = _legacy[id] ?? id;
    return all.where((v) => v.id == key).firstOrNull ?? female;
  }

  /// 按名称查找（语音指令“换成男声”）；也接受“女生 / 男生”与旧音色名。
  static VoiceProfile? byName(String name) {
    final n = const {'女生': '女声', '男生': '男声', '云汐': '女声', '小柚': '女声', '晚星': '女声', '清川': '男声', '暮言': '男声'}[name] ?? name;
    return all.where((v) => v.name == n).firstOrNull;
  }
}
