import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';

import 'capture_files.dart';
import '../models/annotation.dart';
import '../models/capture_item.dart';

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  static const MethodChannel _macClipboardChannel = MethodChannel(
    'snap_craft/clipboard',
  );

  /// 원본 이미지와 모든 마크업(보안 가림 포함)을 지정된 Canvas에 렌더링합니다.
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

    final allItems = <AnnotationItem>[...annotations, ?activeAnnotation];

    // 2. 일반 주석은 추가한 순서대로 렌더링합니다.
    for (final item in allItems) {
      switch (item.tool) {
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
        case AnnotationTool.stepCounter:
          _drawStepCounter(canvas, item);
          break;
        case AnnotationTool.redaction:
          // Apply last so the mask remains opaque above all other annotations.
          break;
      }
    }

    // 3. 보안 가림은 항상 마지막에 적용하여 다른 주석이 원본을 다시 드러내지 못하게 합니다.
    for (final item in allItems) {
      if (item.tool != AnnotationTool.redaction) continue;
      final rect = item.boundingRect.intersect(imageRect);
      if (rect.isEmpty) continue;
      // Cover every touched source pixel, including fractional drag boundaries.
      final pixelRect = Rect.fromLTRB(
        rect.left.floorToDouble(),
        rect.top.floorToDouble(),
        rect.right.ceilToDouble(),
        rect.bottom.ceilToDouble(),
      );
      canvas.drawRect(
        pixelRect,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.fill
          ..isAntiAlias = false
          ..blendMode = BlendMode.src,
      );
    }
  }

  static void _drawFreehand(
    Canvas canvas,
    AnnotationItem item, {
    required bool isHighlighter,
  }) {
    if (item.points.isEmpty) return;

    final paint = Paint()
      ..color = isHighlighter ? item.color.withValues(alpha: 0.36) : item.color
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

  static void _drawStepCounter(Canvas canvas, AnnotationItem item) {
    if (item.points.isEmpty) return;
    final center = item.points.first;
    final text = item.text ?? '1';
    final radius = (item.strokeWidth * 3.6).clamp(14.0, 36.0);

    // 1. 외곽 그림자
    canvas.drawCircle(
      center + const Offset(0, 1.5),
      radius,
      Paint()
        ..color = Colors.black45
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );

    // 2. 메인 채우기 원 (선택된 색상)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = item.color
        ..style = PaintingStyle.fill,
    );

    // 3. 흰색 윤곽 테두리 (어떤 배경에서도 구분 가능)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..strokeWidth = (radius * 0.12).clamp(1.5, 3.0)
        ..style = PaintingStyle.stroke,
    );

    // 4. 숫자 텍스트 (색상 밝기에 따라 텍스트 색상 자동 결정)
    final textColor = item.color.computeLuminance() > 0.55
        ? Colors.black87
        : Colors.white;

    final fontSize = (radius * 1.15).clamp(12.0, 32.0);
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: textColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.0,
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    )..layout();

    final textOffset = Offset(
      center.dx - textPainter.width / 2,
      center.dy - textPainter.height / 2,
    );
    textPainter.paint(canvas, textOffset);
  }

  /// 마크업이 포함된 CaptureItem을 원본 해상도 PNG 바이트로 렌더링합니다.
  Future<Uint8List> renderAnnotatedPng(CaptureItem item) async {
    if (item.annotations.isEmpty) {
      return item.originalBytes;
    }

    // Keep an independent handle while the capture may be removed from history.
    final image = item.decodedImage.clone();
    final recorder = ui.PictureRecorder();
    ui.Picture? picture;
    ui.Image? renderedImage;
    try {
      final canvas = Canvas(recorder);
      paintCaptureScene(
        canvas: canvas,
        image: image,
        annotations: List.of(item.annotations),
      );
      picture = recorder.endRecording();
      renderedImage = await picture.toImage(image.width, image.height);
      final byteData = await renderedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) throw StateError('PNG 인코딩 실패');
      return byteData.buffer.asUint8List();
    } finally {
      renderedImage?.dispose();
      if (recorder.isRecording) recorder.endRecording().dispose();
      picture?.dispose();
      image.dispose();
    }
  }

  /// 원본 캡쳐본과 현재 마크업을 지정된 Rect 영역(원본 픽셀 좌표계)으로 잘라내어 새 CaptureItem을 반환합니다.
  Future<CaptureItem> cropCapture({
    required CaptureItem item,
    required Rect cropRect,
  }) async {
    final imageRect = Rect.fromLTWH(
      0,
      0,
      item.width.toDouble(),
      item.height.toDouble(),
    );
    final clampedRect = cropRect.intersect(imageRect);
    if (clampedRect.width < 10 || clampedRect.height < 10) {
      throw ArgumentError('자르기 영역이 너무 작습니다 (최소 10x10 px 필요).');
    }

    final cropLeft = clampedRect.left.round();
    final cropTop = clampedRect.top.round();
    final cropWidth = clampedRect.width.round();
    final cropHeight = clampedRect.height.round();

    final image = item.decodedImage.clone();
    final recorder = ui.PictureRecorder();
    ui.Picture? picture;
    ui.Image? croppedImage;
    try {
      final canvas = Canvas(recorder);
      canvas.translate(-cropLeft.toDouble(), -cropTop.toDouble());

      paintCaptureScene(
        canvas: canvas,
        image: image,
        annotations: List.of(item.annotations),
      );

      picture = recorder.endRecording();
      croppedImage = await picture.toImage(cropWidth, cropHeight);
      final byteData = await croppedImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData == null) {
        throw StateError('PNG 인코딩 실패');
      }
      final croppedBytes = byteData.buffer.asUint8List();

      final tempDir = await getTemporaryDirectory();
      final capturesDir = Directory('${tempDir.path}/snap_craft_captures');
      if (!await capturesDir.exists()) {
        await capturesDir.create(recursive: true);
      }
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${capturesDir.path}/snap_crop_$timestamp.png';
      await File(filePath).writeAsBytes(croppedBytes, flush: true);

      // Clone a retained image for the new CaptureItem
      final returnedImage = croppedImage.clone();

      return CaptureItem(
        id: 'crop_$timestamp',
        filePath: filePath,
        originalBytes: croppedBytes,
        decodedImage: returnedImage,
        capturedAt: DateTime.now(),
        mode: item.mode,
      );
    } finally {
      croppedImage?.dispose();
      if (recorder.isRecording) recorder.endRecording().dispose();
      picture?.dispose();
      image.dispose();
    }
  }

  Future<void> cleanStaleFiles() async {
    try {
      String? clipboardPath;
      if (Platform.isMacOS) {
        clipboardPath = await _macClipboardChannel.invokeMethod<String>(
          'currentFilePath',
        );
      }
      await CaptureFiles.cleanStale(clipboardPath: clipboardPath);
    } catch (_) {
      // Never let cleanup prevent capture or startup.
    }
  }

  /// 에이전트(터미널 AI, Claude CLI, agy 등)에게 전달하기 적합한 템플릿 형태로 클립보드에 복사합니다.
  Future<String?> copyForAgent(
    CaptureItem item, {
    String template = '[image: {path}] 이 스크린샷을 분석해서 설명해줘.',
  }) async {
    final pngBytes = await renderAnnotatedPng(item);
    final temp = await getTemporaryDirectory();
    final folder = Directory('${temp.path}/snap_craft_clipboard');
    await folder.create(recursive: true);
    final clipboardFile = File(
      '${folder.path}/agent_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await clipboardFile.writeAsBytes(pngBytes, flush: true);

    final text = template.replaceAll('{path}', clipboardFile.path);
    await Clipboard.setData(ClipboardData(text: text));
    return text;
  }

  int _clipboardRequest = 0;
  Future<void>? _clipboardWrites;

  /// 마크업이 반영된 최종 이미지를 시스템 클립보드에 복사합니다.
  /// 최신 요청만 기록하고 네이티브 쓰기는 직렬화합니다.
  /// [shouldCopy]가 false이면 대기 중인 요청을 취소합니다.
  /// macOS에서는 이미지(PNG/TIFF)와 임시 파일 경로(fileURL/string)를 동시에 등록하여
  /// 일반 메신저/Claude Code(이미지 붙여넣기)와 터미널 CLI(agy 등 경로 붙여넣기) 모두에서 작동합니다.
  Future<bool> copyToClipboard(
    CaptureItem item, {
    bool Function()? shouldCopy,
  }) async {
    final request = ++_clipboardRequest;
    bool isCurrent() =>
        request == _clipboardRequest && (shouldCopy?.call() ?? true);
    try {
      // Snapshot and clone synchronously, before edits or disposal can occur.
      final pngBytes = await renderAnnotatedPng(item);
      if (!isCurrent()) return false;
      final previousWrite = _clipboardWrites;
      Future<bool> writeLatest() async {
        if (previousWrite != null) await previousWrite;
        if (!isCurrent()) return false;
        if (Platform.isMacOS) {
          final temp = await getTemporaryDirectory();
          final folder = Directory('${temp.path}/snap_craft_clipboard');
          await folder.create(recursive: true);
          if (!isCurrent()) return false;
          final clipboardFile = File(
            '${folder.path}/clipboard_${DateTime.now().microsecondsSinceEpoch}.png',
          );
          await clipboardFile.writeAsBytes(pngBytes, flush: true);
          if (!isCurrent()) {
            await clipboardFile.delete();
            return false;
          }
          final ok = await _macClipboardChannel.invokeMethod<bool>(
            'copyImageAndFile',
            {'bytes': pngBytes, 'path': clipboardFile.path},
          );
          return ok ?? true;
        }

        await Pasteboard.writeImage(pngBytes);
        return true;
      }

      final write = writeLatest();
      // A failed write must not poison the queue for subsequent requests.
      _clipboardWrites = write.then<void>((_) {}, onError: (Object _) {});
      return await write;
    } catch (_) {
      return false;
    }
  }

  /// 마크업이 반영된 최종 이미지를 PNG 파일로 저장합니다.
  Future<String?> saveToFile(
    CaptureItem item, {
    String? directory,
    @visibleForTesting Future<void> Function(File, Uint8List)? writeFile,
  }) async {
    final pngBytes = await renderAnnotatedPng(item);
    if (directory == null && Platform.isMacOS) {
      await FilePicker.skipEntitlementsChecks();
    }

    final defaultFileName =
        'SnapCraft_${item.capturedAt.year}${_twoDigits(item.capturedAt.month)}${_twoDigits(item.capturedAt.day)}_'
        '${_twoDigits(item.capturedAt.hour)}${_twoDigits(item.capturedAt.minute)}${_twoDigits(item.capturedAt.second)}.png';

    if (directory != null) {
      final folder = Directory(directory);
      if (!await folder.exists()) {
        throw FileSystemException('저장 폴더를 찾을 수 없습니다', directory);
      }
      final stem = defaultFileName.substring(0, defaultFileName.length - 4);
      for (var suffix = 0; ; suffix++) {
        final name = suffix == 0 ? defaultFileName : '${stem}_$suffix.png';
        final file = File.fromUri(folder.absolute.uri.resolve(name));
        try {
          await file.create(exclusive: true);
        } on FileSystemException {
          if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.notFound) {
            continue;
          }
          rethrow;
        }
        try {
          if (writeFile != null) {
            await writeFile(file, pngBytes);
          } else {
            await file.writeAsBytes(pngBytes, flush: true);
          }
          return file.path;
        } catch (_) {
          try {
            await file.delete();
          } on FileSystemException {
            // Preserve the write error if cleanup also fails.
          }
          rethrow;
        }
      }
    }

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

    final finalPath = savePath.toLowerCase().endsWith('.png')
        ? savePath
        : '$savePath.png';
    final file = File(finalPath);
    await file.writeAsBytes(pngBytes);
    return finalPath;
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
