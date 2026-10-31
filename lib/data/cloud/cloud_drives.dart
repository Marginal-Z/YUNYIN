import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

/// 网盘类型（预设地址与说明）。都通过 WebDAV 访问；阿里云盘、百度网盘、夸克、115、天翼云盘、OneDrive、
/// Google Drive 等没有直接的 WebDAV 接口，可以用 Alist / OpenList 挂载后再添加。
enum CloudKind {
  alist(
    'Alist / OpenList',
    'http://192.168.1.2:5244/dav',
    '挂载阿里云盘、百度网盘、夸克、115、天翼云盘、OneDrive、Google Drive 等后填写其 WebDAV 地址',
  ),
  jianguoyun(
    '坚果云',
    'https://dav.jianguoyun.com/dav/',
    '账号为坚果云邮箱，密码使用“第三方应用管理”中生成的应用密码',
  ),
  nextcloud(
    'Nextcloud / ownCloud',
    'https://example.com/remote.php/dav/files/用户名/',
    '把地址中的“用户名”换成你的账号',
  ),
  synology(
    '群晖 NAS',
    'https://nas.example.com:5006',
    '在 WebDAV Server 套件中启用 HTTPS（默认端口 5006）',
  ),
  pcloud(
    'pCloud',
    'https://webdav.pcloud.com',
    '欧洲数据中心的账号使用 https://ewebdav.pcloud.com',
  ),
  webdav('其他 WebDAV', '', 'Box、Koofr、TeraCloud、自建服务器等任何支持 WebDAV 的网盘或 NAS');

  const CloudKind(this.label, this.defaultUrl, this.hint);
  final String label;
  final String defaultUrl;
  final String hint;
}

/// 一个挂载的网盘。
class CloudDrive {
  const CloudDrive({
    required this.id,
    required this.kind,
    required this.name,
    required this.url,
    this.username = '',
    this.password = '',
  });

  final String id;
  final CloudKind kind;
  final String name;

  /// WebDAV 根地址。
  final String url;
  final String username;
  final String password;

  Map<String, String> get headers => username.isEmpty && password.isEmpty
      ? const {}
      : {
          'Authorization':
              'Basic ${base64.encode(utf8.encode('$username:$password'))}',
        };

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'url': url,
    'username': username,
    'password': password,
  };

  factory CloudDrive.fromJson(Map<String, dynamic> j) => CloudDrive(
    id: '${j['id']}',
    kind: CloudKind.values.asNameMap()[j['kind']] ?? CloudKind.webdav,
    name: '${j['name']}',
    url: '${j['url']}',
    username: '${j['username'] ?? ''}',
    password: '${j['password'] ?? ''}',
  );

  /// 文件的完整地址：[href] 是 WebDAV 返回的（已编码的）路径或地址。
  String fileUrl(String href) =>
      Uri.parse(url.endsWith('/') ? url : '$url/').resolve(href).toString();
}

/// 目录中的一项。
class CloudEntry {
  const CloudEntry({
    required this.name,
    required this.href,
    required this.isDir,
    this.size = 0,
  });

  final String name;

  /// 已编码的路径（相对根地址或绝对路径），用于继续浏览与播放。
  final String href;
  final bool isDir;
  final int size;

  static const audioExtensions = [
    'mp3',
    'flac',
    'm4a',
    'aac',
    'ogg',
    'opus',
    'wav',
    'ape',
    'wma',
    'aiff',
    'alac',
    'dsf',
    'dff',
  ];

  bool get isAudio =>
      !isDir && audioExtensions.contains(name.split('.').last.toLowerCase());
  bool get isLyrics => !isDir && name.toLowerCase().endsWith('.lrc');
}

