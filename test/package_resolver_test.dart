import 'package:ft_patch_package/src/package_resolver.dart';
import 'package:test/test.dart';

void main() {
  group('PackageResolver.parsePatchFilename', () {
    test('parses versioned filename', () {
      final result = PackageResolver.parsePatchFilename('health+13.3.1.patch');
      expect(result, isNotNull);
      expect(result!.name, 'health');
      expect(result.version, '13.3.1');
    });

    test('parses package with underscores', () {
      final result =
          PackageResolver.parsePatchFilename('flutter_local_notifications+17.2.4.patch');
      expect(result, isNotNull);
      expect(result!.name, 'flutter_local_notifications');
      expect(result.version, '17.2.4');
    });

    test('returns null for unversioned filename', () {
      final result = PackageResolver.parsePatchFilename('health.patch');
      expect(result, isNull);
    });

    test('returns null for empty name', () {
      final result = PackageResolver.parsePatchFilename('+1.0.0.patch');
      expect(result, isNull);
    });

    test('returns null for empty version', () {
      final result = PackageResolver.parsePatchFilename('health+.patch');
      expect(result, isNull);
    });
  });

  group('PackageResolver.extractVersion', () {
    test('extracts version from directory name', () {
      final version = PackageResolver.extractVersion(
        '/Users/dev/.pub-cache/hosted/pub.dev/health-13.3.1',
        'health',
      );
      expect(version, '13.3.1');
    });

    test('handles package names with underscores', () {
      final version = PackageResolver.extractVersion(
        '/cache/flutter_local_notifications-17.2.4',
        'flutter_local_notifications',
      );
      expect(version, '17.2.4');
    });

    test('returns null for non-matching name', () {
      final version = PackageResolver.extractVersion(
        '/cache/other_package-1.0.0',
        'health',
      );
      expect(version, isNull);
    });
  });

  group('PackageResolver.findPubCacheDir', () {
    test('finds pub cache directory', () {
      // This test depends on the local environment
      final dir = PackageResolver.findPubCacheDir();
      // Should find it on any machine with Dart installed
      expect(dir, isNotNull);
    });
  });
}
