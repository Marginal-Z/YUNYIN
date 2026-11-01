import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yunyin/core/settings.dart';
import 'package:yunyin/data/downloads.dart';
import 'package:yunyin/data/models.dart';
import 'package:yunyin/data/sources/music_source.dart';
import 'package:yunyin/data/sources/source_manager.dart';

class _Source extends MusicSource {
  late Future<StreamInfo> Function(Song) resolve;
  int calls = 0;
  @override
  String get id => 'test';
  @override
  String get name => 'test';
  @override
  String get description => '';
  @override
  Set<SourceFeature> get features => const {};
  @override
  Future<StreamInfo> stream(Song song, AudioQuality quality) {
    calls++;
    return resolve(song);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late HttpServer server;
  late _Source source;
  late DownloadManager downloads;

  setUp(() async {
    HttpOverrides.global = null;
    directory = await Directory.systemTemp.createTemp('yunyin-downloads');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => directory.path,
    );
    SharedPreferences.setMockInitialValues({'downloadDir': '${directory.path}/music'});
    final settings = AppSettings();
    await settings.init();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/missing.mp3') {
        request.response.statusCode = 404;
      } else {
        request.response.write(request.uri.queryParameters['id'] ?? 'audio');
      }
      await request.response.close();
    });
    source = _Source()..resolve = (song) async => StreamInfo(url: 'http://127.0.0.1:${server.port}/audio.mp3?id=${song.id}');
    downloads = DownloadManager(SourceManager([source]), settings);
  });

  tearDown(() async {
    downloads.dispose();
    await server.close(force: true);
    await directory.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), null);
  });

  const song = Song(id: '1', sourceId: 'test', name: '同名歌曲');

  test('解析地址期间重复下载共用同一个结果', () async {
    final resolving = Completer<StreamInfo>();
    source.resolve = (_) => resolving.future;
    final first = downloads.download(song);
    final second = downloads.download(song);
    expect(identical(first, second), isTrue);
    expect(downloads.progress, contains(song.key));
    resolving.complete(StreamInfo(url: 'http://127.0.0.1:${server.port}/audio.mp3'));
    expect(await Future.wait([first, second]), [true, true]);
    expect(source.calls, 1);
    expect(downloads.items, hasLength(1));
    expect(downloads.progress, isEmpty);
  });

  test('不同歌曲同名时文件独立，删除一首不影响另一首，索引可恢复', () async {
    const other = Song(id: '2', sourceId: 'test', name: '同名歌曲');
    expect(await Future.wait([downloads.download(song), downloads.download(other)]), [true, true]);
    final first = downloads.local(song)!.localPath!;
    final second = downloads.local(other)!.localPath!;
    expect(first, isNot(second));
    expect(await File(first).readAsString(), '1');
    expect(await File(second).readAsString(), '2');
    final index = jsonDecode(await File('${directory.path}/downloads.json').readAsString()) as List;
    expect(index, hasLength(2));
    await downloads.remove(song);
    expect(await File(second).exists(), isTrue);
    final restored = DownloadManager(downloads.sources, downloads.settings);
    addTearDown(restored.dispose);
    await restored.init();
    expect(restored.items, hasLength(1));
    expect(restored.local(other), isNotNull);
  });

  test('无扩展名与编码斜线不会生成错误路径，失败不保留半成品', () async {
    source.resolve = (_) async => StreamInfo(url: 'http://127.0.0.1:${server.port}/audio.a%2Fb');
    expect(await downloads.download(song), isTrue);
    expect(downloads.local(song)!.localPath, endsWith('.mp3'));
    const missing = Song(id: '3', sourceId: 'test', name: '失败');
    source.resolve = (_) async => StreamInfo(url: 'http://127.0.0.1:${server.port}/missing.mp3');
    await expectLater(downloads.download(missing), throwsException);
    expect(downloads.isDownloaded(missing), isFalse);
    expect(downloads.progress, isEmpty);
    expect(await directory.list(recursive: true).where((entry) => entry.path.endsWith('.part')).toList(), isEmpty);
  });
}
