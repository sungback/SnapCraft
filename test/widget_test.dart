import 'package:flutter_test/flutter_test.dart';
import 'package:snap_craft/main.dart';

void main() {
  testWidgets('SnapCraft app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SnapCraftApp());
    expect(find.text('영역 캡쳐'), findsOneWidget);
    expect(find.text('전체 화면'), findsOneWidget);
    expect(find.text('창 캡쳐'), findsOneWidget);
  });
}
