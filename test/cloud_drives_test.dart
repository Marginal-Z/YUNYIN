import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/data/cloud/cloud_drives.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/cloud/cloud_source.dart';

const _body = '''<?xml version="1.0" encoding="utf-8"?>
<D:multistatus xmlns:D="DAV:">
  <D:response><D:href>/dav/%E9%9F%B3%E4%B9%90/</D:href>
    <D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
  <D:response><D:href>/dav/%E9%9F%B3%E4%B9%90/%E5%91%A8%E6%9D%B0%E4%BC%A6%20-%20%E6%99%B4%E5%A4%A9.flac</D:href>
    <D:propstat><D:prop><D:resourcetype/><D:getcontentlength>31457280</D:getcontentlength></D:prop></D:propstat></D:response>
  <D:response><D:href>/dav/%E9%9F%B3%E4%B9%90/%E5%91%A8%E6%9D%B0%E4%BC%A6%20-%20%E6%99%B4%E5%A4%A9.lrc</D:href>
    <D:propstat><D:prop><D:resourcetype/></D:prop></D:propstat></D:response>
  <D:response><D:href>/dav/%E9%9F%B3%E4%B9%90/Live/</D:href>
    <D:propstat><D:prop><D:displayname>Live</D:displayname><D:resourcetype><D:collection/></D:resourcetype></D:prop></D:propstat></D:response>
</D:multistatus>''';

void main() {
  SharedPreferences.setMockInitialValues({});
  const drive = CloudDrive(id: 'a', kind: CloudKind.alist, name: 'Alist', url: 'http://nas:5244/dav', username: 'u', password: 'p');

  test('解析 PROPFIND 响应：排除目录自身，文件夹在前', () {
    final items = CloudDrives.parseMultiStatus(_body, '/dav/%E9%9F%B3%E4%B9%90');
    expect(items.map((e) => e.name), ['Live', '周杰伦 - 晴天.flac', '周杰伦 - 晴天.lrc']);
    expect(items.first.isDir, isTrue);
    expect(items[1].isAudio, isTrue);
    expect(items[1].size, 31457280);
    expect(items[2].isLyrics, isTrue);
  });

  test('文件地址与认证', () {
    final items = CloudDrives.parseMultiStatus(_body, '/dav/%E9%9F%B3%E4%B9%90/');
    expect(drive.fileUrl(items[1].href), 'http://nas:5244/dav/%E9%9F%B3%E4%B9%90/%E5%91%A8%E6%9D%B0%E4%BC%A6%20-%20%E6%99%B4%E5%A4%A9.flac');
    expect(drive.fileUrl(''), 'http://nas:5244/dav/');
    expect(drive.headers['Authorization'], 'Basic dTpw');
  });

  test('文件路径不能把网盘凭据发送给其他服务器或文件协议', () {
    for (final href in ['https://other.example/music.mp3', '//other.example/music.mp3', 'file:///tmp/music.mp3', 'http://user:pass@nas:5244/dav/x.mp3']) {
      expect(() => drive.fileUrl(href), throwsFormatException);
    }
  });

  test('忽略 WebDAV 返回的失败项与失败属性', () {
    const body = '''<d:multistatus xmlns:d="DAV:">
      <d:response><d:href>/dav/missing.mp3</d:href><d:status>HTTP/1.1 404 Not Found</d:status></d:response>
      <d:response><d:href>/dav/song.mp3</d:href>
        <d:propstat><d:prop><d:displayname>错误名称</d:displayname><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat>
        <d:propstat><d:prop><d:displayname>song.mp3</d:displayname></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
      </d:response></d:multistatus>''';
    final items = CloudDrives.parseMultiStatus(body, '/dav');
    expect(items, hasLength(1));
    expect(items.single.name, 'song.mp3');
    expect(items.single.isDir, isFalse);
  });

  test('歌词跨服务器跳转不携带认证，播放地址能解析多级跳转', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    addTearDown(() => cdn.close(force: true));
    String? leaked;
    cdn.listen((request) async {
      leaked = request.headers.value('authorization');
      request.response.write('[00:01.00]歌词');
      await request.response.close();
    });
    server.listen((request) async {
      request.response.statusCode = 302;
      request.response.headers.set('location', request.uri.path == '/dav/song.mp3' ? '/dav/redirect.mp3' : 'http://127.0.0.1:${cdn.port}/file');
      await request.response.close();
    });
    final mounted = CloudDrive(id: 'd', kind: CloudKind.webdav, name: 'test', url: 'http://127.0.0.1:${server.port}/dav', username: 'u', password: 'p');
    final drives = CloudDrives();
    expect(await drives.readText(mounted, 'song.lrc'), contains('歌词'));
    expect(leaked, isNull);
    expect(await drives.resolveDirect(mounted, 'song.mp3'), 'http://127.0.0.1:${cdn.port}/file');
  });

  test('文件名拆出歌手与歌名', () {
    final s = CloudSource.songOf(drive, const CloudEntry(name: '03. 周杰伦 - 晴天.flac', href: '/dav/x.flac', isDir: false));
    expect(s.name, '晴天');
    expect(s.artistText, '周杰伦');
    expect(s.id, 'a|/dav/x.flac');
    final t = CloudSource.songOf(drive, const CloudEntry(name: 'Intro.mp3', href: '/dav/i.mp3', isDir: false));
    expect(t.name, 'Intro');
    expect(t.artists, isEmpty);
  });

  test('配置序列化', () {
    final back = CloudDrive.fromJson(drive.toJson());
    expect(back.kind, CloudKind.alist);
    expect(back.url, drive.url);
    expect(back.password, 'p');
  });

  test('通过 PROPFIND 列目录、读取歌词，并校验账号', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final auth = req.headers.value('authorization');
      if (auth != 'Basic ${base64.encode(utf8.encode('u:p'))}') {
        req.response.statusCode = 401;
      } else if (req.method == 'PROPFIND' && req.headers.value('depth') == '1') {
        req.response
          ..statusCode = 207
          ..headers.contentType = ContentType('application', 'xml', charset: 'utf-8')
          ..write(_body);
      } else if (req.method == 'GET' && req.uri.path.endsWith('.flac')) {
        // 模拟 Alist：跳转到网盘直链（另一个域名）。
        req.response
          ..statusCode = 302
          ..headers.set('location', 'http://localhost:${server.port}/direct.flac?sign=1');
      } else if (req.method == 'GET' && req.uri.path.endsWith('.lrc')) {
        req.response.write('[00:01.00]刮风这天');
      } else {
        req.response.statusCode = 404;
      }
      await req.response.close();
    });
    final d = CloudDrive(
      id: 'b',
      kind: CloudKind.webdav,
      name: 'T',
      url: 'http://127.0.0.1:${server.port}/dav/%E9%9F%B3%E4%B9%90/',
      username: 'u',
      password: 'p',
    );
    final drives = CloudDrives();
    final items = await drives.list(d);
    expect(items.length, 3);
    expect(await drives.readText(d, items[2].href), contains('刮风这天'));
    final source = CloudSource(drives..upsert(d));
    final song = CloudSource.songOf(d, items[1]);
    final info = await source.stream(song, AudioQuality.standard);
    expect(info.url, 'http://localhost:${server.port}/direct.flac?sign=1');
    expect(info.headers, isEmpty);
    expect((await source.lyrics(song)).lines.first.text, '刮风这天');
    await expectLater(drives.list(CloudDrive(id: 'c', kind: CloudKind.webdav, name: 'T', url: d.url, username: 'u', password: 'x')), throwsA(isA<Exception>()));
    await server.close(force: true);
  });
}
