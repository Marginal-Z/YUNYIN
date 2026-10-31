import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/lx/lx_runtime.dart';

/// YUNYIN_LX_SELFTEST=1：在打包后的应用里启动一个最小的洛雪音源脚本，确认 QuickJS 运行库能加载，然后退出。
bool get lxSelfTestRequested => !kIsWeb && Platform.environment['YUNYIN_LX_SELFTEST'] == '1';

Future<void> runLxSelfTest() async {
  try {
    final rt = await LxRuntime.start('''
const { EVENT_NAMES, on, send, utils } = globalThis.lx
on(EVENT_NAMES.request, async ({ info }) => 'https://example.com/' + utils.crypto.md5(info.musicInfo.songmid) + '/' + utils.buffer.from('ok').toString('base64'))
send(EVENT_NAMES.inited, { sources: { tx: { type: 'music', actions: ['musicUrl'], qualitys: ['128k', '320k'] } } })
''');
    final url = await rt.musicUrl('tx', '320k', {'songmid': 'abc'});
    stderr.writeln('lx selftest: ok ${rt.sources} $url');
    rt.dispose();
    exit(0);
  } catch (e) {
    stderr.writeln('lx selftest: failed $e');
    exit(1);
  }
}
