/// Time helpers, ported from the desktop program (core.py).

/// '90' -> 90s, '1:30' -> 90s, '1:02:03' -> 3723s. Returns null if empty.
/// Throws FormatException for unreadable text.
double? parseTime(String text) {
  text = text.trim();
  if (text.isEmpty) return null;
  final parts = text.split(':');
  if (parts.length > 3) throw FormatException(text);
  final nums = parts.map((p) {
    final s = p.trim();
    if (s.isEmpty) return 0.0;
    final v = double.tryParse(s);
    if (v == null || v < 0) throw FormatException(text);
    return v;
  }).toList();
  if ((nums.length > 1 && nums.last >= 60) ||
      (nums.length == 3 && nums[1] >= 60)) {
    throw FormatException(text);
  }
  var total = 0.0;
  for (final n in nums) {
    total = total * 60 + n;
  }
  return total;
}

/// 83 -> '1:23', 3723 -> '1:02:03'
String fmtTime(double sec) {
  final s = sec.round();
  final h = s ~/ 3600;
  final rem = s % 3600;
  final m = rem ~/ 60;
  final ss = rem % 60;
  final two = ss.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$two';
  return '$m:$two';
}
