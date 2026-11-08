import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_engine.dart';

/// 兼容 OpenAI 接口的大模型服务预设（用户填写自己的密钥）。
class AiProvider {
  const AiProvider(this.name, this.baseUrl, this.model, this.keyUrl);

  final String name;
  final String baseUrl;
  final String model;

  /// 申请密钥的页面。
  final String keyUrl;

  static const presets = [
    AiProvider('DeepSeek', 'https://api.deepseek.com/v1', 'deepseek-chat', 'https://platform.deepseek.com/api_keys'),
    AiProvider('通义千问', 'https://dashscope.aliyuncs.com/compatible-mode/v1', 'qwen-plus', 'https://bailian.console.aliyun.com/'),
    AiProvider('Kimi', 'https://api.moonshot.cn/v1', 'moonshot-v1-8k', 'https://platform.moonshot.cn/console/api-keys'),
    AiProvider('智谱 GLM', 'https://open.bigmodel.cn/api/paas/v4', 'glm-4-flash', 'https://open.bigmodel.cn/usercenter/apikeys'),
    AiProvider('OpenAI', 'https://api.openai.com/v1', 'gpt-4o-mini', 'https://platform.openai.com/api-keys'),
  ];
}

/// 云音助手的设置（单独保存，不放进 [AppSettings]）。
class AssistantSettings extends ChangeNotifier {
  late SharedPreferences _p;

  /// 语音唤醒（说“你好云音”）：打开后在后台常驻监听，Android 显示常驻通知。
  bool voiceWake = false;

  /// 用语音播报助手的回答。
  bool speakReplies = true;

  /// 大模型接口（兼容 OpenAI 的 /chat/completions）。
  String baseUrl = AiProvider.presets.first.baseUrl;
  String model = AiProvider.presets.first.model;

  /// 用户自己的密钥，只保存在本机，只发送给上面的接口地址。
  String apiKey = '';

  /// 语音识别模型。
  AsrModel asrModel = AsrModel.senseVoice;

  /// 自定义唤醒词（为空时使用默认的“你好云音”）。
  String wakeWord = '';

  /// 自定义唤醒词转换成的模型标记（由 [setWakeWord] 生成），为空时使用默认唤醒词。
  List<String> get wakeWordTokens => _wakeTokens.isEmpty ? kWakeWords : [_wakeTokens, ...kWakeWords.take(1)];
  String _wakeTokens = '';

  /// 桌宠（为空表示关闭）：团团、星月或阿曜（见 PetKind），在桌面上显示并可以点按说话。
  String pet = '';

  /// 桌宠大小：0 小、1 中、2 大。
  int petSize = 1;

  /// 桌宠本身的高度（逻辑像素）。
  double get petHeight => const [104.0, 132.0, 164.0][petSize.clamp(0, 2)];

  bool get llmConfigured => apiKey.trim().isNotEmpty && baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    voiceWake = _p.getBool('assistant.voiceWake') ?? false;
    speakReplies = _p.getBool('assistant.speak') ?? true;
    baseUrl = _p.getString('assistant.baseUrl') ?? baseUrl;
    model = _p.getString('assistant.model') ?? model;
    apiKey = _p.getString('assistant.apiKey') ?? '';
    asrModel = AsrModel.values.asNameMap()[_p.getString('assistant.asr')] ?? AsrModel.senseVoice;
    wakeWord = _p.getString('assistant.wakeWord') ?? '';
    _wakeTokens = _p.getString('assistant.wakeTokens') ?? '';
    pet = _p.getString('assistant.pet') ?? '';
    petSize = _p.getInt('assistant.petSize') ?? 1;
  }

  void setPet(String v) {
    pet = v;
    _p.setString('assistant.pet', v);
    notifyListeners();
  }

  void setPetSize(int v) {
    petSize = v.clamp(0, 2);
    _p.setInt('assistant.petSize', petSize);
    notifyListeners();
  }

  void setAsrModel(AsrModel m) {
    asrModel = m;
    _p.setString('assistant.asr', m.name);
    notifyListeners();
  }

  /// 设置自定义唤醒词：[tokens] 为拼音标记（见 [wakeWordToTokens]），为空表示恢复默认。
  void setWakeWord(String word, String tokens) {
    wakeWord = word;
    _wakeTokens = tokens;
    _p.setString('assistant.wakeWord', word);
    _p.setString('assistant.wakeTokens', tokens);
    notifyListeners();
  }

  void setVoiceWake(bool v) {
    voiceWake = v;
    _p.setBool('assistant.voiceWake', v);
    notifyListeners();
  }

  void setSpeakReplies(bool v) {
    speakReplies = v;
    _p.setBool('assistant.speak', v);
    notifyListeners();
  }

  void setLlm({String? baseUrl, String? model, String? apiKey}) {
    if (baseUrl != null) {
      this.baseUrl = baseUrl.trim();
      _p.setString('assistant.baseUrl', this.baseUrl);
    }
    if (model != null) {
      this.model = model.trim();
      _p.setString('assistant.model', this.model);
    }
    if (apiKey != null) {
      this.apiKey = apiKey.trim();
      _p.setString('assistant.apiKey', this.apiKey);
    }
    notifyListeners();
  }
}
