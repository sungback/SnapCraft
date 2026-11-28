import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:screen_capturer/screen_capturer.dart';

import '../models/annotation.dart';
import '../models/capture_item.dart';
import '../services/capture_files.dart';
import '../services/capture_service.dart';
import '../services/export_service.dart';
import '../services/export_settings_service.dart';
import '../services/ocr_service.dart';
import '../widgets/top_toolbar.dart';

/// 워크스페이스의 캡쳐 히스토리, 마크업 편집, 자르기, 내보내기 상태를 관리합니다.
class WorkspaceController extends ChangeNotifier {
  static const int maxHistoryItems = 20;
  static const int maxHistoryBytes = 256 * 1024 * 1024;

  WorkspaceController({ExportSettingsService? exportSettings})
    : _exportSettings = exportSettings ?? ExportSettingsService();

  final ExportSettingsService _exportSettings;
  final List<CaptureItem> _history = [];

  CaptureItem? _selectedItem;
  String? _selectedAnnotationId;
  int _clipboardRequest = 0;

  AnnotationTool _selectedTool = AnnotationTool.pen;
  Color _selectedColor = TopToolbar.paletteColors.first;
  double _strokeWidth = 5.0;

  bool _isCropping = false;
  Rect? _cropRect;

  bool _isOcrRunning = false;
  bool _isCapturing = false;
  bool _exportSettingsLoading = true;
  bool _exportBusy = false;
  bool _hideWindowDuringCapture = true;
  bool _disposed = false;
  String _statusMessage = '준비됨 · 상단 버튼 또는 글로벌 단축키로 화면을 캡쳐하세요.';

  List<CaptureItem> get history => List.unmodifiable(_history);
  CaptureItem? get selectedItem => _selectedItem;
  String? get selectedAnnotationId => _selectedAnnotationId;
  AnnotationTool get selectedTool => _selectedTool;
  Color get selectedColor => _selectedColor;
  double get strokeWidth => _strokeWidth;
  bool get isCropping => _isCropping;
  Rect? get cropRect => _cropRect;
  bool get isOcrRunning => _isOcrRunning;
  bool get isCapturing => _isCapturing;
  String? get saveDirectory => _exportSettings.directory;
  bool get autoSaveEnabled => _exportSettings.autoSave;
  bool get isExportBusy => _exportSettingsLoading || _exportBusy;
  bool get hideWindowDuringCapture => _hideWindowDuringCapture;
  String get statusMessage => _statusMessage;

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _releaseCapture(CaptureItem item) {
    // Painters from the previous frame must finish before their image is released.
    try {
      WidgetsBinding.instance.addPostFrameCallback((_) => item.dispose());
    } catch (_) {
      item.dispose();
    }
    unawaited(CaptureFiles.deleteOriginal(item.filePath));
  }

  bool _trimHistory() {
    int size(CaptureItem item) =>
        item.originalBytes.length + item.width * item.height * 4;
    var bytes = _history.fold<int>(0, (total, item) => total + size(item));
    var trimmed = false;
    while (_history.length > 1 &&
        (_history.length > maxHistoryItems || bytes > maxHistoryBytes)) {
      final oldest = _history.removeLast();
      bytes -= size(oldest);
      if (_selectedItem?.id == oldest.id) {
        _selectedItem = _history.first;
      }
      _releaseCapture(oldest);
      trimmed = true;
    }
    return trimmed;
  }

  void setStatusMessage(String message) {
    _statusMessage = message;
    _notify();
  }

  void selectItem(CaptureItem item) {
    _clipboardRequest++;
    _isCropping = false;
    _cropRect = null;
    _selectedAnnotationId = null;
    _selectedItem = item;
    _notify();
  }

  void selectTool(AnnotationTool tool) {
    _selectedTool = tool;
    if (tool != AnnotationTool.select) {
      _selectedAnnotationId = null;
    }
    _notify();
  }

  void selectColor(Color color) {
    _selectedColor = color;
    _notify();
  }

  void selectStrokeWidth(double width) {
    _strokeWidth = width;
    _notify();
  }

  void selectAnnotation(String? id) {
    if (_selectedAnnotationId == id) return;
    _selectedAnnotationId = id;
    _notify();
  }

