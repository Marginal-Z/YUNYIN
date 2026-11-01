import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yunyin/core/data_cache.dart';
import 'package:yunyin/core/ui/feedback.dart';

void main() {
  setUp(DataCache.clear);

  testWidgets('账号缓存清空后旧请求不能重新填回缓存', (tester) async {
    final pending = Completer<String>();
    await tester.pumpWidget(
      MaterialApp(
        home: AsyncView<String>(
          cacheKey: 'account',
          load: () => pending.future,
          loading: const Text('loading'),
          builder: (context, data, reload) => Text(data),
        ),
      ),
    );
    DataCache.clear();
    pending.complete('old account');
    await tester.pump();
    expect(DataCache.lookup('account'), isNull);
    expect(find.text('old account'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  for (final width in [375.0, 1000.0]) {
    testWidgets('切换到已有缓存的数据后忽略旧请求（$width）', (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final oldRequest = Completer<String>();
      Widget view(String key, Future<String> Function() load) => MaterialApp(
        home: AsyncView<String>(cacheKey: key, load: load, loading: const Text('loading'), builder: (context, value, reload) => Text(value)),
      );
      await tester.pumpWidget(view('old', () => oldRequest.future));
      DataCache.put('new', 'new data');
      await tester.pumpWidget(view('new', () async => 'unused'));
      oldRequest.complete('stale data');
      await tester.pumpAndSettle();
      expect(find.text('new data'), findsOneWidget);
      expect(DataCache.lookup('new')?.$1, 'new data');
    });
  }
}
