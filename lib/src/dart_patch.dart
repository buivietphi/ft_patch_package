import 'dart:io';

import 'package:path/path.dart' as p;

/// Pure Dart unified diff patch applier — no external `patch` command needed.
class DartPatch {
  /// Applies a patch to [targetDir]. Returns null on success, error message on failure.
  static String? apply(String targetDir, String patchContent) {
    return _run(targetDir, patchContent, reverse: false, dryRun: false);
  }

  /// Returns true if the patch is already applied (reverse dry-run succeeds).
  static bool isApplied(String targetDir, String patchContent) {
    return _run(targetDir, patchContent, reverse: true, dryRun: true) == null;
  }

  /// Returns true if the patch can be applied (forward dry-run succeeds).
  static bool isApplicable(String targetDir, String patchContent) {
    return _run(targetDir, patchContent, reverse: false, dryRun: true) == null;
  }

  // ── Path safety ────────────────────────────────────────────────────────

  /// Validates that [filePath] is within [baseDir]. Prevents path traversal.
  static bool _isPathSafe(String baseDir, String filePath) {
    final normalizedBase = p.canonicalize(baseDir);
    final normalizedFile = p.canonicalize(filePath);
    return p.isWithin(normalizedBase, normalizedFile);
  }

  /// Joins [baseDir] with [relativePath] and validates safety.
  /// Returns null with error message if path traversal is detected.
  static (String?, String?) _safePath(String baseDir, String relativePath) {
    if (relativePath == '/dev/null') return (null, null);
    final joined = p.join(baseDir, relativePath);
    if (!_isPathSafe(baseDir, joined)) {
      return (null, 'Blocked path traversal attempt: $relativePath');
    }
    return (joined, null);
  }

  // ── Core logic ─────────────────────────────────────────────────────────

  /// Runs the patch operation. Returns null on success, error message on failure.
  static String? _run(
    String targetDir,
    String patchContent, {
    required bool reverse,
    required bool dryRun,
  }) {
    final fileDiffs = _parsePatch(patchContent);
    if (fileDiffs.isEmpty) {
      return 'No valid hunks found in patch.';
    }

    for (final fileDiff in fileDiffs) {
      final forwardTarget = fileDiff.modifiedPath;
      final forwardSource = fileDiff.originalPath;

      final targetPath = reverse ? forwardSource : forwardTarget;
      final sourcePath = reverse ? forwardTarget : forwardSource;

      // Handle /dev/null (new or deleted files)
      final isCreatingFile = sourcePath == '/dev/null';
      final isDeletingFile = targetPath == '/dev/null';

      if (isDeletingFile) {
        final actualPath = reverse ? forwardTarget : forwardSource;
        final (filePath, error) = _safePath(targetDir, actualPath);
        if (error != null) return error;
        if (filePath == null) continue;
        final file = File(filePath);
        if (reverse) {
          if (!file.existsSync()) return 'Expected file $actualPath to exist.';
        } else {
          if (!file.existsSync()) return 'File $actualPath not found.';
          if (!dryRun) file.deleteSync();
        }
        continue;
      }

      if (isCreatingFile) {
        final (filePath, error) = _safePath(targetDir, targetPath);
        if (error != null) return error;
        if (filePath == null) continue;
        final newLines = <String>[];
        for (final hunk in fileDiff.hunks) {
          for (final op in hunk.ops) {
            if (reverse) {
              if (op.type == '-') newLines.add(op.line);
            } else {
              if (op.type == '+') newLines.add(op.line);
            }
          }
        }
        if (reverse) {
          final file = File(filePath);
          if (!file.existsSync()) {
            return 'Expected file $targetPath to exist for reverse check.';
          }
          final current = _readFileLines(file);
          if (!_linesMatch(current, newLines)) {
            return 'Content mismatch in $targetPath for reverse check.';
          }
          if (!dryRun) file.deleteSync();
        } else {
          if (!dryRun) {
            final file = File(filePath);
            file.parent.createSync(recursive: true);
            file.writeAsStringSync('${newLines.join('\n')}\n');
          }
        }
        continue;
      }

      // Normal file modification
      final (filePath, error) = _safePath(targetDir, targetPath);
      if (error != null) return error;
      if (filePath == null) continue;
      final file = File(filePath);
      if (!file.existsSync()) {
        return 'File not found: $targetPath';
      }

      final currentLines = _readFileLines(file);
      final result = _applyHunks(currentLines, fileDiff.hunks, reverse);

      if (result == null) {
        return 'Hunk failed for $targetPath';
      }

      if (!dryRun) {
        file.writeAsStringSync('${result.join('\n')}\n');
      }
    }

    return null; // Success
  }

  static List<String> _readFileLines(File file) {
    final content = file.readAsStringSync();
    if (content.isEmpty) return [];
    final lines = content.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines;
  }