  void setCropRect(Rect? rect) {
    _cropRect = rect;
    _notify();
  }

  void toggleHideWindowDuringCapture() {
    _hideWindowDuringCapture = !_hideWindowDuringCapture;
    _notify();
  }

  Future<void> loadExportSettings() async {
    try {
      await _exportSettings.load();
    } catch (e) {
      _statusMessage = '저장 폴더 설정을 불러오지 못했습니다: $e';
    } finally {
      _exportSettingsLoading = false;
      _notify();
    }
  }

  @visibleForTesting
  bool addCaptureItem(CaptureItem item) {
    _history.insert(0, item);
    _selectedItem = item;
    _selectedAnnotationId = null;
    return _trimHistory();
  }

  Future<void> triggerCapture(CaptureMode mode) async {
    if (_isCapturing) return;
    _clipboardRequest++;

    _isCapturing = true;
    _isCropping = false;
    _cropRect = null;
    _selectedAnnotationId = null;
    _statusMessage = '화면 캡쳐 진행 중... (ESC 키를 누르면 취소됩니다)';
    _notify();

    try {
      final item = await CaptureService.instance.capture(
        mode,
        hideAppWindow: _hideWindowDuringCapture,
      );
      if (_disposed) {
        item?.dispose();
        if (item != null) unawaited(CaptureFiles.deleteOriginal(item.filePath));
        return;
      }

      if (item == null) {
        _statusMessage = '캡쳐가 취소되었습니다.';
      } else {
        final trimmed = addCaptureItem(item);
        _statusMessage =
            '${item.modeLabel} 완료 (${item.resolutionLabel}) · '
            '${item.copiedToClipboard ? '클립보드에 자동 복사되었습니다.' : '클립보드 복사에 실패했습니다. 복사 버튼으로 다시 시도하세요.'}'
            '${trimmed ? ' · 보관 한도에 도달해 오래된 캡쳐를 정리했습니다.' : ''}';
      }
      _notify();

      if (item != null &&
          _exportSettings.autoSave &&
          _exportSettings.directory != null) {
        try {
          final savedPath = await ExportService.instance.saveToFile(
            item,
            directory: _exportSettings.directory!,
          );
          if (!_disposed && savedPath != null) {
            _statusMessage = '$_statusMessage · 자동 저장 완료: $savedPath';
            _notify();
          }
        } catch (saveError) {
          if (!_disposed) {
            _statusMessage = '$_statusMessage · 자동 저장 실패: $saveError';
            _notify();
          }
        }
      }
    } catch (error) {
      if (!_disposed) {
        _statusMessage = '캡쳐에 실패했습니다. 화면 기록 권한을 확인한 후 다시 시도하세요. ($error)';
        _notify();
      }
    } finally {
      _isCapturing = false;
      _notify();
    }
  }

  Future<void> openImageFile() async {
    if (_isCapturing) return;
    try {
      if (Platform.isMacOS) await FilePicker.skipEntitlementsChecks();
      final result = await FilePicker.pickFiles(
        dialogTitle: '이미지 파일 열기',
        type: FileType.image,
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty || _disposed) return;

      final item = await CaptureService.instance.createFromFile(path);
      if (_disposed) {
        item?.dispose();
        if (item != null) unawaited(CaptureFiles.deleteOriginal(item.filePath));
        return;
      }
      if (item == null) {
        _statusMessage = '이미지 파일을 불러올 수 없습니다.';
        _notify();
        return;
      }

      _clipboardRequest++;
      _isCropping = false;
      _cropRect = null;
      final trimmed = addCaptureItem(item);
      _statusMessage =
          '이미지 열기 완료 (${item.resolutionLabel})'
          '${trimmed ? ' · 보관 한도에 도달해 오래된 항목을 정리했습니다.' : ''}';
      _notify();
    } catch (e) {
      if (!_disposed) {
        _statusMessage = '이미지 열기 실패: $e';
        _notify();
      }
    }
  }

