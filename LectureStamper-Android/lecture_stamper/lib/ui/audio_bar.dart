import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../core/time_utils.dart';
import '../l10n/l10n.dart';

const List<double> kSpeeds = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3];

String _speedLabel(double s) => '${s == s.roundToDouble() ? s.toInt() : s}×';

const _tabular = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

/// The audio navigation bar: draggable timeline with stamp markers, an exact
/// time bubble while dragging, play / pause, skip 5 s and 10 s, speed, and an
/// optional End marker (where the video is cut).
class AudioBar extends StatefulWidget {
  final Duration position, total;
  final bool playing;
  final double speed;
  final List<double> marks;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onToggle;
  final ValueChanged<int> onSkip; // seconds, negative = back
  final ValueChanged<double> onSpeed;

  /// End marker: null = off (the video runs to the end of the audio).
  final double? endSec;
  final bool endLocked;
  final VoidCallback onEndToggle, onEndLock;
  final ValueChanged<double> onEndChanged;

  const AudioBar({
    super.key,
    required this.position,
    required this.total,
    required this.playing,
    required this.speed,
    required this.marks,
    required this.onSeek,
    required this.onToggle,
    required this.onSkip,
    required this.onSpeed,
    required this.endSec,
    required this.endLocked,
    required this.onEndToggle,
    required this.onEndLock,
    required this.onEndChanged,
  });

  @override
  State<AudioBar> createState() => _AudioBarState();
}

class _AudioBarState extends State<AudioBar> {
  double? _dragSec; // exact second under the finger while dragging the playhead

  double get _totalSec => widget.total.inMilliseconds / 1000;

