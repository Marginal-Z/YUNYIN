import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/voice/moss/moss_models.dart';

/// 模型下载的断点续传：服务器支持续传时接着写；不支持（返回 200 与完整文件）时从头写，不会把整个文件接在后面。
void main() {
  final body = List<int>.generate(10000, (i) => i % 251);
  late HttpServer server;
  var honorRange = true;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final range = req.headers.value('range');
      if (honorRange && range != null) {
        final start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = 206;
        req.response.add(body.sublist(start));
      } else {
        req.response.add(body);
      }
      await req.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  Future<List<int>> run(int have) async {
    final dir = await Directory.systemTemp.createTemp('moss_dl');
    final part = File('${dir.path}/x.part');
    if (have > 0) part.writeAsBytesSync(body.sublist(0, have));
    await MossModels.fetch(Dio(), 'http://127.0.0.1:${server.port}/x', part, have, null, (_) {});
    final out = part.readAsBytesSync();
    await dir.delete(recursive: true);
    return out;
  }

  test('支持续传时从断点继续', () async {
    honorRange = true;
    expect(await run(4000), body);
  });

  test('不支持续传时从头写入', () async {
    honorRange = false;
    expect(await run(4000), body);
  });

  test('从零开始', () async {
    expect(await run(0), body);
  });
}
