// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/legacy.dart';

typedef ShowWindowCallback = Future<void> Function();
typedef TriggerCaptureCallback = Future<void> Function(CaptureMode mode);

class TrayService with TrayListener {
  TrayService._();
  static final TrayService instance = TrayService._();

  static const String _prefKeyCloseToTray = 'snap_craft_close_to_tray';

  bool _initialized = false;
  bool _closeToTray = true;
  ShowWindowCallback? _onShowWindow;
  TriggerCaptureCallback? _onTriggerCapture;

  bool get isInitialized => _initialized;
  bool get closeToTray => _closeToTray;

  Future<void> init({
    required ShowWindowCallback onShowWindow,
    required TriggerCaptureCallback onTriggerCapture,
  }) async {
    _onShowWindow = onShowWindow;
    _onTriggerCapture = onTriggerCapture;

    await _loadPreferences();

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _initialized = true;
      return;
    }

    try {
      trayManager.addListener(this);

      final iconPath = Platform.isWindows
          ? 'assets/images/tray_icon.ico'
          : 'assets/images/tray_icon.png';

      await trayManager.setIcon(
        iconPath,
        isTemplate: Platform.isMacOS,
      );

      await trayManager.setToolTip('SnapCraft - 화면 캡쳐 & 마크업');
      await updateContextMenu();
      _initialized = true;
    } catch (e) {
      debugPrint('TrayService 초기화 실패 (테스트 또는 미지원 환경): $e');
    }
  }

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _closeToTray = prefs.getBool(_prefKeyCloseToTray) ?? true;
    } catch (e) {
      debugPrint('TrayService 설정 로드 실패: $e');
    }
  }

  Future<void> setCloseToTray(bool value) async {
    _closeToTray = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefKeyCloseToTray, value);
    } catch (e) {
      debugPrint('TrayService 설정 저장 실패: $e');
    }
  }

  Future<void> updateContextMenu() async {
    try {
      final menu = Menu(
        items: [
          MenuItem(
            key: 'capture_screen',
            label: Platform.isMacOS ? '전체 화면 캡쳐 (Cmd+Shift+1)' : '전체 화면 캡쳐 (Ctrl+Shift+1)',
          ),
          MenuItem(
            key: 'capture_region',
            label: Platform.isMacOS ? '영역 지정 캡쳐 (Cmd+Shift+2)' : '영역 지정 캡쳐 (Ctrl+Shift+2)',
          ),
          MenuItem(
            key: 'capture_window',
            label: Platform.isMacOS ? '창 캡쳐 (Cmd+Shift+3)' : '창 캡쳐 (Ctrl+Shift+3)',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'show_window',
            label: 'SnapCraft 열기',
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'quit',
            label: '종료 (Quit)',
          ),
        ],
      );
      await trayManager.setContextMenu(menu);
    } catch (e) {
      debugPrint('트레이 컨텍스트 메뉴 설정 실패: $e');
    }
  }

  @override
  void onTrayIconMouseDown() {
    _onShowWindow?.call();
  }

  @override
  void onTrayIconRightMouseDown() {
    try {
      trayManager.popUpContextMenu();
    } catch (e) {
      debugPrint('트레이 메뉴 팝업 실패: $e');
    }
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'capture_screen':
        _onTriggerCapture?.call(CaptureMode.screen);
        break;
      case 'capture_region':
        _onTriggerCapture?.call(CaptureMode.region);
        break;
      case 'capture_window':
        _onTriggerCapture?.call(CaptureMode.window);
        break;
      case 'show_window':
        _onShowWindow?.call();
        break;
      case 'quit':
        exit(0);
    }
  }

  void dispose() {
    try {
      trayManager.removeListener(this);
      trayManager.destroy();
    } catch (e) {
      debugPrint('TrayService 해제 실패: $e');
    }
    _initialized = false;
  }
}
