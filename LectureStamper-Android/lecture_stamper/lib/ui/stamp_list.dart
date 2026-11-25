import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/models.dart';
import '../core/project.dart';
import '../core/time_utils.dart';
import '../l10n/l10n.dart';

/// Bottom panel with every stamp: jump to it, edit it, delete it, undo.
Future<void> showStampList(
  BuildContext context, {
  required Project project,
  required void Function(Stamp) onJump,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _StampListBody(
        project: project,
        scroll: scroll,
        onJump: (s) {
          Navigator.pop(ctx);
          onJump(s);
        },
        onChanged: onChanged,
      ),
    ),
  );
}

class _StampListBody extends StatefulWidget {
  final Project project;
  final ScrollController scroll;
  final void Function(Stamp) onJump;
  final VoidCallback onChanged;
  const _StampListBody({required this.project, required this.scroll, required this.onJump, required this.onChanged});

  @override
  State<_StampListBody> createState() => _StampListBodyState();
}

class _StampListBodyState extends State<_StampListBody> {
  Project get pr => widget.project;

  Future<void> _edit(Stamp s) async {
    final tc = TextEditingController(text: fmtTime(s.seconds));
    final pc = TextEditingController(text: '${s.page + 1}');
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(tr('Edit stamp')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: tc,
              decoration: InputDecoration(labelText: tr('Time (m:ss or h:mm:ss)')),
            ),
            TextField(
              controller: pc,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: tr('Page')),
            ),
            if (err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err!, style: const TextStyle(color: Colors.red))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(
              onPressed: () {
                try {
                  final t = parseTime(tc.text);
                  final pg = int.tryParse(pc.text);
                  if (t == null || pg == null || pg < 1) throw const FormatException();
                  final updated = s.copyWith(seconds: t, page: pg - 1);
                  if (!pr.book.edit(s, updated)) {
                    setD(() => err = tr('That stamp already exists.'));
                    return;
                  }
                  Navigator.pop(ctx, true);
                } on FormatException {
                  setD(() => err = tr('Cannot read this time or page.'));
                }
              },
              child: Text(tr('OK')),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      widget.onChanged();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final stamps = pr.book.stamps;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          Expanded(child: Text(tr('Stamps ({n})', {'n': stamps.length}), style: Theme.of(context).textTheme.titleMedium)),
          TextButton.icon(
            onPressed: pr.book.canUndo
                ? () {
                    pr.book.undo();
                    widget.onChanged();
                    setState(() {});
                  }
                : null,
            icon: const Icon(Icons.undo),
            label: Text(tr('Undo')),
          ),
        ]),
      ),
      Expanded(
        child: stamps.isEmpty
            ? Center(child: Text(tr('No stamps yet. Tap the Stamp button while a slide is on screen.'), textAlign: TextAlign.center))
            : ListView.builder(
                controller: widget.scroll,
                itemCount: stamps.length,
                itemBuilder: (_, i) {
                  final s = stamps[i];
                  final pdfName = s.pdf < pr.pdfs.length ? p.basenameWithoutExtension(pr.pdfs[s.pdf].path) : '?';
                  return ListTile(
                    leading: Text(fmtTime(s.seconds), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    title: Text(tr('Page {n}', {'n': s.page + 1})),
                    subtitle: Text(pdfName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => widget.onJump(s),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(icon: const Icon(Icons.edit), tooltip: tr('Edit'), onPressed: () => _edit(s)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: tr('Delete'),
                        onPressed: () {
                          pr.book.delete(s);
                          widget.onChanged();
                          setState(() {});
                        },
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}
