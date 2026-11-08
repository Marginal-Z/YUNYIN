import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 页面级的转场如果缩放或淡入整个页面，必须作用在快照上（TransitionSnapshot）：Impeller 按“字号 × 缩放比例”
/// 光栅化字形，直接缩放满屏文字时每一帧都要把所有文字重新光栅化。三星 S23 Ultra 上实测，16 次页面切换的掉帧
/// 从约 300 帧（直接缩放）降到几十帧以内。这里检查页面切换、底部标签切换、播放页与歌词页的转场代码。
void main() {
  test('页面级转场的缩放作用在快照上', () {
    final scale = RegExp(r'ScaleTransition|Transform\.scale|scaleByDouble');
    final files = {
      'lib/features/shell/transitions.dart': null,
      'lib/features/common/sheet_route.dart': null,
      // actions.dart 中只检查 fadeRoute（歌词页等整页路由）。
      'lib/features/common/actions.dart': RegExp(r'Route<T> fadeRoute<T>[\s\S]*?\n\);'),
    };
    for (final MapEntry(key: path, value: section) in files.entries) {
      final text = File(path).readAsStringSync();
      final code = section == null ? text : (section.firstMatch(text)?.group(0) ?? '');
      expect(code, isNotEmpty, reason: '$path 中没有找到要检查的代码');
      final withoutComments = code.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
      if (scale.hasMatch(withoutComments)) {
        expect(withoutComments, contains('TransitionSnapshot('), reason: '$path 的页面转场有缩放，但没有作用在快照上，会导致页面切换掉帧');
      }
    }
  });
}
