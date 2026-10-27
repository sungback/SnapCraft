import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef CaptureModeCallback = void Function(CaptureMode mode);

class HotkeyService {
  HotkeyService._();
  static final HotkeyService instance = HotkeyService._();

  static const String _prefKeyRegion = 'snap_craft_hotkey_region';
  static const String _prefKeyScreen = 'snap_craft_hotkey_screen';
  static const String _prefKeyWindow = 'snap_craft_hotkey_window';

  final Map<CaptureMode, HotKey> _hotKeys = {};
  CaptureModeCallback? _onTriggered;

  Map<CaptureMode, HotKey> get hotKeys => Map.unmodifiable(_hotKeys);

  HotKey get defaultRegionHotKey => HotKey(
        key: PhysicalKeyboardKey.keyA,
        modifiers: [
          Platform.isMacOS ? HotKeyModifier.meta : HotKeyModifier.control,
          HotKeyModifier.shift,
        ],
        scope: HotKeyScope.system,
      );

  HotKey get defaultScreenHotKey => HotKey(
        key: PhysicalKeyboardKey.keyS,
        modifiers: [
          Platform.isMacOS ? HotKeyModifier.meta : HotKeyModifier.control,
          HotKeyModifier.shift,
        ],
        scope: HotKeyScope.system,
      );

  HotKey get defaultWindowHotKey => HotKey(
        key: PhysicalKeyboardKey.keyW,
        modifiers: [
          Platform.isMacOS ? HotKeyModifier.meta : HotKeyModifier.control,
          HotKeyModifier.shift,
        ],
        scope: HotKeyScope.system,
      );

  Future<void> initialize(CaptureModeCallback onTriggered) async {
    _onTriggered = onTriggered;
    final prefs = await SharedPreferences.getInstance();

    _hotKeys[CaptureMode.region] =
        _loadHotKey(prefs, _prefKeyRegion) ?? defaultRegionHotKey;
    _hotKeys[CaptureMode.screen] =
        _loadHotKey(prefs, _prefKeyScreen) ?? defaultScreenHotKey;
    _hotKeys[CaptureMode.window] =
        _loadHotKey(prefs, _prefKeyWindow) ?? defaultWindowHotKey;

    await _registerAll();
  }

  HotKey? _loadHotKey(SharedPreferences prefs, String key) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return HotKey.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> _registerAll() async {
    try {
      await hotKeyManager.unregisterAll();
      for (final entry in _hotKeys.entries) {
        final mode = entry.key;
        final hotKey = entry.value;
        await hotKeyManager.register(
          hotKey,
          keyDownHandler: (_) {
            _onTriggered?.call(mode);
          },
        );
      }
    } catch (_) {
      // 일부 OS/권한 환경에서 단축키 등록 실패 시 앱 크래시 방지
    }
  }

  Future<void> updateHotKey(CaptureMode mode, HotKey newHotKey) async {
    final scopedHotKey = HotKey(
      key: newHotKey.key,
      modifiers: newHotKey.modifiers,
      scope: HotKeyScope.system,
    );
    _hotKeys[mode] = scopedHotKey;

    final prefs = await SharedPreferences.getInstance();
    final prefKey = switch (mode) {
      CaptureMode.region => _prefKeyRegion,
      CaptureMode.screen => _prefKeyScreen,
      CaptureMode.window => _prefKeyWindow,
    };
    await prefs.setString(prefKey, jsonEncode(scopedHotKey.toJson()));
    await _registerAll();
  }

  Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeyRegion);
    await prefs.remove(_prefKeyScreen);
    await prefs.remove(_prefKeyWindow);

    _hotKeys[CaptureMode.region] = defaultRegionHotKey;
    _hotKeys[CaptureMode.screen] = defaultScreenHotKey;
    _hotKeys[CaptureMode.window] = defaultWindowHotKey;
    await _registerAll();
  }

  String formatHotKey(CaptureMode mode) {
    final hotKey = _hotKeys[mode];
    if (hotKey == null) return '';
    return formatHotKeyObject(hotKey);
  }

  static String formatHotKeyObject(HotKey hotKey) {
    final isMac = Platform.isMacOS;
    final parts = <String>[];
    final modifiers = hotKey.modifiers ?? [];

    for (final mod in modifiers) {
      switch (mod) {
        case HotKeyModifier.meta:
          parts.add(isMac ? '⌘' : 'Win');
        case HotKeyModifier.control:
          parts.add(isMac ? '⌃' : 'Ctrl');
        case HotKeyModifier.shift:
          parts.add(isMac ? '⇧' : 'Shift');
        case HotKeyModifier.alt:
          parts.add(isMac ? '⌥' : 'Alt');
        case HotKeyModifier.capsLock:
          parts.add('Caps');
        case HotKeyModifier.fn:
          parts.add('Fn');
      }
    }

    final keyLabel = hotKey.key.keyLabel.isNotEmpty
        ? hotKey.key.keyLabel.toUpperCase()
        : (hotKey.physicalKey.debugName ?? 'Key');
    parts.add(keyLabel);

    return parts.join(isMac ? ' ' : ' + ');
  }
}
