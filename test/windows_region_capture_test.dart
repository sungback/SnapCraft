import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:snap_craft/services/windows_region_capture.dart';

class _CapturePlatform extends ScreenCapturerPlatform {
  String? savedPath;

  @override
  SystemScreenCapturer get systemScreenCapturer => throw UnimplementedError();

  @override
  Future<void> saveClipboardImageAsPngFile({required String imagePath}) async {
    savedPath = imagePath;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('waits for the selected image after the picker loses focus', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final previous = ScreenCapturerPlatform.instance;
    final capture = _CapturePlatform();
    ScreenCapturerPlatform.instance = capture;
    var polls = 0;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('snap_craft/windows_capture'),
      (call) async {
        if (call.method == 'regionCaptureState') {
          polls++;
          return {'active': polls == 1, 'image': polls >= 3};
        }
        return null;
      },
    );
    addTearDown(() {
      ScreenCapturerPlatform.instance = previous;
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
      messenger.setMockMethodCallHandler(
        const MethodChannel('snap_craft/windows_capture'),
        null,
      );
    });
    await captureWindowsRegion('capture.png');
    expect(polls, 3);
    expect(capture.savedPath, 'capture.png');
  });
}
