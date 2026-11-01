import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as hash;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_js/flutter_js.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';

/// 洛雪音乐（LX Music）自定义音源脚本的运行环境。
///
/// 脚本运行在 QuickJS / JavaScriptCore 中，只能通过下面提供的 `globalThis.lx` 接口与外界交互：
/// `lx.request` 发起 HTTP 请求（由云音代为执行），`lx.on('request')` 注册取播放地址的处理函数，
/// `lx.send('inited')` 声明支持的平台与音质，`lx.utils` 提供 Buffer、MD5、AES、RSA、zlib 等工具。
class LxRuntime {
  LxRuntime._(this._js, this.script);

  final JavascriptRuntime _js;
  final String script;
  final Dio _dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20), responseType: ResponseType.bytes));

  /// 脚本声明的平台：键为洛雪的平台代号（wy、tx、kg、kw、mg），值为支持的音质（128k、320k、flac、flac24bit）。
  final Map<String, List<String>> sources = {};

  final _inited = Completer<void>();
  final Map<int, Completer<String>> _pending = {};
  int _seq = 0;
  Timer? _pump;
  bool _disposed = false;

  /// 启动脚本并等待它声明支持的平台（最多 [timeout]）。
  static Future<LxRuntime> start(String script, {Duration timeout = const Duration(seconds: 8), Map<String, String> info = const {}}) async {
    _preloadLinux();
    final js = getJavascriptRuntime(xhr: false);
    final rt = LxRuntime._(js, script);
    try {
      rt._bind();
      final prelude = _prelude.replaceFirst('__SCRIPT_INFO__', jsonEncode(info));
      final p = js.evaluate(prelude);
      if (p.isError) throw Exception('洛雪运行环境初始化失败：${p.stringResult}');
      final r = js.evaluate(script);
      if (r.isError) {
        throw Exception('音源脚本执行出错：${r.stringResult}');
      }
      rt._jobs();
      rt._keepPumping();
      try {
        await rt._inited.future.timeout(timeout);
      } on TimeoutException {
        throw Exception('音源脚本没有完成初始化（未调用 lx.send(\'inited\')）');
      }
      return rt;
    } catch (_) {
      rt.dispose();
      rethrow;
    }
  }

  /// Linux 上 QuickJS 动态库放在可执行文件旁的 lib 目录：先按绝对路径加载一次，
  /// flutter_js 之后按文件名加载时就会使用已加载的这份。
  static bool _preloaded = false;
  static void _preloadLinux() {
    if (_preloaded || kIsWeb || !Platform.isLinux || Platform.environment['FLUTTER_TEST'] == 'true') return;
    final f = File('${File(Platform.resolvedExecutable).parent.path}/lib/libquickjs_c_bridge_plugin.so');
    if (!f.existsSync()) throw Exception('当前系统架构暂不支持洛雪音源（缺少 QuickJS 运行库）');
    DynamicLibrary.open(f.path);
    _preloaded = true;
  }

  void _jobs() {
    if (_disposed) return;
    try {
      _js.executePendingJob();
    } catch (e) {
      debugPrint('lx jobs: $e');
    }
  }

  /// 有未完成的请求时每 16ms 执行一次 Promise 任务队列。
  void _keepPumping() {
    _pump ??= Timer.periodic(const Duration(milliseconds: 16), (_) {
      _jobs();
      if (_pending.isEmpty && _inited.isCompleted) {
        _pump?.cancel();
        _pump = null;
      }
    });
  }

  void _eval(String code) {
    if (_disposed) return;
    final r = _js.evaluate(code);
    if (r.isError) debugPrint('lx eval: ${r.stringResult}');
    _jobs();
  }

  void _bind() {
    _js.onMessage('lx_send', (args) {
      final m = args as Map;
      final name = '${m['name']}';
      if (name == 'inited') {
        final data = m['data'];
        // 脚本明确报告初始化失败（status: false）：不能当作可用的音源，把脚本给出的原因传出去。
        // 没有 status 字段的旧脚本照常视为成功。
        if (data is Map && data['status'] == false) {
          final reason = '${data['errorMessage'] ?? data['message'] ?? ''}'.trim();
          if (!_inited.isCompleted) _inited.completeError(Exception(reason.isEmpty ? '音源脚本报告初始化失败' : '音源脚本初始化失败：$reason'));
          return 'ok';
        }
        final srcs = data is Map ? data['sources'] : null;
        if (srcs is Map) {
          srcs.forEach((k, v) {
            final q = v is Map ? v['qualitys'] : null;
            sources['$k'] = [for (final x in (q is List ? q : const [])) '$x'];
          });
        }
        if (!_inited.isCompleted) _inited.complete();
      }
      return 'ok';
    });
    _js.onMessage('lx_request', (args) {
      final m = (args as Map).cast<String, dynamic>();
      final id = m['id'] as int;
      final token = _cancels[id] = CancelToken();
      unawaited(_request(id, '${m['url']}', (m['opts'] as Map?)?.cast<String, dynamic>() ?? const {}, token));
      _keepPumping();
      return 'ok';
    });
    // 脚本调用 lx.request 返回的取消函数：真正取消底层网络请求（尚未发出的请求不再发出）。
    _js.onMessage('lx_cancel_request', (args) {
      _cancels.remove((args as num).toInt())?.cancel('音源脚本取消了请求');
      return 'ok';
    });
    _js.onMessage('lx_result', (args) {
      final m = args as Map;
      final c = _pending.remove(m['rid']);
      if (c != null && !c.isCompleted) {
        final url = m['url'];
        final parsed = url is String ? Uri.tryParse(url) : null;
        if (parsed != null && (parsed.scheme == 'http' || parsed.scheme == 'https') && parsed.host.isNotEmpty && parsed.userInfo.isEmpty) {
          c.complete(url);
        } else {
          c.completeError(Exception(m['error'] ?? '音源没有返回播放地址'));
        }
      }
      return 'ok';
    });
    _js.onMessage('lx_md5', (args) => hash.md5.convert(utf8.encode('$args')).toString());
    _js.onMessage('lx_aes', (args) {
      final m = args as Map;
      return _aes(_bytes(m['data']), '${m['mode']}', _bytes(m['key']), m['iv'] == null ? null : _bytes(m['iv']));
    });
    _js.onMessage('lx_rsa', (args) {
      final m = args as Map;
      return _rsa(_bytes(m['data']), '${m['key']}');
    });
    _js.onMessage('lx_random', (args) {
      final r = math.Random.secure();
      return [for (var i = 0; i < (args as num).toInt(); i++) r.nextInt(256)];
    });
    _js.onMessage('lx_zlib', (args) {
      final m = args as Map;
      final data = _bytes(m['data']);
      return m['op'] == 'inflate' ? ZLibCodec().decode(data) : ZLibCodec().encode(data);
    });
    _js.onMessage('lx_timer', (args) {
      final m = args as Map;
      final id = (m['id'] as num).toInt();
      final t = Timer(Duration(milliseconds: (m['ms'] as num).toInt()), () {
        _timers.remove(id);
        _eval('__lx_timer($id)');
      });
      _timers[id] = t;
      return 'ok';
    });
    _js.onMessage('lx_clear_timer', (args) {
      _timers.remove((args as num).toInt())?.cancel();
      return 'ok';
    });
    _js.onMessage('lx_log', (args) {
      debugPrint('lx: $args');
      return 'ok';
    });
  }

  static Uint8List _bytes(Object? v) => Uint8List.fromList([for (final x in (v as List? ?? const [])) (x as num).toInt() & 0xFF]);

  /// AES 加密（PKCS7 填充，与 Node.js 的 createCipheriv 默认行为一致）。
  static List<int> _aes(Uint8List data, String mode, Uint8List key, Uint8List? iv) {
    final ecb = mode.toLowerCase().contains('ecb') || iv == null || iv.isEmpty;
    final BlockCipher cipher = ecb ? ECBBlockCipher(AESEngine()) : CBCBlockCipher(AESEngine());
    final params = ecb ? KeyParameter(key) : ParametersWithIV<KeyParameter>(KeyParameter(key), iv);
    final padded = PaddedBlockCipherImpl(PKCS7Padding(), cipher)..init(true, PaddedBlockCipherParameters<CipherParameters, CipherParameters?>(params, null));
    return padded.process(data);
  }

  /// RSA 无填充加密（数据左侧补零到 128 字节，与洛雪桌面版一致）。[pem] 为 PEM 格式公钥。
  static List<int> _rsa(Uint8List data, String pem) {
    final der = base64.decode(pem.replaceAll(RegExp(r'-----[^-]+-----'), '').replaceAll(RegExp(r'\s'), ''));
    var seq = ASN1Parser(der).nextObject() as ASN1Sequence;
    // SubjectPublicKeyInfo：取出其中的 RSAPublicKey。
    if (seq.elements!.first is ASN1Sequence) {
      final bits = seq.elements![1] as ASN1BitString;
      seq = ASN1Parser(Uint8List.fromList(bits.stringValues!)).nextObject() as ASN1Sequence;
    }
    final n = (seq.elements![0] as ASN1Integer).integer!;
    final e = (seq.elements![1] as ASN1Integer).integer!;
    final size = (n.bitLength + 7) ~/ 8;
    final padded = Uint8List(size)..setRange(size - data.length, size, data);
    var m = BigInt.zero;
    for (final b in padded) {
      m = (m << 8) | BigInt.from(b);
    }
    var c = m.modPow(e, n);
    final out = Uint8List(size);
    for (var i = size - 1; i >= 0; i--) {
      out[i] = (c & BigInt.from(0xFF)).toInt();
      c = c >> 8;
    }
    return out;
  }

  /// 进行中的 lx.request，按请求编号取消。
  final Map<int, CancelToken> _cancels = {};

  Future<void> _request(int id, String url, Map<String, dynamic> opts, CancelToken token) async {
    Object? err;
    Map<String, dynamic>? resp;
    // 让脚本同步调用的取消先生效，再真正发出请求。
    await Future<void>.delayed(Duration.zero);
    if (token.isCancelled || _disposed) {
      _cancels.remove(id);
      return;
    }
    try {
      final headers = <String, dynamic>{...?(opts['headers'] as Map?)?.cast<String, dynamic>()};
      Object? body = opts['body'];
      if (opts['form'] is Map) {
        body = (opts['form'] as Map).entries.map((e) => '${Uri.encodeQueryComponent('${e.key}')}=${Uri.encodeQueryComponent('${e.value}')}').join('&');
        headers.putIfAbsent('Content-Type', () => 'application/x-www-form-urlencoded');
      } else if (opts['formData'] is Map) {
        body = FormData.fromMap((opts['formData'] as Map).cast<String, dynamic>());
      } else if (body is Map || body is List) {
        body = jsonEncode(body);
        headers.putIfAbsent('Content-Type', () => 'application/json');
      }
      final timeout = Duration(milliseconds: (opts['timeout'] as num?)?.toInt() ?? 15000);
      final res = await _dio.request<List<int>>(
        url,
        data: body,
        cancelToken: token,
        options: Options(
          method: '${opts['method'] ?? 'GET'}'.toUpperCase(),
          headers: headers,
          sendTimeout: timeout,
          receiveTimeout: timeout,
          validateStatus: (_) => true,
          followRedirects: true,
        ),
      );
      final raw = res.data ?? const <int>[];
      final text = utf8.decode(raw, allowMalformed: true);
      Object? parsed = text;
      try {
        parsed = jsonDecode(text);
      } catch (_) {}
      resp = {
        'statusCode': res.statusCode,
        'statusMessage': res.statusMessage,
        'headers': {for (final e in res.headers.map.entries) e.key: e.value.join(', ')},
        'body': parsed,
        'raw': raw,
      };
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _cancels.remove(id);
        return;
      }
      err = e is DioException ? (e.message ?? e.type.name) : '$e';
    }
    _cancels.remove(id);
    _eval('__lx_response($id, ${jsonEncode(err?.toString())}, ${jsonEncode(resp)})');
  }

  /// 调用脚本的 `request` 处理函数获取播放地址。[source] 为洛雪平台代号，[quality] 为 128k / 320k / flac / flac24bit。
  Future<String> musicUrl(String source, String quality, Map<String, dynamic> musicInfo, {Duration timeout = const Duration(seconds: 20)}) {
    if (_disposed) return Future.error(StateError('音源已停止'));
    final rid = ++_seq;
    final c = Completer<String>();
    _pending[rid] = c;
    final payload = {
      'source': source,
      'action': 'musicUrl',
      'info': {'type': quality, 'musicInfo': musicInfo},
    };
    _eval('__lx_dispatch($rid, ${jsonEncode(payload)})');
    _keepPumping();
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(rid);
        throw Exception('音源响应超时');
      },
    );
  }

  /// 脚本中未到期的定时器（停止音源时一并取消）。
  final _timers = <int, Timer>{};

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final t in _cancels.values) {
      t.cancel('音源已停止');
    }
    _cancels.clear();
    _dio.close(force: true);
    _pump?.cancel();
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(Exception('音源已停止'));
    }
    _pending.clear();
    try {
      _js.dispose();
    } catch (_) {}
  }
}

