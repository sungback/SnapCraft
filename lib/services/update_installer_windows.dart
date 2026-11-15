import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'update_scripts.dart';

/// 내려받은 Windows 업데이트(.zip)를 풀어 설치 폴더를 교체한다.
class WindowsUpdateInstaller {
  const WindowsUpdateInstaller();

  Future<void> install({
    required String archivePath,
    required Directory updateDir,
    required void Function(double progress, String status) onProgress,
  }) async {
    onProgress(0.85, '다운로드한 업데이트 패키지 압축 해제 중...');
    final extractDir = Directory('${updateDir.path}\\extracted');
    await extractDir.create(recursive: true);

    final expandResult = await Process.run('powershell', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "Expand-Archive -LiteralPath '${archivePath.replaceAll("'", "''")}' -DestinationPath '${extractDir.path.replaceAll("'", "''")}' -Force",
    ]);

    if (expandResult.exitCode != 0) {
      throw Exception('압축 해제 실패: ${expandResult.stderr}');
    }

    final currentExePath = Platform.resolvedExecutable;
    final appDirectory = File(currentExePath).parent;
    final currentAppDir = appDirectory.path;
    // Only replace a dedicated application bundle, never a shared user folder.
    await for (final entry in appDirectory.list()) {
      final name = entry.uri.pathSegments
          .where((part) => part.isNotEmpty)
          .last
          .toLowerCase();
      if ((entry is Directory && name == 'data') ||
          (entry is File &&
              (name == 'snap_craft.exe' ||
                  name.endsWith('.dll') ||
                  name.endsWith('.pdb')))) {
        continue;
      }
      throw StateError('전용 SnapCraft 설치 폴더에서만 자동 업데이트할 수 있습니다.');
    }

    onProgress(0.96, '새 버전 적용 및 앱 재시작 중...');
    final executable = File(currentExePath).uri.pathSegments.last;
    for (final entry in [
      executable,
      'flutter_windows.dll',
      'data/flutter_assets',
    ]) {
      if (!await FileSystemEntity.type('${extractDir.path}/$entry')
          .then((type) => type != FileSystemEntityType.notFound)) {
        throw FormatException('업데이트 패키지에 $entry 파일이 없습니다.');
      }
    }
    final scriptFile = File('${updateDir.path}/install_update.ps1');
    await scriptFile.writeAsString(UpdateScripts.windows, encoding: utf8);
    final logDir = await getApplicationSupportDirectory();
    await logDir.create(recursive: true);
    await Process.start(
      'powershell',
      [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        scriptFile.path,
        '-Target',
        currentAppDir,
        '-Source',
        extractDir.path,
        '-Executable',
        executable,
        '-AppProcessId',
        '$pid',
        '-LogPath',
        '${logDir.path}/update-install.log',
      ],
      mode: ProcessStartMode.detached,
      workingDirectory: updateDir.path,
    );

    exit(0);
  }
}
