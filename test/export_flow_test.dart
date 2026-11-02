import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
// FilePicker does not export its platform seam in this package version.
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snap_craft/main.dart';
import 'package:snap_craft/services/capture_service.dart';
import 'package:snap_craft/widgets/top_toolbar.dart';

class _Picker extends FilePickerPlatform {
  Completer<String?>? _directory;
  Completer<String?> get directory => _directory ??= Completer<String?>();
  set directory(Completer<String?> value) => _directory = value;
  Completer<String?>? _save;
  Completer<String?> get save => _save ??= Completer<String?>();
  set save(Completer<String?> value) => _save = value;
  int directoryCalls = 0;
  int saveCalls = 0;
  String? lastInitialDirectory;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    bool lockParentWindow = false,
    String? initialDirectory,
  }) {
    directoryCalls++;
    lastInitialDirectory = initialDirectory;
    return directory.future;
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) {
    saveCalls++;
    return save.future;
  }
}

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
  late _Picker picker;
  late FilePickerPlatform previousPicker;

  setUp(() {
    SharedPreferences.setMockInitialValues({'png_save_directory': '/기존 폴더'});
    previousPicker = FilePickerPlatform.instance;
    picker = _Picker();
    FilePickerPlatform.instance = picker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isVisible' ? false : null,
        );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.leanflutter.plugins/hotkey_manager_event'),
          (call) async => null,
        );
  });

  tearDown(() {
    FilePickerPlatform.instance = previousPicker;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.leanflutter.plugins/hotkey_manager_event'),
          null,
        );
  });

  TopToolbar toolbar(WidgetTester tester) =>
      tester.widget<TopToolbar>(find.byType(TopToolbar));

  Future<void> launch(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(880, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SnapCraftApp());
    await tester.pumpAndSettle();
  }

  Future<void> chooseDirectory(WidgetTester tester) async {
    final previousCalls = picker.directoryCalls;
    await tester.runAsync(() async {
      picker.directory = Completer<String?>();
      toolbar(tester).onChooseSaveDirectory();
      for (var i = 0; i < 100 && picker.directoryCalls == previousCalls; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();
    expect(picker.directoryCalls, previousCalls + 1);
  }

  Future<void> finishDirectory(
    WidgetTester tester,
    String? directory, {
    Object? error,
  }) async {
    await tester.runAsync(() async {
      if (error == null) {
        picker.directory.complete(directory);
      } else {
        picker.directory.completeError(error);
      }
      await Future<void>.delayed(Duration.zero);
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'folder picker cancellation preserves restored settings and guard',
    (tester) async {
      await launch(tester);
      expect(toolbar(tester).saveDirectory, '/기존 폴더');
      await chooseDirectory(tester);
      expect(toolbar(tester).isExportBusy, isTrue);
      expect(picker.directoryCalls, 1);
      expect(picker.lastInitialDirectory, isNull);

      toolbar(tester).onChooseSaveDirectory();
      toolbar(tester).onClearSaveDirectory();
      toolbar(tester).onSaveFile();
      await tester.pump();
      expect(picker.directoryCalls, 1);
      expect(picker.saveCalls, 0);
      expect(toolbar(tester).saveDirectory, '/기존 폴더');

      await finishDirectory(tester, null);
      expect(toolbar(tester).isExportBusy, isFalse);
      expect(toolbar(tester).saveDirectory, '/기존 폴더');
      expect(
        (await SharedPreferences.getInstance()).getString('png_save_directory'),
        '/기존 폴더',
      );
    },
  );

  testWidgets('changing and clearing folders update persistent settings', (
    tester,
  ) async {
    await launch(tester);
    await chooseDirectory(tester);
    await finishDirectory(tester, '/새 폴더');
    expect(toolbar(tester).saveDirectory, '/새 폴더');
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('png_save_directory'), '/새 폴더');

    toolbar(tester).onClearSaveDirectory();
    await tester.pumpAndSettle();
    expect(toolbar(tester).saveDirectory, isNull);
    expect(preferences.containsKey('png_save_directory'), isFalse);
    expect(toolbar(tester).isExportBusy, isFalse);
  });

  testWidgets('picker failure keeps the folder and allows retry', (
    tester,
  ) async {
    await launch(tester);
    await chooseDirectory(tester);
    await finishDirectory(
      tester,
      null,
      error: PlatformException(code: 'picker_failure'),
    );
    expect(toolbar(tester).isExportBusy, isFalse);
    expect(toolbar(tester).saveDirectory, '/기존 폴더');
    expect(find.textContaining('저장 폴더 설정 실패:'), findsOneWidget);

    await chooseDirectory(tester);
    expect(picker.directoryCalls, 2);
    await finishDirectory(tester, '/복구 폴더');
    expect(toolbar(tester).saveDirectory, '/복구 폴더');
  });

  testWidgets(
    'save button and keyboard share a guard until cancel or failure',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final previousPaths = PathProviderPlatform.instance;
      final previousCapture = ScreenCapturerPlatform.instance;
      late Directory temp;
      await tester.runAsync(() async {
        temp = await Directory.systemTemp.createTemp('snapcraft export flow ');
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawColor(Colors.white, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 16);
        picture.dispose();
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
            .buffer
            .asUint8List();
        image.dispose();
        ScreenCapturerPlatform.instance = _CapturePlatform(
          _SystemCapture(bytes),
        );
        PathProviderPlatform.instance = _Paths(temp.path);
      });
      addTearDown(() async {
        PathProviderPlatform.instance = previousPaths;
        ScreenCapturerPlatform.instance = previousCapture;
        await temp.delete(recursive: true);
      });
      await launch(tester);
      await tester.runAsync(() async {
        toolbar(tester).onTriggerCapture(CaptureMode.region);
        for (var i = 0; i < 100 && CaptureService.instance.isCapturing; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(toolbar(tester).hasActiveCapture, isTrue);

      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.runAsync(() async {
          toolbar(tester).onSaveFile();
          for (var i = 0; i < 100 && picker.saveCalls <= attempt; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pumpAndSettle();
        expect(toolbar(tester).isExportBusy, isTrue);
        expect(picker.saveCalls, attempt + 1);
        toolbar(tester).onSaveFile();
        toolbar(tester).onClearSaveDirectory();
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        expect(picker.saveCalls, attempt + 1);
        await tester.runAsync(() async {
          if (attempt == 0) {
            picker.save.complete(null);
          } else {
            picker.save.completeError(PlatformException(code: 'save_failure'));
          }
          await Future<void>.delayed(Duration.zero);
        });
        await tester.pumpAndSettle();
        expect(toolbar(tester).isExportBusy, isFalse);
        picker.save = Completer<String?>();
      }
      expect(find.textContaining('파일 저장 실패:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
}
