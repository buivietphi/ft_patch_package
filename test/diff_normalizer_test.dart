import 'package:ft_patch_package/src/diff_normalizer.dart';
import 'package:test/test.dart';

void main() {
  group('DiffNormalizer', () {
    test('normalizes absolute paths to a/ b/ prefixes', () {
      const input = '''diff -ruN /tmp/ft_patch_package/health-13.3.1/ios/Classes/Foo.swift /Users/dev/.pub-cache/hosted/pub.dev/health-13.3.1/ios/Classes/Foo.swift
--- /tmp/ft_patch_package/health-13.3.1/ios/Classes/Foo.swift\t2026-01-01 00:00:00
+++ /Users/dev/.pub-cache/hosted/pub.dev/health-13.3.1/ios/Classes/Foo.swift\t2026-01-01 00:00:00
@@ -1,3 +1,3 @@
 line1
-line2
+line2_modified
 line3''';

      final result = DiffNormalizer.normalize(
        input,
        '/tmp/ft_patch_package/health-13.3.1',
        '/Users/dev/.pub-cache/hosted/pub.dev/health-13.3.1',
      );

      expect(result, contains('--- a/ios/Classes/Foo.swift'));
      expect(result, contains('+++ b/ios/Classes/Foo.swift'));
      expect(result, contains('diff -ruN a/ios/Classes/Foo.swift b/ios/Classes/Foo.swift'));
      expect(result, isNot(contains('/tmp/')));
      expect(result, isNot(contains('/Users/')));
      expect(result, isNot(contains('.pub-cache')));
    });

    test('preserves hunk content unchanged', () {
      const input = '''diff -ruN /tmp/a/file.txt /cache/b/file.txt
--- /tmp/a/file.txt\t2026-01-01
+++ /cache/b/file.txt\t2026-01-01
@@ -1,3 +1,3 @@
 unchanged
-old
+new
 unchanged''';

      final result = DiffNormalizer.normalize(input, '/tmp/a', '/cache/b');

      expect(result, contains(' unchanged'));
      expect(result, contains('-old'));
      expect(result, contains('+new'));
    });

    test('handles multiple files in one diff', () {
      const input = '''diff -ruN /tmp/pkg/a.dart /cache/pkg/a.dart
--- /tmp/pkg/a.dart\t2026-01-01
+++ /cache/pkg/a.dart\t2026-01-01
@@ -1 +1 @@
-old_a
+new_a
diff -ruN /tmp/pkg/b.dart /cache/pkg/b.dart
--- /tmp/pkg/b.dart\t2026-01-01
+++ /cache/pkg/b.dart\t2026-01-01
@@ -1 +1 @@
-old_b
+new_b''';

      final result = DiffNormalizer.normalize(input, '/tmp/pkg', '/cache/pkg');

      expect(result, contains('--- a/a.dart'));
      expect(result, contains('+++ b/a.dart'));
      expect(result, contains('--- a/b.dart'));
      expect(result, contains('+++ b/b.dart'));
    });

    test('handles paths with trailing slash', () {
      const input = '''--- /tmp/pkg/file.txt\t2026-01-01
+++ /cache/pkg/file.txt\t2026-01-01''';

      final result = DiffNormalizer.normalize(input, '/tmp/pkg/', '/cache/pkg/');

      expect(result, contains('--- a/file.txt'));
      expect(result, contains('+++ b/file.txt'));
    });
  });
}
