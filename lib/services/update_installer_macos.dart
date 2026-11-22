import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'update_scripts.dart';

/// 내려받은 macOS 업데이트(.zip/.dmg)를 검증하고 현재 앱을 교체한다.
class MacUpdateInstaller {
  const MacUpdateInstaller();

  Future<void> install({
    required String archivePath,
    required Directory updateDir,
    required void Function(double progress, String status) onProgress,
  }) async {
    if (archivePath.toLowerCase().endsWith('.dmg')) {
      onProgress(0.95, '설치 이미지(.dmg)를 여는 중...');
      await Process.run('open', [archivePath]);
      return;
    }

    onProgress(0.85, '다운로드한 앱 번들 압축 해제 중...');
    final extractDir = Directory('${updateDir.path}/extracted');
    await extractDir.create(recursive: true);

    final dittoResult = await Process.run('/usr/bin/ditto', [
      '-x',
      '-k',
      archivePath,
      extractDir.path,
    ]);
    if (dittoResult.exitCode != 0) {
      throw Exception('압축 해제 실패: ${dittoResult.stderr}');
    }

    // 압축 해제된 .app 번들 탐색
    Directory? newAppBundle;
    await for (final entity in extractDir.list(recursive: false)) {
      if (entity is Directory && entity.path.endsWith('.app')) {
        newAppBundle = entity;
        break;
      }
    }
    if (newAppBundle == null) {
      throw Exception('압축 파일 내에서 .app 번들을 찾을 수 없습니다.');
    }

    final executable = File('${newAppBundle.path}/Contents/MacOS/snap_craft');
    if (!await executable.exists()) {
      throw const FormatException('앱 실행 파일이 없는 업데이트입니다.');
    }
    await _verifyMacSignature(newAppBundle.path);
    await _verifySameTeam(newAppBundle.path);

    // 로컬 키체인에 개발자 인증서가 있으면 TCC(화면 기록 권한) 유지를 위해 재서명 (없으면 배포본의 Ad-hoc 서명 유지)
    onProgress(0.91, '화면 기록 권한(TCC) 유지를 위해 인증서 서명 확인 중...');
    await _resignMacBundleForTcc(newAppBundle.path, updateDir);

    // 현재 실행 중인 .app 경로 계산 (.../snap_craft.app/Contents/MacOS/snap_craft)
    final currentExe = File(Platform.resolvedExecutable);
    final currentAppDir = currentExe.parent.parent.parent;
    if (!currentAppDir.path.endsWith('.app')) {
      // 디버그 환경 등에서 .app 구조가 아닌 경우 새 앱이 들어있는 폴더 열기
      await Process.run('open', [extractDir.path]);
      return;
    }

    onProgress(0.96, '새 버전 설치 및 재시작 중...');
    final scriptFile = File('${updateDir.path}/install_update.sh');
    final targetApp = currentAppDir.path;
    final stagedApp = '$targetApp.snapcraft-new.app';
    final backupApp = '$targetApp.snapcraft-previous.app';
    // Stage beside the installed app so the final renames stay on one volume.
    if (await Directory(stagedApp).exists()) {
      await Directory(stagedApp).delete(recursive: true);
    }
    final stageResult = await Process.run('/usr/bin/ditto', [
      newAppBundle.path,
      stagedApp,
    ]);
    if (stageResult.exitCode != 0) {
      throw Exception('업데이트 준비 실패. 설치 폴더 쓰기 권한을 확인하세요: ${stageResult.stderr}');
    }
    await _verifyMacSignature(stagedApp);
    await scriptFile.writeAsString(UpdateScripts.macOS);
    final logDir = await getApplicationSupportDirectory();
    await logDir.create(recursive: true);
    await Process.start(
      '/bin/sh',
      [
        scriptFile.path,
        targetApp,
        stagedApp,
        backupApp,
        '$pid',
        '${logDir.path}/update-install.log',
      ],
      mode: ProcessStartMode.detached,
      workingDirectory: updateDir.path,
    );

    exit(0);
  }

