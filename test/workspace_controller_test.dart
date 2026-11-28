import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:snap_craft/controllers/workspace_controller.dart';
import 'package:snap_craft/models/annotation.dart';
import 'package:snap_craft/models/capture_item.dart';

Future<CaptureItem> _createDummyCapture(
  Directory dir,
  String id, {
  int width = 40,
  int height = 30,
}) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blueGrey, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final bytes = (await image.toByteData(
    format: ui.ImageByteFormat.png,
  ))!.buffer.asUint8List();
  final file = File('${dir.path}/$id.png');
  await file.writeAsBytes(bytes);

  return CaptureItem(
    id: id,
    filePath: file.path,
    originalBytes: bytes,
    decodedImage: image,
    capturedAt: DateTime.now(),
    mode: CaptureMode.region,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('snap_craft_ctrl_test');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('WorkspaceController', () {
    test('히스토리 추가 및 최대 보관 개수(maxHistoryItems) 초과 시 오래된 항목을 정리한다', () async {
      final controller = WorkspaceController();
      addTearDown(controller.dispose);

      for (var i = 0; i < WorkspaceController.maxHistoryItems + 3; i++) {
        final item = await _createDummyCapture(tempDir, 'cap_$i');
        controller.addCaptureItem(item);
      }

      expect(controller.history.length, WorkspaceController.maxHistoryItems);
      expect(controller.selectedItem?.id, 'cap_${WorkspaceController.maxHistoryItems + 2}');
    });

    test('주석 추가·이동·삭제·Undo·Redo가 선택 상태와 함께 일관되게 동작한다', () async {
      final controller = WorkspaceController();
      addTearDown(controller.dispose);

      final item = await _createDummyCapture(tempDir, 'edit_item');
      controller.addCaptureItem(item);

      const ann = AnnotationItem(
        id: 'a1',
        tool: AnnotationTool.rectangle,
        color: Colors.red,
        strokeWidth: 4,
        points: [Offset(5, 5), Offset(20, 20)],
      );

      controller.addAnnotation(ann);
      expect(item.annotations.length, 1);
      expect(controller.selectedAnnotationId, 'a1');

      final moved = ann.translated(const Offset(5, 5));
      controller.updateAnnotation(moved);
      expect(item.annotations.single.points, const [
        Offset(10, 10),
        Offset(25, 25),
      ]);

      controller.undo();
      expect(item.annotations, isEmpty);
      expect(item.redoStack.length, 1);
      expect(controller.selectedAnnotationId, isNull);

      controller.redo();
      expect(item.annotations.length, 1);
      expect(item.redoStack, isEmpty);

      controller.selectAnnotation('a1');
      expect(controller.selectedAnnotationId, 'a1');

      controller.deleteSelectedAnnotation();
      expect(item.annotations, isEmpty);
      expect(controller.selectedAnnotationId, isNull);
    });
  });
}
