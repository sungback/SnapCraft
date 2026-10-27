import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:window_manager/window_manager.dart';
import '../models/capture_item.dart';
import 'export_service.dart';

class CaptureService {
  CaptureService._();
  static final CaptureService instance = CaptureService._();

  bool _isCapturing = false;
  bool get isCapturing => _isCapturing;

  /// macOS 화면 기록 권한 설정 창 수동 열기
  Future<void> openMacScreenRecordingSettings() async {
    if (!Platform.isMacOS) return;
    try {
      await screenCapturer.requestAccess(onlyOpenPrefPane: true);
    } catch (_) {}
  }

  /// 지정된 모드로 화면 캡쳐 실행
  Future<CaptureItem?> capture(
    CaptureMode mode, {
    bool hideAppWindow = true,
  }) async {
    if (_isCapturing) return null;
    _isCapturing = true;

    bool wasVisible = true;
    try {
      if (hideAppWindow) {
        wasVisible = await windowManager.isVisible();
        if (wasVisible) {
          await windowManager.hide();
          // 창 숨김 애니메이션이 완전히 끝날 때까지 대기
          await Future.delayed(const Duration(milliseconds: 240));
        }
      }

      final tempDir = await getTemporaryDirectory();
      final capturesDir = Directory('${tempDir.path}/snap_craft_captures');
      if (!await capturesDir.exists()) {
        await capturesDir.create(recursive: true);
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filePath = '${capturesDir.path}/snap_$timestamp.png';

      final capturedData = await screenCapturer.capture(
        mode: mode,
        imagePath: filePath,
        copyToClipboard: false,
        silent: true,
      );

      final file = File(filePath);
      Uint8List? imageBytes = capturedData?.imageBytes;

      if (imageBytes == null && await file.exists()) {
        final length = await file.length();
        if (length > 0) {
          imageBytes = await file.readAsBytes();
        }
      }

      if (imageBytes == null || imageBytes.isEmpty) {
        // 사용자가 ESC 등으로 캡쳐를 취소한 경우
        return null;
      }

      final codec = await ui.instantiateImageCodec(imageBytes);
      final frame = await codec.getNextFrame();

      final item = CaptureItem(
        id: 'snap_$timestamp',
        filePath: filePath,
        originalBytes: imageBytes,
        decodedImage: frame.image,
        capturedAt: DateTime.now(),
        mode: mode,
      );

      // 캡쳐 직후 클립보드에 이미지 + 파일 경로 자동 복사
      await ExportService.instance.copyToClipboard(item);

      return item;
    } finally {
      _isCapturing = false;
      if (hideAppWindow && wasVisible) {
        await windowManager.show();
        await windowManager.focus();
      }
    }
  }
}
