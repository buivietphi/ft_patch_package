import 'dart:io';

import 'package:path/path.dart' as p;

/// Pure Dart unified diff generator — no external `diff` command needed.
/// Generates diffs with portable `a/` `b/` prefixes.
class DartDiff {
  static const _contextLines = 3;

  /// Maximum lines per file for LCS diff. Files larger than this are
  /// treated as fully replaced to avoid O(m*n) memory usage.
  static const _maxLcsLines = 5000;

  /// Generates a unified diff between two directories.
  /// Returns empty string if no differences found.
  static String diffDirectories(String originalPath, String modifiedPath) {
    final origFiles = _collectFiles(Directory(originalPath), originalPath);
    final modFiles = _collectFiles(Directory(modifiedPath), modifiedPath);

    final allPaths = {...origFiles.keys, ...modFiles.keys}.toList()..sort();
    final buffer = StringBuffer();

    for (final relPath in allPaths) {
      final origFile = origFiles[relPath];
      final modFile = modFiles[relPath];

      // Read files (checks binary, reads content once)
      final origData = origFile != null ? _readFile(origFile) : null;
      final modData = modFile != null ? _readFile(modFile) : null;

      // Skip binary files
      if (origData != null && origData.isBinary) continue;
      if (modData != null && modData.isBinary) continue;

      final origLines = origData?.lines ?? <String>[];
      final modLines = modData?.lines ?? <String>[];

      if (_linesEqual(origLines, modLines)) continue;

      // New file
      if (origFile == null) {
        buffer.writeln('diff -ruN a/$relPath b/$relPath');
        buffer.writeln('--- /dev/null');
        buffer.writeln('+++ b/$relPath');
        buffer.writeln('@@ -0,0 +1,${modLines.length} @@');
        for (final line in modLines) {
          buffer.writeln('+$line');
        }
        continue;
      }

      // Deleted file
      if (modFile == null) {
        buffer.writeln('diff -ruN a/$relPath b/$relPath');
        buffer.writeln('--- a/$relPath');
        buffer.writeln('+++ /dev/null');
        buffer.writeln('@@ -1,${origLines.length} +0,0 @@');
        for (final line in origLines) {
          buffer.writeln('-$line');
        }
        continue;
      }

      // Both exist — compute diff
      final ops = _computeEditScript(origLines, modLines);
      if (ops.every((op) => op.type == ' ')) continue;

      buffer.writeln('diff -ruN a/$relPath b/$relPath');
      buffer.writeln('--- a/$relPath');
      buffer.writeln('+++ b/$relPath');

      final hunks = _buildHunks(ops);
      for (final hunk in hunks) {
        buffer.write(hunk);
      }
    }

    return buffer.toString();
  }

  /// Collects all files in a directory. Uses forward slashes for portability.
  static Map<String, File> _collectFiles(Directory dir, String basePath) {
    final files = <String, File>{};
    if (!dir.existsSync()) return files;
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File) {
        // Always use forward slashes for cross-platform patch compatibility
        final rel = p.relative(entity.path, from: basePath)
            .replaceAll('\\', '/');
        files[rel] = entity;
      }
    }
    return files;
  }

  /// Reads a file once: checks binary (first 8KB), then returns lines.
  static _FileData _readFile(File file) {
    try {
      // Read only first 8KB for binary check
      final raf = file.openSync();
      try {
        final length = raf.lengthSync();
        final checkLen = length < 8192 ? length : 8192;
        final header = raf.readSync(checkLen);
        for (var i = 0; i < header.length; i++) {
          if (header[i] == 0) return _FileData(isBinary: true, lines: []);
        }
      } finally {
        raf.closeSync();
      }

      // Not binary — read full content as text
      final content = file.readAsStringSync();
      if (content.isEmpty) return _FileData(isBinary: false, lines: []);
      final lines = content.split('\n');
      if (lines.isNotEmpty && lines.last.isEmpty) {
        lines.removeLast();
      }
      return _FileData(isBinary: false, lines: lines);
    } catch (_) {
      return _FileData(isBinary: true, lines: []);
    }
  }

  static bool _linesEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Computes edit script using LCS (Longest Common Subsequence).
  /// Falls back to full replacement for files exceeding [_maxLcsLines].
  static List<_EditOp> _computeEditScript(
    List<String> origLines,
    List<String> modLines,
  ) {
    final m = origLines.length;
    final n = modLines.length;

    // Guard: avoid O(m*n) memory for very large files
    if (m > _maxLcsLines || n > _maxLcsLines) {
      return [
        for (final line in origLines) _EditOp('-', line),
        for (final line in modLines) _EditOp('+', line),
      ];
    }

    // Build LCS table
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        if (origLines[i - 1] == modLines[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = dp[i - 1][j] > dp[i][j - 1]
              ? dp[i - 1][j]
              : dp[i][j - 1];
        }
      }
    }

    // Backtrack to build edit script
    final ops = <_EditOp>[];
    var i = m, j = n;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && origLines[i - 1] == modLines[j - 1]) {
        ops.add(_EditOp(' ', origLines[i - 1]));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        ops.add(_EditOp('+', modLines[j - 1]));
        j--;
      } else {
        ops.add(_EditOp('-', origLines[i - 1]));
        i--;
      }
    }

    return ops.reversed.toList();
  }

  /// Groups edit operations into unified diff hunks with context lines.
  static List<String> _buildHunks(List<_EditOp> ops) {
    final changeIndices = <int>[];
    for (var i = 0; i < ops.length; i++) {
      if (ops[i].type != ' ') changeIndices.add(i);
    }
    if (changeIndices.isEmpty) return [];

    final hunkRanges = <({int start, int end})>[];
    var hunkStart = changeIndices.first;
    var hunkEnd = changeIndices.first;

    for (var i = 1; i < changeIndices.length; i++) {
      if (changeIndices[i] - hunkEnd <= _contextLines * 2) {
        hunkEnd = changeIndices[i];
      } else {
        hunkRanges.add((start: hunkStart, end: hunkEnd));
        hunkStart = changeIndices[i];
        hunkEnd = changeIndices[i];
      }
    }
    hunkRanges.add((start: hunkStart, end: hunkEnd));

    final hunks = <String>[];
    for (final range in hunkRanges) {
      final contextStart = (range.start - _contextLines).clamp(0, ops.length);
      final contextEnd = (range.end + _contextLines + 1).clamp(0, ops.length);

      var origStart = 1;
      var modStart = 1;
      for (var i = 0; i < contextStart; i++) {
        if (ops[i].type != '+') origStart++;
        if (ops[i].type != '-') modStart++;
      }

      var origCount = 0;
      var modCount = 0;
      final lines = StringBuffer();
      for (var i = contextStart; i < contextEnd; i++) {
        final op = ops[i];
        lines.writeln('${op.type}${op.line}');
        if (op.type != '+') origCount++;
        if (op.type != '-') modCount++;
      }

      hunks.add('@@ -$origStart,$origCount +$modStart,$modCount @@\n$lines');
    }

    return hunks;
  }
}

class _FileData {
  final bool isBinary;
  final List<String> lines;
  _FileData({required this.isBinary, required this.lines});
}

class _EditOp {
  final String type; // ' ', '-', '+'
  final String line;
  _EditOp(this.type, this.line);
}
