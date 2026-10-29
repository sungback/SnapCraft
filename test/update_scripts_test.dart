import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_craft/services/update_scripts.dart';

void main() {
  group('macOS installer transaction', () {
    late Directory root;
    late Directory target;
    late Directory stage;
    late String backup;
    late File script;
    late int exitedPid;

    setUp(() async {
      root = await Directory.systemTemp.createTemp("snapcraft test ' \$ ");
      target = await Directory('${root.path}/Snap Craft.app').create();
      await File('${target.path}/version').writeAsString('old');
      stage = await Directory('${root.path}/staged.app').create();
      await File('${stage.path}/version').writeAsString('new');
      backup = '${root.path}/previous.app';
      script = await File('${root.path}/install.sh')
          .writeAsString(UpdateScripts.macOS);
      final open = await File('${root.path}/open').writeAsString(
        '#!/bin/sh\nif [ "\${FAIL_NEW:-0}" = 1 ] && '
        '[ "\$(cat "\$1/version")" = new ]; then exit 1; fi\nexit 0\n',
      );
      await Process.run('chmod', ['+x', open.path]);
      exitedPid = (await Process.run('/usr/bin/true', [])).pid;
    });
    tearDown(() => root.delete(recursive: true));

    Future<ProcessResult> install({bool failLaunch = false}) => Process.run(
      '/bin/sh',
      [
        script.path,
        target.path,
        stage.path,
        backup,
        '$exitedPid',
        '${root.path}/install.log',
      ],
      environment: {
        'PATH': '${root.path}:${Platform.environment['PATH']}',
        'FAIL_NEW': failLaunch ? '1' : '0',
      },
    );

    test(
      'replaces app and retains recovery copy, including special paths',
      () async {
        expect((await install()).exitCode, 0);
        expect(await File('${target.path}/version').readAsString(), 'new');
        expect(await File('$backup/version').readAsString(), 'old');
      },
    );
    test('restores old app if staged app cannot be moved', () async {
      await stage.delete(recursive: true);
      expect((await install()).exitCode, 1);
      expect(await File('${target.path}/version').readAsString(), 'old');
    });
    test('restores old app if launch command fails', () async {
      expect((await install(failLaunch: true)).exitCode, 1);
      expect(await File('${target.path}/version').readAsString(), 'old');
      expect(await File('${stage.path}/version').readAsString(), 'new');
    });
  }, skip: Platform.isWindows);

  group('Windows installer transaction', () {
    late Directory root;
    late Directory target;
    late Directory source;
    late File script;
    late String originalExe;
    late int exitedPid;
    setUp(() async {
      root = await Directory.systemTemp.createTemp('snapcraft update test ');
      target = await Directory('${root.path}/app').create();
      source = await Directory('${root.path}/source').create();
      originalExe =
          '${Platform.environment['SystemRoot']}\\System32\\whoami.exe';
      await File(originalExe).copy('${target.path}/snap_craft.exe');
      await File('${target.path}/version').writeAsString('old');
      await File(originalExe).copy('${source.path}/snap_craft.exe');
      await File('${source.path}/flutter_windows.dll').writeAsString('fixture');
      await Directory('${source.path}/data/flutter_assets')
          .create(recursive: true);
      script = await File('${root.path}/install.ps1')
          .writeAsString(UpdateScripts.windows);
      exitedPid = (await Process.run(originalExe, [])).pid;
    });
    tearDown(() async {
      // The fixture executable launched by PowerShell may still be exiting.
      for (var attempt = 0; ; attempt++) {
        try {
          await root.delete(recursive: true);
          break;
        } on FileSystemException {
          if (attempt >= 20) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    });
    Future<ProcessResult> install() => Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
      '-Target',
      target.path,
      '-Source',
      source.path,
      '-Executable',
      'snap_craft.exe',
      '-AppProcessId',
      '$exitedPid',
      '-LogPath',
      '${root.path}/install.log',
    ]);
    test('installs complete bundle and keeps backup', () async {
      final result = await install();
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(
        await File('${target.path}.snapcraft-previous/version').readAsString(),
        'old',
      );
      expect(await File('${target.path}/flutter_windows.dll').exists(), isTrue);
    });
    test('incomplete package preserves original', () async {
      await File('${source.path}/flutter_windows.dll').delete();
      expect((await install()).exitCode, 1);
      expect(await File('${target.path}/version').readAsString(), 'old');
    });
    test('failed launch restores original', () async {
      await File('${source.path}/snap_craft.exe')
          .writeAsString('invalid executable');
      expect((await install()).exitCode, 1);
      expect(await File('${target.path}/version').readAsString(), 'old');
    });
  }, skip: !Platform.isWindows);
}
