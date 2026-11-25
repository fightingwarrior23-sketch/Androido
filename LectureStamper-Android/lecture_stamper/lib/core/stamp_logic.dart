import 'models.dart';

/// All stamp rules live here, with no Flutter or platform code, so the same
/// logic is mirrored in Python (tools/mirror/stamp_logic.py) and tested.
class StampBook {
  final List<Stamp> _stamps = [];

  /// Undo history: each entry is a full copy of the list before a change.
  final List<List<Stamp>> _undo = [];

  List<Stamp> get stamps => List.unmodifiable(_stamps);
  bool get canUndo => _undo.isNotEmpty;

  StampBook([Iterable<Stamp> initial = const []]) {
    _stamps.addAll(initial);
    _sort();
  }

  void _sort() {
    _stamps.sort((a, b) {
      final t = a.seconds.compareTo(b.seconds);
      if (t != 0) return t;
      final p = a.pdf.compareTo(b.pdf);
      return p != 0 ? p : a.page.compareTo(b.page);
    });
  }

  void _remember() {
    _undo.add(List<Stamp>.of(_stamps));
    if (_undo.length > 100) _undo.removeAt(0);
  }

  /// Stamp rules:
  /// * single view  -> [left] is the page on screen.
  /// * split screen -> [target] says left, right or both.
  /// Returns the stamps really added (exact duplicates are skipped).
  List<Stamp> stamp({
    required double seconds,
    required bool split,
    required (int pdf, int page) left,
    (int pdf, int page)? right,
    StampTarget target = StampTarget.left,
  }) {
    final wanted = <(int, int)>[];
    if (!split || right == null) {
      wanted.add(left);
    } else {
      if (target == StampTarget.left || target == StampTarget.both) {
        wanted.add(left);
      }
      if (target == StampTarget.right || target == StampTarget.both) {
        wanted.add(right);
      }
    }
    final s = seconds < 0 ? 0.0 : seconds;
    final added = <Stamp>[];
    for (final w in wanted) {
      final st = Stamp(w.$1, w.$2, s);
      if (_stamps.any((x) => x.sameAs(st)) || added.any((x) => x.sameAs(st))) {
        continue;
      }
      added.add(st);
    }
    if (added.isEmpty) return added;
    _remember();
    _stamps.addAll(added);
    _sort();
    return added;
  }

  void delete(Stamp s) {
    final i = _stamps.indexWhere((x) => x.sameAs(s));
    if (i < 0) return;
    _remember();
    _stamps.removeAt(i);
  }

  /// Change a stamp's time (and optionally page). Returns false if it would
  /// duplicate another stamp.
  bool edit(Stamp old, Stamp updated) {
    final i = _stamps.indexWhere((x) => x.sameAs(old));
    if (i < 0) return false;
    final clash = _stamps
        .asMap()
        .entries
        .any((e) => e.key != i && e.value.sameAs(updated));
    if (clash) return false;
    _remember();
    _stamps[i] = updated;
    _sort();
    return true;
  }

  /// Move a stamp by [delta] seconds (never below 0:00). Returns false if
  /// nothing moved or it would land on an identical stamp.
  bool nudge(Stamp s, double delta) {
    final t = s.seconds + delta;
    final nt = t < 0 ? 0.0 : t;
    if ((nt - s.seconds).abs() < 0.0005) return false;
    return edit(s, s.copyWith(seconds: nt));
  }

  /// Undo the last change (add, delete or edit). Returns false if none.
  bool undo() {
    if (_undo.isEmpty) return false;
    final prev = _undo.removeLast();
    _stamps
      ..clear()
      ..addAll(prev);
    return true;
  }

  /// A PDF was removed: drop its stamps and renumber the later PDFs.
  void removePdf(int index) {
    _remember();
    _stamps.removeWhere((s) => s.pdf == index);
    for (var i = 0; i < _stamps.length; i++) {
      final s = _stamps[i];
      if (s.pdf > index) _stamps[i] = s.copyWith(pdf: s.pdf - 1);
    }
  }

  void clear() {
    if (_stamps.isEmpty) return;
    _remember();
    _stamps.clear();
  }

  /// Stamps of one page, in time order.
  List<Stamp> forPage(int pdf, int page) =>
      _stamps.where((s) => s.pdf == pdf && s.page == page).toList();

  // ------------------------------------------------------------- video maths

  /// Group same-time stamps (desktop: group_cues with "together" on).
  List<(double, List<(int, int)>)> groups() {
    final out = <(double, List<(int, int)>)>[];
    for (final s in _stamps) {
      if (out.isNotEmpty && (out.last.$1 - s.seconds).abs() < 0.0005) {
        out.last.$2.add((s.pdf, s.page));
      } else {
        out.add((s.seconds, [(s.pdf, s.page)]));
      }
    }
    return out;
  }

  /// Slide timeline for the export. The first group always starts at 0:00 and
  /// the last one stays until the audio ends (end == null).
  List<Segment> segments() {
    final g = groups();
    final segs = <Segment>[];
    for (var i = 0; i < g.length; i++) {
      final start = i == 0 ? 0.0 : g[i].$1;
      final end = i + 1 < g.length ? g[i + 1].$1 : null;
      segs.add(Segment(start, end, g[i].$2));
    }
    return segs;
  }

  /// Slide timeline for the trimmed export: the video begins at the first
  /// stamp (everything before it is dropped) and, if [endAt] is given, is cut
  /// there. Stamps at or after [endAt] are ignored. Times are absolute
  /// (audio seconds); the first segment's start is the begin time.
  List<Segment> trimmedSegments({double? endAt}) {
    final g = groups().where((e) => endAt == null || e.$1 < endAt).toList();
    final segs = <Segment>[];
    for (var i = 0; i < g.length; i++) {
      final end = i + 1 < g.length ? g[i + 1].$1 : endAt;
      segs.add(Segment(g[i].$1, end, g[i].$2));
    }
    return segs;
  }
}

/// n slides -> number of slides in each row (desktop: grid_layout).
List<int> gridLayout(int n) {
  var cols = 1;
  while (cols * cols < n) {
    cols++;
  }
  final rows = <int>[];
  var left = n;
  while (left > 0) {
    rows.add(left < cols ? left : cols);
    left -= cols;
  }
  if (n == 2) return [2];
  return rows;
}

/// Rectangles for n slides; a shorter last row is centred (desktop: grid_rects).
List<Rect4> gridRects(int n,
    {double width = 1920, double height = 1080, double gap = 8}) {
  final rows = gridLayout(n);
  final cols = rows.reduce((a, b) => a > b ? a : b);
  final cw = width / cols;
  final ch = height / rows.length;
  final rects = <Rect4>[];
  for (var r = 0; r < rows.length; r++) {
    final k = rows[r];
    final xOff = (cols - k) * cw / 2;
    for (var c = 0; c < k; c++) {
      final x0 = xOff + c * cw;
      final y0 = r * ch;
      rects.add(Rect4(x0 + gap, y0 + gap, x0 + cw - gap, y0 + ch - gap));
    }
  }
  return rects;
}
