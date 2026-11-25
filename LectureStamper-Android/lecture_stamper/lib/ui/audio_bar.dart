import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import '../core/time_utils.dart';
import '../l10n/l10n.dart';

const List<double> kSpeeds = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.75, 3];

String _speedLabel(double s) => '${s == s.roundToDouble() ? s.toInt() : s}×';

/// The audio navigation bar: draggable timeline with stamp markers, time box,
/// play / pause, back 5 s, forward 5 s and speed.
class AudioBar extends StatelessWidget {
  final Duration position, total;
  final bool playing;
  final double speed;
  final List<double> marks;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onToggle, onBack, onForward;
  final ValueChanged<double> onSpeed;

  const AudioBar({
    super.key,
    required this.position,
    required this.total,
    required this.playing,
    required this.speed,
    required this.marks,
    required this.onSeek,
    required this.onToggle,
    required this.onBack,
    required this.onForward,
    required this.onSpeed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                    position: position,
                    total: total,
                    marks: marks,
                    onSeek: onSeek,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${fmtTime(position.inMilliseconds / 1000)} / ${fmtTime(total.inMilliseconds / 1000)}',
                    style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()], fontSize: 13),
                  ),
                ),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                  iconSize: 30,
                  tooltip: tr('Back 5 s'),
                  icon: const Icon(Icons.replay_5),
                  onPressed: onBack,
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  iconSize: 38,
                  tooltip: playing ? tr('Pause') : tr('Play'),
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: onToggle,
                ),
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 30,
                  tooltip: tr('Forward 5 s'),
                  icon: const Icon(Icons.forward_5),
                  onPressed: onForward,
                ),
                const SizedBox(width: 16),
                PopupMenuButton<double>(
                  tooltip: tr('Speed'),
                  onSelected: onSpeed,
                  itemBuilder: (_) => [
                    for (final v in kSpeeds)
                      CheckedPopupMenuItem(value: v, checked: v == speed, child: Text(_speedLabel(v))),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: cs.outline),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(_speedLabel(speed), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A big, easy-to-grab timeline. Tap or drag to jump; stamp markers are small ticks.
class Timeline extends StatefulWidget {
  final Duration position, total;
  final List<double> marks;
  final ValueChanged<Duration> onSeek;
  const Timeline({super.key, required this.position, required this.total, required this.marks, required this.onSeek});

  @override
  State<Timeline> createState() => _TimelineState();
}

class _TimelineState extends State<Timeline> {
  double? _drag; // 0..1 while the finger is down

  double get _frac {
    final t = widget.total.inMilliseconds;
    if (t <= 0) return 0;
    return (widget.position.inMilliseconds / t).clamp(0.0, 1.0);
  }

  double _fromX(double x, double width) => (x / width).clamp(0.0, 1.0);

  void _commit(double f) =>
      widget.onSeek(Duration(milliseconds: (widget.total.inMilliseconds * f).round()));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (_, c) {
      final width = c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) => _commit(_fromX(d.localPosition.dx, width)),
        onHorizontalDragStart: (d) => setState(() => _drag = _fromX(d.localPosition.dx, width)),
        onHorizontalDragUpdate: (d) => setState(() => _drag = _fromX(d.localPosition.dx, width)),
        onHorizontalDragEnd: (_) {
          final f = _drag;
          setState(() => _drag = null);
          if (f != null) _commit(f);
        },
        onHorizontalDragCancel: () => setState(() => _drag = null),
        child: SizedBox(
          height: 52,
          child: CustomPaint(
            size: Size(width, 52),
            painter: _TimelinePainter(
              frac: _drag ?? _frac,
              marks: widget.marks,
              totalSec: widget.total.inMilliseconds / 1000,
              track: cs.surfaceContainerHighest,
              played: cs.primary,
              mark: cs.tertiary,
              thumb: cs.primary,
              dragging: _drag != null,
            ),
          ),
        ),
      );
    });
  }
}

class _TimelinePainter extends CustomPainter {
  final double frac, totalSec;
  final List<double> marks;
  final Color track, played, mark, thumb;
  final bool dragging;
  _TimelinePainter({
    required this.frac,
    required this.marks,
    required this.totalSec,
    required this.track,
    required this.played,
    required this.mark,
    required this.thumb,
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
      final m = Paint()..color = mark..strokeWidth = 3..strokeCap = StrokeCap.round;
      for (final t in marks) {
        final x = left + w * (t / totalSec).clamp(0.0, 1.0);
        canvas.drawLine(Offset(x, cy - 14), Offset(x, cy - 6), m);
      }
    }
    canvas.drawCircle(Offset(left + w * frac, cy), dragging ? 15 : 12, Paint()..color = thumb);
  }

  @override
  bool shouldRepaint(_TimelinePainter o) =>
      o.frac != frac || o.marks != marks || o.totalSec != totalSec || o.dragging != dragging;
}
