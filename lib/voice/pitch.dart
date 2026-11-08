import 'dart:math' as math;
import 'dart:typed_data';

/// 估计一段 16 位 PCM WAV 中人声的基频（Hz，取有声帧的中位数）。没有可用的有声帧时返回 null。
///
/// 用来区分系统朗读里的男声与女声：成年女声的基频通常在 165 Hz 以上，男声在 165 Hz 以下。
double? medianPitch(Uint8List wav) {
  final d = ByteData.sublistView(wav);
  if (wav.length < 44 || String.fromCharCodes(wav.sublist(0, 4)) != 'RIFF') return null;
  var pos = 12, rate = 0, channels = 1, bits = 16;
  Float32List? samples;
  while (pos + 8 <= wav.length) {
    final id = String.fromCharCodes(wav.sublist(pos, pos + 4));
    final size = d.getUint32(pos + 4, Endian.little);
    if (id == 'fmt ') {
      channels = d.getUint16(pos + 10, Endian.little);
      rate = d.getUint32(pos + 12, Endian.little);
      bits = d.getUint16(pos + 22, Endian.little);
    } else if (id == 'data') {
      if (bits != 16 || rate == 0) return null;
      final end = math.min(wav.length, pos + 8 + size);
      final n = (end - pos - 8) ~/ (2 * channels);
      samples = Float32List(n);
      for (var i = 0; i < n; i++) {
        samples[i] = d.getInt16(pos + 8 + i * 2 * channels, Endian.little) / 32768;
      }
      break;
    }
    pos += 8 + size + (size & 1);
  }
  if (samples == null || samples.isEmpty) return null;
  final frame = rate * 40 ~/ 1000, hop = rate * 20 ~/ 1000;
  final minLag = rate ~/ 400, maxLag = rate ~/ 60;
  var peak = 0.0;
  for (final s in samples) {
    peak = math.max(peak, s.abs());
  }
  final pitches = <double>[];
  for (var start = 0; start + frame + maxLag < samples.length; start += hop) {
    var energy = 0.0;
    for (var i = start; i < start + frame; i++) {
      energy += samples[i] * samples[i];
    }
    // 只看响度足够的帧（有声段）。
    if (math.sqrt(energy / frame) < peak * 0.12) continue;
    final r = Float64List(maxLag + 1);
    var best = 0.0;
    for (var lag = minLag; lag <= maxLag; lag++) {
      var c = 0.0, e2 = 0.0;
      for (var i = start; i < start + frame; i++) {
        c += samples[i] * samples[i + lag];
        e2 += samples[i + lag] * samples[i + lag];
      }
      r[lag] = c / math.sqrt(energy * e2 + 1e-12);
      best = math.max(best, r[lag]);
    }
    if (best < 0.6) continue;
    // 取第一个接近最高相关度的延迟（避免把两个周期当成一个，算出低一个八度的音高）。
    for (var lag = minLag; lag <= maxLag; lag++) {
      if (r[lag] >= best * 0.85 && (lag == maxLag || r[lag] >= r[lag + 1])) {
        pitches.add(rate / lag);
        break;
      }
    }
  }
  if (pitches.length < 3) return null;
  pitches.sort();
  return pitches[pitches.length ~/ 2];
}
