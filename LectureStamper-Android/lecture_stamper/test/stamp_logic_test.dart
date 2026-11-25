import 'package:flutter_test/flutter_test.dart';
import 'package:lecture_stamper/core/models.dart';
import 'package:lecture_stamper/core/project.dart';
import 'package:lecture_stamper/core/stamp_logic.dart';
import 'package:lecture_stamper/core/time_utils.dart';

void main() {
  test('time parsing and formatting', () {
    expect(parseTime('90'), 90);
    expect(parseTime('1:30'), 90);
    expect(parseTime('1:02:03'), 3723);
    expect(parseTime('  '), isNull);
    expect(() => parseTime('1:75'), throwsFormatException);
    expect(() => parseTime('abc'), throwsFormatException);
    expect(fmtTime(83), '1:23');
    expect(fmtTime(3723), '1:02:03');
  });

  test('stamp rules', () {
    var b = StampBook();
    expect(
        b.stamp(
            seconds: 10,
            split: false,
            left: (0, 2),
            right: (1, 5),
            target: StampTarget.both),
        hasLength(1));
    b = StampBook();
    b.stamp(
        seconds: 10,
        split: true,
        left: (0, 2),
        right: (1, 5),
        target: StampTarget.both);
    expect(b.stamps, hasLength(2));
    expect(
        b.stamp(
            seconds: 10,
            split: true,
            left: (0, 2),
            right: (1, 5),
            target: StampTarget.both),
        isEmpty);
  });

  test('undo, delete, edit, remove pdf', () {
    final b = StampBook();
    b.stamp(seconds: 5, split: false, left: (0, 0));
    b.stamp(seconds: 8, split: false, left: (0, 1));
    expect(b.undo(), isTrue);
    expect(b.stamps, hasLength(1));
    expect(b.edit(b.stamps.first, const Stamp(0, 0, 2)), isTrue);
    expect(b.stamps.first.seconds, 2);
    final c = StampBook(const [Stamp(0, 0, 1), Stamp(1, 3, 2), Stamp(2, 4, 3)]);
    c.removePdf(1);
    expect(c.stamps.map((s) => (s.pdf, s.page)), [(0, 0), (1, 4)]);
  });

  test('segments: first at 0, same time grouped, last open', () {
    final b = StampBook(const [
      Stamp(0, 0, 12),
      Stamp(0, 1, 40),
      Stamp(1, 0, 40),
      Stamp(0, 0, 90),
    ]);
    final s = b.segments();
    expect(s.length, 3);
    expect(s[0].start, 0);
    expect(s[0].end, 40);
    expect(s[1].pages, [(0, 1), (1, 0)]);
    expect(s[2].end, isNull);
  });

  test('grid matches desktop', () {
    expect(gridLayout(2), [2]);
    expect(gridLayout(3), [2, 1]);
    expect(gridLayout(5), [3, 2]);
  });

  test('project json round trip and lvm', () {
    final p = Project(
        name: 'x',
        audio: const FileRef('/a.mp3', 'a.mp3'),
        pdfs: [const FileRef('/s.pdf', 's.pdf')],
        book: StampBook(const [Stamp(0, 0, 5), Stamp(0, 1, 9)]));
    final q = Project.fromJson(p.toJson());
    expect(q.book.stamps, hasLength(2));
    expect(q.audio.path, '/a.mp3');
    final lvm = p.toLvm();
    expect(lvm['app'], 'LectureVideoMaker');
    expect((lvm['records'] as List).first['times']['0,1'], [9.0]);
  });
}
