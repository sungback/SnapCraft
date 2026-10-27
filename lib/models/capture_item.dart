import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:screen_capturer/screen_capturer.dart';
import 'annotation.dart';

/// 캡쳐된 단일 스크린샷 항목과 마크업 편집 히스토리 모델
class CaptureItem {
  final String id;
  final String filePath;
  final Uint8List originalBytes;
  final ui.Image decodedImage;
  final DateTime capturedAt;
  final CaptureMode mode;
  final List<AnnotationItem> annotations;
  final List<AnnotationItem> redoStack;

  CaptureItem({
    required this.id,
    required this.filePath,
    required this.originalBytes,
    required this.decodedImage,
    required this.capturedAt,
    required this.mode,
    List<AnnotationItem>? annotations,
    List<AnnotationItem>? redoStack,
  })  : annotations = annotations ?? [],
        redoStack = redoStack ?? [];

  int get width => decodedImage.width;
  int get height => decodedImage.height;

  String get resolutionLabel => '${width}x$height';

  String get modeLabel {
    switch (mode) {
      case CaptureMode.region:
        return '영역 캡쳐';
      case CaptureMode.screen:
        return '전체 화면';
      case CaptureMode.window:
        return '창 캡쳐';
    }
  }
}
