import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:window_manager/window_manager.dart';

import '../models/capture_item.dart';
import 'export_service.dart';

class CaptureService {
  CaptureService._();
  static final CaptureService instance = CaptureService._();

  static const MethodChannel _windowsCaptureChannel = MethodChannel(
    'snap_craft/windows_capture',
  );

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

    bool wasVisible = false;
    CaptureItem? item;
    bool completed = false;
    String? pendingPath;
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
      pendingPath = filePath;

      Uint8List? imageBytes;
      if (Platform.isWindows && mode == CaptureMode.window) {
        // Windows에서 기본 ms-screenclip 창 모드는 다른 창에 가려진 영역이 그대로 찍히고
        // 7px 투명 테두리가 포함되는 문제가 있으므로 네이티브 Win32 창 선택/전면화 캡쳐 채널 사용
        final ok = await _windowsCaptureChannel.invokeMethod<bool>(
          'captureWindow',
          {'path': filePath},
        );
        if (ok != true) {
          return null;
        }
      } else {
        // The convenience wrapper decodes another image without exposing its
        // lifetime. Capture the file directly and decode exactly once below.
        await ScreenCapturerPlatform.instance.systemScreenCapturer.capture(
          mode: mode,
          imagePath: filePath,
          copyToClipboard: false,
          silent: true,
        );
      }

      final file = File(filePath);
      if (await file.exists()) {
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
      late ui.FrameInfo frame;
      try {
        frame = await codec.getNextFrame();
      } finally {
        codec.dispose();
      }

      item = CaptureItem(
        id: 'snap_$timestamp',
        filePath: filePath,
        originalBytes: imageBytes,
        decodedImage: frame.image,
        capturedAt: DateTime.now(),
        mode: mode,
      );

      // 캡쳐 직후 클립보드에 이미지 + 파일 경로 자동 복사
      item.copiedToClipboard = await ExportService.instance.copyToClipboard(
        item,
      );
      completed = true;

      return item;
    } finally {
      try {
        if (!completed) item?.dispose();
        if (!completed && pendingPath != null) {
          try {
            final file = File(pendingPath);
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }
        if (hideAppWindow && wasVisible) {
          try {
            await windowManager.show();
            await windowManager.focus();
          } catch (error) {
            // A restoration failure must not discard a successful capture.
            debugPrint('캡쳐 후 창 복원 실패: $error');
          }
        }
      } finally {
        _isCapturing = false;
      }
    }
  }
}
