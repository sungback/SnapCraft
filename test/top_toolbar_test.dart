import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snap_craft/models/annotation.dart';
import 'package:snap_craft/widgets/top_toolbar.dart';

void main() {
  Future<void> pumpToolbar(
    WidgetTester tester, {
    bool hasCapture = false,
    bool busy = false,
    String? directory,
    VoidCallback? onChoose,
    VoidCallback? onClear,
    VoidCallback? onSaveAs,
  }) async {
    await tester.binding.setSurfaceSize(const Size(880, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TopToolbar(
            hasActiveCapture: hasCapture,
            isCapturing: false,
            selectedTool: AnnotationTool.pen,
            selectedColor: Colors.red,
            strokeWidth: 5,
            canUndo: false,
            canRedo: false,
            onTriggerCapture: (_) {},
            onSelectTool: (_) {},
            onSelectColor: (_) {},
            onSelectStrokeWidth: (_) {},
            onUndo: () {},
            onRedo: () {},
            onClearAnnotations: () {},
            onCopyClipboard: () {},
            onSaveFile: () {},
            saveDirectory: directory,
            isExportBusy: busy,
            onChooseSaveDirectory: onChoose ?? () {},
            onClearSaveDirectory: onClear ?? () {},
            onSaveFileAs: onSaveAs ?? () {},
            onOpenShortcutSettings: () {},
            onOpenUpdateDialog: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('folder selection is available without a capture', (
    tester,
  ) async {
    var choices = 0;
    await pumpToolbar(tester, onChoose: () => choices++);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'PNG 저장'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('PNG 저장 옵션'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuItem>(
            find.ancestor(
              of: find.text('다른 위치에 저장…'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            ),
          )
          .enabled,
      isFalse,
    );
    expect(
      tester
          .widget<PopupMenuItem>(
            find.ancestor(
              of: find.text('저장 폴더 지정 해제'),
              matching: find.byWidgetPredicate(
                (widget) => widget is PopupMenuItem,
              ),
            ),
          )
          .enabled,
      isFalse,
    );
    await tester.tap(find.text('저장 폴더 지정…'));
    await tester.pumpAndSettle();
    expect(choices, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy export disables saving and the menu', (tester) async {
    await pumpToolbar(tester, hasCapture: true, busy: true);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'PNG 저장'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('PNG 저장 옵션'));
    await tester.pumpAndSettle();
    expect(find.text('저장 폴더 지정…'), findsNothing);
  });

  testWidgets('long folder path fits at minimum width and actions work', (
    tester,
  ) async {
    final directory = '/한글 폴더/${List.filled(30, '긴 경로').join('/')}/';
    var clears = 0;
    var saves = 0;
    await pumpToolbar(
      tester,
      hasCapture: true,
      directory: directory,
      onClear: () => clears++,
      onSaveAs: () => saves++,
    );
    await tester.tap(find.byTooltip('PNG 저장 옵션'));
    await tester.pumpAndSettle();
    expect(find.text('저장 폴더 변경…'), findsOneWidget);
    expect(find.byTooltip(directory), findsOneWidget);
    expect(
      tester.widget<Text>(find.text(directory)).overflow,
      TextOverflow.ellipsis,
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('다른 위치에 저장…'));
    await tester.pumpAndSettle();
    expect(saves, 1);
    await tester.tap(find.byTooltip('PNG 저장 옵션'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('저장 폴더 지정 해제'));
    await tester.pumpAndSettle();
    expect(clears, 1);
    expect(tester.takeException(), isNull);
  });
}
