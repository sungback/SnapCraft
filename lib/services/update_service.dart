import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'update_installer_macos.dart';
import 'update_installer_windows.dart';

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

  /// 릴리즈의 SHA256SUMS.txt 에셋 URL. 없으면 자동 설치를 거부한다.
  final String? checksumUrl;

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
    this.checksumUrl,
  });
}

class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const String githubOwner = 'sungback';
  static const String githubRepo = 'SnapCraft';
  static const String defaultVersion = '1.0.0';
  static const String checksumAssetName = 'SHA256SUMS.txt';

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

      String? checksumUrl;
      for (final raw in assets) {
        final asset = raw as Map<String, dynamic>;
        if ((asset['name'] as String?) == checksumAssetName) {
          checksumUrl = asset['browser_download_url'] as String?;
          break;
        }
      }

      final hasUpdate = isNewerVersion(currentVer, latestVer);
      final info = ReleaseInfo(
        checksumUrl: checksumUrl,
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

    if (Platform.isMacOS || Platform.isWindows) {
      onProgress(0.82, '다운로드한 파일의 무결성(SHA256) 확인 중...');
      await _verifyChecksum(release, archivePath, assetName);
    }

    if (Platform.isMacOS) {
      await const MacUpdateInstaller().install(
        archivePath: archivePath,
        updateDir: updateDir,
        onProgress: onProgress,
      );
    } else if (Platform.isWindows) {
      await const WindowsUpdateInstaller().install(
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

  /// 릴리즈의 SHA256SUMS.txt와 내려받은 파일의 해시를 비교한다. 체크섬이 없으면 설치하지 않는다.
  Future<void> _verifyChecksum(
    ReleaseInfo release,
    String archivePath,
    String assetName,
  ) async {
    final checksumUrl = release.checksumUrl;
    if (checksumUrl == null) {
      await File(archivePath).delete();
      throw const FormatException('릴리즈에 $checksumAssetName가 없어 자동 설치를 중단했습니다.');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    final String sums;
    try {
      final request = await client.getUrl(Uri.parse(checksumUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'SnapCraft-Updater');
      final response = await request.close();
      if (response.statusCode != 200) {
        throw HttpException('체크섬 다운로드 실패 (HTTP ${response.statusCode})');
      }
      sums = await response.transform(utf8.decoder).join();
    } finally {
      client.close();
    }

    final expected = parseChecksum(sums, assetName);
    if (expected == null) {
      await File(archivePath).delete();
      throw FormatException('$checksumAssetName에 $assetName 항목이 없습니다.');
    }
    final actual = await _sha256Of(archivePath);
    if (actual != expected) {
      await File(archivePath).delete();
      throw const FormatException('업데이트 파일의 SHA256이 일치하지 않아 설치를 중단했습니다.');
    }
  }

  Future<String> _sha256Of(String path) async {
    final ProcessResult result;
    if (Platform.isWindows) {
      result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "(Get-FileHash -Algorithm SHA256 -LiteralPath '${path.replaceAll("'", "''")}').Hash",
      ]);
    } else {
      result = await Process.run('/usr/bin/shasum', ['-a', '256', path]);
    }
    if (result.exitCode != 0) {
      throw Exception('SHA256 계산 실패: ${result.stderr}');
    }
    return result.stdout
        .toString()
        .trim()
        .split(RegExp(r'\s+'))
        .first
        .toLowerCase();
  }

  /// `sha256sum` 형식("<해시>  <파일명>")에서 파일의 해시를 소문자로 반환한다. 없으면 null.
  static String? parseChecksum(String sums, String assetName) {
    for (final line in const LineSplitter().convert(sums)) {
      final match = RegExp(r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$')
          .firstMatch(line);
      if (match != null && match.group(2) == assetName) {
        return match.group(1)!.toLowerCase();
      }
    }
    return null;
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
