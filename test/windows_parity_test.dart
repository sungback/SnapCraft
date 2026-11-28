import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:snap_craft/services/ocr_service.dart';

void main() {
  group('Windows OCR parity', () {
    test('buildWindowsOcrScript가 경로의 작은따옴표를 이스케이프하고 WinRT OCR을 호출한다', () {
      final script = OcrService.buildWindowsOcrScript(
        r"C:\Users\O'Connor\Pictures\snap'1.png",
      );

      expect(
        script,
        contains(r"GetFileFromPathAsync('C:\Users\O''Connor\Pictures\snap''1.png')"),
      );
      expect(script, contains('Windows.Media.Ocr.OcrEngine'));
      expect(script, contains('TryCreateFromUserProfileLanguages'));
      expect(script, contains('[System.Text.Encoding]::UTF8'));
    });

    test('extractWindowsTextWithRunner가 정상 출력 트림 및 실패 오류를 처리한다', () async {
      final ok = await OcrService.instance.extractWindowsTextWithRunner(
        r'C:\temp\shot.png',
        (executable, arguments) async {
          expect(executable, 'powershell.exe');
          expect(arguments, contains('-Command'));
          return ProcessResult(0, 0, '  Hello Windows OCR\r\nLine 2  \r\n', '');
        },
      );
      expect(ok, 'Hello Windows OCR\r\nLine 2');

      expect(
        () => OcrService.instance.extractWindowsTextWithRunner(
          r'C:\temp\shot.png',
          (executable, arguments) async =>
              ProcessResult(0, 1, '', 'No OCR language pack'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
