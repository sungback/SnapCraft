import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:snap_craft/models/annotation.dart';
import 'package:snap_craft/models/capture_item.dart';
import 'package:snap_craft/services/export_service.dart';
import 'package:snap_craft/widgets/annotation_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late CaptureItem item;

  setUp(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(Colors.white, BlendMode.src);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 16, 24),
      Paint()..color = Colors.red,
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 24);
    picture.dispose();
    item = CaptureItem(
      id: 'redaction',
      filePath: 'unused.png',
      originalBytes: (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List(),
      decodedImage: image,
      capturedAt: DateTime(2026),
      mode: CaptureMode.region,
    );
  });

  tearDown(() => item.dispose());

  AnnotationItem redact(List<Offset> points) => AnnotationItem(
    id: 'mask',
    tool: AnnotationTool.redaction,
    // Even transparent colors and thin strokes must produce an opaque mask.
    color: Colors.transparent,
    strokeWidth: 0.1,
    points: points,
  );

  Future<void> expectPixels(ui.Image image, Rect mask) async {
    final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
        .buffer
        .asUint8List();
    // Compare outside the mask against normal scene rendering, which applies
    // high-quality image filtering even at the original resolution.
    final recorder = ui.PictureRecorder();
    ExportService.paintCaptureScene(
      canvas: Canvas(recorder),
      image: item.decodedImage,
      annotations: [],
    );
    final picture = recorder.endRecording();
    final baseline = await picture.toImage(32, 24);
    late Uint8List original;
    try {
      original = (await baseline.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
    } finally {
      baseline.dispose();
      picture.dispose();
    }
    for (var y = 0; y < 24; y++) {
      for (var x = 0; x < 32; x++) {
        final offset = (y * 32 + x) * 4;
        expect(
          pixels.sublist(offset, offset + 4),
          mask.contains(Offset(x.toDouble(), y.toDouble()))
              ? [0, 0, 0, 255]
              : original.sublist(offset, offset + 4),
          reason: 'pixel ($x, $y)',
        );
      }
    }
  }

  Future<void> expectPng(Uint8List bytes, Rect mask) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    try {
      await expectPixels(image, mask);
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  test(
    'export masks every touched pixel of a reversed fractional drag',
    () async {
      item.annotations.add(
        redact([const Offset(25.2, 19.1), const Offset(4.8, 3.7)]),
      );
      await expectPng(
        await ExportService.instance.renderAnnotatedPng(item),
        const Rect.fromLTRB(4, 3, 26, 20),
      );
    },
  );

  test(
    'redaction clips to image bounds and covers a single touched pixel',
    () async {
      for (final points in [
        [const Offset(-8, -4), const Offset(50, 40)],
        [const Offset(4.2, 3.2), const Offset(4.3, 3.3)],
        [const Offset(40, 30), const Offset(50, 40)],
        [const Offset(4, 3)],
      ]) {
        item.annotations
          ..clear()
          ..add(redact(points));
        final mask = points.first.dx < 0
            ? const Rect.fromLTWH(0, 0, 32, 24)
            : points.length == 2 && points.first.dx < 32
            ? const Rect.fromLTWH(4, 3, 1, 1)
            : Rect.zero;
        await expectPng(
          await ExportService.instance.renderAnnotatedPng(item),
          mask,
        );
      }
    },
  );

  test('redaction stays opaque above later annotations', () async {
    const points = [Offset(0, 0), Offset(32, 24)];
    item.annotations.addAll([
      redact(points),
      const AnnotationItem(
        id: 'later-highlighter',
        tool: AnnotationTool.highlighter,
        color: Colors.white,
        strokeWidth: 5,
        points: points,
      ),
    ]);
    await expectPng(
      await ExportService.instance.renderAnnotatedPng(item),
      const Rect.fromLTWH(0, 0, 32, 24),
    );
  });

  test('active draft uses the same opaque rendering as exported PNG', () async {
    final recorder = ui.PictureRecorder();
    ExportService.paintCaptureScene(
      canvas: Canvas(recorder),
      image: item.decodedImage,
      annotations: [],
      activeAnnotation: redact([const Offset(4, 3), const Offset(26, 20)]),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 24);
    try {
      await expectPixels(image, const Rect.fromLTRB(4, 3, 26, 20));
    } finally {
      image.dispose();
      picture.dispose();
    }
  });

  testWidgets('canvas creates a rectangular redaction from a drag', (
    tester,
  ) async {
    final annotations = <AnnotationItem>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnnotationCanvas(
            captureItem: item,
            selectedTool: AnnotationTool.redaction,
            selectedColor: Colors.transparent,
            strokeWidth: 3,
            onAddAnnotation: annotations.add,
          ),
        ),
      ),
    );
    final canvas = find.descendant(
      of: find.byType(AnnotationCanvas),
      matching: find.byType(GestureDetector),
    );
    await tester.drag(canvas, const Offset(60, 40));
    await tester.pump();
    expect(annotations, hasLength(1));
    expect(annotations.single.tool, AnnotationTool.redaction);
    expect(annotations.single.points, hasLength(2));
    expect(annotations.single.boundingRect.isEmpty, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