  void _nudgeEnd(double d) {
    final cur = widget.endSec ?? _totalSec;
    final max = _totalSec > 0 ? _totalSec : cur + d;
    widget.onEndChanged((cur + d).clamp(0.0, max));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final posSec = widget.position.inMilliseconds / 1000;
    final shown = _dragSec ?? posSec;
    final endOn = widget.endSec != null;
    return Directionality(
      textDirection: TextDirection.ltr, // the timeline always runs left to right
      child: Material(
        elevation: 8,
        color: cs.surfaceContainer,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                  child: Timeline(
                    position: widget.position,
                    total: widget.total,
                    marks: widget.marks,
                    endSec: widget.endSec,
                    endLocked: widget.endLocked,
                    onSeek: widget.onSeek,
                    onDragSec: (v) => setState(() => _dragSec = v),
                    onEndChanged: widget.onEndChanged,
                    onEndLock: widget.onEndLock,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _dragSec != null ? cs.primaryContainer : cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${fmtTime(shown)} / ${fmtTime(_totalSec)}',
                    style: _tabular.copyWith(
                      fontSize: 13,
                      fontWeight: _dragSec != null ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  iconSize: 28,
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Back 10 s'),
                  icon: const Icon(Icons.replay_10),
                  onPressed: () => widget.onSkip(-10),
                ),
                IconButton(
                  iconSize: 28,
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Back 5 s'),
                  icon: const Icon(Icons.replay_5),
                  onPressed: () => widget.onSkip(-5),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  iconSize: 36,
                  tooltip: widget.playing ? tr('Pause') : tr('Play'),
                  icon: Icon(widget.playing ? Icons.pause : Icons.play_arrow),
                  onPressed: widget.onToggle,
                ),
                const SizedBox(width: 4),
                IconButton(
                  iconSize: 28,
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Forward 5 s'),
                  icon: const Icon(Icons.forward_5),
                  onPressed: () => widget.onSkip(5),
                ),
                IconButton(
                  iconSize: 28,
                  visualDensity: VisualDensity.compact,
                  tooltip: tr('Forward 10 s'),
                  icon: const Icon(Icons.forward_10),
                  onPressed: () => widget.onSkip(10),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<double>(
                  tooltip: tr('Speed'),
                  onSelected: widget.onSpeed,
                  itemBuilder: (_) => [
                    for (final v in kSpeeds)
                      CheckedPopupMenuItem(value: v, checked: v == widget.speed, child: Text(_speedLabel(v))),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outline),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_speedLabel(widget.speed), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
              // ---- End marker row
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                FilterChip(
                  avatar: Icon(Icons.content_cut, size: 18, color: endOn ? cs.onErrorContainer : null),
                  label: Text(tr('Cut the end')),
                  selected: endOn,
                  selectedColor: cs.errorContainer,
                  showCheckmark: false,
                  onSelected: (_) => widget.onEndToggle(),
                ),
                if (endOn) ...[
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: tr('End earlier by 1 s'),
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: widget.endLocked ? null : () => _nudgeEnd(-1),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      fmtTime(widget.endSec!),
                      style: _tabular.copyWith(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onErrorContainer),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: tr('End later by 1 s'),
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: widget.endLocked ? null : () => _nudgeEnd(1),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: widget.endLocked ? tr('Unlock the end') : tr('Lock the end'),
                    isSelected: widget.endLocked,
                    icon: const Icon(Icons.lock_open),
                    selectedIcon: const Icon(Icons.lock),
                    onPressed: widget.onEndLock,
                  ),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A big, easy-to-grab timeline. Tap or drag to jump; stamp markers are small
/// ticks. While dragging, a bubble shows the exact time. If the End marker is on
/// (and not locked) dragging near it moves the marker instead of the playhead;
/// double-tap the marker to lock / unlock it.
class Timeline extends StatefulWidget {
  final Duration position, total;
  final List<double> marks;
  final double? endSec;
  final bool endLocked;
  final ValueChanged<Duration> onSeek;
  final ValueChanged<double?> onDragSec;
  final ValueChanged<double> onEndChanged;
  final VoidCallback onEndLock;
  const Timeline({
    super.key,
    required this.position,
    required this.total,
    required this.marks,
    required this.endSec,
    required this.endLocked,
    required this.onSeek,
    required this.onDragSec,
    required this.onEndChanged,
    required this.onEndLock,
  });

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  static const double pad = 14.0;
  static const double grab = 30.0; // how close a finger must be to the End marker

  double? _drag; // 0..1 while the playhead is being dragged
  double? _endDrag; // 0..1 while the End marker is being dragged
  Offset? _dtPos;

  double get _totalSec => widget.total.inMilliseconds / 1000;

  double get _frac {
    final t = widget.total.inMilliseconds;
    if (t <= 0) return 0;
    return (widget.position.inMilliseconds / t).clamp(0.0, 1.0);
  }

  double? get _endFrac {
    final e = widget.endSec;
    if (e == null || _totalSec <= 0) return null;
    return (e / _totalSec).clamp(0.0, 1.0);
  }

  double _fromX(double x, double width) => ((x - pad) / (width - 2 * pad)).clamp(0.0, 1.0);
  double _toX(double f, double width) => pad + (width - 2 * pad) * f;

  bool _nearEnd(double x, double width) {
    final ef = _endFrac;
    return ef != null && (x - _toX(ef, width)).abs() < grab;
  }

  void _commit(double f) =>
      widget.onSeek(Duration(milliseconds: (widget.total.inMilliseconds * f).round()));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (_, c) {
      final width = c.maxWidth;
      final firstMark = widget.marks.isEmpty ? null : widget.marks.reduce((a, b) => a < b ? a : b);
      final bubbleFrac = _endDrag ?? _drag;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (_nearEnd(d.localPosition.dx, width)) return;
          _commit(_fromX(d.localPosition.dx, width));
        },
        onDoubleTapDown: (d) => _dtPos = d.localPosition,
        onDoubleTap: () {
          final p = _dtPos;
          if (p != null && _nearEnd(p.dx, width)) widget.onEndLock();
        },
        onHorizontalDragStart: (d) {
          if (_nearEnd(d.localPosition.dx, width)) {
            if (widget.endLocked) return;
            setState(() => _endDrag = _fromX(d.localPosition.dx, width));
            widget.onDragSec(_endDrag! * _totalSec);
          } else {
            setState(() => _drag = _fromX(d.localPosition.dx, width));
            widget.onDragSec(_drag! * _totalSec);
          }
        },
        onHorizontalDragUpdate: (d) {
          final f = _fromX(d.localPosition.dx, width);
          if (_endDrag != null) {
            setState(() => _endDrag = f);
            widget.onDragSec(f * _totalSec);
            widget.onEndChanged(f * _totalSec);
          } else if (_drag != null) {
            setState(() => _drag = f);
            widget.onDragSec(f * _totalSec);
          }
        },
        onHorizontalDragEnd: (_) {
          final f = _drag;
          setState(() {
            _drag = null;
            _endDrag = null;
          });
          widget.onDragSec(null);
          if (f != null) _commit(f);
        },
        onHorizontalDragCancel: () {
          setState(() {
            _drag = null;
            _endDrag = null;
          });
          widget.onDragSec(null);
        },
        child: SizedBox(
          height: 52,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _TimelinePainter(
                  frac: _drag ?? _frac,
                  marks: widget.marks,
                  totalSec: _totalSec,
                  beginSec: firstMark,
                  endFrac: _endDrag ?? _endFrac,
                  endLocked: widget.endLocked,
                  track: cs.surfaceContainerHighest,
                  played: cs.primary,
                  mark: cs.tertiary,
                  thumb: cs.primary,
                  endColor: cs.error,
                  dim: cs.surface.withOpacity(0.55),
                  dragging: _drag != null,
                ),
              ),
            ),
            if (bubbleFrac != null)
              Positioned(
                left: (_toX(bubbleFrac, width) - 34).clamp(0.0, width - 68),
                top: -30,
                child: Container(
                  width: 68,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: _endDrag != null ? cs.error : cs.inverseSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    fmtTime(bubbleFrac * _totalSec),
                    style: _tabular.copyWith(
                      color: _endDrag != null ? cs.onError : cs.onInverseSurface,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

class _TimelinePainter extends CustomPainter {
  final double frac, totalSec;
  final double? beginSec, endFrac;
  final bool endLocked;
  final List<double> marks;
  final Color track, played, mark, thumb, endColor, dim;
  final bool dragging;
  _TimelinePainter({
    required this.frac,
    required this.marks,
    required this.totalSec,
    required this.beginSec,
    required this.endFrac,
    required this.endLocked,
    required this.track,
    required this.played,
    required this.mark,
    required this.thumb,
    required this.endColor,
    required this.dim,
    required this.dragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 14.0;
    final left = pad, right = size.width - pad, cy = size.height / 2;
    final w = right - left;
    final bar = Paint()..strokeCap = StrokeCap.round..strokeWidth = 8;
    canvas.drawLine(Offset(left, cy), Offset(right, cy), bar..color = track);
    canvas.drawLine(Offset(left, cy), Offset(left + w * frac, cy), bar..color = played);
    if (totalSec > 0) {
      // the parts that will not be in the video: before the first stamp, after End
      final cut = Paint()..color = dim..strokeWidth = 8..strokeCap = StrokeCap.butt;
      if (beginSec != null && beginSec! > 0) {
        final bx = left + w * (beginSec! / totalSec).clamp(0.0, 1.0);
        canvas.drawLine(Offset(left, cy), Offset(bx, cy), cut);
      }
      if (endFrac != null) {
        canvas.drawLine(Offset(left + w * endFrac!, cy), Offset(right, cy), cut);
      }
      final m = Paint()..color = mark..strokeWidth = 3..strokeCap = StrokeCap.round;
      for (final t in marks) {
        final x = left + w * (t / totalSec).clamp(0.0, 1.0);
        canvas.drawLine(Offset(x, cy - 14), Offset(x, cy - 6), m);
      }
    }
    if (endFrac != null) {
      final x = left + w * endFrac!;
      final e = Paint()..color = endColor..strokeWidth = endLocked ? 5 : 4..strokeCap = StrokeCap.round;
      canvas.drawLine(Offset(x, cy - 22), Offset(x, cy + 22), e);
      // a head on the marker, like a second playhead (filled when locked)
      final head = Paint()
        ..color = endColor
        ..style = endLocked ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(Offset(x, cy - 22), 7, head);
    }
    canvas.drawCircle(Offset(left + w * frac, cy), dragging ? 15 : 12, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(_TimelinePainter o) =>
      o.frac != frac ||
      o.marks != marks ||
      o.totalSec != totalSec ||
      o.dragging != dragging ||
      o.endFrac != endFrac ||
      o.endLocked != endLocked ||
      o.beginSec != beginSec;
}
