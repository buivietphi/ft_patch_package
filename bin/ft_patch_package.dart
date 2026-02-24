import 'dart:io';

import 'package:ft_patch_package/src/applier.dart';
import 'package:ft_patch_package/src/console.dart';
import 'package:ft_patch_package/src/patcher.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    _printUsage();
    exit(1);
  }

  final command = args.first;
  final packageName = args.length > 1 ? args[1] : null;

  switch (command) {
    case 'start':
      if (packageName == null) {
        Console.error('Missing package name.');
        _printUsage();
        exit(1);
      }
      final startOk = Patcher().start(packageName);
      if (!startOk) exit(1);

    case 'done':
      if (packageName == null) {
        Console.error('Missing package name.');
        _printUsage();
        exit(1);
      }
      final doneOk = Patcher().done(packageName);
      if (!doneOk) exit(1);

    case 'apply':
      final applyOk = Applier().apply();
      if (!applyOk) exit(1);

    default:
      Console.error('Unknown command: $command');
      _printUsage();
      exit(1);
  }
}

void _printUsage() {
  print('''
ft_patch_package - Patch Flutter packages like React Native's patch-package

Usage:
  dart run ft_patch_package <command> [package_name]

Commands:
  start <package>   Save a snapshot before editing
  done  <package>   Generate a patch from your changes
  apply             Apply all patches from patches/

Workflow:
  1. dart run ft_patch_package start <package>
  2. Edit the package files in .pub-cache
  3. dart run ft_patch_package done <package>
  4. Commit the patches/ directory
  5. After flutter pub get, run: dart run ft_patch_package apply''');
}
