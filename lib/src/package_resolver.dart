import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves package locations within the .pub-cache directory.
class PackageResolver {
  /// Finds the project root by walking up from the current directory
  /// looking for pubspec.yaml.
  static String? findProjectRoot() {
    var dir = Directory.current;
    while (true) {
      if (File(p.join(dir.path, 'pubspec.yaml')).existsSync()) {
        return dir.path;
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }

  /// Finds the .pub-cache directory for the current platform.
  static String? findPubCacheDir() {
    // Check PUB_CACHE environment variable first
    final pubCache = Platform.environment['PUB_CACHE'];
    if (pubCache != null && Directory(pubCache).existsSync()) {
      return pubCache;
    }

    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null) {
        final cachePath = p.join(appData, 'Pub', 'Cache');
        if (Directory(cachePath).existsSync()) return cachePath;
      }
    } else {
      final home = Platform.environment['HOME'];
      if (home != null) {
        final cachePath = p.join(home, '.pub-cache');
        if (Directory(cachePath).existsSync()) return cachePath;
      }
    }

    return null;
  }

  /// Resolves the exact path for [packageName] at [version] in .pub-cache.
  ///
  /// Returns the directory path like `~/.pub-cache/hosted/pub.dev/health-13.3.1`
  /// or `null` if not found.
  static String? resolvePackage(String packageName, String version) {
    final pubCache = findPubCacheDir();
    if (pubCache == null) return null;

    final hostedDir = Directory(p.join(pubCache, 'hosted'));
    if (!hostedDir.existsSync()) return null;

    final targetDirName = '$packageName-$version';

    for (final sourceDir in hostedDir.listSync().whereType<Directory>()) {
      final candidate = Directory(p.join(sourceDir.path, targetDirName));
      if (candidate.existsSync()) return candidate.path;
    }

    return null;
  }

  /// Resolves any available version of [packageName] in .pub-cache.
  ///
  /// Returns `(path, version)` or `null`.
  /// When multiple versions exist, returns the latest by directory name sort.
  static ({String path, String version})? resolvePackageAny(
      String packageName) {
    final pubCache = findPubCacheDir();
    if (pubCache == null) return null;

    final hostedDir = Directory(p.join(pubCache, 'hosted'));
    if (!hostedDir.existsSync()) return null;

    final pattern = RegExp('^${RegExp.escape(packageName)}-(.+)\$');
    final matches = <({String path, String version})>[];

    for (final sourceDir in hostedDir.listSync().whereType<Directory>()) {
      for (final pkgDir in sourceDir.listSync().whereType<Directory>()) {
        final dirName = p.basename(pkgDir.path);
        final match = pattern.firstMatch(dirName);
        if (match != null) {
          matches.add((path: pkgDir.path, version: match.group(1)!));
        }
      }
    }

    if (matches.isEmpty) return null;

    // Sort by semantic version descending to get latest
    matches.sort((a, b) => _compareVersions(b.version, a.version));
    return matches.first;
  }

  /// Extracts the version from a .pub-cache package directory path.
  ///
  /// Given `~/.pub-cache/hosted/pub.dev/health-13.3.1`, returns `13.3.1`.
  static String? extractVersion(String packagePath, String packageName) {
    final dirName = p.basename(packagePath);
    final prefix = '$packageName-';
    if (dirName.startsWith(prefix)) {
      return dirName.substring(prefix.length);
    }
    return null;
  }

  /// Compares two version strings semantically.
  /// Returns negative if a < b, zero if equal, positive if a > b.
  static int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = b.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen =
        aParts.length > bParts.length ? aParts.length : bParts.length;
    for (var i = 0; i < maxLen; i++) {
      final aVal = i < aParts.length ? aParts[i] : 0;
      final bVal = i < bParts.length ? bParts[i] : 0;
      if (aVal != bVal) return aVal.compareTo(bVal);
    }
    return 0;
  }

  /// Parses a patch filename like `health+13.3.1.patch` into name and version.
  ///
  /// Returns `(name, version)` or `null` if format doesn't match.
  static ({String name, String version})? parsePatchFilename(String filename) {
    // Remove .patch extension
    final base = p.basenameWithoutExtension(filename);
    final plusIndex = base.indexOf('+');
    if (plusIndex == -1) return null;

    final name = base.substring(0, plusIndex);
    final version = base.substring(plusIndex + 1);
    if (name.isEmpty || version.isEmpty) return null;

    return (name: name, version: version);
  }
}
