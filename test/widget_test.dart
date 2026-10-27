import 'package:flutter_test/flutter_test.dart';
import 'package:snap_craft/main.dart';
import 'package:snap_craft/services/update_service.dart';

void main() {
  testWidgets('SnapCraft app smoke test', (WidgetTester tester) async {
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
