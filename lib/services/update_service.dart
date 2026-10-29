import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'update_scripts.dart';

class ReleaseInfo {
  final String currentVersion;
  final String latestVersion;
  final String tagName;
  final String releaseTitle;
  final String releaseNotes;
  final String htmlUrl;
  final String? downloadUrl;
  final String? assetName;
  final int assetSize;
  final bool hasUpdate;

  const ReleaseInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.releaseTitle,
    required this.releaseNotes,
    required this.htmlUrl,
    required this.downloadUrl,
    required this.assetName,
    required this.assetSize,
    required this.hasUpdate,
  });
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String githubOwner = 'sungback';
  static const String githubRepo = 'SnapCraft';
  static const String defaultVersion = '1.0.0';

  bool _isInstalling = false;
  String? _cachedCurrentVersion;
  ReleaseInfo? _latestReleaseInfo;
  ReleaseInfo? get latestReleaseInfo => _latestReleaseInfo;

  /// 현재 실행 중인 앱의 버전(예: 1.0.0)을 반환합니다.
  Future<String> getCurrentVersion() async {
    if (_cachedCurrentVersion != null) return _cachedCurrentVersion!;

    const envVersion = String.fromEnvironment('APP_VERSION');
    if (envVersion.isNotEmpty) {
      _cachedCurrentVersion = _normalizeVersion(envVersion);
      return _cachedCurrentVersion!;
    }

    // macOS 번들 내부 Info.plist에서 CFBundleShortVersionString 확인
    if (Platform.isMacOS) {
      try {
        final exeFile = File(Platform.resolvedExecutable);
        // .../snap_craft.app/Contents/MacOS/snap_craft -> .../snap_craft.app/Contents/Info.plist
        final contentsDir = exeFile.parent.parent;
        final plistFile = File('${contentsDir.path}/Info.plist');
        if (await plistFile.exists()) {
          final content = await plistFile.readAsString();
          final match = RegExp(
            r'<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>',
          ).firstMatch(content);
          if (match != null && match.group(1) != null) {
            final plistVer = _normalizeVersion(match.group(1)!);
            if (plistVer.isNotEmpty && !plistVer.contains(r'$')) {
              _cachedCurrentVersion = plistVer;
              return _cachedCurrentVersion!;
            }
          }
        }
      } catch (_) {}
    }

    // 개발 환경에서 로컬 pubspec.yaml 확인
    try {
      final pubspecFile = File('pubspec.yaml');
      if (await pubspecFile.exists()) {
        final content = await pubspecFile.readAsString();
        final match = RegExp(
          r'^version:\s*([^\s+#]+)',
          multiLine: true,
        ).firstMatch(content);
        if (match != null && match.group(1) != null) {
          _cachedCurrentVersion = _normalizeVersion(match.group(1)!);
          return _cachedCurrentVersion!;
        }
      }
    } catch (_) {}

    _cachedCurrentVersion = defaultVersion;
    return _cachedCurrentVersion!;
  }

  /// GitHub Releases API를 조회하여 최신 버전 여부와 다운로드 에셋 정보를 확인합니다.
  Future<ReleaseInfo?> checkForUpdate() async {
    final currentVer = await getCurrentVersion();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$githubOwner/$githubRepo/releases/latest',
      );
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.userAgentHeader, 'SnapCraft-Updater');
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );

      final response = await request.close();
      if (response.statusCode == 404) {
        // 아직 게시된 GitHub Release가 없는 경우
        final info = ReleaseInfo(
          currentVersion: currentVer,
          latestVersion: currentVer,
          tagName: 'v$currentVer',
          releaseTitle: 'SnapCraft v$currentVer',
          releaseNotes: '현재 최신 버전을 사용 중입니다.',
          htmlUrl: 'https://github.com/$githubOwner/$githubRepo/releases',
          downloadUrl: null,
          assetName: null,
          assetSize: 0,
          hasUpdate: false,
        );
        _latestReleaseInfo = info;
        return info;
      }

      if (response.statusCode != 200) {
        return null;
      }

      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;

      final tagName = (json['tag_name'] as String?) ?? 'v$currentVer';
      final latestVer = _normalizeVersion(tagName);
      final releaseTitle = (json['name'] as String?)?.trim().isNotEmpty == true
          ? (json['name'] as String)
          : tagName;
      final releaseNotes = (json['body'] as String?)?.trim().isNotEmpty == true
          ? (json['body'] as String)
          : '새로운 버전이 출시되었습니다.';
      final htmlUrl =
          (json['html_url'] as String?) ??
          'https://github.com/$githubOwner/$githubRepo/releases';

      String? downloadUrl;
      String? assetName;
      int assetSize = 0;

      final assets = (json['assets'] as List<dynamic>?) ?? const [];
      if (Platform.isMacOS) {
        // 자동 교체 설치를 위해 .zip 에셋을 우선 선택하고, 없으면 .dmg 선택
        Map<String, dynamic>? selectedAsset;
        for (final raw in assets) {
          final asset = raw as Map<String, dynamic>;
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.contains('macos') && name.endsWith('.zip')) {
            selectedAsset = asset;
            break;
          }
        }
        if (selectedAsset == null) {
          for (final raw in assets) {
            final asset = raw as Map<String, dynamic>;
            final name = (asset['name'] as String? ?? '').toLowerCase();
            if (name.contains('macos') && name.endsWith('.dmg')) {
              selectedAsset = asset;
              break;
            }
          }
        }
        if (selectedAsset != null) {
          downloadUrl = selectedAsset['browser_download_url'] as String?;
          assetName = selectedAsset['name'] as String?;
          assetSize = (selectedAsset['size'] as int?) ?? 0;
        }
      } else if (Platform.isWindows) {
        for (final raw in assets) {
          final asset = raw as Map<String, dynamic>;
          final name = (asset['name'] as String? ?? '').toLowerCase();
          if (name.contains('windows') && name.endsWith('.zip')) {
            downloadUrl = asset['browser_download_url'] as String?;
            assetName = asset['name'] as String?;
            assetSize = (asset['size'] as int?) ?? 0;
            break;
          }
        }
      }

      final hasUpdate = isNewerVersion(currentVer, latestVer);
      final info = ReleaseInfo(
        currentVersion: currentVer,
        latestVersion: latestVer,
        tagName: tagName,
        releaseTitle: releaseTitle,
        releaseNotes: releaseNotes,
        htmlUrl: htmlUrl,
        downloadUrl: downloadUrl,
        assetName: assetName,
        assetSize: assetSize,
        hasUpdate: hasUpdate,
      );
      _latestReleaseInfo = info;
      return info;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// 최신 릴리즈 에셋을 다운로드하고 자동으로 기존 앱을 교체한 뒤 재시작합니다.
  Future<void> downloadAndInstallUpdate(
    ReleaseInfo release, {
    required void Function(double progress, String status) onProgress,
  }) async {
    if (_isInstalling) throw StateError('업데이트가 이미 진행 중입니다.');
    _isInstalling = true;
    try {
      await _downloadAndInstallUpdate(release, onProgress: onProgress);
    } finally {
      _isInstalling = false;
    }
  }

  Future<void> _downloadAndInstallUpdate(
    ReleaseInfo release, {
    required void Function(double progress, String status) onProgress,
  }) async {
    final downloadUrl = release.downloadUrl;
    final assetName = release.assetName;
    if (downloadUrl == null || assetName == null) {
      await openUrl(release.htmlUrl);
      return;
    }

    onProgress(0.02, '업데이트 파일 다운로드 준비 중...');
    final tempDir = await getTemporaryDirectory();
    if (assetName.contains('/') ||
        assetName.contains('\\') ||
        assetName == '.' ||
        assetName == '..') {
      throw const FormatException('잘못된 업데이트 파일 이름');
    }
    final updateRoot = Directory('${tempDir.path}/snap_craft_update');
    await updateRoot.create(recursive: true);
    final updateDir = await updateRoot.createTemp('install_');

    final archivePath = '${updateDir.path}/$assetName';
    await _downloadFile(
      downloadUrl,
      archivePath,
      expectedBytes: release.assetSize,
      onProgress: (p) {
        final percent = (p * 100).toStringAsFixed(0);
        onProgress(0.05 + p * 0.75, '업데이트 패키지 다운로드 중... ($percent%)');
      },
    );

    if (Platform.isMacOS) {
      await _installOnMacOS(
        archivePath: archivePath,
        updateDir: updateDir,
        onProgress: onProgress,
      );
    } else if (Platform.isWindows) {
      await _installOnWindows(
        archivePath: archivePath,
        updateDir: updateDir,
        onProgress: onProgress,
      );
    } else {
      await openUrl(release.htmlUrl);
    }
  }

  Future<void> _downloadFile(
    String url,
    String savePath, {
    required int expectedBytes,
    required void Function(double progress) onProgress,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, 'SnapCraft-Updater');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('다운로드 실패 (HTTP ${response.statusCode})');
      }

      final total = response.contentLength > 0
          ? response.contentLength
          : expectedBytes;
      final file = File(savePath);
      final sink = file.openWrite();
      int received = 0;

      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress((received / total).clamp(0.0, 1.0));
        }
        await sink.flush();
      } finally {
        await sink.close();
      }
      if (received == 0 ||
          (total > 0 && received != total) ||
          (expectedBytes > 0 && received != expectedBytes)) {
        await file.delete();
        throw const FormatException('업데이트 다운로드가 완전하지 않습니다.');
      }
    } finally {
      client.close();
    }
  }

  Future<void> _installOnMacOS({
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

    // macOS TCC(화면 기록 권한) 유지를 위해 로컬 키체인의 개발자 인증서가 있으면 자동 서명 적용
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
    final details = await Process.run('/usr/bin/codesign', ['-dv', appPath]);
    if (result.exitCode != 0 ||
        details.exitCode != 0 ||
        !details.stderr.toString().contains('TeamIdentifier=') ||
        details.stderr.toString().contains('TeamIdentifier=not set')) {
      throw Exception('정식 인증서로 서명되지 않은 업데이트입니다: ${result.stderr}');
    }
  }

  Future<void> _installOnWindows({
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

  /// 브라우저로 지정된 URL을 엽니다.
  Future<void> openUrl(String url) async {
    try {
      if (Platform.isMacOS) {
        await Process.run('open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  /// 두 시맨틱 버전 문자열(예: 1.0.0 vs 1.0.1)을 비교하여 latest가 더 최신이면 true를 반환합니다.
  static bool isNewerVersion(String current, String latest) {
    final currParts = _parseVersionParts(current);
    final latestParts = _parseVersionParts(latest);
    final length = currParts.length > latestParts.length
        ? currParts.length
        : latestParts.length;

    for (int i = 0; i < length; i++) {
      final c = i < currParts.length ? currParts[i] : 0;
      final l = i < latestParts.length ? latestParts[i] : 0;
      if (l > c) return true;
      if (l < c) return false;
    }
    return false;
  }

  static String _normalizeVersion(String raw) {
    var cleaned = raw.trim();
    if (cleaned.startsWith('v') || cleaned.startsWith('V')) {
      cleaned = cleaned.substring(1);
    }
    final plusIndex = cleaned.indexOf('+');
    if (plusIndex != -1) {
      cleaned = cleaned.substring(0, plusIndex);
    }
    return cleaned.trim();
  }

  static List<int> _parseVersionParts(String version) {
    final normalized = _normalizeVersion(version).split('-').first;
    return normalized
        .split('.')
        .map((part) => int.tryParse(part.trim()) ?? 0)
        .toList();
  }
}