  Future<void> importFromClipboard() async {
    if (_isCapturing) return;
    try {
      final bytes = await Pasteboard.image;
      if (_disposed) return;
      if (bytes == null || bytes.isEmpty) {
        _statusMessage = '클립보드에 붙여넣을 이미지가 없습니다.';
        _notify();
        return;
      }

      final item = await CaptureService.instance.createFromBytes(
        bytes,
        prefix: 'paste',
      );
      if (_disposed) {
        item?.dispose();
        if (item != null) unawaited(CaptureFiles.deleteOriginal(item.filePath));
        return;
      }
      if (item == null) return;

      _clipboardRequest++;
      _isCropping = false;
      _cropRect = null;
      final trimmed = addCaptureItem(item);
      _statusMessage =
          '클립보드 이미지 붙여넣기 완료 (${item.resolutionLabel})'
          '${trimmed ? ' · 보관 한도에 도달해 오래된 항목을 정리했습니다.' : ''}';
      _notify();
    } catch (e) {
      if (!_disposed) {
        _statusMessage = '클립보드 이미지 불러오기 실패: $e';
        _notify();
      }
    }
  }

  void addAnnotation(AnnotationItem annotation) {
    final current = _selectedItem;
    if (current == null) return;
    current.annotations.add(annotation);
    current.redoStack.clear();
    _selectedAnnotationId = annotation.id;
    _statusMessage = '${annotation.tool.label} 주석이 추가되었습니다.';
    _notify();

    if (annotation.tool == AnnotationTool.redaction) {
      unawaited(copyToClipboard(automatic: true));
    }
  }

  void updateAnnotation(AnnotationItem updated) {
    final current = _selectedItem;
    if (current == null) return;
    final idx = current.annotations.indexWhere((a) => a.id == updated.id);
    if (idx == -1) return;
    current.annotations[idx] = updated;
    current.redoStack.clear();
    _selectedAnnotationId = updated.id;
    _statusMessage = '${updated.tool.label} 주석을 이동했습니다.';
    _notify();
  }

  void deleteSelectedAnnotation([String? id]) {
    final current = _selectedItem;
    final targetId = id ?? _selectedAnnotationId;
    if (current == null || targetId == null) return;
    final idx = current.annotations.indexWhere((a) => a.id == targetId);
    if (idx == -1) return;
    _clipboardRequest++;
    final removed = current.annotations.removeAt(idx);
    current.redoStack.clear();
    if (_selectedAnnotationId == targetId) {
      _selectedAnnotationId = null;
    }
    _statusMessage = '${removed.tool.label} 주석을 삭제했습니다.';
    _notify();
  }

  void undo() {
    final current = _selectedItem;
    if (current == null || current.annotations.isEmpty) return;
    _clipboardRequest++;
    final last = current.annotations.removeLast();
    current.redoStack.add(last);
    if (_selectedAnnotationId == last.id) {
      _selectedAnnotationId = null;
    }
    _statusMessage = '실행 취소됨 (${last.tool.label})';
    _notify();
  }

  void redo() {
    final current = _selectedItem;
    if (current == null || current.redoStack.isEmpty) return;
    _clipboardRequest++;
    final restored = current.redoStack.removeLast();
    current.annotations.add(restored);
    _selectedAnnotationId = null;
    _statusMessage = '다시 실행됨 (${restored.tool.label})';
    _notify();
  }

  void clearAnnotations() {
    final current = _selectedItem;
    if (current == null || current.annotations.isEmpty) return;
    _clipboardRequest++;
    current.annotations.clear();
    current.redoStack.clear();
    _selectedAnnotationId = null;
    _statusMessage = '모든 마크업 주석을 초기화했습니다.';
    _notify();
  }

  void toggleCrop() {
    if (_isCropping) {
      cancelCrop();
    } else {
      startCrop();
    }
  }

  void startCrop() {
    if (_selectedItem == null) return;
    _isCropping = true;
    _cropRect = null;
    _statusMessage = '자르기 모드 · 마우스 드래그로 영역을 지정하세요. (Enter: 적용, ESC: 취소)';
    _notify();
  }

  void cancelCrop() {
    if (!_isCropping) return;
    _isCropping = false;
    _cropRect = null;
    _statusMessage = '자르기가 취소되었습니다.';
    _notify();
  }

