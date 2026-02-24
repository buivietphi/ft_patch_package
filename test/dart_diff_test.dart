import 'dart:io';

import 'package:ft_patch_package/src/dart_diff.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dart_diff_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Creates a file under [base]/[relPath] with [content].
  File createFile(String base, String relPath, String content) {
    final file = File(p.join(base, relPath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  group('DartDiff.diffDirectories', () {
    test('returns empty string for identical directories', () {
      final origDir = Directory(p.join(tempDir.path, 'orig'))..createSync();
      final modDir = Directory(p.join(tempDir.path, 'mod'))..createSync();

      createFile(origDir.path, 'file.txt', 'hello\nworld\n');
      createFile(modDir.path, 'file.txt', 'hello\nworld\n');

      final diff = DartDiff.diffDirectories(origDir.path, modDir.path);
      expect(diff, isEmpty);
    });

    test('detects new file', () {
      final origDir = Directory(p.join(tempDir.path, 'orig'))..createSync();
      final modDir = Directory(p.join(tempDir.path, 'mod'))..createSync();

      createFile(modDir.path, 'new_file.txt', 'line1\nline2\n');

      final diff = DartDiff.diffDirectories(origDir.path, modDir.path);
      expect(diff, contains('--- /dev/null'));
      expect(diff, contains('+++ b/new_file.txt'));
      expect(diff, contains('+line1'));
      expect(diff, contains('+line2'));
    });

    test('detects deleted file', () {
      final origDir = Directory(p.join(tempDir.path, 'orig'))..createSync();
      final modDir = Directory(p.join(tempDir.path, 'mod'))..createSync();

      createFile(origDir.path, 'old_file.txt', 'line1\nline2\n');

      final diff = DartDiff.diffDirectories(origDir.path, modDir.path);
      expect(diff, contains('--- a/old_file.txt'));
      expect(diff, contains('+++ /dev/null'));
      expect(diff, contains('-line1'));
      expect(diff, contains('-line2'));
    });

    test('detects modified file', () {
      final origDir = Directory(p.join(tempDir.path, 'orig'))..createSync();
      final modDir = Directory(p.join(tempDir.path, 'mod'))..createSync();

      createFile(origDir.path, 'file.txt', 'line1\nold_line\nline3\n');
      createFile(modDir.path, 'file.txt', 'line1\nnew_line\nline3\n');

      final diff = DartDiff.diffDirectories(origDir.path, modDir.path);
      expect(diff, contains('--- a/file.txt'));
      expect(diff, contains('+++ b/file.txt'));
      expect(diff, contains('-old_line'));
      expect(diff, contains('+new_line'));
    });

    test('handles files in subdirectories', () {
      final origDir = Directory(p.join(tempDir.path, 'orig'))..createSync();
      final modDir = Directory(p.join(tempDir.path, 'mod'))..createSync();

      createFile(origDir.path, 'src/lib/util.dart', 'void old() {}\n');
      createFile(modDir.path, 'src/lib/util.dart', 'void updated() {}\n');

      final diff = DartDiff.diffDirectories(origDir.path, modDir.path);
      expect(diff, contains('a/src/lib/util.dart'));
      expect(diff, contains('b/src/lib/util.dart'));
    });

    test('skips binary files', () {
      final origDir = Directory(p.join(tempDir.path, 'orig'))..createSync();
      final modDir = Directory(p.join(tempDir.path, 'mod'))..createSync();

      // Binary file with null byte
      final origBin = File(p.join(origDir.path, 'image.png'));
      origBin.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x00, 0x01, 0x02]);
      final modBin = File(p.join(modDir.path, 'image.png'));
      modBin.writeAsBytesSync([0x89, 0x50, 0x4E, 0x47, 0x00, 0x03, 0x04]);

      final diff = DartDiff.diffDirectories(origDir.path, modDir.path);
      expect(diff, isEmpty);
    });

    test('handles empty files', () {
      final origDir = Directory(p.join(tempDir.path, 'orig'))..createSync();
      final modDir = Directory(p.join(tempDir.path, 'mod'))..createSync();

      createFile(origDir.path, 'empty.txt', '');
      createFile(modDir.path, 'empty.txt', '');

      final diff = DartDiff.diffDirectories(origDir.path, modDir.path);
      expect(diff, isEmpty);
    });

    test('handles multiple changed files sorted by path', () {
      final origDir = Directory(p.join(tempDir.path, 'orig'))..createSync();
      final modDir = Directory(p.join(tempDir.path, 'mod'))..createSync();

      createFile(origDir.path, 'b.txt', 'old_b\n');
      createFile(modDir.path, 'b.txt', 'new_b\n');
      createFile(origDir.path, 'a.txt', 'old_a\n');
      createFile(modDir.path, 'a.txt', 'new_a\n');

      final diff = DartDiff.diffDirectories(origDir.path, modDir.path);
      final aIndex = diff.indexOf('a/a.txt');
      final bIndex = diff.indexOf('a/b.txt');
      expect(aIndex, lessThan(bIndex), reason: 'Files should be sorted');
    });

    test('produces valid hunk headers', () {
      final origDir = Directory(p.join(tempDir.path, 'orig'))..createSync();
      final modDir = Directory(p.join(tempDir.path, 'mod'))..createSync();

      createFile(origDir.path, 'file.txt', 'a\nb\nc\n');
      createFile(modDir.path, 'file.txt', 'a\nx\nc\n');

      final diff = DartDiff.diffDirectories(origDir.path, modDir.path);
      expect(diff, contains(RegExp(r'@@ -\d+,\d+ \+\d+,\d+ @@')));
    });
  });
}
