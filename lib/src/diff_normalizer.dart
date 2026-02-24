/// Normalizes diff output to use portable `a/` and `b/` path prefixes.
///
/// Converts absolute machine-specific paths like:
///   `--- /var/folders/.../T/health/ios/Classes/Foo.swift`
///   `+++ /Users/phibui/.pub-cache/.../health-13.3.1/ios/Classes/Foo.swift`
///
/// Into portable relative paths:
///   `--- a/ios/Classes/Foo.swift`
///   `+++ b/ios/Classes/Foo.swift`
class DiffNormalizer {
  /// Normalizes a unified diff string by replacing absolute paths
  /// with `a/` (original) and `b/` (modified) prefixes.
  ///
  /// [diffOutput] - Raw output from `diff -ruN <original> <modified>`
  /// [originalBasePath] - The base path of the original snapshot directory
  /// [modifiedBasePath] - The base path of the modified package directory
  static String normalize(
    String diffOutput,
    String originalBasePath,
    String modifiedBasePath,
  ) {
    // Ensure paths end with / for clean replacement
    final origPrefix = _ensureTrailingSlash(originalBasePath);
    final modPrefix = _ensureTrailingSlash(modifiedBasePath);

    final lines = diffOutput.split('\n');
    final result = <String>[];

    for (final line in lines) {
      var normalized = line;

      if (line.startsWith('diff -')) {
        // Header: diff -ruN /tmp/.../file /Users/.../file
        normalized = normalized.replaceAll(origPrefix, 'a/');
        normalized = normalized.replaceAll(modPrefix, 'b/');
      } else if (line.startsWith('--- ')) {
        // Original file path: --- /tmp/.../file\t2024-01-01
        normalized = _replacePathInDiffLine('--- ', normalized, origPrefix, 'a/');
      } else if (line.startsWith('+++ ')) {
        // Modified file path: +++ /Users/.../file\t2024-01-01
        normalized = _replacePathInDiffLine('+++ ', normalized, modPrefix, 'b/');
      }

      result.add(normalized);
    }

    return result.join('\n');
  }

  static String _replacePathInDiffLine(
    String prefix,
    String line,
    String basePath,
    String replacement,
  ) {
    final afterPrefix = line.substring(prefix.length);
    // Split on tab to separate path from timestamp
    final tabIndex = afterPrefix.indexOf('\t');
    if (tabIndex == -1) {
      return prefix + afterPrefix.replaceFirst(basePath, replacement);
    }

    final filePath = afterPrefix.substring(0, tabIndex);
    final rest = afterPrefix.substring(tabIndex);
    return prefix + filePath.replaceFirst(basePath, replacement) + rest;
  }

  static String _ensureTrailingSlash(String path) {
    return path.endsWith('/') ? path : '$path/';
  }
}
