import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../models/annotation.dart';
import '../models/capture_item.dart';

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  static const MethodChannel _macClipboardChannel = MethodChannel(
    'snap_craft/clipboard',
  );

  /// 원본 이미지와 모든 마크업(모자이크 포함)을 지정된 Canvas에 렌더링합니다.
  /// 화면 캔버스(CustomPainter)와 최종 PNG 내보내기 양쪽에서 동일하게 사용됩니다.
  static void paintCaptureScene({
    required Canvas canvas,
    required ui.Image image,
    required List<AnnotationItem> annotations,
    AnnotationItem? activeAnnotation,
  }) {
    final imageRect = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    // 1. 기본 이미지 렌더링
    canvas.drawImage(
      image,
      Offset.zero,
      Paint()..filterQuality = FilterQuality.high,
    );

    final allItems = <AnnotationItem>[
      ...annotations,
      ?activeAnnotation,
    ];

    // 2. 모자이크/블러 레이어 먼저 적용 (그 위에 펜/텍스트를 올릴 수 있도록 순서대로 처리하되 각 아이템별 렌더링)
    for (final item in allItems) {
      switch (item.tool) {
        case AnnotationTool.mosaic:
          _drawMosaic(canvas, image, imageRect, item);
          break;
        case AnnotationTool.pen:
          _drawFreehand(canvas, item, isHighlighter: false);
          break;
        case AnnotationTool.highlighter:
          _drawFreehand(canvas, item, isHighlighter: true);
          break;
        case AnnotationTool.rectangle:
          _drawRectangle(canvas, item);
          break;
        case AnnotationTool.arrow:
          _drawArrow(canvas, item);
          break;
        case AnnotationTool.text:
          _drawText(canvas, item);
          break;
      }
    }
  }

  static void _drawMosaic(
    Canvas canvas,
    ui.Image image,
    Rect imageRect,
    AnnotationItem item,
  ) {
    final rect = item.boundingRect.intersect(imageRect);
    if (rect.width < 2 || rect.height < 2) return;

    canvas.save();
    canvas.clipRect(rect);

    // 강한 가우시안 블러 + 모자이크 블록 격자 패턴 결합으로 민감 정보 완벽 차폐
    final blurSigma = (item.strokeWidth * 2.4).clamp(10.0, 28.0);
    canvas.saveLayer(
      rect,
      Paint()
        ..imageFilter = ui.ImageFilter.blur(
          sigmaX: blurSigma,
          sigmaY: blurSigma,
          tileMode: TileMode.clamp,
        ),
    );
    canvas.drawImage(image, Offset.zero, Paint());
    canvas.restore();

    // 모자이크 타일 격자 질감 표현
    final blockSize = (item.strokeWidth * 2.5).clamp(10.0, 24.0);
    final lightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;
    final darkPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..style = PaintingStyle.fill;

    int row = 0;
    for (double y = rect.top; y < rect.bottom; y += blockSize) {
      int col = 0;
      for (double x = rect.left; x < rect.right; x += blockSize) {
        final cellRect = Rect.fromLTWH(
          x,
          y,
          math.min(blockSize, rect.right - x),
          math.min(blockSize, rect.bottom - y),
        );
        canvas.drawRect(
          cellRect,
          ((row + col) % 2 == 0) ? lightPaint : darkPaint,
        );
        col++;
      }
      row++;
    }

    canvas.restore();
  }

  static void _drawFreehand(
    Canvas canvas,
    AnnotationItem item, {
    required bool isHighlighter,
  }) {
    if (item.points.isEmpty) return;

    final paint = Paint()
      ..color = isHighlighter
          ? item.color.withValues(alpha: 0.36)
          : item.color
      ..strokeWidth = isHighlighter ? item.strokeWidth * 3.2 : item.strokeWidth
      ..strokeCap = isHighlighter ? StrokeCap.square : StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    if (item.points.length == 1) {
      canvas.drawPoints(ui.PointMode.points, item.points, paint);
      return;
    }

    final path = Path()..moveTo(item.points.first.dx, item.points.first.dy);
    for (int i = 1; i < item.points.length; i++) {
      final p0 = item.points[i - 1];
      final p1 = item.points[i];
      final mid = Offset((p0.dx + p1.dx) / 2, (p0.dy + p1.dy) / 2);
      path.quadraticBezierTo(p0.dx, p0.dy, mid.dx, mid.dy);
    }
    path.lineTo(item.points.last.dx, item.points.last.dy);
    canvas.drawPath(path, paint);
  }

  static void _drawRectangle(Canvas canvas, AnnotationItem item) {
    if (item.points.length < 2) return;
    final rect = item.boundingRect;
    final paint = Paint()
      ..color = item.color
      ..strokeWidth = item.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
    canvas.drawRRect(rrect, paint);
  }

  static void _drawArrow(Canvas canvas, AnnotationItem item) {
    if (item.points.length < 2) return;
    final start = item.points.first;
    final end = item.points.last;
    final delta = end - start;
    if (delta.distance < 4) return;

    final strokePaint = Paint()
      ..color = item.color
      ..strokeWidth = item.strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = item.color
      ..style = PaintingStyle.fill;

    final angle = delta.direction;
    final headLength = (item.strokeWidth * 4.2).clamp(14.0, 38.0);
    final headAngle = 0.48; // 약 27.5도

    final shaftEnd = Offset(
      end.dx - headLength * 0.7 * math.cos(angle),
      end.dy - headLength * 0.7 * math.sin(angle),
    );
    canvas.drawLine(start, shaftEnd, strokePaint);

    final p1 = Offset(
      end.dx - headLength * math.cos(angle - headAngle),
      end.dy - headLength * math.sin(angle - headAngle),
    );
    final p2 = Offset(
      end.dx - headLength * math.cos(angle + headAngle),
      end.dy - headLength * math.sin(angle + headAngle),
    );

    final headPath = Path()
      ..moveTo(end.dx, end.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..close();

    canvas.drawPath(headPath, fillPaint);
  }

  static void _drawText(Canvas canvas, AnnotationItem item) {
    final text = item.text;
    if (text == null || text.trim().isEmpty || item.points.isEmpty) return;

    final position = item.points.first;
    final fontSize = (item.strokeWidth * 4.5).clamp(16.0, 56.0);

    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: item.color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        height: 1.2,
        shadows: const [
          Shadow(
            color: Colors.black54,
            offset: Offset(1.0, 1.0),
            blurRadius: 3.0,
          ),
        ],
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final bgRect = Rect.fromLTWH(
      position.dx - 8,
      position.dy - 4,
      textPainter.width + 16,
      textPainter.height + 8,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(bgRect, const Radius.circular(6)),
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );

    textPainter.paint(canvas, position);
  }

  /// 마크업이 포함된 CaptureItem을 원본 해상도 PNG 바이트로 렌더링합니다.
  Future<Uint8List> renderAnnotatedPng(CaptureItem item) async {
    if (item.annotations.isEmpty) {
      return item.originalBytes;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    paintCaptureScene(
      canvas: canvas,
      image: item.decodedImage,
      annotations: item.annotations,
    );

    final picture = recorder.endRecording();
    final renderedImage = await picture.toImage(item.width, item.height);
    final byteData = await renderedImage.toByteData(
      format: ui.ImageByteFormat.png,
    );
    return byteData!.buffer.asUint8List();
  }

  /// 마크업이 반영된 최종 이미지를 시스템 클립보드에 복사합니다.
  /// macOS에서는 이미지(PNG/TIFF)와 임시 파일 경로(fileURL/string)를 동시에 등록하여
  /// 일반 메신저/Claude Code(이미지 붙여넣기)와 터미널 CLI(agy 등 경로 붙여넣기) 모두에서 작동합니다.
  Future<bool> copyToClipboard(CaptureItem item) async {
    try {
      final pngBytes = await renderAnnotatedPng(item);
      await File(item.filePath).writeAsBytes(pngBytes);

      if (Platform.isMacOS) {
        final ok = await _macClipboardChannel.invokeMethod<bool>(
          'copyImageAndFile',
          {
            'bytes': pngBytes,
            'path': item.filePath,
          },
        );
        return ok ?? true;
      }

      await Pasteboard.writeImage(pngBytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 마크업이 반영된 최종 이미지를 PNG 파일로 저장합니다.
  Future<String?> saveToFile(CaptureItem item) async {
    if (Platform.isMacOS) {
      await FilePicker.skipEntitlementsChecks();
    }

    final pngBytes = await renderAnnotatedPng(item);
    final defaultFileName =
        'SnapCraft_${item.capturedAt.year}${_twoDigits(item.capturedAt.month)}${_twoDigits(item.capturedAt.day)}_'
        '${_twoDigits(item.capturedAt.hour)}${_twoDigits(item.capturedAt.minute)}${_twoDigits(item.capturedAt.second)}.png';

    final savePath = await FilePicker.saveFile(
      dialogTitle: '캡쳐 이미지 저장',
      fileName: defaultFileName,
      type: FileType.custom,
      allowedExtensions: ['png'],
      bytes: pngBytes,
    );

    if (savePath == null || savePath.isEmpty) {
      return null;
    }

    final finalPath =
        savePath.toLowerCase().endsWith('.png') ? savePath : '$savePath.png';
    final file = File(finalPath);
    await file.writeAsBytes(pngBytes);
    return finalPath;
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
