import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/models.dart';
import '../core/project.dart';
import '../l10n/l10n.dart';
import '../services/project_store.dart';
import '../services/settings.dart';
import 'file_browser.dart';
import 'player_screen.dart';
import 'settings_screen.dart';

/// Recent projects, and the "new project" flow: audio first, then the first PDF.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<ProjectInfo>? _list;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final l = await ProjectStore.list();
    if (mounted) setState(() => _list = l);
  }

  Future<void> _newProject() async {
    final s = AppSettings.i;
    final audio = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => FileBrowserScreen(audio: true, title: tr('Choose the audio'))),
    );
    if (audio == null || !mounted) return;
    final pdf = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => FileBrowserScreen(audio: false, title: tr('Choose the first PDF'))),
    );
    if (pdf == null || !mounted) return;
    final pr = Project(
      name: p.basenameWithoutExtension(audio),
      audio: FileRef(audio),
      pdfs: [FileRef(pdf)],
      corner: s.corner,
      speed: s.speed,
      exportFolder: s.exportFolder,
      stampWhilePlaying: s.stampWhilePlaying,
    );
    final id = ProjectStore.newId();
    await ProjectStore.save(id, pr);
    await _play(id, pr);
  }

  Future<void> _open(ProjectInfo info) async {
    final pr = await ProjectStore.load(info.id);
    if (pr == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('This project cannot be opened.'))));
      return;
    }
    ProjectStore.resolve(pr);
    // help re-find PDFs that moved
    for (var i = 0; i < pr.pdfs.length; i++) {
      if (File(pr.pdfs[i].path).existsSync()) continue;
      if (!mounted) return;
      final pick = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('PDF not found')),
          content: Text(p.basename(pr.pdfs[i].path)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Skip'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Choose the file'))),
          ],
        ),
      );
      if (pick == true && mounted) {
        final path = await Navigator.push<String>(
          context,
          MaterialPageRoute(builder: (_) => FileBrowserScreen(audio: false, title: tr('Choose a PDF'))),
        );
        if (path != null) pr.pdfs[i] = FileRef(path);
      }
    }
    if (mounted) await _play(info.id, pr);
  }

  Future<void> _play(String id, Project pr) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(id: id, project: pr)));
    _refresh();
  }

  Future<void> _delete(ProjectInfo info) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('Delete this project?')),
        content: Text(tr('Your audio and PDFs are not touched.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete'))),
        ],
      ),
    );
    if (ok == true) {
      await ProjectStore.delete(info.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr('Lecture Stamper')),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: tr('Settings'),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newProject,
        icon: const Icon(Icons.add),
        label: Text(tr('New project')),
      ),
      body: list == null
          ? const Center(child: CircularProgressIndicator())
          : list.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      tr('No projects yet. Tap New project, choose the lecture audio, then the slides.'),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final e = list[i];
                    final d = e.modified;
                    return ListTile(
                      leading: const Icon(Icons.school, size: 32),
                      title: Text(e.name.isEmpty ? tr('Untitled') : e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${tr('Stamps ({n})', {'n': e.stamps})} · ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'),
                      onTap: () => _open(e),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: tr('Delete'),
                        onPressed: () => _delete(e),
                      ),
                    );
                  },
                ),
    );
  }
}