/// 已挂载的网盘与 WebDAV 访问。配置（含密码）保存在本机应用数据中，只发送给对应的网盘服务器。
class CloudDrives extends ChangeNotifier {
  CloudDrives({Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 30),
              responseType: ResponseType.plain,
            ),
          );

  static const _key = 'cloud.drives';
  final Dio _dio;
  SharedPreferences? _p;
  final List<CloudDrive> _drives = [];

  List<CloudDrive> get drives => List.unmodifiable(_drives);

  CloudDrive? byId(String id) => _drives.where((d) => d.id == id).firstOrNull;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    try {
      final raw = _p!.getString(_key);
      if (raw != null) {
        for (final j in jsonDecode(raw) as List) {
          _drives.add(CloudDrive.fromJson(Map<String, dynamic>.from(j as Map)));
        }
      }
    } catch (e) {
      debugPrint('cloud drives: $e');
    }
  }

  void _save() {
    _p?.setString(_key, jsonEncode([for (final d in _drives) d.toJson()]));
    notifyListeners();
  }

  void upsert(CloudDrive d) {
    final i = _drives.indexWhere((x) => x.id == d.id);
    if (i >= 0) {
      _drives[i] = d;
    } else {
      _drives.add(d);
    }
    _save();
  }

  void remove(String id) {
    _drives.removeWhere((d) => d.id == id);
    _save();
  }

  /// 列出目录（WebDAV PROPFIND，深度 1）。文件夹在前，按名称排序。
  Future<List<CloudEntry>> list(CloudDrive d, [String href = '']) async {
    final target = d.fileUrl(href);
    final res = await _dio.request<String>(
      target,
      data: '<?xml version="1.0" encoding="utf-8"?><d:propfind xmlns:d="DAV:"><d:prop><d:displayname/><d:resourcetype/><d:getcontentlength/></d:prop></d:propfind>',
      options: Options(
        method: 'PROPFIND',
        headers: {
          ...d.headers,
          'Depth': '1',
          'Content-Type': 'application/xml; charset=utf-8',
        },
        validateStatus: (s) => s != null && s < 500,
      ),
    );
    final code = res.statusCode ?? 0;
    if (code == 401 || code == 403) throw Exception('账号或密码不正确（$code）');
    if (code == 404) throw Exception('路径不存在（404）');
    if (code != 207 && code != 200)
      throw Exception('服务器返回 $code，请确认地址是 WebDAV 地址');
    return parseMultiStatus(res.data ?? '', Uri.parse(target).path);
  }

  /// 解析 PROPFIND 的 207 响应；[self] 为当前目录的路径（用于排除目录自身）。
  @visibleForTesting
  static List<CloudEntry> parseMultiStatus(String body, String self) {
    final doc = XmlDocument.parse(body);
    String norm(String p) => Uri.decodeFull(p).replaceAll(RegExp(r'/+$'), '');
    final out = <CloudEntry>[];
    for (final r in doc.findAllElements('response', namespaceUri: '*')) {
      final href =
          r
              .findAllElements('href', namespaceUri: '*')
              .firstOrNull
              ?.innerText
              .trim() ??
          '';
      if (href.isEmpty) continue;
      final hrefPath = href.startsWith('http') ? Uri.parse(href).path : href;
      if (norm(hrefPath) == norm(self)) continue;
      final isDir = r
          .findAllElements('collection', namespaceUri: '*')
          .isNotEmpty;
      final size =
          int.tryParse(
            r
                    .findAllElements('getcontentlength', namespaceUri: '*')
                    .firstOrNull
                    ?.innerText
                    .trim() ??
                '',
          ) ??
          0;
      var name =
          r
              .findAllElements('displayname', namespaceUri: '*')
              .firstOrNull
              ?.innerText
              .trim() ??
          '';
      if (name.isEmpty)
        name = Uri.decodeFull(
          hrefPath.replaceAll(RegExp(r'/+$'), '').split('/').last,
        );
      out.add(CloudEntry(name: name, href: hrefPath, isDir: isDir, size: size));
    }
    out.sort(
      (a, b) => a.isDir != b.isDir
          ? (a.isDir ? -1 : 1)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return out;
  }

  /// 文件的直链：Alist 等挂载阿里云盘、百度网盘时会 302 跳转到网盘的临时直链。
  /// 直链带签名，不能再附带 WebDAV 的认证头（对象存储会拒绝），所以先解析跳转，返回跨域的直链；
  /// 没有跳转或跳转仍在同一服务器时返回 null（照常带认证头访问）。
  Future<String?> resolveDirect(CloudDrive d, String href) async {
    final url = d.fileUrl(href);
    try {
      final res = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: {...d.headers, 'Range': 'bytes=0-0'},
          followRedirects: false,
          responseType: ResponseType.stream,
          validateStatus: (s) => s != null && s < 400,
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      unawaited(res.data?.stream.listen(null).cancel());
      final location = res.headers.value('location');
      if ((res.statusCode ?? 0) ~/ 100 != 3 || location == null) return null;
      final target = Uri.parse(url).resolve(location);
      return target.origin == Uri.parse(url).origin ? null : target.toString();
    } catch (e) {
      debugPrint('cloud direct link: $e');
      return null;
    }
  }

  /// 读取文本文件（同名 .lrc 歌词），不存在时返回 null。
  Future<String?> readText(CloudDrive d, String href) async {
    try {
      final res = await _dio.get<List<int>>(
        d.fileUrl(href),
        options: Options(
          headers: d.headers,
          responseType: ResponseType.bytes,
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (res.statusCode != 200 || res.data == null) return null;
      return utf8.decode(res.data!, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }
}
