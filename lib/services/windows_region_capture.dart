import 'package:flutter/services.dart';
import 'package:screen_capturer/screen_capturer.dart';

const _channel = MethodChannel('snap_craft/windows_capture');

/// Wait for the Windows clipping UI and its clipboard result, including slow starts.
Future<void> captureWindowsRegion(String imagePath) async {
  await Clipboard.setData(const ClipboardData(text: ''));
  await _channel.invokeMethod<void>('startRegionCapture');
  var seenPicker = false;
  var absentSince = DateTime.now();
  final deadline = DateTime.now().add(const Duration(minutes: 2));
  while (DateTime.now().isBefore(deadline)) {
    final state = await _channel.invokeMapMethod<String, bool>(
      'regionCaptureState',
    );
    if (state?['image'] == true) {
      await ScreenCapturerPlatform.instance.saveClipboardImageAsPngFile(
        imagePath: imagePath,
      );
      return;
    }
    if (state?['active'] == true) {
      seenPicker = true;
      absentSince = DateTime.now();
    } else if (DateTime.now().difference(absentSince) >
        Duration(seconds: seenPicker ? 2 : 10)) {
      if (!seenPicker) {
        throw StateError('Windows 영역 캡쳐 화면을 시작하지 못했습니다.');
      }
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  throw StateError('Windows 영역 캡쳐가 시간 초과되었습니다.');
}
