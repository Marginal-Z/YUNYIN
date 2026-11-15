import 'dart:convert';
import 'dart:typed_data';

/// SentencePiece BPE 分词（MOSS-TTS-Nano 的 tokenizer.model）。
///
/// 按 Google SentencePiece 的实现移植：nmt_nfkc 规范化（模型里预编译的字符映射表，darts-clone 双数组 Trie）、
/// 去掉多余空白、开头加“▁”、按分数合并相邻片段（分数相同取左边的），不在词表中的字退回 UTF-8 字节（<0xXX>）。
/// 结果与官方 Python 库逐个 ID 一致（见 test/moss_tokenizer_test.dart）。
class SentencePieceBpe {
  SentencePieceBpe._(this._pieces, this._reserved, this._userDefined, this._unknownId, this._trie, this._normalized, this._addDummyPrefix,
      this._removeExtraWhitespaces, this._escapeWhitespaces, this._unused);

  /// 普通片段（含用户定义符号与未使用片段）：片段 → (ID, 分数)。
  final Map<String, (int, double)> _pieces;

  /// 控制符号与字节片段：片段 → ID。
  final Map<String, int> _reserved;

  /// 用户定义符号（不拆分、不规范化），按长度从长到短。
  final List<String> _userDefined;
  final int _unknownId;
  final Uint32List? _trie;
  final Uint8List _normalized;
  final bool _addDummyPrefix;
  final bool _removeExtraWhitespaces;
  final bool _escapeWhitespaces;
  final Set<int> _unused;

  static const _space = '▁';

  /// 解析 tokenizer.model（protobuf 格式的 ModelProto）。
  factory SentencePieceBpe.fromBytes(Uint8List bytes) {
    final pieces = <String, (int, double)>{};
    final reserved = <String, int>{};
    final userDefined = <String>[];
    final unused = <int>{};
    var unknown = 0;
    var index = 0;
    Uint8List? charsmap;
    var addDummyPrefix = true, removeExtra = true, escape = true;
    final r = _Proto(bytes);
    while (!r.done) {
      final (field, wire) = r.tag();
      if (field == 1 && wire == 2) {
        // SentencePiece { piece = 1; score = 2; type = 3 }
        final p = _Proto(r.bytes());
        var piece = '', score = 0.0, type = 1;
        while (!p.done) {
          final (f, w) = p.tag();
          if (f == 1 && w == 2) {
            piece = utf8.decode(p.bytes());
          } else if (f == 2 && w == 5) {
            score = p.float32();
          } else if (f == 3 && w == 0) {
            type = p.varint();
          } else {
            p.skip(w);
          }
        }
        // 1 普通、2 未知、3 控制、4 用户定义、5 未使用、6 字节。
        if (type == 1 || type == 4 || type == 5) {
          pieces[piece] = (index, score);
          if (type == 4) userDefined.add(piece);
          if (type == 5) unused.add(index);
        } else {
          reserved[piece] = index;
          if (type == 2) unknown = index;
        }
        index++;
      } else if (field == 3 && wire == 2) {
        // NormalizerSpec { name = 1; precompiled_charsmap = 2; add_dummy_prefix = 3; remove_extra_whitespaces = 4; escape_whitespaces = 5 }
        final p = _Proto(r.bytes());
        while (!p.done) {
          final (f, w) = p.tag();
          if (f == 2 && w == 2) {
            charsmap = p.bytes();
          } else if (f == 3 && w == 0) {
            addDummyPrefix = p.varint() != 0;
          } else if (f == 4 && w == 0) {
            removeExtra = p.varint() != 0;
          } else if (f == 5 && w == 0) {
            escape = p.varint() != 0;
          } else {
            p.skip(w);
          }
        }
      } else {
        r.skip(wire);
      }
    }
    Uint32List? trie;
    var normalized = Uint8List(0);
    if (charsmap != null && charsmap.length > 4) {
      final data = ByteData.sublistView(charsmap);
      final size = data.getUint32(0, Endian.little);
      trie = Uint32List(size ~/ 4);
      for (var i = 0; i < trie.length; i++) {
        trie[i] = data.getUint32(4 + i * 4, Endian.little);
      }
      normalized = Uint8List.sublistView(charsmap, 4 + size);
    }
    userDefined.sort((a, b) => b.length.compareTo(a.length));
    return SentencePieceBpe._(pieces, reserved, userDefined, unknown, trie, normalized, addDummyPrefix, removeExtra, escape, unused);
  }

