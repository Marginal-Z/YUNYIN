import 'dart:async';

import 'package:flutter/foundation.dart';

import 'models.dart';
import 'sources/source_manager.dart';

/// 列表里没有封面的歌曲：按需向歌曲所属平台查询一次封面（洛雪曲库的榜单、部分歌单与电台节目不带封面）。
///
/// 结果保存在内存中，同一首歌只查询一次；最多同时查询 4 首，快速滚动长列表时不会一次发出上百个请求。
class CoverResolver {
  CoverResolver._();

  static final instance = CoverResolver._();

  final Map<String, String?> _done = {};
  final Map<String, Future<String?>> _pending = {};
  int _running = 0;
  final List<Completer<void>> _waiting = [];

  /// 已经查到的封面（还没查或查不到时为 null）。
  String? known(Song song) => song.coverUrl ?? _done[song.key];

  /// 是否已经查询过（查不到也算），查询过的不再重复请求。
  bool tried(Song song) => _done.containsKey(song.key);

  /// 记下取播放地址时平台一并给出的封面。
  void remember(Song song, String? cover) {
    if (cover != null && cover.isNotEmpty) _done[song.key] = cover;
  }

  Future<String?> resolve(SourceManager sources, Song song) {
    final cover = known(song);
    if (cover != null || tried(song)) return Future.value(cover);
    return _pending[song.key] ??= _run(sources, song);
  }

  Future<String?> _run(SourceManager sources, Song song) async {
    if (_running >= 4) {
      final turn = Completer<void>();
      _waiting.add(turn);
      await turn.future;
    }
    _running++;
    String? cover;
    try {
      cover = await sources.byId(song.sourceId).songCover(song).timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('cover ${song.key}: $e');
    } finally {
      _running--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
    _done[song.key] = cover;
    _pending.remove(song.key);
    return cover;
  }
}
