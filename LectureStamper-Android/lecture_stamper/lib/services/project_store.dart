import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/models.dart';
import '../core/project.dart';

class ProjectInfo {
  final String id;
  final String name;
  final int stamps;
  final DateTime modified;
  const ProjectInfo(this.id, this.name, this.stamps, this.modified);
}

/// Projects live in the app's private folder as small JSON files and are
/// auto-saved. Paths keep a relative fallback (relative to the audio's folder)
/// so a moved folder can still be found, like the desktop .lvm file.
class ProjectStore {
  static Future<Directory> _dir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory(p.join(docs.path, 'projects'));
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String newId() => DateTime.now().millisecondsSinceEpoch.toString();

  static Future<List<ProjectInfo>> list() async {
    final d = await _dir();
    final out = <ProjectInfo>[];
    await for (final e in d.list()) {
      if (e is! File || !e.path.endsWith('.json')) continue;
      try {
        final j = jsonDecode(await e.readAsString()) as Map<String, dynamic>;
        out.add(ProjectInfo(
          p.basenameWithoutExtension(e.path),
          (j['name'] ?? '') as String,
          ((j['stamps'] as List?) ?? []).length,
          (await e.stat()).modified,
        ));
      } catch (_) {}
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  static Future<void> save(String id, Project pr) async {
    final d = await _dir();
    final f = File(p.join(d.path, '$id.json'));
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(withRel(pr).toJson()));
    await tmp.rename(f.path);
  }

  static Future<Project?> load(String id) async {
    final d = await _dir();
    final f = File(p.join(d.path, '$id.json'));
    if (!await f.exists()) return null;
    try {
      return Project.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> delete(String id) async {
    final d = await _dir();
    final f = File(p.join(d.path, '$id.json'));
    if (await f.exists()) await f.delete();
  }

  /// Fills in the `rel` part of every file reference.
  static Project withRel(Project pr) {
    if (pr.audio.path.isEmpty) return pr;
    final base = p.dirname(pr.audio.path);
    pr.audio = FileRef(pr.audio.path, p.basename(pr.audio.path));
    pr.pdfs = pr.pdfs
        .map((r) => FileRef(r.path, r.path.isEmpty ? '' : p.relative(r.path, from: base)))
        .toList();
    return pr;
  }

  /// After loading: re-find files that moved. Returns what is still missing.
  static List<String> resolve(Project pr) {
    final missing = <String>[];
    String fix(FileRef r, String? base) {
      if (r.path.isNotEmpty && File(r.path).existsSync()) return r.path;
      if (base != null && r.rel.isNotEmpty) {
        final q = p.normalize(p.join(base, r.rel));
        if (File(q).existsSync()) return q;
      }
      return r.path;
    }

    final audioPath = fix(pr.audio, null);
    pr.audio = FileRef(audioPath, pr.audio.rel);
    String? base;
    if (File(audioPath).existsSync()) base = p.dirname(audioPath);
    pr.pdfs = pr.pdfs.map((r) => FileRef(fix(r, base), r.rel)).toList();
    if (!File(pr.audio.path).existsSync()) missing.add(pr.audio.path);
    for (final r in pr.pdfs) {
      if (!File(r.path).existsSync()) missing.add(r.path);
    }
    return missing;
  }
}
