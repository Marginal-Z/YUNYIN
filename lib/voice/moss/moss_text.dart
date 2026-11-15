/// 送给 MOSS-TTS-Nano 之前整理文字。
///
/// 模型按字发音，阿拉伯数字、百分号、时间等容易读错或跳过（官方 Python 版用 WeTextProcessing 做这一步），
/// 这里把常见写法转成汉字读法；去掉 Markdown 标记与表情；句末没有标点时补一个句号（没有句末标点时模型容易拖长或乱读结尾）。
String mossText(String text) {
  var s = text;
  // Markdown 与表情。
  s = s.replaceAll(RegExp(r'```[\s\S]*?```'), '');
  s = s.replaceAll(RegExp(r'[*_`#>|~]+'), '');
  s = s.replaceAll(RegExp(r'\[([^\]]*)\]\([^)]*\)'), r'$1');
  s = s.replaceAll(RegExp(r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true), '');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();

  // 日期与时间。
  s = s.replaceAllMapped(RegExp(r'(\d{4})年'), (m) => '${_digits(m[1]!)}年');
  s = s.replaceAllMapped(RegExp(r'(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})'), (m) => '${_digits(m[1]!)}年${_int(m[2]!)}月${_int(m[3]!)}日');
  s = s.replaceAllMapped(RegExp(r'(?<!\d)(\d{1,2}):(\d{2})(?::(\d{2}))?(?!\d)'), (m) {
    final min = int.parse(m[2]!);
    final sec = m[3] == null ? '' : '${_int(m[3]!)}秒';
    return '${_int(m[1]!)}点${min == 0 ? (sec.isEmpty ? '整' : '零分') : '${min < 10 ? '零' : ''}${_int(m[2]!)}分'}$sec';
  });
  // 百分数、分数、范围、小数、序号。
  s = s.replaceAllMapped(RegExp(r'(-?\d+(?:\.\d+)?)\s*[%％]'), (m) => '百分之${_number(m[1]!)}');
  s = s.replaceAllMapped(RegExp(r'(?<![\d.])(\d+)/(\d+)(?![\d.])'), (m) => '${_int(m[2]!)}分之${_int(m[1]!)}');
  s = s.replaceAllMapped(RegExp(r'(\d+(?:\.\d+)?)\s*[-~～]\s*(\d+(?:\.\d+)?)'), (m) => '${_number(m[1]!)}到${_number(m[2]!)}');
  s = s.replaceAllMapped(RegExp(r'[vV](\d+(?:\.\d+)+)'), (m) => '版本${m[1]!.split('.').map(_int).join('点')}');
  s = s.replaceAllMapped(RegExp(r'\d+(?:\.\d+){2,}'), (m) => m[0]!.split('.').map(_int).join('点'));
  // 其余数字：很长的数字（电话、编号）逐位读，其他按数值读。
  s = s.replaceAllMapped(RegExp(r'-?\d+(?:\.\d+)?'), (m) {
    final v = m[0]!;
    final digits = v.replaceAll(RegExp(r'[^0-9]'), '');
    if (!v.contains('.') && (digits.length > 9 || (digits.length > 1 && digits.startsWith('0')))) return _digits(v);
    return _number(v);
  });
  // 常见符号。
  s = s.replaceAll('&', '和').replaceAll('+', '加').replaceAll('=', '等于').replaceAll('℃', '摄氏度').replaceAll('°', '度');
  s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return s;
  if (!RegExp(r'[。！？!?.…~～」』”"）)]$').hasMatch(s)) s = '$s。';
  return s;
}

const _cn = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

String _digits(String s) => s.split('').map((c) => c == '-' ? '杠' : (int.tryParse(c) == null ? c : _cn[int.parse(c)])).join();

String _number(String s) {
  var neg = false;
  if (s.startsWith('-')) {
    neg = true;
    s = s.substring(1);
  }
  final parts = s.split('.');
  var out = _int(parts[0]);
  if (parts.length > 1 && parts[1].isNotEmpty) out = '$out点${_digits(parts[1])}';
  return neg ? '负$out' : out;
}

/// 整数的汉字读法（到千亿）；“10”读作“十”，“2”在量词前仍读“二”（不区分“两”，听感差别很小）。
String _int(String s) {
  final n = int.tryParse(s);
  if (n == null) return _digits(s);
  if (n == 0) return '零';
  if (n >= 1000000000000) return _digits(s);
  String section(int v) {
    // 0–9999。
    const units = ['', '十', '百', '千'];
    final buf = StringBuffer();
    var zero = false;
    for (var i = 3; i >= 0; i--) {
      final p = [1, 10, 100, 1000][i];
      final d = v ~/ p % 10;
      if (d == 0) {
        if (buf.isNotEmpty) zero = true;
        continue;
      }
      if (zero) {
        buf.write('零');
        zero = false;
      }
      buf.write('${_cn[d]}${units[i]}');
    }
    return buf.toString();
  }

  final yi = n ~/ 100000000, wan = n ~/ 10000 % 10000, rest = n % 10000;
  final buf = StringBuffer();
  if (yi > 0) buf.write('${section(yi)}亿');
  if (wan > 0) {
    if (yi > 0 && wan < 1000) buf.write('零');
    buf.write('${section(wan)}万');
  } else if (yi > 0 && rest > 0) {
    buf.write('零');
  }
  if (rest > 0) {
    if ((yi > 0 || wan > 0) && rest < 1000 && wan > 0) buf.write('零');
    buf.write(section(rest));
  }
  var out = buf.toString();
  // “一十二”读作“十二”。
  if (out.startsWith('一十')) out = out.substring(1);
  return out;
}
