import 'dart:io';

import 'package:flutter/services.dart';

import '../models/capture_item.dart';
import 'export_service.dart';

class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  static const MethodChannel _channel = MethodChannel('snap_craft/ocr');

  /// 지정된 이미지 파일에서 텍스트를 추출합니다.
  Future<String?> extractTextFromPath(String filePath) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('현재 화면 텍스트 추출(로컬 OCR)은 macOS에서 지원됩니다.');
    }

    try {
      final text = await _channel.invokeMethod<String>(
        'recognizeText',
        {'path': filePath},
      );
      return text?.trim();
    } on PlatformException catch (e) {
      throw StateError('텍스트 추출 실패: ${e.message ?? e.code}');
    }
  }

  /// CaptureItem(현재 편집된 주석 포함)에서 텍스트를 추출합니다.
  Future<String?> recognizeText(CaptureItem item) async {
    String imagePathToUse = item.filePath;
    File? tempAnnotatedFile;

    try {
      // 주석이 있는 경우 주석이 포함된 PNG를 임시 생성하여 OCR 분석
      if (item.annotations.isNotEmpty) {
        final pngBytes = await ExportService.instance.renderAnnotatedPng(item);
        final tempDir = Directory.systemTemp;
        tempAnnotatedFile = File(
          '${tempDir.path}/snap_ocr_${DateTime.now().microsecondsSinceEpoch}.png',
        );
        await tempAnnotatedFile.writeAsBytes(pngBytes, flush: true);
        imagePathToUse = tempAnnotatedFile.path;
      }

      return await extractTextFromPath(imagePathToUse);
    } finally {
      if (tempAnnotatedFile != null && await tempAnnotatedFile.exists()) {
        try {
          await tempAnnotatedFile.delete();
        } catch (_) {}
      }
    }
  }
}
