import 'dart:async';
import 'dart:io';

/// Wait until the installer has actually started before allowing the app to exit.
Future<void> startWindowsUpdateProcess({
  required List<String> arguments,
  required Directory updateDir,
}) async {
  final readyFile = File('${updateDir.path}/installer.ready');
  if (await readyFile.exists()) await readyFile.delete();
  // Dart's detached mode uses DETACHED_PROCESS on Windows, which does not
  // provide the console required by Windows PowerShell. Normal mode uses a
  // hidden console and the child continues after this process exits.
  final process = await Process.start('powershell', [
    ...arguments,
    '-ReadyPath',
    readyFile.path,
  ], workingDirectory: updateDir.path);
  unawaited(process.stdout.drain<void>());
  unawaited(process.stderr.drain<void>());
  var exited = false;
  var exitCode = 0;
  unawaited(
    process.exitCode.then((code) {
      exited = true;
      exitCode = code;
    }),
  );
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (await readyFile.exists()) return;
    if (exited) {
      throw StateError('Windows 업데이트 설치기를 시작하지 못했습니다 (종료 코드: $exitCode).');
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  process.kill();
  throw StateError('Windows 업데이트 설치기가 응답하지 않았습니다. 앱을 종료하지 않았습니다.');
}
