import 'dart:typed_data';

/// 把 -1..1 的浮点采样编码为单声道 16 位 WAV，可在末尾补一段静音（句间停顿）。
Uint8List encodeWav(Float32List samples, int sampleRate, {int trailingSilenceMs = 0}) {
  final silence = sampleRate * trailingSilenceMs ~/ 1000;
  final n = samples.length + silence;
  final data = ByteData(44 + n * 2);
  void str(int o, String s) {
    for (var i = 0; i < s.length; i++) {
      data.setUint8(o + i, s.codeUnitAt(i));
    }
  }

  str(0, 'RIFF');
  data.setUint32(4, 36 + n * 2, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  str(36, 'data');
  data.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    data.setInt16(44 + i * 2, (samples[i].clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

/// 16 位单声道 PCM 包装为 WAV。
Uint8List pcm16ToWav(Uint8List pcm, int sampleRate) {
  final out = ByteData(44 + pcm.length);
  final bytes = out.buffer.asUint8List();
  bytes.setAll(0, 'RIFF'.codeUnits);
  out.setUint32(4, 36 + pcm.length, Endian.little);
  bytes.setAll(8, 'WAVEfmt '.codeUnits);
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  bytes.setAll(36, 'data'.codeUnits);
  out.setUint32(40, pcm.length, Endian.little);
  bytes.setAll(44, pcm);
  return bytes;
}

/// 解码 16 位单声道 PCM 的 WAV，返回 -1..1 的浮点采样与采样率。
(Float32List, int) decodeWav16(Uint8List wav) {
  final data = ByteData.sublistView(wav);
  String tag(int o) => String.fromCharCodes(wav.sublist(o, o + 4));
  if (wav.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') throw const FormatException('不是 WAV 文件');
  var rate = 0;
  var o = 12;
  while (o + 8 <= wav.length) {
    final size = data.getUint32(o + 4, Endian.little);
    final body = o + 8;
    if (tag(o) == 'fmt ') {
      if (data.getUint16(body, Endian.little) != 1 || data.getUint16(body + 2, Endian.little) != 1 || data.getUint16(body + 14, Endian.little) != 16) {
        throw const FormatException('只支持 16 位单声道 PCM');
      }
      rate = data.getUint32(body + 4, Endian.little);
    } else if (tag(o) == 'data') {
      final n = (size.clamp(0, wav.length - body)) ~/ 2;
      final out = Float32List(n);
      for (var i = 0; i < n; i++) {
        out[i] = data.getInt16(body + i * 2, Endian.little) / 32768;
      }
      if (rate == 0) throw const FormatException('WAV 缺少 fmt 段');
      return (out, rate);
    }
    o = body + size + (size & 1);
  }
  throw const FormatException('WAV 缺少 data 段');
}
