import 'dart:io';

import 'package:path/path.dart' as p;

import 'console.dart';
import 'package_resolver.dart';

/// Applies all patches from the `patches/` directory to .pub-cache packages.
class Applier {
  /// Scans `patches/` for `.patch` files and applies them.
  Future<void> apply() async {
    final patchesDir = Directory('patches');
    if (!patchesDir.existsSync()) {
      Console.warn('No patches/ directory found. Nothing to apply.');
      return;
    }

    final patchFiles = patchesDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.patch'))
        .toList();

    if (patchFiles.isEmpty) {
      Console.warn('No .patch files found in patches/.');
      return;
    }

    var applied = 0;
    var skipped = 0;
    var failed = 0;

    for (final patchFile in patchFiles) {
      final filename = p.basename(patchFile.path);
      final parsed = PackageResolver.parsePatchFilename(filename);

      String? packageDir;

      if (parsed != null) {
        // Versioned filename: health+13.3.1.patch
        packageDir = PackageResolver.resolvePackage(parsed.name, parsed.version);
        if (packageDir == null) {
          // Version not found, try any version with warning
          final any = PackageResolver.resolvePackageAny(parsed.name);
          if (any != null) {
            Console.warn(
                '$filename: expected ${parsed.name}@${parsed.version}, '
                'found @${any.version}. Attempting anyway...');
            packageDir = any.path;
          }
        }
      } else {
        // Legacy filename without version: health.patch
        final base = p.basenameWithoutExtension(filename);
        final any = PackageResolver.resolvePackageAny(base);
        if (any != null) {
          Console.warn(
              '$filename: no version in filename. '
              'Consider renaming to $base+${any.version}.patch');
          packageDir = any.path;
        }
      }

      if (packageDir == null) {
        final name = parsed?.name ?? p.basenameWithoutExtension(filename);
        Console.error('$filename: package "$name" not found in .pub-cache.');
        failed++;
        continue;
      }

      final absolutePatchPath = patchFile.absolute.path;

      // Check if already applied (reverse dry-run succeeds = already applied)
      final reverseCheck = await Process.run('patch', [
        '-d', packageDir,
        '-p1',
        '--dry-run',
        '--reverse',
        '--force',
        '-i', absolutePatchPath,
      ]);

      if (reverseCheck.exitCode == 0) {
        Console.info('$filename: already applied, skipping.');
        skipped++;
        continue;
      }

      // Check if applicable (forward dry-run)
      final forwardCheck = await Process.run('patch', [
        '-d', packageDir,
        '-p1',
        '--dry-run',
        '--forward',
        '-i', absolutePatchPath,
      ]);

      if (forwardCheck.exitCode != 0) {
        Console.error(
            '$filename: cannot apply patch.\n'
            '  ${forwardCheck.stderr.toString().trim()}');
        failed++;
        continue;
      }

      // Apply the patch
      final result = await Process.run('patch', [
        '-d', packageDir,
        '-p1',
        '--forward',
        '-i', absolutePatchPath,
      ]);

      if (result.exitCode == 0) {
        Console.success('$filename: applied successfully.');
        applied++;
      } else {
        Console.error(
            '$filename: failed to apply.\n'
            '  ${result.stderr.toString().trim()}');
        failed++;
      }
    }

    // Summary
    print('');
    if (failed == 0) {
      Console.success(
          'Done. $applied applied, $skipped already up-to-date.');
    } else {
      Console.warn(
          'Done. $applied applied, $skipped skipped, $failed failed.');
    }
  }
}
