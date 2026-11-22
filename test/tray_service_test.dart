// ignore_for_file: deprecated_member_use

import 'package:flutter_test/flutter_test.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snap_craft/services/tray_service.dart';
import 'package:tray_manager/legacy.dart';

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

    test('트레이 메뉴 아이템 클릭 시 대응하는 콜백이 호출된다', () async {
      final service = TrayService.instance;
      CaptureMode? capturedMode;
      bool showWindowCalled = false;

      await service.init(
        onShowWindow: () async {
          showWindowCalled = true;
        },
        onTriggerCapture: (mode) async {
          capturedMode = mode;
        },
      );

      // 전체 화면 캡쳐 클릭
      service.onTrayMenuItemClick(MenuItem(key: 'capture_screen'));
      expect(capturedMode, equals(CaptureMode.screen));

      // 영역 캡쳐 클릭
      service.onTrayMenuItemClick(MenuItem(key: 'capture_region'));
      expect(capturedMode, equals(CaptureMode.region));

      // 창 캡쳐 클릭
      service.onTrayMenuItemClick(MenuItem(key: 'capture_window'));
      expect(capturedMode, equals(CaptureMode.window));

      // SnapCraft 열기 클릭
      service.onTrayMenuItemClick(MenuItem(key: 'show_window'));
      expect(showWindowCalled, isTrue);
    });

    test('트레이 아이콘 마우스 다운 시 onShowWindow가 호출된다', () async {
      final service = TrayService.instance;
      bool showWindowCalled = false;

      await service.init(
        onShowWindow: () async {
          showWindowCalled = true;
        },
        onTriggerCapture: (mode) async {},
      );

      service.onTrayIconMouseDown();
      expect(showWindowCalled, isTrue);
    });
  });
}
