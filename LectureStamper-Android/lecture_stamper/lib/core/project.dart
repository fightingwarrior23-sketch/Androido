import 'models.dart';
import 'stamp_logic.dart';

/// Everything saved in a project (pure data: no Flutter, no dart:io).
class Project {
  String name;
  FileRef audio;
  List<FileRef> pdfs;
  StampBook book;

  bool split;
  String corner; // topLeft | topRight | bottomLeft | bottomRight
  double? dragX, dragY; // 0..1 position if the button was dragged
  double speed;
  String exportFolder; // sub-folder inside Movies ('' = Movies itself)
  bool stampWhilePlaying; // false = pause-then-stamp (recommended)
  double position; // last audio position (seconds)
  List<int> lastPages; // last viewed page per PDF (0-based)

  Project({
    this.name = '',
    this.audio = const FileRef(''),
    List<FileRef>? pdfs,
    StampBook? book,
    this.split = false,
    this.corner = 'topRight',
    this.dragX,
    this.dragY,
    this.speed = 1.0,
    this.exportFolder = '',
    this.stampWhilePlaying = false,
    this.position = 0,
    List<int>? lastPages,
  })  : pdfs = pdfs ?? [],
        book = book ?? StampBook(),
        lastPages = lastPages ?? [];

  Map<String, dynamic> toJson() => {
        'app': 'LectureStamper',
        'version': 1,
        'name': name,
        'audio': audio.toJson(),
        'pdfs': pdfs.map((p) => p.toJson()).toList(),
        'stamps': book.stamps.map((s) => s.toJson()).toList(),
        'settings': {
          'split': split,
          'corner': corner,
          'dragX': dragX,
          'dragY': dragY,
          'speed': speed,
          'exportFolder': exportFolder,
          'stampWhilePlaying': stampWhilePlaying,
        },
        'position': position,
        'lastPages': lastPages,
      };

  factory Project.fromJson(Map<String, dynamic> j) {
    final st = (j['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    final pdfs = ((j['pdfs'] as List?) ?? [])
        .map((e) => FileRef.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final stamps = ((j['stamps'] as List?) ?? [])
        .map((e) => Stamp.fromJson((e as Map).cast<String, dynamic>()))
        .where((s) => s.pdf >= 0 && s.pdf < pdfs.length && s.page >= 0)
        .toList();
    return Project(
      name: (j['name'] ?? '') as String,
      audio: FileRef.fromJson((j['audio'] as Map?)?.cast<String, dynamic>()),
      pdfs: pdfs,
      book: StampBook(stamps),
      split: (st['split'] ?? false) as bool,
      corner: (st['corner'] ?? 'topRight') as String,
      dragX: (st['dragX'] as num?)?.toDouble(),
      dragY: (st['dragY'] as num?)?.toDouble(),
      speed: ((st['speed'] ?? 1.0) as num).toDouble(),
      exportFolder: (st['exportFolder'] ?? '') as String,
      stampWhilePlaying: (st['stampWhilePlaying'] ?? false) as bool,
      position: ((j['position'] ?? 0) as num).toDouble(),
      lastPages: ((j['lastPages'] as List?) ?? []).map((e) => (e as num).toInt()).toList(),
    );
  }

  /// Desktop Lecture Video Maker project (.lvm), one record, same-time slides
  /// together on. The desktop program resolves the paths itself.
  /// Phone paths will only be found on the desktop if the folders were copied
  /// along (the `rel` part is what makes that work).
  Map<String, dynamic> toLvm({String outputPath = ''}) {
    final times = <String, List<double>>{};
    for (final s in book.stamps) {
      times.putIfAbsent('${s.pdf},${s.page}', () => []).add(s.seconds);
    }
    return {
      'app': 'LectureVideoMaker',
      'version': 1,
      'rec_i': 0,
      'output': {'path': outputPath, 'rel': ''},
      'settings': {
        'fps': '2',
        'crf': '30',
        'multi': true,
        'rec_on': false,
        'grid_on': false,
        'hour_on': false,
        'hour': '1',
        'dead_on': false,
        'noise_on': false,
        'log_on': false,
      },
      'records': [
        {
          'pdfs': pdfs.map((p) => p.toJson()).toList(),
          'times': times,
          'cur': null,
          'audio': audio.toJson(),
          'cut_on': false,
          'cuts': <List<double>>[],
        }
      ],
    };
  }
}
