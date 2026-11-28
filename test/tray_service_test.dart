import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snap_craft/services/hotkey_service.dart';
import 'package:snap_craft/services/tray_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TrayService.instance.dispose();
  });

  group('TrayService', () {
    test('기본 설정으로 closeToTray는 true이다', () async {
      final service = TrayService.instance;
      await service.init(
        onShowWindow: () async {},
        onTriggerCapture: (mode) async {},
      );

      expect(service.closeToTray, isTrue);
    });

    test('closeToTray 설정을 변경하고 영속화할 수 있다', () async {
      final service = TrayService.instance;
      await service.init(
        onShowWindow: () async {},
        onTriggerCapture: (mode) async {},
      );

      await service.setCloseToTray(false);
      expect(service.closeToTray, isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('snap_craft_close_to_tray'), isFalse);
    });

    test('트레이 메뉴 액션 실행 시 대응하는 콜백이 호출된다', () async {
      final service = TrayService.instance;
      CaptureMode? capturedMode;
      var showWindowCalled = false;

      await service.init(
        onShowWindow: () async {
          showWindowCalled = true;
        },
        onTriggerCapture: (mode) async {
          capturedMode = mode;
        },
      );

      service.handleMenuAction('capture_screen');
      expect(capturedMode, equals(CaptureMode.screen));

      service.handleMenuAction('capture_region');
      expect(capturedMode, equals(CaptureMode.region));

      service.handleMenuAction('capture_window');
      expect(capturedMode, equals(CaptureMode.window));

      service.handleMenuAction('show_window');
      expect(showWindowCalled, isTrue);
    });

    test('트레이 아이콘 클릭 시 onShowWindow가 호출된다', () async {
      final service = TrayService.instance;
      var showWindowCalled = false;

      await service.init(
        onShowWindow: () async {
          showWindowCalled = true;
        },
        onTriggerCapture: (mode) async {},
      );

      service.handleIconClick();
      expect(showWindowCalled, isTrue);
    });

    test('트레이 메뉴 라벨이 HotkeyService의 실제 단축키를 반영한다', () async {
      const hotkeyChannel = MethodChannel('dev.leanflutter.plugins/hotkey_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(hotkeyChannel, (call) async => null);
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(hotkeyChannel, null);
      });

      await HotkeyService.instance.initialize((_) {});
      final service = TrayService.instance;

      final defaultLabels = service.buildMenuLabels();
      expect(
        defaultLabels['capture_region'],
        '영역 지정 캡쳐 (${HotkeyService.instance.formatHotKey(CaptureMode.region)})',
      );
      expect(
        defaultLabels['capture_screen'],
        '전체 화면 캡쳐 (${HotkeyService.instance.formatHotKey(CaptureMode.screen)})',
      );
      expect(
        defaultLabels['capture_window'],
        '창 선택 캡쳐 (${HotkeyService.instance.formatHotKey(CaptureMode.window)})',
      );

      await HotkeyService.instance.updateHotKey(
        CaptureMode.region,
        HotKey(
          key: PhysicalKeyboardKey.keyR,
          modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
          scope: HotKeyScope.system,
        ),
      );
      final updatedLabels = service.buildMenuLabels();
      expect(
        updatedLabels['capture_region'],
        '영역 지정 캡쳐 (${HotkeyService.instance.formatHotKey(CaptureMode.region)})',
      );
      await HotkeyService.instance.resetToDefaults();
    });
  });
}
