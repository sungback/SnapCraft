import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/capture_item.dart';
import 'export_service.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class OcrService {
  OcrService._();
  static final OcrService instance = OcrService._();

  static const MethodChannel _channel = MethodChannel('snap_craft/ocr');

  @visibleForTesting
  static String buildWindowsOcrScript(String filePath) {
    final escapedPath = filePath.replaceAll("'", "''");
    return '''
\$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Add-Type -AssemblyName System.Runtime.WindowsRuntime
\$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
  \$_.Name -eq 'AsTask' -and \$_.GetParameters().Count -eq 1 -and \$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
})[0]
function Await(\$WinRtTask, \$ResultType) {
  \$asTask = \$asTaskGeneric.MakeGenericMethod(\$ResultType)
  \$netTask = \$asTask.Invoke(\$null, @(\$WinRtTask))
  \$netTask.Wait(-1) | Out-Null
  \$netTask.Result
}
\$null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
\$null = [Windows.Graphics.Imaging.BitmapDecoder,Windows.Graphics.Imaging,ContentType=WindowsRuntime]
\$null = [Windows.Media.Ocr.OcrEngine,Windows.Media.Ocr,ContentType=WindowsRuntime]
\$file = Await ([Windows.Storage.StorageFile]::GetFileFromPathAsync('$escapedPath')) ([Windows.Storage.StorageFile])
\$stream = Await (\$file.OpenAsync([Windows.Storage.FileAccessMode]::Read)) ([Windows.Storage.Streams.IRandomAccessStream])
\$bitmap = \$null
try {
  \$decoder = Await ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync(\$stream)) ([Windows.Graphics.Imaging.BitmapDecoder])
  \$bitmap = Await (\$decoder.GetSoftwareBitmapAsync()) ([Windows.Graphics.Imaging.SoftwareBitmap])
  \$engine = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
  if (\$null -eq \$engine) {
    throw 'No OCR language pack available for user profile languages.'
  }
  \$ocrResult = Await (\$engine.RecognizeAsync(\$bitmap)) ([Windows.Media.Ocr.OcrResult])
  (\$ocrResult.Lines | ForEach-Object { \$_.Text }) -join "`n"
} finally {
  if (\$null -ne \$bitmap) { \$bitmap.Dispose() }
  if (\$null -ne \$stream) { \$stream.Dispose() }
}
''';
  }

  /// 지정된 이미지 파일에서 텍스트를 추출합니다.
  Future<String?> extractTextFromPath(String filePath) async {
    if (Platform.isMacOS) {
      try {
        final text = await _channel.invokeMethod<String>('recognizeText', {
          'path': filePath,
        });
        return text?.trim();
      } on PlatformException catch (e) {
        throw StateError('텍스트 추출 실패: ${e.message ?? e.code}');
      }
    }

    if (Platform.isWindows) {
      return extractWindowsTextWithRunner(filePath, Process.run);
    }

    throw UnsupportedError('화면 텍스트 추출(로컬 OCR)은 macOS 및 Windows에서 지원됩니다.');
  }

  @visibleForTesting
  Future<String?> extractWindowsTextWithRunner(
    String filePath,
    ProcessRunner runProcess,
  ) async {
    final script = buildWindowsOcrScript(filePath);
    final result = await runProcess('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-ExecutionPolicy',
      'Bypass',
      '-Command',
      script,
    ]);
    if (result.exitCode != 0) {
      final err = (result.stderr ?? '').toString().trim();
      throw StateError(
        err.isEmpty ? 'Windows OCR 실행 실패 (exitCode: ${result.exitCode})' : err,
      );
    }
    return (result.stdout ?? '').toString().trim();
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
