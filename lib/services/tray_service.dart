import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';

import 'hotkey_service.dart';

typedef ShowWindowCallback = Future<void> Function();
typedef TriggerCaptureCallback = Future<void> Function(CaptureMode mode);

class TrayService {
  TrayService._();
  static final TrayService instance = TrayService._();

  static const String _prefKeyCloseToTray = 'snap_craft_close_to_tray';

  bool _initialized = false;
  bool _closeToTray = true;
  ShowWindowCallback? _onShowWindow;
  TriggerCaptureCallback? _onTriggerCapture;

  TrayIcon? _trayIcon;
  Menu? _menu;
  List<MenuItem> _menuItems = [];

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
      _trayIcon?.dispose();
      final trayIcon = TrayIcon.create();
      if (trayIcon == null) return;
      _trayIcon = trayIcon;

      final iconPath = Platform.isWindows
          ? 'assets/images/tray_icon.ico'
          : 'assets/images/tray_icon.png';

      trayIcon.icon = ImageAsset.fromAsset(iconPath);
      if (Platform.isMacOS) {
        trayIcon.isIconTemplate = true;
      }
      trayIcon.setTooltip('SnapCraft - 화면 캡쳐 & 마크업');
      trayIcon.addListener((event) {
        if (event is TrayIconClickedEvent) {
          handleIconClick();
        }
      });
      trayIcon.setContextMenuTrigger(ContextMenuTrigger.rightClicked);

      await updateContextMenu();
      trayIcon.setVisible(true);
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

  @visibleForTesting
  Map<String, String> buildMenuLabels() {
    String withShortcut(String base, CaptureMode mode) {
      final shortcut = HotkeyService.instance.formatHotKey(mode);
      return shortcut.isEmpty ? base : '$base ($shortcut)';
    }

    return {
      'capture_screen': withShortcut('전체 화면 캡쳐', CaptureMode.screen),
      'capture_region': withShortcut('영역 지정 캡쳐', CaptureMode.region),
      'capture_window': withShortcut('창 선택 캡쳐', CaptureMode.window),
      'show_window': 'SnapCraft 열기',
      'quit': '종료 (Quit)',
    };
  }

  Future<void> updateContextMenu() async {
    final trayIcon = _trayIcon;
    if (trayIcon == null) return;

    try {
      final labels = buildMenuLabels();
      final menu = Menu.create();
      if (menu == null) return;

      final items = <MenuItem>[];

      void addActionItem(String key) {
        final label = labels[key];
        if (label == null) return;
        final item = MenuItem.createWithLabelAndType(
          label,
          MenuItemType.normal,
        );
        if (item == null) return;
        item.addListener((event) {
          if (event is MenuItemClickedEvent) {
            handleMenuAction(key);
          }
        });
        items.add(item);
        menu.addItem(item);
      }

      addActionItem('capture_screen');
      addActionItem('capture_region');
      addActionItem('capture_window');
      menu.addSeparator();
      addActionItem('show_window');
      menu.addSeparator();
      addActionItem('quit');

      trayIcon.setContextMenu(menu);
      _menu?.dispose();
      for (final oldItem in _menuItems) {
        oldItem.dispose();
      }
      _menu = menu;
      _menuItems = items;
    } catch (e) {
      debugPrint('트레이 컨텍스트 메뉴 설정 실패: $e');
    }
  }

  @visibleForTesting
  void handleIconClick() {
    _onShowWindow?.call();
  }

  @visibleForTesting
  void handleMenuAction(String key) {
    switch (key) {
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
      _trayIcon?.dispose();
      _menu?.dispose();
      for (final item in _menuItems) {
        item.dispose();
      }
    } catch (e) {
      debugPrint('TrayService 해제 실패: $e');
    }
    _trayIcon = null;
    _menu = null;
    _menuItems = [];
    _initialized = false;
  }
}
