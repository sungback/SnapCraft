import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snap_craft/main.dart';
import 'package:snap_craft/models/annotation.dart';
import 'package:snap_craft/models/capture_item.dart';
import 'package:snap_craft/services/export_service.dart';
import 'package:snap_craft/widgets/annotation_canvas.dart';
import 'package:snap_craft/widgets/history_sidebar.dart';
import 'package:snap_craft/widgets/top_toolbar.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

class _SystemCapture with SystemScreenCapturer {
  _SystemCapture(this.bytes);
  final Uint8List bytes;
  @override
  Future<void> capture({
    required CaptureMode mode,
    String? imagePath,
    bool copyToClipboard = true,
    bool silent = true,
  }) async {
    await File(imagePath!).writeAsBytes(bytes);
  }
}

class _CapturePlatform extends ScreenCapturerPlatform {
  _CapturePlatform(this.systemScreenCapturer);
  @override
  final SystemScreenCapturer systemScreenCapturer;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const clipboard = MethodChannel('snap_craft/clipboard');
  const pasteboard = MethodChannel('pasteboard');
  late Directory temp;
  late PathProviderPlatform previousPaths;
  late ScreenCapturerPlatform previousCapture;
  late CaptureItem source;
  final writes = <Uint8List>[];
  Future<void> Function()? beforeWrite;
  var fail = false;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('snapcraft auto clipboard ');
    previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _Paths(temp.path);
    previousCapture = ScreenCapturerPlatform.instance;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 24);
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    source = CaptureItem(
      id: 'source',
      filePath: '${temp.path}/source.png',
      originalBytes: bytes,
      decodedImage: image,
      capturedAt: DateTime.now(),
      mode: CaptureMode.region,
    );
    ScreenCapturerPlatform.instance = _CapturePlatform(_SystemCapture(bytes));
    writes.clear();
    beforeWrite = null;
    fail = false;
    Future<Object?> handle(MethodCall call) async {
      if (call.method != 'copyImageAndFile' && call.method != 'writeImage') {
        return null;
      }
      final args = call.arguments;
      final Uint8List bytes;
      if (args is Uint8List) {
        bytes = args;
      } else if ((args as Map).containsKey('bytes')) {
        bytes = args['bytes'] as Uint8List;
      } else {
        bytes = await File(args['fileName'] as String).readAsBytes();
      }
      await beforeWrite?.call();
      if (fail) throw PlatformException(code: 'clipboard_failed');
      writes.add(bytes);
      return true;
    }

    messenger.setMockMethodCallHandler(clipboard, handle);
    messenger.setMockMethodCallHandler(pasteboard, handle);
    messenger.setMockMethodCallHandler(
      const MethodChannel('window_manager'),
      (call) async => call.method == 'isVisible' ? false : null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.leanflutter.plugins/hotkey_manager_event'),
      (call) async => null,
    );
  });

  tearDown(() async {
    source.dispose();
    PathProviderPlatform.instance = previousPaths;
    ScreenCapturerPlatform.instance = previousCapture;
    for (final channel in [
      clipboard,
      pasteboard,
      const MethodChannel('window_manager'),
      const MethodChannel('dev.leanflutter.plugins/hotkey_manager_event'),
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
    await temp.delete(recursive: true);
  });

  AnnotationItem mask(String id, double left) => AnnotationItem(
    id: id,
    tool: AnnotationTool.redaction,
    color: Colors.transparent,
    strokeWidth: 1,
    points: [Offset(left, 2), Offset(left + 5, 8)],
  );

  Future<void> expectBlack(Uint8List bytes, int x, int y) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    try {
      final rgba = (await image.toByteData())!.buffer.asUint8List();
      final offset = (y * image.width + x) * 4;
      expect(rgba.sublist(offset, offset + 4), [0, 0, 0, 255]);
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  TopToolbar toolbar(WidgetTester tester) =>
      tester.widget(find.byType(TopToolbar));
  AnnotationCanvas canvas(WidgetTester tester) =>
      tester.widget(find.byType(AnnotationCanvas));

  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1180, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SnapCraftApp());
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await (Function.apply(toolbar(tester).onTriggerCapture, [
        CaptureMode.region,
      ]) as Future<void>);
    });
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    writes.clear();
  }

  Future<void> finish(WidgetTester tester, {VoidCallback? action}) async {
    // Start image/IO work in the real async zone, like the desktop event loop.
    await tester.runAsync(() async {
      action?.call();
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'only completed redactions auto-copy, and undo/redo do not copy',
    (tester) async {
      await launch(tester);
      canvas(tester).onAddAnnotation(
        const AnnotationItem(
          id: 'pen',
          tool: AnnotationTool.pen,
          color: Colors.red,
          strokeWidth: 1,
          points: [Offset(20, 15), Offset(25, 15)],
        ),
      );
      await finish(tester);
      expect(writes, isEmpty);
      await finish(
        tester,
        action: () => canvas(tester).onAddAnnotation(mask('first', 2)),
      );

      expect(writes, hasLength(1));
      await tester.runAsync(() => expectBlack(writes.single, 3, 3));
      expect(find.text('보안 가림이 반영된 이미지를 클립보드에 자동 복사했습니다.'), findsOneWidget);
      toolbar(tester).onUndo();
      await tester.pump();
      toolbar(tester).onRedo();
      await finish(tester);
      expect(writes, hasLength(1));
      await tester.pumpWidget(const SizedBox.shrink());
    },
    skip: !Platform.isMacOS && !Platform.isWindows,
  );

  testWidgets('rapid redactions copy only the latest image with both masks', (
    tester,
  ) async {
    await launch(tester);
    final add = canvas(tester).onAddAnnotation;
    await finish(
      tester,
      action: () {
        add(mask('first', 2));
        add(mask('second', 12));
      },
    );
    expect(writes, hasLength(1));
    await tester.runAsync(() async {
      await expectBlack(writes.single, 3, 3);
      await expectBlack(writes.single, 13, 3);
    });
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isMacOS && !Platform.isWindows);

  for (final action in ['undo', 'clear', 'delete', 'dispose']) {
    testWidgets('$action cancels a pending automatic copy', (tester) async {
      await launch(tester);
      canvas(tester).onAddAnnotation(mask('first', 2));
      switch (action) {
        case 'undo':
          toolbar(tester).onUndo();
        case 'clear':
          toolbar(tester).onClearAnnotations();
        case 'delete':
          final sidebar = tester.widget<HistorySidebar>(
            find.byType(HistorySidebar),
          );
          sidebar.onDeleteItem(sidebar.items.single);
        case 'dispose':
          await tester.pumpWidget(const SizedBox.shrink());
      }
      await finish(tester);
      expect(writes, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, skip: !Platform.isMacOS && !Platform.isWindows);
  }

  testWidgets('auto-copy failure is reported and manual retry works', (
    tester,
  ) async {
    await launch(tester);
    fail = true;
    await finish(
      tester,
      action: () => canvas(tester).onAddAnnotation(mask('first', 2)),
    );
    expect(
      find.text('보안 가림 이미지 자동 복사에 실패했습니다. 복사 버튼으로 다시 시도하세요.'),
      findsOneWidget,
    );
    fail = false;
    await tester.runAsync(() async {
      await (Function.apply(toolbar(tester).onCopyClipboard, [])
          as Future<void>);
    });
    await tester.pumpAndSettle();
    expect(writes, hasLength(1));
    await tester.runAsync(() => expectBlack(writes.single, 3, 3));
    await tester.pumpWidget(const SizedBox.shrink());
  }, skip: !Platform.isMacOS && !Platform.isWindows);

  test('in-flight native writes are serialized and latest copy wins', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    var calls = 0;
    beforeWrite = () async {
      calls++;
      if (calls == 1) {
        started.complete();
        await release.future;
      }
    };
    final first = ExportService.instance.copyToClipboard(source);
    try {
      await started.future.timeout(const Duration(seconds: 10));
      source.annotations.add(mask('latest', 2));
      final latest = ExportService.instance.copyToClipboard(source);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(calls, 1);
      release.complete();
      expect(await first, isTrue);
      expect(await latest, isTrue);
      expect(writes, hasLength(2));
      await expectBlack(writes.last, 3, 3);
    } finally {
      if (!release.isCompleted) release.complete();
      await first;
    }
  }, skip: !Platform.isMacOS && !Platform.isWindows);

  test('cancelled queued write never reaches the native clipboard', () async {
    var valid = true;
    final pending = ExportService.instance.copyToClipboard(
      source,
      shouldCopy: () => valid,
    );
    valid = false;
    expect(await pending, isFalse);
    expect(writes, isEmpty);
    expect(await ExportService.instance.copyToClipboard(source), isTrue);
    expect(writes, hasLength(1));
  }, skip: !Platform.isMacOS && !Platform.isWindows);
}
