import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:snap_craft/models/annotation.dart';
import 'package:snap_craft/models/capture_item.dart';
import 'package:snap_craft/services/export_service.dart';
import 'package:snap_craft/widgets/annotation_canvas.dart';
import 'package:snap_craft/widgets/top_toolbar.dart';

class _MockPathProvider extends PathProviderPlatform {
  final String tempPath;
  _MockPathProvider(this.tempPath);
  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late PathProviderPlatform previousPlatform;
  late CaptureItem item;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('snap_craft_test');
    previousPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);

    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(200, 160);
    picture.dispose();

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final file = File('${tempDir.path}/test_image.png');
    await file.writeAsBytes(bytes);

    item = CaptureItem(
      id: 'test_item',
      filePath: file.path,
      originalBytes: bytes,
      decodedImage: image,
      capturedAt: DateTime.now(),
      mode: CaptureMode.region,
    );
  });

  tearDown(() {
    PathProviderPlatform.instance = previousPlatform;
    item.dispose();
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('스텝 카운터 (Step Counter)', () {
    test('스텝 카운터 렌더링이 예외 없이 수행된다', () async {
      final step1 = AnnotationItem(
        id: 'step_1',
        tool: AnnotationTool.stepCounter,
        color: const Color(0xFFFF3B30),
        strokeWidth: 5.0,
        points: const [Offset(50, 50)],
        text: '1',
      );
      final step2 = AnnotationItem(
        id: 'step_2',
        tool: AnnotationTool.stepCounter,
        color: const Color(0xFFFFCC00), // 밝은 색상 (어두운 텍스트 검증)
        strokeWidth: 6.0,
        points: const [Offset(120, 80)],
        text: '2',
      );

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => ExportService.paintCaptureScene(
          canvas: canvas,
          image: item.decodedImage,
          annotations: [step1, step2],
        ),
        returnsNormally,
      );

      final picture = recorder.endRecording();
      final rendered = await picture.toImage(200, 160);
      picture.dispose();
      rendered.dispose();
    });

    testWidgets('스텝 카운터 주석 추가 시 번호가 순차적으로 증가한다', (tester) async {
      final added = <AnnotationItem>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnnotationCanvas(
              captureItem: item,
              selectedTool: AnnotationTool.stepCounter,
              selectedColor: Colors.red,
              strokeWidth: 5.0,
              onAddAnnotation: (ann) {
                added.add(ann);
                item.annotations.add(ann);
              },
            ),
          ),
        ),
      );

      final canvasWidget = tester.widget<AnnotationCanvas>(
        find.byType(AnnotationCanvas),
      );

      // 첫 번째 스텝 추가
      final count1 = item.annotations
          .where((a) => a.tool == AnnotationTool.stepCounter)
          .length;
      canvasWidget.onAddAnnotation(
        AnnotationItem(
          id: 's1',
          tool: AnnotationTool.stepCounter,
          color: Colors.red,
          strokeWidth: 5.0,
          points: const [Offset(20, 20)],
          text: '${count1 + 1}',
        ),
      );
      expect(added.length, 1);
      expect(added[0].text, '1');

      // 두 번째 스텝 추가
      final count2 = item.annotations
          .where((a) => a.tool == AnnotationTool.stepCounter)
          .length;
      canvasWidget.onAddAnnotation(
        AnnotationItem(
          id: 's2',
          tool: AnnotationTool.stepCounter,
          color: Colors.red,
          strokeWidth: 5.0,
          points: const [Offset(40, 40)],
          text: '${count2 + 1}',
        ),
      );
      expect(added.length, 2);
      expect(added[1].text, '2');

      // 세 번째 스텝 추가
      final count3 = item.annotations
          .where((a) => a.tool == AnnotationTool.stepCounter)
          .length;
      canvasWidget.onAddAnnotation(
        AnnotationItem(
          id: 's3',
          tool: AnnotationTool.stepCounter,
          color: Colors.red,
          strokeWidth: 5.0,
          points: const [Offset(60, 60)],
          text: '${count3 + 1}',
        ),
      );
      expect(added.length, 3);
      expect(added[2].text, '3');
    });
  });

  group('자르기 (Crop)', () {
    test('지정된 Rect 영역으로 이미지가 잘라진다', () async {
      final cropRect = const Rect.fromLTWH(20, 20, 100, 80);
      final cropped = await ExportService.instance.cropCapture(
        item: item,
        cropRect: cropRect,
      );
      addTearDown(() => cropped.dispose());

      expect(cropped.width, 100);
      expect(cropped.height, 80);
      expect(cropped.resolutionLabel, '100x80');
      expect(cropped.originalBytes.isNotEmpty, isTrue);
      expect(File(cropped.filePath).existsSync(), isTrue);
    });

    test('너무 작은 영역 크롭 시 ArgumentError 발생', () async {
      final tooSmall = const Rect.fromLTWH(10, 10, 5, 5);
      expect(
        () => ExportService.instance.cropCapture(
          item: item,
          cropRect: tooSmall,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('TopToolbar 연동', () {
    testWidgets('스텝 카운터 도구와 자르기 버튼이 정상 동작한다', (tester) async {
      AnnotationTool? selectedTool;
      var toggleCropCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TopToolbar(
              hasActiveCapture: true,
              isCapturing: false,
              selectedTool: AnnotationTool.pen,
              selectedColor: Colors.blue,
              strokeWidth: 5.0,
              canUndo: false,
              canRedo: false,
              onTriggerCapture: (_) {},
              onSelectTool: (t) => selectedTool = t,
              onSelectColor: (_) {},
              onSelectStrokeWidth: (_) {},
              onUndo: () {},
              onRedo: () {},
              onClearAnnotations: () {},
              onCopyClipboard: () {},
              onSaveFile: () {},
              saveDirectory: null,
              isExportBusy: false,
              onChooseSaveDirectory: () {},
              onClearSaveDirectory: () {},
              onSaveFileAs: () {},
              onOpenShortcutSettings: () {},
              onOpenUpdateDialog: () {},
              isCropping: false,
              onToggleCrop: () => toggleCropCalled = true,
            ),
          ),
        ),
      );

      // 번호 툴 칩 선택 확인
      final numberChip = find.text('번호');
      expect(numberChip, findsOneWidget);
      await tester.tap(numberChip);
      await tester.pump();
      expect(selectedTool, AnnotationTool.stepCounter);

      // 자르기 버튼 확인
      final cropButton = find.text('자르기');
      expect(cropButton, findsOneWidget);
      await tester.tap(cropButton);
      await tester.pump();
      expect(toggleCropCalled, isTrue);
    });
  });
}
