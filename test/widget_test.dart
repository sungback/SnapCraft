import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snap_craft/services/capture_service.dart';
import 'package:snap_craft/widgets/top_toolbar.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:snap_craft/main.dart';
import 'package:snap_craft/services/update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('capture errors release both guards and allow retry', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(880, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var calls = 0;
    const channel = MethodChannel('window_manager');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isVisible') {
            calls++;
            throw PlatformException(code: 'capture_failure');
          }
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    await tester.pumpWidget(const SnapCraftApp());
    await tester.pumpAndSettle();
    for (var attempt = 0; attempt < 2; attempt++) {
      final toolbar = tester.widget<TopToolbar>(find.byType(TopToolbar));
      toolbar.onTriggerCapture(CaptureMode.region);
      await tester.pumpAndSettle();
      expect(find.textContaining('캡쳐에 실패했습니다.'), findsOneWidget);
      expect(
        tester.widget<TopToolbar>(find.byType(TopToolbar)).isCapturing,
        isFalse,
      );
      expect(CaptureService.instance.isCapturing, isFalse);
    }
    expect(calls, 2);
  });

  testWidgets('SnapCraft app smoke test', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1180, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SnapCraftApp());
    expect(find.text('영역 캡쳐'), findsOneWidget);
    expect(find.text('전체 화면'), findsOneWidget);
    expect(find.text('창 캡쳐'), findsOneWidget);
  });

  test('UpdateService semantic version comparison', () {
    expect(UpdateService.isNewerVersion('1.0.0', '1.0.1'), isTrue);
    expect(UpdateService.isNewerVersion('1.0.0', 'v1.1.0'), isTrue);
    expect(UpdateService.isNewerVersion('1.2.0', '1.2.0'), isFalse);
    expect(UpdateService.isNewerVersion('1.2.3', '1.2.2'), isFalse);
    expect(UpdateService.isNewerVersion('1.0.0+1', 'v2.0.0+1'), isTrue);
  });
}