  /// 把文字切分为 ID。
  List<int> encode(String text) {
    final normalized = normalize(text);
    if (normalized.isEmpty) return const [];
    final out = <int>[];
    for (final piece in _bpe(normalized)) {
      final id = _reserved[piece] ?? _pieces[piece]?.$1;
      if (id != null && id != _unknownId) {
        out.add(id);
        continue;
      }
      // 不在词表中：按 UTF-8 字节输出。
      for (final b in utf8.encode(piece)) {
        out.add(_reserved['<0x${b.toRadixString(16).toUpperCase().padLeft(2, '0')}>'] ?? _unknownId);
      }
    }
    return out;
  }

  // ── 规范化 ──────────────────────────────────────────

  /// nmt_nfkc 规范化，空白替换为“▁”。
  String normalize(String text) {
    final input = utf8.encode(text);
    final out = BytesBuilder(copy: false);
    final space = utf8.encode(_space);
    var prevSpace = _removeExtraWhitespaces;
    var pos = 0;
    var started = false;
    while (pos < input.length) {
      final (piece, consumed) = _normalizePrefix(input, pos);
      var sp = piece;
      if (prevSpace) {
        var s = 0;
        while (s < sp.length && sp[s] == 0x20) {
          s++;
        }
        sp = sp.sublist(s);
      }
      if (sp.isNotEmpty) {
        if (!started) {
          started = true;
          if (_addDummyPrefix) out.add(space);
        }
        for (final c in sp) {
          if (_escapeWhitespaces && c == 0x20) {
            out.add(space);
          } else {
            out.addByte(c);
          }
        }
        if (_removeExtraWhitespaces) prevSpace = sp.last == 0x20;
      }
      pos += consumed;
      if (!_removeExtraWhitespaces) prevSpace = false;
    }
    var s = utf8.decode(out.takeBytes(), allowMalformed: true);
    if (_removeExtraWhitespaces) {
      final ws = _escapeWhitespaces ? _space : ' ';
      while (s.endsWith(ws)) {
        s = s.substring(0, s.length - ws.length);
      }
    }
    return s;
  }

  /// 规范化输入开头的一段：用户定义符号原样保留；预编译映射表中最长的匹配替换为映射结果；否则保留一个 UTF-8 字符。
  (List<int>, int) _normalizePrefix(List<int> input, int pos) {
    for (final u in _userDefined) {
      final b = utf8.encode(u);
      if (_startsWith(input, pos, b)) return (b, b.length);
    }
    var longestLength = 0, longestValue = 0;
    final trie = _trie;
    if (trie != null && trie.isNotEmpty) {
      var node = 0;
      var unit = trie[0];
      node ^= _offset(unit);
      for (var i = pos; i < input.length; i++) {
        final c = input[i];
        node ^= c;
        if (node >= trie.length) break;
        unit = trie[node];
        if (_label(unit) != c) break;
        node ^= _offset(unit);
        if (_hasLeaf(unit) && node < trie.length) {
          longestLength = i - pos + 1;
          longestValue = trie[node] & 0x7fffffff;
        }
      }
    }
    if (longestLength == 0) {
      final len = _utf8Length(input, pos);
      if (len == 0) return (const [0xEF, 0xBF, 0xBD], 1);
      return (input.sublist(pos, pos + len), len);
    }
    var end = longestValue;
    while (end < _normalized.length && _normalized[end] != 0) {
      end++;
    }
    return (_normalized.sublist(longestValue, end), longestLength);
  }

  static int _offset(int unit) => (unit >> 10) << ((unit & (1 << 9)) >> 6);
  static int _label(int unit) => unit & ((1 << 31) | 0xFF);
  static bool _hasLeaf(int unit) => ((unit >> 8) & 1) == 1;

  static bool _startsWith(List<int> s, int pos, List<int> p) {
    if (pos + p.length > s.length) return false;
    for (var i = 0; i < p.length; i++) {
      if (s[pos + i] != p[i]) return false;
    }
    return true;
  }

  /// [pos] 处 UTF-8 字符的字节数；不是合法的 UTF-8 时为 0。
  static int _utf8Length(List<int> s, int pos) {
    final c = s[pos];
    final int n;
    if (c < 0x80) {
      return 1;
    } else if (c >= 0xC2 && c <= 0xDF) {
      n = 2;
    } else if (c >= 0xE0 && c <= 0xEF) {
      n = 3;
    } else if (c >= 0xF0 && c <= 0xF4) {
      n = 4;
    } else {
      return 0;
    }
    if (pos + n > s.length) return 0;
    for (var i = 1; i < n; i++) {
      if (s[pos + i] & 0xC0 != 0x80) return 0;
    }
    return n;
  }

  // ── BPE ─────────────────────────────────────────────

