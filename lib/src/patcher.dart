import 'dart:io';

import 'package:path/path.dart' as p;

import 'console.dart';
import 'dart_diff.dart';
import 'package_resolver.dart';

/// Handles the `start` and `done` commands for creating patches.
class Patcher {
  /// Creates a snapshot of [packageName] from .pub-cache for later diffing.
  /// Returns `true` on success.
  bool start(String packageName) {
    final projectRoot = PackageResolver.findProjectRoot();
    if (projectRoot == null) {
      Console.error('Could not find project root (no pubspec.yaml found).');
      return false;
    }

    final resolved = PackageResolver.resolvePackageAny(packageName);
    if (resolved == null) {
      Console.error(
          'Package "$packageName" not found in .pub-cache. '
          'Run "flutter pub get" first.');
      return false;
    }

    final snapshotDir = _snapshotPath(projectRoot, packageName, resolved.version);
    final snapshot = Directory(snapshotDir);

    if (snapshot.existsSync()) {
      snapshot.deleteSync(recursive: true);
    }
    snapshot.createSync(recursive: true);

    _copyDirectory(Directory(resolved.path), snapshot);

    Console.success(
        'Snapshot saved for $packageName@${resolved.version}');
    Console.info(
        'Now edit the package in .pub-cache, then run: '
        'dart run ft_patch_package done $packageName');
    return true;
  }

  /// Generates a patch by diffing the snapshot against the current .pub-cache.
  /// Returns `true` on success.
  bool done(String packageName) {
    final projectRoot = PackageResolver.findProjectRoot();
    if (projectRoot == null) {
      Console.error('Could not find project root (no pubspec.yaml found).');
      return false;
    }

    // Find the snapshot
    final snapshotBase = p.join(
        projectRoot, '.dart_tool', 'ft_patch_package');
    final snapshotBaseDir = Directory(snapshotBase);
    if (!snapshotBaseDir.existsSync()) {
      Console.error(
          'No snapshot found. Run "dart run ft_patch_package start $packageName" first.');
      return false;
    }

    // Find snapshot directory (name-version format)
    Directory? snapshotDir;
    String? version;
    for (final dir in snapshotBaseDir.listSync().whereType<Directory>()) {
      final dirName = p.basename(dir.path);
      if (dirName.startsWith('$packageName-')) {
        snapshotDir = dir;
        version = PackageResolver.extractVersion(dir.path, packageName);
        break;
      }
    }

    if (snapshotDir == null || version == null) {
      Console.error(
          'Snapshot for "$packageName" not found. Did you run start first?');
      return false;
    }

    // Find current package in .pub-cache
    final currentPath = PackageResolver.resolvePackage(packageName, version);
    if (currentPath == null) {
      Console.error(
          '$packageName@$version not found in .pub-cache.');
      return false;
    }

    // Generate diff using pure Dart (no external commands needed)
    Console.info('Generating diff for $packageName@$version...');
    final diffOutput = DartDiff.diffDirectories(snapshotDir.path, currentPath);

    if (diffOutput.isEmpty) {
      Console.warn('No changes detected for $packageName. No patch created.');
      _cleanupSnapshot(snapshotDir);
      return true;
    }

    // Write patch file
    final patchFileName = '$packageName+$version.patch';
    final patchesDir = Directory(p.join(projectRoot, 'patches'));
    if (!patchesDir.existsSync()) {
      patchesDir.createSync(recursive: true);
    }

    final patchFile = File(p.join(patchesDir.path, patchFileName));
    patchFile.writeAsStringSync(diffOutput);

    // Cleanup snapshot
    _cleanupSnapshot(snapshotDir);

    Console.success('Patch created: patches/$patchFileName');
    Console.info(
        'Commit patches/ to version control. '
        'Apply with: dart run ft_patch_package apply');
    return true;
  }

  String _snapshotPath(String projectRoot, String packageName, String version) {
    return p.join(
      projectRoot,
      '.dart_tool',
      'ft_patch_package',
      '$packageName-$version',
    );
  }

  void _cleanupSnapshot(Directory snapshotDir) {
    try {
      snapshotDir.deleteSync(recursive: true);
      // Clean parent if empty
      final parent = snapshotDir.parent;
      if (parent.listSync().isEmpty) {
        parent.deleteSync();
      }
    } catch (_) {}
  }

  void _copyDirectory(Directory source, Directory dest) {
    for (final entity in source.listSync(recursive: false, followLinks: false)) {
      final newPath = p.join(dest.path, p.basename(entity.path));
      try {
        if (entity is Link) {
          // Recreate symlink with the same target
          Link(newPath).createSync(entity.targetSync());
        } else if (entity is Directory) {
          final newDir = Directory(newPath);
          newDir.createSync();
          _copyDirectory(entity, newDir);
        } else if (entity is File) {
          entity.copySync(newPath);
        }
      } catch (e) {
        Console.warn('Failed to copy ${p.basename(entity.path)}: $e');
      }
    }
  }
}
