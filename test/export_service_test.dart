import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
// The package exposes no public platform-interface entry point.
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:snap_craft/models/annotation.dart';
import 'package:snap_craft/models/capture_item.dart';
import 'package:snap_craft/services/export_service.dart';

class _Picker extends FilePickerPlatform {
  String? result;
  int calls = 0;
  int entitlementCalls = 0;
  String? suggestedName;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    calls++;
    suggestedName = fileName;
    return result;
  }

  @override
  Future<void> skipEntitlementsChecks() async => entitlementCalls++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late CaptureItem item;
  late FilePickerPlatform previousPicker;
  late _Picker picker;
  final export = ExportService.instance;
  const name = 'SnapCraft_20260102_030405.png';

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('SnapCraft 한글 폴더 ');
    previousPicker = FilePickerPlatform.instance;
    picker = _Picker();
    FilePickerPlatform.instance = picker;
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 24);
    picture.dispose();
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!
        .buffer
        .asUint8List();
    item = CaptureItem(
      id: 'export',
      filePath: '${folder.path}/original.png',
      originalBytes: bytes,
      decodedImage: image,
      capturedAt: DateTime(2026, 1, 2, 3, 4, 5),
      mode: CaptureMode.region,
      annotations: [
        const AnnotationItem(
          id: 'rectangle',
          tool: AnnotationTool.rectangle,
          color: Colors.red,
          strokeWidth: 2,
          points: [Offset(4, 4), Offset(28, 20)],
        ),
      ],
    );
  });

  tearDown(() async {
    item.dispose();
    FilePickerPlatform.instance = previousPicker;
    await folder.delete(recursive: true);
  });

  Future<void> expectAnnotatedPng(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    try {
      expect(image.width, 32);
      expect(image.height, 24);
      final rgba = (await image.toByteData())!;
      // Top border, away from the rounded corners.
      final border = (4 * image.width + 16) * 4;
      expect(rgba.getUint8(border), 244);
      expect(rgba.getUint8(border + 1), 67);
      expect(rgba.getUint8(border + 2), 54);
      final center = (12 * image.width + 16) * 4;
      expect(rgba.getUint8(center + 1), 255);
    } finally {
      image.dispose();
      codec.dispose();
    }
  }

  test(
    'direct save uses the configured Unicode path and annotated pixels',
    () async {
      final path = await export.saveToFile(item, directory: folder.path);
      expect(path, File('${folder.path}/$name').path);
      expect(picker.calls, 0);
      expect(picker.entitlementCalls, 0);
      await expectAnnotatedPng(path!);
    },
  );

  test(
    'repeated saves preserve existing files and choose numbered names',
    () async {
      final original = File('${folder.path}/$name');
      await original.writeAsString('existing file');
      final first = await export.saveToFile(item, directory: folder.path);
      final firstBytes = await File(first!).readAsBytes();
      final second = await export.saveToFile(item, directory: folder.path);
      expect(first, '${folder.path}/SnapCraft_20260102_030405_1.png');
      expect(second, '${folder.path}/SnapCraft_20260102_030405_2.png');
      expect(await original.readAsString(), 'existing file');
      expect(await File(first).readAsBytes(), orderedEquals(firstBytes));
      await expectAnnotatedPng(second!);
    },
  );

  test('concurrent saves never claim the same file', () async {
    final paths = await Future.wait([
      export.saveToFile(item, directory: folder.path),
      export.saveToFile(item, directory: folder.path),
    ]);
    expect(paths.toSet(), hasLength(2));
    for (final path in paths) {
      await expectAnnotatedPng(path!);
    }
  });

  test('a missing configured folder fails without recreating it', () async {
    final missing = Directory('${folder.path}/removed');
    await expectLater(
      export.saveToFile(item, directory: missing.path),
      throwsA(isA<FileSystemException>()),
    );
    expect(await missing.exists(), isFalse);
    expect(await folder.list().toList(), isEmpty);
    expect(picker.calls, 0);
  });

  test('dialog save adds the PNG extension and renders annotations', () async {
    picker.result = '${folder.path}/chosen';
    final path = await export.saveToFile(item);
    expect(path, '${folder.path}/chosen.png');
    expect(picker.calls, 1);
    expect(picker.suggestedName, name);
    expect(picker.entitlementCalls, Platform.isMacOS ? 1 : 0);
    await expectAnnotatedPng(path!);
  });

  test('cancelled dialog creates no file', () async {
    expect(await export.saveToFile(item), isNull);
    expect(picker.calls, 1);
    expect(await folder.list().toList(), isEmpty);
  });
}
