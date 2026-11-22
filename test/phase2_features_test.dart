import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:snap_craft/models/annotation.dart';
import 'package:snap_craft/models/capture_item.dart';
import 'package:snap_craft/services/export_service.dart';
import 'package:snap_craft/services/ocr_service.dart';
import 'package:snap_craft/widgets/ocr_result_dialog.dart';
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
    tempDir = await Directory.systemTemp.createTemp('snap_craft_phase2_test');
    previousPlatform = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _MockPathProvider(tempDir.path);

    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(100, 80);
    picture.dispose();

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData!.buffer.asUint8List();

    final file = File('${tempDir.path}/test_item.png');
    await file.writeAsBytes(bytes);

    item = CaptureItem(
      id: 'phase2_item',
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

  group('에이전트용 복사 (Copy for Agent)', () {
    test('템플릿의 {path}가 올바르게 치환되어 클립보드에 기록된다', () async {
      String? copiedClipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedClipboardText = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });

      const template = '[image: {path}] 이 에러 화면을 분석해줘.';
      final result = await ExportService.instance.copyForAgent(
        item,
        template: template,
      );

      expect(result, isNotNull);
      expect(result!.contains('[image: '), isTrue);
      expect(result.contains('.png] 이 에러 화면을 분석해줘.'), isTrue);
      expect(copiedClipboardText, equals(result));
    });
  });

  group('화면 텍스트 추출 (OCR)', () {
    test('macOS 환경에서 OCR 채널을 호출하여 텍스트를 인식한다', () async {
      const channel = MethodChannel('snap_craft/ocr');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'recognizeText') {
              return '추출된 텍스트 예시\nFlutter Error: 404';
            }
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      if (Platform.isMacOS) {
        final text = await OcrService.instance.recognizeText(item);
        expect(text, contains('추출된 텍스트 예시'));
      }
    });

    testWidgets('OcrResultDialog가 텍스트를 표시하고 복사 동작을 수행한다', (tester) async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              copiedText = (call.arguments as Map)['text'] as String?;
            }
            return null;
          });

      const sampleText = 'Exception: Network connection timeout';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: OcrResultDialog(initialText: sampleText)),
        ),
      );

      expect(find.text(sampleText), findsOneWidget);
      expect(find.text('화면 텍스트 추출 (OCR)'), findsOneWidget);

      final copyButton = find.text('클립보드 복사');
      expect(copyButton, findsOneWidget);
      await tester.tap(copyButton);
      await tester.pumpAndSettle();

      expect(copiedText, equals(sampleText));
      expect(find.text('복사됨'), findsOneWidget);
    });
  });

  group('TopToolbar Phase 2 연동', () {
    testWidgets('텍스트 추출, 에이전트 복사, 핀 고정 버튼이 정상 작동한다', (tester) async {
      var extractTextCalled = false;
      String? selectedAgentTemplate;
      var togglePinCalled = false;

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
              onSelectTool: (_) {},
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
              onExtractText: () => extractTextCalled = true,
              onCopyForAgent: (tpl) => selectedAgentTemplate = tpl,
              isPinned: false,
              onTogglePin: () => togglePinCalled = true,
            ),
          ),
        ),
      );

      // 1. 텍스트 추출 버튼 테스트
      final extractButton = find.text('텍스트 추출');
      expect(extractButton, findsOneWidget);
      await tester.tap(extractButton);
      await tester.pump();
      expect(extractTextCalled, isTrue);

      // 2. 에이전트 복사 팝업 테스트
      final agentButton = find.text('에이전트 복사');
      expect(agentButton, findsOneWidget);
      await tester.tap(agentButton);
      await tester.pumpAndSettle();

      final firstTemplateOption = find.text('기본: 분석 및 문제 설명');
      expect(firstTemplateOption, findsOneWidget);
      await tester.tap(firstTemplateOption);
      await tester.pumpAndSettle();
      expect(selectedAgentTemplate, contains('[image: {path}]'));

      // 3. 핀 고정 버튼 테스트
      final pinButton = find.byTooltip('화면 최상단 핀 고정 (Always-on-Top)');
      expect(pinButton, findsOneWidget);
      await tester.tap(pinButton);
      await tester.pump();
      expect(togglePinCalled, isTrue);
    });
  });
}
