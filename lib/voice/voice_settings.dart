import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tts_types.dart';

/// 云端引擎的接入配置：用户自己的密钥，或者自建代理地址（代理在服务器端附加密钥，客户端不保存密钥）。
/// 客户端代码中不包含任何密钥。
class EngineConfig {
  const EngineConfig({this.apiKey = '', this.proxy = '', this.model = ''});

  final String apiKey;

  /// 自建代理的地址（替换官方接口地址）。填写后可以不填密钥。
  final String proxy;

  /// 覆盖默认的合成模型（留空使用音色库中的默认模型）。
  final String model;

  bool get usable => apiKey.trim().isNotEmpty || proxy.trim().isNotEmpty;

  Map<String, String> toJson() => {'apiKey': apiKey, 'proxy': proxy, 'model': model};

  factory EngineConfig.fromJson(Map<String, dynamic> j) =>
      EngineConfig(apiKey: '${j['apiKey'] ?? ''}', proxy: '${j['proxy'] ?? ''}', model: '${j['model'] ?? ''}');

  EngineConfig copyWith({String? apiKey, String? proxy, String? model}) =>
      EngineConfig(apiKey: apiKey ?? this.apiKey, proxy: proxy ?? this.proxy, model: model ?? this.model);
}

/// 音色系统的设置（持久化在 SharedPreferences）。
class VoiceSettings extends ChangeNotifier {
  SharedPreferences? _p;

  /// 默认音色。
  String voiceId = 'yunxi';

  /// 优先使用的引擎（auto 表示按“已配置的云端引擎 → 本地离线 → 系统朗读”自动选择）。
  String preferredEngine = 'auto';

  /// 按聊天内容自动调整情绪、语速与停顿。
  bool expressive = true;

  /// 基础语速倍数。
  double rate = 1;

  /// 各云端引擎的配置。
  final Map<String, EngineConfig> engines = {};

  /// 用户为某个音色在某个引擎上填写的声音 ID（覆盖音色库中的默认值）：'音色/引擎/语言' → ID。
  final Map<String, String> overrides = {};

  Future<void> init() async {
    final p = _p = await SharedPreferences.getInstance();
    voiceId = p.getString('voice.id') ?? voiceId;
    preferredEngine = p.getString('voice.engine') ?? preferredEngine;
    expressive = p.getBool('voice.expressive') ?? expressive;
    rate = (p.getDouble('voice.rate') ?? rate).clamp(0.6, 1.6).toDouble();
    try {
      final e = jsonDecode(p.getString('voice.engines') ?? '{}') as Map<String, dynamic>;
      for (final k in e.keys) {
        engines[k] = EngineConfig.fromJson(Map<String, dynamic>.from(e[k] as Map));
      }
      overrides.addAll(Map<String, String>.from(jsonDecode(p.getString('voice.overrides') ?? '{}') as Map));
    } catch (_) {}
  }

  EngineConfig engine(String id) => engines[id] ?? const EngineConfig();

  void setVoice(String id) {
    voiceId = id;
    _p?.setString('voice.id', id);
    notifyListeners();
  }

  void setPreferredEngine(String id) {
    preferredEngine = id;
    _p?.setString('voice.engine', id);
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

  void setEngine(String id, EngineConfig config) {
    engines[id] = config;
    _p?.setString('voice.engines', jsonEncode({for (final e in engines.entries) e.key: e.value.toJson()}));
    notifyListeners();
  }

  String? override(String voice, String engine, VoiceLanguage lang) => overrides['$voice/$engine/${lang.name}'];

  void setOverride(String voice, String engine, VoiceLanguage lang, String? id) {
    final key = '$voice/$engine/${lang.name}';
    if (id == null || id.trim().isEmpty) {
      overrides.remove(key);
    } else {
      overrides[key] = id.trim();
    }
    _p?.setString('voice.overrides', jsonEncode(overrides));
    notifyListeners();
  }
}