/// 在脚本之前执行的运行环境：`globalThis.lx`、精简版 Buffer 与桥接到云音的工具函数。
const _prelude = r'''
(function () {
  var g = globalThis;
  var B64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
  function toB64(bytes) {
    var out = '', i;
    for (i = 0; i + 2 < bytes.length; i += 3) {
      var n = (bytes[i] << 16) | (bytes[i + 1] << 8) | bytes[i + 2];
      out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63] + B64[(n >> 6) & 63] + B64[n & 63];
    }
    if (i < bytes.length) {
      var a = bytes[i], b = i + 1 < bytes.length ? bytes[i + 1] : 0;
      var m = (a << 16) | (b << 8);
      out += B64[(m >> 18) & 63] + B64[(m >> 12) & 63] + (i + 1 < bytes.length ? B64[(m >> 6) & 63] : '=') + '=';
    }
    return out;
  }
  function fromB64(s) {
    s = String(s).replace(/[^A-Za-z0-9+/_-]/g, '').replace(/-/g, '+').replace(/_/g, '/');
    var out = [], buf = 0, bits = 0;
    for (var i = 0; i < s.length; i++) {
      buf = (buf << 6) | B64.indexOf(s[i]);
      bits += 6;
      if (bits >= 8) { bits -= 8; out.push((buf >> bits) & 255); }
    }
    return out;
  }
  function utf8Encode(s) {
    var bin = unescape(encodeURIComponent(String(s))), out = new Array(bin.length);
    for (var i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }
  function utf8Decode(bytes) {
    var bin = '';
    for (var i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
    try { return decodeURIComponent(escape(bin)); } catch (e) { return bin; }
  }
  function LxBuffer(bytes) {
    var u = new Uint8Array(bytes);
    Object.setPrototypeOf(u, LxBuffer.prototype);
    return u;
  }
  LxBuffer.prototype = Object.create(Uint8Array.prototype);
  LxBuffer.prototype.constructor = LxBuffer;
  LxBuffer.prototype.toString = function (enc) {
    var arr = Array.prototype.slice.call(this);
    enc = (enc || 'utf8').toLowerCase();
    if (enc === 'hex') return arr.map(function (b) { return (b < 16 ? '0' : '') + b.toString(16); }).join('');
    if (enc === 'base64') return toB64(arr);
    if (enc === 'binary' || enc === 'latin1') return arr.map(function (b) { return String.fromCharCode(b); }).join('');
    return utf8Decode(arr);
  };
  LxBuffer.from = function (data, enc) {
    if (data instanceof Uint8Array || Array.isArray(data)) return LxBuffer(Array.prototype.slice.call(data));
    if (data instanceof ArrayBuffer) return LxBuffer(Array.prototype.slice.call(new Uint8Array(data)));
    enc = (enc || 'utf8').toLowerCase();
    var s = String(data);
    if (enc === 'hex') { var o = []; for (var i = 0; i + 1 < s.length; i += 2) o.push(parseInt(s.substr(i, 2), 16)); return LxBuffer(o); }
    if (enc === 'base64') return LxBuffer(fromB64(s));
    if (enc === 'binary' || enc === 'latin1') { var b = []; for (var j = 0; j < s.length; j++) b.push(s.charCodeAt(j) & 255); return LxBuffer(b); }
    return LxBuffer(utf8Encode(s));
  };
  LxBuffer.alloc = function (n) { return LxBuffer(new Array(n).fill(0)); };
  LxBuffer.concat = function (list) { var o = []; list.forEach(function (x) { o = o.concat(Array.prototype.slice.call(x)); }); return LxBuffer(o); };
  LxBuffer.isBuffer = function (x) { return x instanceof Uint8Array; };
  if (!g.Buffer) g.Buffer = LxBuffer;
  function arr(x) { return Array.prototype.slice.call(x instanceof Uint8Array ? x : LxBuffer.from(x)); }

  var EVENT_NAMES = { request: 'request', inited: 'inited', updateAlert: 'updateAlert' };
  var handlers = {};
  var callbacks = {};
  var seq = 0;
  var utils = {
    crypto: {
      md5: function (s) { return sendMessage('lx_md5', JSON.stringify(String(s))); },
      aesEncrypt: function (buf, mode, key, iv) {
        return LxBuffer(sendMessage('lx_aes', JSON.stringify({ data: arr(buf), mode: mode, key: arr(key), iv: iv == null || iv === '' ? null : arr(iv) })));
      },
      rsaEncrypt: function (buf, key) { return LxBuffer(sendMessage('lx_rsa', JSON.stringify({ data: arr(buf), key: String(key) }))); },
      randomBytes: function (n) { return LxBuffer(sendMessage('lx_random', JSON.stringify(n))); },
    },
    buffer: {
      from: function (d, e) { return LxBuffer.from(d, e); },
      bufToString: function (b, f) { return LxBuffer.from(b).toString(f); },
    },
    zlib: {
      inflate: function (b) { return Promise.resolve(LxBuffer(sendMessage('lx_zlib', JSON.stringify({ op: 'inflate', data: arr(b) })))); },
      deflate: function (b) { return Promise.resolve(LxBuffer(sendMessage('lx_zlib', JSON.stringify({ op: 'deflate', data: arr(b) })))); },
    },
  };
  g.lx = {
    EVENT_NAMES: EVENT_NAMES,
    version: '2.0.0',
    env: 'mobile',
    currentScriptInfo: __SCRIPT_INFO__,
    utils: utils,
    on: function (name, handler) { handlers[name] = handler; return Promise.resolve(); },
    send: function (name, data) { sendMessage('lx_send', JSON.stringify({ name: name, data: data })); return Promise.resolve(); },
    request: function (url, options, callback) {
      var id = ++seq;
      callbacks[id] = callback;
      sendMessage('lx_request', JSON.stringify({ id: id, url: url, opts: options || {} }));
      // 取消：丢弃回调并通知云音取消底层请求；重复调用或请求完成后调用都没有副作用。
      return function () {
        if (!callbacks[id]) return;
        delete callbacks[id];
        sendMessage('lx_cancel_request', JSON.stringify(id));
      };
    },
  };
  // 定时器：flutter_js 自带的 setTimeout 不返回编号、不传额外参数，也没有 clearTimeout / setInterval，
  // 而音源脚本常用它们给请求加超时；这里完整实现一套，由云音按时回调。
  var timers = {};
  var timerSeq = 0;
  var startTimer = function (fn, ms, args, repeat) {
    var id = ++timerSeq;
    timers[id] = { fn: fn, args: args, repeat: repeat, ms: Math.max(0, Number(ms) || 0) };
    sendMessage('lx_timer', JSON.stringify({ id: id, ms: timers[id].ms }));
    return id;
  };
  g.setTimeout = function (fn, ms) { return startTimer(fn, ms, Array.prototype.slice.call(arguments, 2), false); };
  g.setInterval = function (fn, ms) { return startTimer(fn, ms, Array.prototype.slice.call(arguments, 2), true); };
  g.clearTimeout = g.clearInterval = function (id) {
    if (!timers[id]) return;
    delete timers[id];
    sendMessage('lx_clear_timer', JSON.stringify(id));
  };
  g.__lx_timer = function (id) {
    var t = timers[id];
    if (!t) return;
    if (t.repeat) sendMessage('lx_timer', JSON.stringify({ id: id, ms: t.ms }));
    else delete timers[id];
    if (typeof t.fn === 'function') t.fn.apply(null, t.args);
  };
  g.console = g.console || {};
  ['log', 'info', 'warn', 'error', 'debug'].forEach(function (k) {
    g.console[k] = function () { try { sendMessage('lx_log', JSON.stringify(Array.prototype.join.call(arguments, ' '))); } catch (e) {} };
  });
  g.__lx_response = function (id, err, resp) {
    var cb = callbacks[id];
    delete callbacks[id];
    if (!cb) return;
    if (resp && resp.raw) resp.raw = LxBuffer(resp.raw);
    cb(err ? new Error(err) : null, resp, resp ? resp.body : null);
  };
  g.__lx_dispatch = function (rid, payload) {
    var h = handlers.request;
    if (!h) { sendMessage('lx_result', JSON.stringify({ rid: rid, error: '音源没有注册请求处理函数' })); return; }
    Promise.resolve()
      .then(function () { return h(payload); })
      .then(function (url) { sendMessage('lx_result', JSON.stringify({ rid: rid, url: url })); })
      .catch(function (e) { sendMessage('lx_result', JSON.stringify({ rid: rid, error: String((e && e.message) || e) })); });
  };
})();
''';
