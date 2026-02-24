/// CLI console output utilities.
class Console {
  static void info(String msg) => print('\x1B[36mℹ\x1B[0m $msg');
  static void success(String msg) => print('\x1B[32m✓\x1B[0m $msg');
  static void warn(String msg) => print('\x1B[33m⚠\x1B[0m $msg');
  static void error(String msg) => print('\x1B[31m✗\x1B[0m $msg');
}