  static bool _linesMatch(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Applies all hunks to the given lines. Returns null if any hunk fails.
  static List<String>? _applyHunks(
    List<String> lines,
    List<_Hunk> hunks,
    bool reverse,
  ) {
    var result = List<String>.from(lines);
    var offset = 0;

    for (final hunk in hunks) {
      final startLine = reverse
          ? hunk.modifiedStart - 1 + offset
          : hunk.originalStart - 1 + offset;

      final expected = <String>[];
      final replacement = <String>[];

      for (final op in hunk.ops) {
        if (reverse) {
          if (op.type == ' ' || op.type == '+') expected.add(op.line);
          if (op.type == ' ' || op.type == '-') replacement.add(op.line);
        } else {
          if (op.type == ' ' || op.type == '-') expected.add(op.line);
          if (op.type == ' ' || op.type == '+') replacement.add(op.line);
        }
      }

      if (startLine < 0 || startLine + expected.length > result.length) {
        return null;
      }

      for (var i = 0; i < expected.length; i++) {
        if (result[startLine + i] != expected[i]) {
          return null;
        }
      }

      result.replaceRange(startLine, startLine + expected.length, replacement);
      offset += replacement.length - expected.length;
    }

    return result;
  }

  // ── Unified diff parser ──────────────────────────────────────────────

  static List<_FileDiff> _parsePatch(String content) {
    final fileDiffs = <_FileDiff>[];
    final lines = content.split('\n');

    var i = 0;
    while (i < lines.length) {
      if (!lines[i].startsWith('--- ')) {
        i++;
        continue;
      }

      final origPath = _extractPath(lines[i], '--- ');
      i++;
      if (i >= lines.length || !lines[i].startsWith('+++ ')) continue;
      final modPath = _extractPath(lines[i], '+++ ');
      i++;

      final hunks = <_Hunk>[];
      while (i < lines.length && lines[i].startsWith('@@ ')) {
        final header = _parseHunkHeader(lines[i]);
        if (header == null) {
          i++;
          continue;
        }
        i++;

        final ops = <_HunkOp>[];
        var origSeen = 0;
        var modSeen = 0;

        while (i < lines.length &&
            origSeen < header.origCount &&
            modSeen < header.modCount) {
          final line = lines[i];

          if (line.startsWith('-')) {
            ops.add(_HunkOp('-', line.substring(1)));
            origSeen++;
          } else if (line.startsWith('+')) {
            ops.add(_HunkOp('+', line.substring(1)));
            modSeen++;
          } else if (line.startsWith(' ')) {
            ops.add(_HunkOp(' ', line.substring(1)));
            origSeen++;
            modSeen++;
          } else if (line.startsWith('\\')) {
            // "\ No newline at end of file" — skip
          } else {
            ops.add(_HunkOp(' ', line));
            origSeen++;
            modSeen++;
          }
          i++;
        }

        while (i < lines.length && modSeen < header.modCount) {
          final line = lines[i];
          if (line.startsWith('+')) {
            ops.add(_HunkOp('+', line.substring(1)));
            modSeen++;
          } else if (line.startsWith('\\')) {
            // skip
          } else {
            break;
          }
          i++;
        }

        while (i < lines.length && origSeen < header.origCount) {
          final line = lines[i];
          if (line.startsWith('-')) {
            ops.add(_HunkOp('-', line.substring(1)));
            origSeen++;
          } else if (line.startsWith('\\')) {
            // skip
          } else {
            break;
          }
          i++;
        }

        hunks.add(_Hunk(
          originalStart: header.origStart,
          originalCount: header.origCount,
          modifiedStart: header.modStart,
          modifiedCount: header.modCount,
          ops: ops,
        ));
      }

      fileDiffs.add(_FileDiff(
        originalPath: origPath,
        modifiedPath: modPath,
        hunks: hunks,
      ));
    }

    return fileDiffs;
  }

  static String _extractPath(String line, String prefix) {
    var path = line.substring(prefix.length);
    final tabIndex = path.indexOf('\t');
    if (tabIndex != -1) path = path.substring(0, tabIndex);
    if (path == '/dev/null') return path;
    if (path.startsWith('a/') || path.startsWith('b/')) {
      path = path.substring(2);
    }
    return path;
  }

  static ({int origStart, int origCount, int modStart, int modCount})?
      _parseHunkHeader(String line) {
    final regex = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');
    final match = regex.firstMatch(line);
    if (match == null) return null;
    return (
      origStart: int.parse(match.group(1)!),
      origCount: int.parse(match.group(2) ?? '1'),
      modStart: int.parse(match.group(3)!),
      modCount: int.parse(match.group(4) ?? '1'),
    );
  }
}

// ── Internal data classes ────────────────────────────────────────────────

class _FileDiff {
  final String originalPath;
  final String modifiedPath;
  final List<_Hunk> hunks;
  _FileDiff({
    required this.originalPath,
    required this.modifiedPath,
    required this.hunks,
  });
}

class _Hunk {
  final int originalStart;
  final int originalCount;
  final int modifiedStart;
  final int modifiedCount;
  final List<_HunkOp> ops;
  _Hunk({
    required this.originalStart,
    required this.originalCount,
    required this.modifiedStart,
    required this.modifiedCount,
    required this.ops,
  });
}

class _HunkOp {
  final String type; // ' ', '-', '+'
  final String line;
  _HunkOp(this.type, this.line);
}
