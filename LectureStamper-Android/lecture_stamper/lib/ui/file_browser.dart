import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../l10n/l10n.dart';
import '../services/native.dart';
import '../services/settings.dart';

/// Picks one audio or PDF file. Two views: by folder, or everything in one list.
/// Pops with the chosen path.
class FileBrowserScreen extends StatefulWidget {
  final bool audio; // true = audio files, false = PDFs
  final String title;
  const FileBrowserScreen({super.key, required this.audio, required this.title});

  @override
  State<FileBrowserScreen> createState() => _FileBrowserScreenState();
}

class _FileBrowserScreenState extends State<FileBrowserScreen> with WidgetsBindingObserver {
  final s = AppSettings.i;
  bool _granted = false, _loading = true;
  String? _error;
  List<MediaFile> _files = [];
  String? _openGroup;
  String _query = '';

  String get kind => widget.audio ? 'audio' : 'pdf';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_granted) _load();
  }

  Future<void> _load({bool force = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final ok = await Native.ensureStorage();
      if (!ok) {
        setState(() {
          _granted = false;
          _loading = false;
        });
        return;
      }
      final idx = await Native.scan(force: force);
      setState(() {
        _granted = true;
        _files = widget.audio ? idx.audio : idx.pdf;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  List<MediaFile> _sorted(List<MediaFile> list) {
    final by = s.sortBy(kind), asc = s.sortAsc(kind);
    final l = list.where((f) => _query.isEmpty || f.name.toLowerCase().contains(_query.toLowerCase())).toList();
    l.sort((a, b) {
      final c = by == 'name'
          ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
          : a.modified.compareTo(b.modified);
      return asc ? c : -c;
    });
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final view = s.view(kind);
    return PopScope(
      canPop: _openGroup == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _openGroup != null) setState(() => _openGroup = null);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_openGroup ?? widget.title),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.sort),
              tooltip: tr('Sort'),
              onSelected: (v) {
                if (v == 'name' || v == 'date') s.setSortBy(kind, v);
                if (v == 'asc') s.setSortAsc(kind, true);
                if (v == 'desc') s.setSortAsc(kind, false);
                setState(() {});
              },
              itemBuilder: (_) => [
                CheckedPopupMenuItem(value: 'name', checked: s.sortBy(kind) == 'name', child: Text(tr('Name'))),
                CheckedPopupMenuItem(value: 'date', checked: s.sortBy(kind) == 'date', child: Text(tr('Date'))),
                const PopupMenuDivider(),
                CheckedPopupMenuItem(value: 'asc', checked: s.sortAsc(kind), child: Text(tr('Ascending'))),
                CheckedPopupMenuItem(value: 'desc', checked: !s.sortAsc(kind), child: Text(tr('Descending'))),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: tr('Scan again'),
              onPressed: () => _load(force: true),
            ),
          ],
        ),
        body: _body(view),
      ),
    );
  }

  Widget _body(String view) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (!_granted) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.folder_open, size: 56),
            const SizedBox(height: 12),
            Text(
              tr('Lecture Stamper needs access to your files to find your audio and PDFs.'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: Text(tr('Allow access'))),
          ]),
        ),
      );
    }
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(children: [
          Expanded(
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'folder', icon: const Icon(Icons.folder), label: Text(tr('By folder'))),
                ButtonSegment(value: 'all', icon: const Icon(Icons.list), label: Text(tr('Show all'))),
              ],
              selected: {view},
              onSelectionChanged: (v) => setState(() {
                s.setView(kind, v.first);
                _openGroup = null;
              }),
            ),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: TextField(
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search),
            hintText: tr('Search by name'),
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
      ),
      Expanded(child: view == 'all' || _query.isNotEmpty ? _fileList(_sorted(_files)) : _folderView()),
    ]);
  }

  Widget _folderView() {
    if (_openGroup != null) {
      return _fileList(_sorted(_files.where((f) => f.group == _openGroup).toList()));
    }
    final groups = <String, List<MediaFile>>{};
    for (final f in _files) {
      groups.putIfAbsent(f.group, () => []).add(f);
    }
    final names = groups.keys.toList();
    final by = s.sortBy(kind), asc = s.sortAsc(kind);
    int newest(String g) => groups[g]!.map((f) => f.modified).reduce((a, b) => a > b ? a : b);
    names.sort((a, b) {
      final c = by == 'name' ? a.toLowerCase().compareTo(b.toLowerCase()) : newest(a).compareTo(newest(b));
      return asc ? c : -c;
    });
    if (names.isEmpty) return Center(child: Text(tr('Nothing found.')));
    return ListView.builder(
      itemCount: names.length,
      itemBuilder: (_, i) => ListTile(
        leading: const Icon(Icons.folder, size: 32),
        title: Text(names[i]),
        subtitle: Text(tr('{n} files', {'n': groups[names[i]]!.length})),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => setState(() => _openGroup = names[i]),
      ),
    );
  }

  Widget _fileList(List<MediaFile> list) {
    if (list.isEmpty) return Center(child: Text(tr('Nothing found.')));
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (_, i) {
        final f = list[i];
        final d = DateTime.fromMillisecondsSinceEpoch(f.modified);
        final mb = f.size / (1024 * 1024);
        return ListTile(
          leading: Icon(widget.audio ? Icons.audiotrack : Icons.picture_as_pdf),
          title: Text(f.name, maxLines: 2, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            '${f.group} · ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} · ${mb.toStringAsFixed(1)} MB',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => Navigator.pop(context, f.path),
        );
      },
    );
  }
}

String pdfLabel(String path) => p.basenameWithoutExtension(path);
