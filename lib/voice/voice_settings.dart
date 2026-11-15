import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_library.dart';

/// 助手声音的设置（持久化在 SharedPreferences）。
///
/// 只用系统自带的语音引擎：此前的云端引擎（CosyVoice、ElevenLabs、Fish Audio）与它们的密钥、
/// 代理地址、声音 ID 设置已经去掉。
class VoiceSettings extends ChangeNotifier {
  SharedPreferences? _p;

  /// 当前的声音：female / male（按音高自动选系统声音），或者 sys:系统声音名称（指定某一个系统声音）。
  String voiceId = 'female';

  /// 按聊天内容自动调整情绪、语速与停顿。
  bool expressive = true;

  /// 基础语速倍数。
  double rate = 1;

  Future<void> init() async {
    final p = _p = await SharedPreferences.getInstance();
    final saved = p.getString('voice.id') ?? voiceId;
    // 旧版本的五个音色 ID 按性别换成女声或男声；指定的系统声音原样保留。
    voiceId = saved.startsWith(VoicePresets.systemPrefix) ? saved : VoicePresets.byId(saved).id;
    expressive = p.getBool('voice.expressive') ?? expressive;
    rate = (p.getDouble('voice.rate') ?? rate).clamp(0.6, 1.6).toDouble();
    // 去掉云端引擎时留下的密钥等设置。
    for (final k in const ['voice.engine', 'voice.engines', 'voice.overrides']) {
      if (p.containsKey(k)) await p.remove(k);
    }
  }

  void setVoice(String id) {
    voiceId = id;
    _p?.setString('voice.id', id);
    notifyListeners();
  }

  void setExpressive(bool v) {
    expressive = v;
    _p?.setBool('voice.expressive', v);
    notifyListeners();
  }

  void setRate(double v) {
    rate = v.clamp(0.6, 1.6).toDouble();
    _p?.setDouble('voice.rate', rate);
    notifyListeners();
  }
}