  List<String> _bpe(String normalized) {
    // 拆成字符（用户定义符号整体保留，不参与合并）。
    final pieces = <String>[];
    final frozen = <bool>[];
    final runes = normalized.runes.toList();
    var i = 0;
    while (i < runes.length) {
      String? user;
      if (_userDefined.isNotEmpty) {
        final rest = String.fromCharCodes(runes, i, (i + 64).clamp(0, runes.length));
        user = _userDefined.where(rest.startsWith).firstOrNull;
      }
      if (user != null) {
        pieces.add(user);
        frozen.add(true);
        i += user.runes.length;
      } else {
        pieces.add(String.fromCharCode(runes[i]));
        frozen.add(false);
        i++;
      }
    }
    final n = pieces.length;
    final prev = List<int>.generate(n, (k) => k - 1);
    final next = List<int>.generate(n, (k) => k + 1 < n ? k + 1 : -1);
    final agenda = _Agenda();
    final revMerge = <String, (String, String)>{};

    void addPair(int left, int right) {
      if (left == -1 || right == -1 || frozen[left] || frozen[right]) return;
      final piece = pieces[left] + pieces[right];
      final hit = _pieces[piece];
      if (hit == null) return;
      agenda.push(_Pair(left, right, hit.$2, piece.length));
      if (_unused.contains(hit.$1)) revMerge[piece] = (pieces[left], pieces[right]);
    }

    for (var k = 1; k < n; k++) {
      addPair(k - 1, k);
    }
    while (agenda.isNotEmpty) {
      final top = agenda.pop();
      final l = pieces[top.left], r = pieces[top.right];
      if (l.isEmpty || r.isEmpty || l.length + r.length != top.size) continue;
      pieces[top.left] = l + r;
      next[top.left] = next[top.right];
      if (next[top.right] >= 0) prev[next[top.right]] = top.left;
      pieces[top.right] = '';
      addPair(prev[top.left], top.left);
      addPair(top.left, next[top.left]);
    }

    final out = <String>[];
    void resegment(String w) {
      final id = _reserved[w] ?? _pieces[w]?.$1;
      final split = id != null && _unused.contains(id) ? revMerge[w] : null;
      if (split == null) {
        out.add(w);
        return;
      }
      resegment(split.$1);
      resegment(split.$2);
    }

    for (var k = n == 0 ? -1 : 0; k != -1; k = next[k]) {
      resegment(pieces[k]);
    }
    return out;
  }
}

class _Pair {
  _Pair(this.left, this.right, this.score, this.size);

  final int left;
  final int right;
  final double score;
  final int size;

  /// 先合并分数高的；分数相同时先合并靠左的。
  bool before(_Pair o) => score > o.score || (score == o.score && left < o.left);
}

/// 二叉堆（优先队列）。
class _Agenda {
  final List<_Pair> _h = [];

  bool get isNotEmpty => _h.isNotEmpty;

  void push(_Pair p) {
    _h.add(p);
    var i = _h.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (!_h[i].before(_h[parent])) break;
      final t = _h[i];
      _h[i] = _h[parent];
      _h[parent] = t;
      i = parent;
    }
  }

  _Pair pop() {
    final top = _h.first;
    final last = _h.removeLast();
    if (_h.isNotEmpty) {
      _h[0] = last;
      var i = 0;
      while (true) {
        final l = i * 2 + 1, r = l + 1;
        var best = i;
        if (l < _h.length && _h[l].before(_h[best])) best = l;
        if (r < _h.length && _h[r].before(_h[best])) best = r;
        if (best == i) break;
        final t = _h[i];
        _h[i] = _h[best];
        _h[best] = t;
        i = best;
      }
    }
    return top;
  }
}

/// 最小的 protobuf 读取器（只支持 SentencePiece 模型用到的几种字段）。
class _Proto {
  _Proto(this._b) : _d = ByteData.sublistView(_b);

  final Uint8List _b;
  final ByteData _d;
  int _p = 0;

  bool get done => _p >= _b.length;

  int varint() {
    var result = 0, shift = 0;
    while (true) {
      final b = _b[_p++];
      result |= (b & 0x7f) << shift;
      if (b & 0x80 == 0) return result;
      shift += 7;
    }
  }

  (int, int) tag() {
    final t = varint();
    return (t >> 3, t & 7);
  }

  Uint8List bytes() {
    final n = varint();
    final out = Uint8List.sublistView(_b, _p, _p + n);
    _p += n;
    return out;
  }

  double float32() {
    final v = _d.getFloat32(_p, Endian.little);
    _p += 4;
    return v;
  }

  void skip(int wire) {
    switch (wire) {
      case 0:
        varint();
      case 1:
        _p += 8;
      case 2:
        // 先读出长度再前移（_p += varint() 会先取 _p 的旧值）。
        final n = varint();
        _p += n;
      case 5:
        _p += 4;
      default:
        throw FormatException('tokenizer.model：不支持的字段类型 $wire');
    }
  }
}
