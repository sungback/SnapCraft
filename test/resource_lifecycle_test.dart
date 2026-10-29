import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:snap_craft/models/annotation.dart';
import 'package:snap_craft/models/capture_item.dart';
import 'package:snap_craft/services/capture_files.dart';
import 'package:snap_craft/services/capture_service.dart';
import 'package:snap_craft/services/export_service.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _SystemCapture with SystemScreenCapturer {
  _SystemCapture(this.action);
  final Future<void> Function(String path) action;
  @override
  Future<void> capture({
    required CaptureMode mode,
    String? imagePath,
    bool copyToClipboard = true,
    bool silent = true,
  }) => action(imagePath!);
}

class _CapturePlatform extends ScreenCapturerPlatform {
  _CapturePlatform(this.systemScreenCapturer);
  @override
  final SystemScreenCapturer systemScreenCapturer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late PathProviderPlatform previousPaths;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('snapcraft resources ');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
  });
  tearDown(() async {
    PathProviderPlatform.instance = previousPaths;
    await temp.delete(recursive: true);
  });

  Future<CaptureItem> capture({bool annotated = true}) async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 32);
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    final file = await File('${temp.path}/original.png').writeAsBytes(bytes);
    return CaptureItem(
      id: 'test',
      filePath: file.path,
      originalBytes: bytes,
      decodedImage: image,
      capturedAt: DateTime.now(),
      mode: CaptureMode.region,
      annotations: annotated
          ? [
              const AnnotationItem(
                id: 'box',
                tool: AnnotationTool.rectangle,
                color: Colors.red,
                strokeWidth: 2,
                points: [Offset(4, 4), Offset(24, 24)],
              ),
            ]
          : [],
    );
  }

  test(
    'native capture failure restores the window and permits another capture',
    () async {
      final previous = ScreenCapturerPlatform.instance;
      var captures = 0;
      var shows = 0;
      String? attemptedPath;
      ScreenCapturerPlatform.instance = _CapturePlatform(
        _SystemCapture((path) async {
          captures++;
          attemptedPath = path;
          if (captures == 1) {
            await File(path).writeAsString('partial capture');
            throw StateError('native capture failed');
          }
        }),
      );
      const window = MethodChannel('window_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(window, (call) async {
            if (call.method == 'isVisible') return true;
            if (call.method == 'isMinimized') return false;
            if (call.method == 'show') shows++;
            return null;
          });
      addTearDown(() {
        ScreenCapturerPlatform.instance = previous;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(window, null);
      });
      await expectLater(
        CaptureService.instance.capture(CaptureMode.region),
        throwsStateError,
      );
      expect(await File(attemptedPath!).exists(), isFalse);
      expect(CaptureService.instance.isCapturing, isFalse);
      expect(await CaptureService.instance.capture(CaptureMode.region), isNull);
      expect(captures, 2);
      expect(shows, 2);
    },
  );

  test(
    'window restoration and clipboard errors do not discard a capture',
    () async {
      final fixture = await capture(annotated: false);
      final previous = ScreenCapturerPlatform.instance;
      ScreenCapturerPlatform.instance = _CapturePlatform(
        _SystemCapture((path) async {
          await File(path).writeAsBytes(fixture.originalBytes);
        }),
      );
      const window = MethodChannel('window_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(window, (call) async {
            if (call.method == 'isVisible') return true;
            if (call.method == 'isMinimized') return false;
            if (call.method == 'show') {
              throw PlatformException(code: 'restore_failed');
            }
            return null;
          });
      addTearDown(() {
        fixture.dispose();
        ScreenCapturerPlatform.instance = previous;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(window, null);
      });
      final item = await CaptureService.instance.capture(CaptureMode.region);
      expect(item, isNotNull);
      expect(item!.width, 32);
      expect(item.copiedToClipboard, isFalse);
      expect(CaptureService.instance.isCapturing, isFalse);
      item.dispose();
    },
  );

  test(
    'in-flight PNG export survives capture disposal and preserves annotations',
    () async {
      final item = await capture();
      final pending = ExportService.instance.renderAnnotatedPng(item);
      item.dispose();
      item.dispose(); // Cleanup is idempotent.
      final bytes = await pending;
      expect(bytes, isNot(orderedEquals(item.originalBytes)));
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 32);
      expect(frame.image.height, 32);
      frame.image.dispose();
      codec.dispose();
    },
  );

  test(
    'stale cleanup retains current clipboard file and recent files',
    () async {
      final dir = await Directory('${temp.path}/snap_craft_clipboard').create();
      final active = await File('${dir.path}/clipboard_1.png')
          .writeAsString('active');
      final stale = await File('${dir.path}/clipboard_2.png')
          .writeAsString('stale');
      final recent = await File('${dir.path}/clipboard_3.png')
          .writeAsString('recent');
      final unrelated = await File('${dir.path}/other.txt')
          .writeAsString('unrelated');
      final old = DateTime.now().subtract(const Duration(days: 8));
      for (final file in [active, stale, unrelated]) {
        await file.setLastModified(old);
      }
      await CaptureFiles.cleanStale(clipboardPath: active.path);
      expect(await active.exists(), isTrue);
      expect(await stale.exists(), isFalse);
      expect(await recent.exists(), isTrue);
      expect(await unrelated.exists(), isTrue);
    },
  );

  test('clipboard export survives deletion of capture original', () async {
    final item = await capture(annotated: false);
    String? clipboardPath;
    const channel = MethodChannel('snap_craft/clipboard');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          clipboardPath = (call.arguments as Map)['path'] as String;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    expect(await ExportService.instance.copyToClipboard(item), isTrue);
    await CaptureFiles.deleteOriginal(item.filePath);
    item.dispose();
    expect(await File(item.filePath).exists(), isFalse);
    expect(
      await File(clipboardPath!).readAsBytes(),
      orderedEquals(item.originalBytes),
    );
  }, skip: !Platform.isMacOS);
}
