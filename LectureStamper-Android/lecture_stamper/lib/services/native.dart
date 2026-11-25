import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;

class MediaFile {
  final String path, name, folder;
  final int size, modified;
  const MediaFile(this.path, this.name, this.folder, this.size, this.modified);

  factory MediaFile.fromMap(Map m) => MediaFile(
        m['path'] as String,
        m['name'] as String,
        m['folder'] as String,
        (m['size'] as num).toInt(),
        (m['modified'] as num).toInt(),
      );

  /// Friendly folder name for the "by folder" view.
  String get group {
    final low = path.toLowerCase();
    if (low.contains('whatsapp')) return 'WhatsApp';
    if (low.contains('telegram')) return 'Telegram';
    return p.basename(folder);
  }
}

class MediaIndex {
  final List<MediaFile> audio, pdf;
  const MediaIndex(this.audio, this.pdf);
}

/// Bridge to the Kotlin side (file scan, video export, saving files).
class Native {
  static const _ch = MethodChannel('lecture_stamper/native');
  static void Function(double)? onProgress;
  static MediaIndex? _cache;

  static void init() {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'progress') {
        onProgress?.call((call.arguments as num).toDouble());
      }
      return null;
    });
  }

  /// Asks for file access. Android 11+ needs "All files access" so the app can
  /// read audio in folders like WhatsApp and PDFs anywhere.
  static Future<bool> ensureStorage() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) {
      // Android 10 and below: plain storage permission is enough.
      return true;
    }
    var s = await Permission.manageExternalStorage.request();
    if (s.isGranted) return true;
    s = await Permission.storage.request();
    return s.isGranted;
  }

  static Future<MediaIndex> scan({bool force = false}) async {
    if (!force && _cache != null) return _cache!;
    final r = await _ch.invokeMapMethod<String, dynamic>('scan') ?? {};
    List<MediaFile> conv(String k) =>
        ((r[k] as List?) ?? []).map((e) => MediaFile.fromMap(e as Map)).toList();
    _cache = MediaIndex(conv('audio'), conv('pdf'));
    return _cache!;
  }

  /// Returns the place where the video was saved (for example Movies/x.mp4).
  static Future<String> export({
    required List<Map<String, Object>> slides,
    required String audio,
    required String name,
    required String folder,
    required int kbps,
  }) async {
    final r = await _ch.invokeMethod<String>('export', {
      'slides': slides,
      'audio': audio,
      'name': name,
      'folder': folder,
      'kbps': kbps,
    });
    return r ?? '';
  }

  static Future<void> cancelExport() => _ch.invokeMethod('cancelExport');

  static Future<String> saveText(String name, String text) async =>
      (await _ch.invokeMethod<String>('saveText', {'name': name, 'text': text})) ?? '';
}