  Future<void> applyCrop() async {
    final current = _selectedItem;
    final cropRect = _cropRect;
    if (current == null || cropRect == null || !_isCropping) return;
    if (cropRect.width < 10 || cropRect.height < 10) {
      _statusMessage = '자르기 영역이 너무 작습니다 (최소 10x10 px).';
      _notify();
      return;
    }

    try {
      final cropped = await ExportService.instance.cropCapture(
        item: current,
        cropRect: cropRect,
      );
      if (_disposed) {
        cropped.dispose();
        unawaited(CaptureFiles.deleteOriginal(cropped.filePath));
        return;
      }

      final idx = _history.indexWhere((e) => e.id == current.id);
      if (idx != -1) {
        _history[idx] = cropped;
      } else {
        _history.insert(0, cropped);
      }
      _selectedItem = cropped;
      _selectedAnnotationId = null;
      _isCropping = false;
      _cropRect = null;
      _statusMessage = '이미지를 잘라냈습니다 (${cropped.resolutionLabel}) · 클립보드에 자동 복사 중...';
      _notify();

      _releaseCapture(current);
      unawaited(copyToClipboard(automatic: true));
    } catch (e) {
      if (!_disposed) {
        _statusMessage = '자르기 실패: $e';
        _notify();
      }
    }
  }

  Future<({String? text, String? emptyMessage, String? errorMessage})>
  extractText() async {
    final current = _selectedItem;
    if (current == null || _isOcrRunning) {
      return (text: null, emptyMessage: null, errorMessage: null);
    }
    _isOcrRunning = true;
    _statusMessage = '화면 텍스트 인식(OCR) 중...';
    _notify();

    try {
      final text = await OcrService.instance.recognizeText(current);
      if (_disposed) {
        return (text: null, emptyMessage: null, errorMessage: null);
      }
      if (text == null || text.trim().isEmpty) {
        _statusMessage = '인식된 텍스트가 없습니다.';
        _notify();
        return (
          text: null,
          emptyMessage: '화면에서 인식된 텍스트가 없습니다.',
          errorMessage: null,
        );
      }

      _statusMessage = '텍스트를 추출하여 클립보드에 복사했습니다 (${text.length}자).';
      _notify();
      return (text: text, emptyMessage: null, errorMessage: null);
    } catch (e) {
      if (!_disposed) {
        _statusMessage = '텍스트 추출 실패: $e';
        _notify();
      }
      return (text: null, emptyMessage: null, errorMessage: '텍스트 추출 실패: $e');
    } finally {
      _isOcrRunning = false;
      _notify();
    }
  }

  Future<bool> copyForAgent(String template) async {
    final current = _selectedItem;
    if (current == null) return false;
    try {
      final text = await ExportService.instance.copyForAgent(
        current,
        template: template,
      );
      if (_disposed || text == null) return false;
      _statusMessage = '에이전트용 프롬프트가 클립보드에 복사되었습니다.';
      _notify();
      return true;
    } catch (e) {
      if (!_disposed) {
        _statusMessage = '에이전트 복사 실패: $e';
        _notify();
      }
      return false;
    }
  }

  Future<bool> copyToClipboard({bool automatic = false}) async {
    final current = _selectedItem;
    if (current == null) return false;
    final request = ++_clipboardRequest;
    bool isCurrent() =>
        !_disposed &&
        request == _clipboardRequest &&
        _selectedItem == current;

    _statusMessage = automatic
        ? '보안 가림 이미지를 클립보드에 자동 복사 중...'
        : '클립보드에 이미지 복사 중...';
    _notify();

    final ok = await ExportService.instance.copyToClipboard(
      current,
      shouldCopy: isCurrent,
    );
    if (!isCurrent()) return false;

    _statusMessage = automatic
        ? (ok
              ? '보안 가림이 반영된 이미지를 클립보드에 자동 복사했습니다.'
              : '보안 가림 이미지 자동 복사에 실패했습니다. 복사 버튼으로 다시 시도하세요.')
        : (ok ? '마크업이 반영된 이미지를 클립보드에 복사했습니다!' : '클립보드 복사에 실패했습니다.');
    _notify();
    return ok;
  }

