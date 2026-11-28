import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StartupService {
  StartupService._();
  static final StartupService instance = StartupService._();

  static const String _prefKeyEnabled = 'snap_craft_launch_at_startup';
  static const String _macBundleId = 'com.example.snapCraft';
  static const String _windowsRunKey =
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
  static const String _windowsValueName = 'SnapCraft';

  bool _enabled = false;
  bool get isEnabled => _enabled;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(_prefKeyEnabled) ?? false;
    } catch (e) {
      debugPrint('StartupService 설정 로드 실패: $e');
    }
  }

  Future<void> setEnabled(bool value, {String? executablePath}) async {
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      final exe = executablePath ?? Platform.resolvedExecutable;
      if (Platform.isMacOS) {
        await _applyMacOs(value, exe);
      } else if (Platform.isWindows) {
        await _applyWindows(value, exe);
      }
    }

    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyEnabled, value);
    } catch (e) {
      debugPrint('StartupService 설정 저장 실패: $e');
    }
  }

  Future<void> _applyMacOs(bool enable, String executablePath) async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      throw StateError('HOME 디렉터리를 찾을 수 없습니다.');
    }
    final agentsDir = Directory('$home/Library/LaunchAgents');
    final plistFile = File('${agentsDir.path}/$_macBundleId.plist');

    if (enable) {
      if (!await agentsDir.exists()) {
        await agentsDir.create(recursive: true);
      }
      await plistFile.writeAsString(
        buildMacLaunchAgentPlist(executablePath),
        flush: true,
      );
    } else if (await plistFile.exists()) {
      await plistFile.delete();
    }
  }

  Future<void> _applyWindows(bool enable, String executablePath) async {
    final result = enable
        ? await Process.run('reg', [
            'add',
            _windowsRunKey,
            '/v',
            _windowsValueName,
            '/t',
            'REG_SZ',
            '/d',
            '"$executablePath" --start-minimized',
            '/f',
          ])
        : await Process.run('reg', [
            'delete',
            _windowsRunKey,
            '/v',
            _windowsValueName,
            '/f',
          ]);

    if (enable && result.exitCode != 0) {
      throw StateError('시작 프로그램 등록 실패: ${result.stderr}');
    }
  }

  @visibleForTesting
  static String buildMacLaunchAgentPlist(String executablePath) {
    final escapedExe = _escapeXml(executablePath);
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$_macBundleId</string>
  <key>ProgramArguments</key>
  <array>
    <string>$escapedExe</string>
    <string>--start-minimized</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''';
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
