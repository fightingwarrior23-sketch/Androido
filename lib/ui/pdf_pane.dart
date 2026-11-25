import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import '../l10n/l10n.dart';

/// One PDF viewer with pinch-to-zoom, swipe/scroll and page buttons.
/// [onPage] reports the page in view (0-based) so Stamp knows what to flag.
class PdfPane extends StatefulWidget {
  final String path;
  final int initialPage;
  final ValueChanged<int> onPage;
  const PdfPane({super.key, required this.path, required this.initialPage, required this.onPage});

  @override
  State<PdfPane> createState() => PdfPaneState();
}

class PdfPaneState extends State<PdfPane> {
  final PdfViewerController controller = PdfViewerController();
  int page = 0; // 0-based
  int count = 0;

  @override
  void initState() {
    super.initState();
    page = widget.initialPage;
  }

  void goTo(int p0) {
    if (count == 0) return;
    final n = p0.clamp(0, count - 1);
    controller.goToPage(pageNumber: n + 1);
  }

  Future<void> _jumpDialog() async {
    final c = TextEditingController(text: '${page + 1}');
    final v = await showDialog<int>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(tr('Go to page')),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: '1 – $count'),
          onSubmitted: (s) => Navigator.pop(context, int.tryParse(s)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(context, int.tryParse(c.text)), child: Text(tr('OK'))),
        ],
      ),
    );
    if (v != null) goTo(v - 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(children: [
        PdfViewer.file(
          widget.path,
          controller: controller,
          params: PdfViewerParams(
            onViewerReady: (doc, ctrl) {
              setState(() => count = doc.pages.length);
              if (widget.initialPage > 0) ctrl.goToPage(pageNumber: widget.initialPage + 1);
            },
            onPageChanged: (n) {
              if (n == null) return;
              setState(() => page = n - 1);
              widget.onPage(n - 1);
            },
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 6,
          child: Center(
            child: Material(
              color: cs.surface.withOpacity(0.92),
              elevation: 3,
              borderRadius: BorderRadius.circular(24),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_left),
                  onPressed: page > 0 ? () => goTo(page - 1) : null,
                ),
                InkWell(
                  onTap: count > 0 ? _jumpDialog : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: Text('${page + 1} / ${count == 0 ? '…' : count}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.chevron_right),
                  onPressed: count > 0 && page < count - 1 ? () => goTo(page + 1) : null,
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
