import 'dart:io';
import 'dart:ui' as ui;
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';
import '../core/stamp_logic.dart';

/// Draws one video frame (1920x1080) for a group of pages: one page fills the
/// picture, several pages share it side by side or in a grid (like the desktop
/// "Same-time slides together" option).
class SlideRenderer {
  static const int w = 1920, h = 1080;
  final List<String> pdfPaths;
  final Map<int, PdfDocument> _docs = {};

  SlideRenderer(this.pdfPaths);

  Future<PdfDocument> _doc(int i) async =>
      _docs[i] ??= await PdfDocument.openFile(pdfPaths[i]);

  Future<void> dispose() async {
    for (final d in _docs.values) {
      await d.dispose();
    }
    _docs.clear();
  }

  /// Renders [pages] ((pdf, page) pairs, 0-based) into a PNG file.
  Future<File> render(List<(int, int)> pages, Directory outDir, int n) async {
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF));
    final rects = gridRects(pages.length, width: w.toDouble(), height: h.toDouble());
    for (var k = 0; k < pages.length; k++) {
      final doc = await _doc(pages[k].$1);
      final pi = pages[k].$2;
      if (pi < 0 || pi >= doc.pages.length) continue;
      final page = doc.pages[pi];
      final r = rects[k];
      final scale = (r.w / page.width) < (r.h / page.height) ? r.w / page.width : r.h / page.height;
      final pw = (page.width * scale).round().clamp(1, 4000);
      final ph = (page.height * scale).round().clamp(1, 4000);
      final img = await page.render(
        width: pw,
        height: ph,
        fullWidth: pw.toDouble(),
        fullHeight: ph.toDouble(),
      );
      if (img == null) continue;
      final uiImg = await img.createImage();
      canvas.drawImage(
          uiImg, ui.Offset(r.x0 + (r.w - pw) / 2, r.y0 + (r.h - ph) / 2), ui.Paint());
      uiImg.dispose();
      img.dispose();
    }
    final pic = rec.endRecording();
    final image = await pic.toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final f = File(p.join(outDir.path, 'slide_$n.png'));
    await f.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
    return f;
  }
}
