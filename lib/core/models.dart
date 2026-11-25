/// Data classes shared by the UI, the project store and the exporter.

class Stamp {
  /// Index into Project.pdfs.
  final int pdf;

  /// 0-based page.
  final int page;

  /// Audio second (millisecond precision is kept).
  final double seconds;

  const Stamp(this.pdf, this.page, this.seconds);

  Stamp copyWith({int? pdf, int? page, double? seconds}) =>
      Stamp(pdf ?? this.pdf, page ?? this.page, seconds ?? this.seconds);

  /// Same slide at (almost) the same moment.
  bool sameAs(Stamp o) =>
      pdf == o.pdf && page == o.page && (seconds - o.seconds).abs() < 0.0005;

  Map<String, dynamic> toJson() => {'pdf': pdf, 'page': page, 's': seconds};

  factory Stamp.fromJson(Map<String, dynamic> j) => Stamp(
        (j['pdf'] as num).toInt(),
        (j['page'] as num).toInt(),
        (j['s'] as num).toDouble(),
      );
}

/// A file reference with a relative-path fallback, like the desktop .lvm file.
class FileRef {
  final String path;
  final String rel;
  const FileRef(this.path, [this.rel = '']);

  Map<String, dynamic> toJson() => {'path': path, 'rel': rel};

  factory FileRef.fromJson(Map<String, dynamic>? j) =>
      FileRef((j?['path'] ?? '') as String, (j?['rel'] ?? '') as String);
}

/// Which side(s) a Stamp tap applies to in split-screen.
enum StampTarget { left, right, both }

/// One slide group in the video: a start time and the pages shown from then on.
class Segment {
  final double start;
  final double? end; // null = until the audio ends
  final List<(int pdf, int page)> pages;
  const Segment(this.start, this.end, this.pages);
}

class Rect4 {
  final double x0, y0, x1, y1;
  const Rect4(this.x0, this.y0, this.x1, this.y1);
  double get w => x1 - x0;
  double get h => y1 - y0;
}
