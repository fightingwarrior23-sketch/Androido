import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../core/project.dart';
import '../l10n/l10n.dart';
import '../services/native.dart';
import '../services/settings.dart';
import '../services/slide_renderer.dart';

/// Export button: asks for name / folder / size, draws the slides, makes the MP4.
Future<void> runExport(BuildContext context, Project pr) async {
  final s = AppSettings.i;
  void say(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  if (pr.book.stamps.isEmpty) return say(tr('Stamp at least one slide first.'));
  if (!File(pr.audio.path).existsSync()) return say(tr('The audio file was not found.'));
  for (final r in pr.pdfs) {
    if (!File(r.path).existsSync()) return say(tr('A PDF was not found: {name}', {'name': p.basename(r.path)}));
  }

  // ---- options
  final nameC = TextEditingController(text: pr.name.isEmpty ? 'lecture' : pr.name);
  final folderC = TextEditingController(text: pr.exportFolder.isNotEmpty ? pr.exportFolder : s.exportFolder);
  var kbps = s.videoKbps;
  final go = await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (ctx, setD) => AlertDialog(
        title: Text(tr('Export video')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: nameC, decoration: InputDecoration(labelText: tr('File name'))),
            const SizedBox(height: 8),
            TextField(
              controller: folderC,
              decoration: InputDecoration(
                labelText: tr('Folder inside Movies'),
                helperText: tr('Leave empty to save in Movies.'),
              ),
            ),
            const SizedBox(height: 12),
            Text(tr('Video size')),
            const SizedBox(height: 4),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 300, label: Text(tr('Smallest'))),
                ButtonSegment(value: 500, label: Text(tr('Balanced'))),
                ButtonSegment(value: 1000, label: Text(tr('Sharpest'))),
              ],
              selected: {kbps},
              onSelectionChanged: (v) => setD(() => kbps = v.first),
            ),
            const SizedBox(height: 12),
            Text(tr('Keep the app open while the video is made.'),
                style: Theme.of(ctx).textTheme.bodySmall),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Export'))),
        ],
      ),
    ),
  );
  if (go != true || !context.mounted) return;
  final safe = nameC.text.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  pr.exportFolder = folderC.text.trim();
  s.exportFolder = pr.exportFolder;
  s.videoKbps = kbps;

  // ---- progress dialog
  final progress = ValueNotifier<double>(0);
  final phase = ValueNotifier<String>(tr('Drawing the slides…'));
  var cancelled = false;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(tr('Making the video')),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (_, v, __) => Column(mainAxisSize: MainAxisSize.min, children: [
            ValueListenableBuilder<String>(
              valueListenable: phase,
              builder: (_, t, __) => Text(t),
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: v),
            const SizedBox(height: 6),
            Text('${(v * 100).round()}%'),
          ]),
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelled = true;
              Native.cancelExport();
            },
            child: Text(tr('Cancel')),
          ),
        ],
      ),
    ),
  );

  final tmp = await getTemporaryDirectory();
  final slidesDir = Directory(p.join(tmp.path, 'stamper_slides'));
  if (slidesDir.existsSync()) slidesDir.deleteSync(recursive: true);
  slidesDir.createSync(recursive: true);
  final renderer = SlideRenderer(pr.pdfs.map((e) => e.path).toList());
  String? result, error;
  try {
    await WakelockPlus.enable();
    final segs = pr.book.segments();
    final slides = <Map<String, Object>>[];
    for (var i = 0; i < segs.length; i++) {
      if (cancelled) throw 'cancelled';
      final f = await renderer.render(segs[i].pages, slidesDir, i);
      slides.add({'start': segs[i].start, 'path': f.path});
      progress.value = 0.3 * (i + 1) / segs.length;
    }
    await renderer.dispose();
    if (cancelled) throw 'cancelled';
    phase.value = tr('Encoding the video…');
    Native.onProgress = (v) => progress.value = 0.3 + 0.7 * v;
    result = await Native.export(
      slides: slides,
      audio: pr.audio.path,
      name: safe.isEmpty ? 'lecture' : safe,
      folder: pr.exportFolder,
      kbps: kbps,
    );
  } catch (e) {
    final msg = '$e';
    error = (cancelled || msg.contains('cancelled')) ? 'cancelled' : msg;
  } finally {
    Native.onProgress = null;
    await renderer.dispose();
    await WakelockPlus.disable();
    try {
      slidesDir.deleteSync(recursive: true);
    } catch (_) {}
  }

  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop(); // progress dialog
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(error == null ? tr('Video ready') : error == 'cancelled' ? tr('Cancelled') : tr('Export failed')),
      content: Text(error == null
          ? tr('Saved to {path}', {'path': result ?? ''})
          : error == 'cancelled'
              ? tr('The unfinished file was deleted.')
              : error),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('OK')))],
    ),
  );
}
