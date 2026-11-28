import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snap_craft/models/annotation.dart';
import 'package:snap_craft/services/capture_service.dart';
import 'package:snap_craft/services/startup_service.dart';

class _MockPathProvider extends PathProviderPlatform {
  final String tempPath;
  _MockPathProvider(this.tempPath);
  @override
  Future<String?> getTemporaryPath() async => tempPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnnotationItem hitTest & translated', () {
    test('translated는 모든 포인트를 동일한 오프셋만큼 이동시킨다', () {
      const rect = AnnotationItem(
        id: 'r1',
        tool: AnnotationTool.rectangle,
        color: Colors.red,
        strokeWidth: 4,
        points: [Offset(10, 20), Offset(60, 80)],
      );

      final moved = rect.translated(const Offset(15, -5));
      expect(moved.points, const [Offset(25, 15), Offset(75, 75)]);
      expect(moved.id, 'r1');
    });

    test('hitTest가 선분·사각형·스텝카운터·텍스트에서 정확하게 동작한다', () {
      const pen = AnnotationItem(
        id: 'p1',
        tool: AnnotationTool.pen,
        color: Colors.blue,
        strokeWidth: 4,
        points: [Offset(0, 0), Offset(100, 0)],
      );
      expect(pen.hitTest(const Offset(50, 5)), isTrue);
      expect(pen.hitTest(const Offset(50, 40)), isFalse);

      const rect = AnnotationItem(
        id: 'r1',
        tool: AnnotationTool.rectangle,
        color: Colors.green,
        strokeWidth: 4,
        points: [Offset(20, 20), Offset(80, 80)],
      );
      expect(rect.hitTest(const Offset(50, 50)), isTrue);
      expect(rect.hitTest(const Offset(150, 150)), isFalse);

      const step = AnnotationItem(
        id: 's1',
        tool: AnnotationTool.stepCounter,
        color: Colors.orange,
        strokeWidth: 5,
        points: [Offset(100, 100)],
        text: '1',
      );
      expect(step.hitTest(const Offset(105, 105)), isTrue);
      expect(step.hitTest(const Offset(200, 200)), isFalse);

      const label = AnnotationItem(
        id: 't1',
        tool: AnnotationTool.text,
        color: Colors.white,
        strokeWidth: 5,
        points: [Offset(40, 40)],
        text: 'Hello',
      );
      expect(label.hitTest(const Offset(55, 50)), isTrue);
      expect(label.hitTest(const Offset(300, 300)), isFalse);
    });
  });

  group('StartupService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('초기 상태는 비활성화이며 setEnabled로 상태를 저장한다', () async {
      await StartupService.instance.init();
      expect(StartupService.instance.isEnabled, isFalse);

      await StartupService.instance.setEnabled(true);
      expect(StartupService.instance.isEnabled, isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('snap_craft_launch_at_startup'), isTrue);

      await StartupService.instance.setEnabled(false);
      expect(StartupService.instance.isEnabled, isFalse);
    });

    test('macOS LaunchAgent plist가 실행 경로와 --start-minimized를 이스케이프 포함 생성한다', () {
      final plist = StartupService.buildMacLaunchAgentPlist(
        '/Applications/Snap & Craft.app/Contents/MacOS/snap_craft',
      );
      expect(plist, contains('<string>com.example.snapCraft</string>'));
      expect(
        plist,
        contains(
          '<string>/Applications/Snap &amp; Craft.app/Contents/MacOS/snap_craft</string>',
        ),
      );
      expect(plist, contains('<string>--start-minimized</string>'));
      expect(plist, contains('<true/>'));
    });
  });

  group('CaptureService.createFromBytes', () {
    late Directory tempDir;
    late PathProviderPlatform previousPlatform;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('snap_craft_import_test');
      previousPlatform = PathProviderPlatform.instance;
      PathProviderPlatform.instance = _MockPathProvider(tempDir.path);
    });

    tearDown(() {
      PathProviderPlatform.instance = previousPlatform;
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('이미지 바이트로 PNG 정규화된 CaptureItem을 생성한다', () async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.teal, BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(64, 48);
      picture.dispose();
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = byteData!.buffer.asUint8List();

      final item = await CaptureService.instance.createFromBytes(
        bytes,
        prefix: 'paste',
      );
      expect(item, isNotNull);
      addTearDown(() => item!.dispose());
      expect(item!.width, 64);
      expect(item.height, 48);
      expect(File(item.filePath).existsSync(), isTrue);
      expect(item.originalBytes.isNotEmpty, isTrue);
    });
  });
}