  Future<void> changeSaveDirectory({bool clear = false}) async {
    if (_exportSettingsLoading || _exportBusy) return;
    _exportBusy = true;
    _notify();
    try {
      String? directory;
      if (!clear) {
        String? initialDirectory;
        final previousDirectory = _exportSettings.directory;
        if (previousDirectory != null) {
          try {
            if (await Directory(previousDirectory).exists()) {
              initialDirectory = previousDirectory;
            }
          } on FileSystemException {
            // A disconnected or inaccessible folder must not block choosing another.
          }
        }
        if (_disposed) return;
        if (Platform.isMacOS) await FilePicker.skipEntitlementsChecks();
        directory = await FilePicker.getDirectoryPath(
          dialogTitle: 'PNG 저장 폴더 지정',
          initialDirectory: initialDirectory,
        );
        if (directory == null || directory.isEmpty || _disposed) return;
      }
      final hadAutoSave = _exportSettings.autoSave;
      await _exportSettings.setDirectory(directory);
      if (_disposed) return;
      _statusMessage = directory == null
          ? (hadAutoSave
                ? '저장 폴더 지정을 해제하고 자동 저장을 껐습니다.'
                : '저장 폴더 지정을 해제했습니다.')
          : 'PNG 저장 폴더: $directory';
      _notify();
    } catch (e) {
      if (!_disposed) {
        _statusMessage = '저장 폴더 설정 실패: $e';
        _notify();
      }
    } finally {
      _exportBusy = false;
      _notify();
    }
  }

  Future<void> toggleAutoSave() async {
    if (_exportSettingsLoading || _exportBusy) return;
    _exportBusy = true;
    _notify();
    try {
      if (_exportSettings.autoSave) {
        await _exportSettings.setAutoSave(false);
        if (_disposed) return;
        _statusMessage = '캡쳐 시 자동 저장을 껐습니다.';
      } else {
        if (_exportSettings.directory == null) {
          if (Platform.isMacOS) await FilePicker.skipEntitlementsChecks();
          final directory = await FilePicker.getDirectoryPath(
            dialogTitle: '자동 저장할 PNG 폴더 지정',
          );
          if (directory == null || directory.isEmpty || _disposed) return;
          await _exportSettings.setDirectory(directory);
        }
        await _exportSettings.setAutoSave(true);
        if (_disposed) return;
        _statusMessage = '캡쳐 시 자동 저장 켜짐: ${_exportSettings.directory}';
      }
      _notify();
    } catch (e) {
      if (!_disposed) {
        _statusMessage = '자동 저장 설정 실패: $e';
        _notify();
      }
    } finally {
      _exportBusy = false;
      _notify();
    }
  }

  Future<String?> saveToFile({bool chooseLocation = false}) async {
    final current = _selectedItem;
    if (current == null || _exportSettingsLoading || _exportBusy) return null;
    final directory = chooseLocation ? null : _exportSettings.directory;
    _exportBusy = true;
    _notify();

    try {
      final savedPath = await ExportService.instance.saveToFile(
        current,
        directory: directory,
      );
      if (_disposed || savedPath == null) return null;

      _statusMessage = '파일 저장 완료: $savedPath';
      _notify();
      return savedPath;
    } catch (e) {
      if (!_disposed) {
        _statusMessage = '파일 저장 실패: $e · PNG 저장 옵션에서 폴더를 변경하거나 다른 위치에 저장하세요.';
        _notify();
      }
      return null;
    } finally {
      _exportBusy = false;
      _notify();
    }
  }

  void deleteCaptureItem(CaptureItem item) {
    _clipboardRequest++;
    _isCropping = false;
    _cropRect = null;
    _selectedAnnotationId = null;
    final idx = _history.indexWhere((e) => e.id == item.id);
    _history.removeWhere((e) => e.id == item.id);
    if (_selectedItem?.id == item.id) {
      if (_history.isEmpty) {
        _selectedItem = null;
      } else {
        final nextIdx = idx.clamp(0, _history.length - 1);
        _selectedItem = _history[nextIdx];
      }
    }
    _statusMessage = '캡쳐 항목을 목록에서 삭제했습니다.';
    _notify();
    _releaseCapture(item);
  }

  @override
  void dispose() {
    _disposed = true;
    _clipboardRequest++;
    for (final item in _history) {
      _releaseCapture(item);
    }
    _history.clear();
    super.dispose();
  }
}
