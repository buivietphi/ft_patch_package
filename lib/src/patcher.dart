import 'dart:io';

import 'package:path/path.dart' as p;

import 'console.dart';
import 'diff_normalizer.dart';
import 'package_resolver.dart';

/// Handles the `start` and `done` commands for creating patches.
class Patcher {
  static const _tempSubDir = 'ft_patch_package';

  /// Creates a snapshot of [packageName] from .pub-cache for later diffing.
  Future<void> start(String packageName) async {
    final resolved = PackageResolver.resolvePackageAny(packageName);
    if (resolved == null) {
      Console.error(
          'Package "$packageName" not found in .pub-cache. '
          'Run "flutter pub get" first.');
      return;
    }

    final snapshotDir = _snapshotPath(packageName, resolved.version);
    final snapshot = Directory(snapshotDir);

    if (snapshot.existsSync()) {
      snapshot.deleteSync(recursive: true);
    }
    snapshot.createSync(recursive: true);

    await _copyDirectory(Directory(resolved.path), snapshot);

    Console.success(
        'Snapshot saved for $packageName@${resolved.version}');
    Console.info(
        'Now edit the package in .pub-cache, then run: '
        'dart run ft_patch_package done $packageName');
  }

  /// Generates a patch by diffing the snapshot against the current .pub-cache.
  Future<void> done(String packageName) async {
    // Find the snapshot
    final tempBase = p.join(Directory.systemTemp.path, _tempSubDir);
    final tempDir = Directory(tempBase);
    if (!tempDir.existsSync()) {
      Console.error(
          'No snapshot found. Run "dart run ft_patch_package start $packageName" first.');
      return;
    }

    // Find snapshot directory (name-version format)
    Directory? snapshotDir;
    String? version;
    for (final dir in tempDir.listSync().whereType<Directory>()) {
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
      return;
    }

    // Find current package in .pub-cache
    final currentPath = PackageResolver.resolvePackage(packageName, version);
    if (currentPath == null) {
      Console.error(
          '$packageName@$version not found in .pub-cache.');
      return;
    }

    // Generate diff
    Console.info('Generating diff for $packageName@$version...');
    final result = await Process.run(
      'diff',
      ['-ruN', snapshotDir.path, currentPath],
    );

    final diffOutput = result.stdout.toString();
    if (diffOutput.isEmpty) {
      Console.warn('No changes detected for $packageName. No patch created.');
      _cleanupSnapshot(snapshotDir);
      return;
    }

    // Normalize paths to portable a/ b/ format
    final normalizedDiff = DiffNormalizer.normalize(
      diffOutput,
      snapshotDir.path,
      currentPath,
    );

    // Write patch file
    final patchFileName = '$packageName+$version.patch';
    final patchesDir = Directory('patches');
    if (!patchesDir.existsSync()) {
      patchesDir.createSync(recursive: true);
    }

    final patchFile = File(p.join('patches', patchFileName));
    patchFile.writeAsStringSync(normalizedDiff);

    // Cleanup snapshot
    _cleanupSnapshot(snapshotDir);

    Console.success('Patch created: patches/$patchFileName');
    Console.info(
        'Commit patches/ to version control. '
        'Apply with: dart run ft_patch_package apply');
  }

  String _snapshotPath(String packageName, String version) {
    return p.join(
      Directory.systemTemp.path,
      _tempSubDir,
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

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    for (final entity in source.listSync(recursive: false)) {
      final newPath = p.join(dest.path, p.basename(entity.path));
      if (entity is Directory) {
        final newDir = Directory(newPath);
        newDir.createSync();
        await _copyDirectory(entity, newDir);
      } else if (entity is File) {
        entity.copySync(newPath);
      }
    }
  }
}
