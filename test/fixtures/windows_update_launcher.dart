import 'dart:io';

import 'package:snap_craft/services/windows_update_process.dart';

Future<void> main(List<String> args) async {
  await startWindowsUpdateProcess(
    updateDir: Directory(args[0]),
    arguments: [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      args[1],
      '-Target',
      args[2],
      '-Source',
      args[3],
      '-Executable',
      'snap_craft.exe',
      '-AppProcessId',
      '$pid',
      '-LogPath',
      args[4],
    ],
  );
  exit(0);
}
