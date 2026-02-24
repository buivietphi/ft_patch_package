import 'dart:io';

import 'package:ft_patch_package/src/dart_patch.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('dart_patch_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  /// Creates a file under [tempDir]/[relPath] with [content].
  File createFile(String relPath, String content) {
    final file = File(p.join(tempDir.path, relPath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file;
  }

  group('DartPatch.apply', () {
    test('applies a simple modification patch', () {
      createFile('file.txt', 'line1\nold_line\nline3\n');

      const patch = '''--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 line1
-old_line
+new_line
 line3
''';

      final error = DartPatch.apply(tempDir.path, patch);
      expect(error, isNull, reason: 'Apply should succeed');

      final content = File(p.join(tempDir.path, 'file.txt')).readAsStringSync();
      expect(content, 'line1\nnew_line\nline3\n');
    });

    test('applies a new file patch', () {
      const patch = '''--- /dev/null
+++ b/new_file.txt
@@ -0,0 +1,2 @@
+hello
+world
''';

      final error = DartPatch.apply(tempDir.path, patch);
      expect(error, isNull);

      final content =
          File(p.join(tempDir.path, 'new_file.txt')).readAsStringSync();
      expect(content, 'hello\nworld\n');
    });

    test('applies a delete file patch', () {
      createFile('to_delete.txt', 'goodbye\n');

      const patch = '''--- a/to_delete.txt
+++ /dev/null
@@ -1,1 +0,0 @@
-goodbye
''';

      final error = DartPatch.apply(tempDir.path, patch);
      expect(error, isNull);
      expect(File(p.join(tempDir.path, 'to_delete.txt')).existsSync(), isFalse);
    });

    test('applies multi-hunk patch', () {
      createFile(
          'multi.txt', 'a\nb\nc\nd\ne\nf\ng\nh\ni\nj\nk\nl\nm\nn\no\n');

      const patch = '''--- a/multi.txt
+++ b/multi.txt
@@ -1,3 +1,3 @@
 a
-b
+B
 c
@@ -13,3 +13,3 @@
 m
-n
+N
 o
''';

      final error = DartPatch.apply(tempDir.path, patch);
      expect(error, isNull);

      final content =
          File(p.join(tempDir.path, 'multi.txt')).readAsStringSync();
      expect(content, contains('B'));
      expect(content, contains('N'));
      expect(content, isNot(contains('\nb\n')));
      expect(content, isNot(contains('\nn\n')));
    });

    test('returns error for missing file', () {
      const patch = '''--- a/missing.txt
+++ b/missing.txt
@@ -1,1 +1,1 @@
-old
+new
''';

      final error = DartPatch.apply(tempDir.path, patch);
      expect(error, isNotNull);
      expect(error, contains('not found'));
    });

    test('returns error for content mismatch', () {
      createFile('mismatch.txt', 'actual_content\n');

      const patch = '''--- a/mismatch.txt
+++ b/mismatch.txt
@@ -1,1 +1,1 @@
-expected_content
+new_content
''';

      final error = DartPatch.apply(tempDir.path, patch);
      expect(error, isNotNull);
      expect(error, contains('Hunk failed'));
    });

    test('blocks path traversal attempt', () {
      const patch = '''--- a/../../../etc/passwd
+++ b/../../../etc/passwd
@@ -1,1 +1,1 @@
-old
+new
''';

      final error = DartPatch.apply(tempDir.path, patch);
      expect(error, isNotNull);
      expect(error, contains('path traversal'));
    });
  });

  group('DartPatch.isApplied', () {
    test('returns true when patch is already applied', () {
      createFile('file.txt', 'line1\nnew_line\nline3\n');

      const patch = '''--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 line1
-old_line
+new_line
 line3
''';

      expect(DartPatch.isApplied(tempDir.path, patch), isTrue);
    });

    test('returns false when patch is not applied', () {
      createFile('file.txt', 'line1\nold_line\nline3\n');

      const patch = '''--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 line1
-old_line
+new_line
 line3
''';

      expect(DartPatch.isApplied(tempDir.path, patch), isFalse);
    });
  });

  group('DartPatch.isApplicable', () {
    test('returns true when patch can be applied', () {
      createFile('file.txt', 'line1\nold_line\nline3\n');

      const patch = '''--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 line1
-old_line
+new_line
 line3
''';

      expect(DartPatch.isApplicable(tempDir.path, patch), isTrue);
    });

    test('returns false when content does not match', () {
      createFile('file.txt', 'completely\ndifferent\n');

      const patch = '''--- a/file.txt
+++ b/file.txt
@@ -1,3 +1,3 @@
 line1
-old_line
+new_line
 line3
''';

      expect(DartPatch.isApplicable(tempDir.path, patch), isFalse);
    });
  });

  group('DartPatch round-trip with DartDiff', () {
    test('apply then isApplied returns true', () {
      createFile('round.txt', 'alpha\nbeta\ngamma\n');

      const patch = '''--- a/round.txt
+++ b/round.txt
@@ -1,3 +1,3 @@
 alpha
-beta
+BETA
 gamma
''';

      // Should be applicable
      expect(DartPatch.isApplicable(tempDir.path, patch), isTrue);

      // Apply
      final error = DartPatch.apply(tempDir.path, patch);
      expect(error, isNull);

      // Should now be detected as applied
      expect(DartPatch.isApplied(tempDir.path, patch), isTrue);

      // Should no longer be applicable (already applied)
      expect(DartPatch.isApplicable(tempDir.path, patch), isFalse);
    });
  });
}