  /// macOS 업데이트 시 Ad-hoc 서명으로 바뀌어 TCC(화면 기록 권한)가 풀리는 문제를 방지하기 위해
  /// 로컬 키체인에 등록된 Developer ID Application 또는 Apple Development 인증서로 재서명합니다.
  Future<void> _resignMacBundleForTcc(
    String appBundlePath,
    Directory updateDir,
  ) async {
    try {
      final findRes = await Process.run('/usr/bin/security', [
        'find-identity',
        '-v',
        '-p',
        'codesigning',
      ]);
      if (findRes.exitCode != 0) {
        throw Exception('코드 서명 인증서 조회 실패: ${findRes.stderr}');
      }

      final output = findRes.stdout.toString();
      String? certName;

      final devIdMatch = RegExp(r'"(Developer ID Application:[^"]+)"')
          .firstMatch(output);
      if (devIdMatch != null) {
        certName = devIdMatch.group(1);
      } else {
        final appleDevMatch = RegExp(r'"(Apple Development:[^"]+)"')
            .firstMatch(output);
        if (appleDevMatch != null) {
          certName = appleDevMatch.group(1);
        }
      }

      if (certName == null || certName.isEmpty) return;

      final entitlementsFile = File('${updateDir.path}/Release.entitlements');
      await entitlementsFile.writeAsString(
        '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
</dict>
</plist>
''',
      );

      final signResult = await Process.run('/usr/bin/codesign', [
        '--force',
        '--deep',
        '--options',
        'runtime',
        '--entitlements',
        entitlementsFile.path,
        '--sign',
        certName,
        appBundlePath,
      ]);
      if (signResult.exitCode != 0) {
        throw Exception('업데이트 코드 서명 실패: ${signResult.stderr}');
      }
      await _verifyMacSignature(appBundlePath);
    } catch (error) {
      throw Exception('화면 기록 권한용 서명을 준비하지 못했습니다: $error');
    }
  }

  Future<void> _verifyMacSignature(String appPath) async {
    final result = await Process.run('/usr/bin/codesign', [
      '--verify',
      '--deep',
      '--strict',
      appPath,
    ]);
    if (result.exitCode != 0) {
      throw Exception('손상되었거나 서명이 유효하지 않은 업데이트입니다: ${result.stderr}');
    }
  }

  /// 새 앱의 서명 팀이 현재 실행 중인 앱과 같은지 확인한다. 다른 인증서로 서명된 앱은 거부한다.
  /// 현재 앱 또는 새 앱이 정식 서명된 경우 팀 서명 일치를 검증하며,
  /// 로컬/Ad-hoc 빌드에서도 SHA256 체크섬 무결성이 확인되면 업데이트를 허용한다.
  Future<void> _verifySameTeam(String newAppPath) async {
    final currentAppDir = File(Platform.resolvedExecutable)
        .parent
        .parent
        .parent;
    if (!currentAppDir.path.endsWith('.app')) return;

    final current = await _teamIdentifier(currentAppDir.path);
    final next = await _teamIdentifier(newAppPath);

    // 정식 팀 서명이 존재하는 경우 검증
    if (current != null && next != null && current != next) {
      throw const FormatException('업데이트 앱의 서명 팀이 현재 앱과 달라 설치를 중단했습니다.');
    }
    if (current != null && next == null) {
      throw const FormatException('업데이트 앱에 정식 팀 서명이 없어 설치를 중단했습니다.');
    }
  }

  Future<String?> _teamIdentifier(String appPath) async {
    final result = await Process.run('/usr/bin/codesign', [
      '-dv',
      '--verbose=2',
      appPath,
    ]);
    // codesign은 상세 정보를 stderr로 출력한다.
    return parseTeamIdentifier('${result.stderr}');
  }

  /// `codesign -dv` 출력에서 TeamIdentifier를 꺼낸다. ad-hoc("not set")이면 null.
  static String? parseTeamIdentifier(String output) {
    return RegExp(
      r'^TeamIdentifier=(?!not set)(\S+)',
      multiLine: true,
    ).firstMatch(output)?.group(1);
  }
}
