import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'controllers/workspace_controller.dart';
import 'models/capture_item.dart';
import 'services/export_service.dart';
import 'services/hotkey_service.dart';
import 'services/startup_service.dart';
import 'services/tray_service.dart';
import 'services/update_service.dart';
import 'widgets/annotation_canvas.dart';
import 'widgets/empty_workspace.dart';
import 'widgets/history_sidebar.dart';
import 'widgets/ocr_result_dialog.dart';
import 'widgets/shortcut_settings_dialog.dart';
import 'widgets/top_toolbar.dart';
import 'widgets/update_dialog.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final startMinimized = args.contains('--start-minimized');

  await windowManager.ensureInitialized();

  final windowOptions = WindowOptions(
    size: const Size(1180, 780),
    minimumSize: const Size(880, 580),
    center: true,
    // Windows에서 backgroundColor를 지정하면 window_manager가
    // SetWindowCompositionAttribute(ACCENT_ENABLE_GRADIENT)를 호출하여
    // DWM 기본 타이틀바의 최소화/최대화/닫기 버튼을 덮어쓰는 문제가 발생하므로 macOS에서만 지정
    backgroundColor: Platform.isMacOS ? const Color(0xFF14161C) : null,
    titleBarStyle: TitleBarStyle.normal,
    windowButtonVisibility: true,
    title: 'SnapCraft - 화면 캡쳐 & 마크업',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setResizable(true);
    await windowManager.setMinimizable(true);
    await windowManager.setMaximizable(true);
    await windowManager.setClosable(true);
    if (!startMinimized) {
      await windowManager.show();
      await windowManager.focus();
    }
  });

  runApp(const SnapCraftApp());
}

class SnapCraftApp extends StatelessWidget {
  const SnapCraftApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SnapCraft',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF14161C),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.dark,
          surface: const Color(0xFF1E2028),
        ),
      ),
      home: const SnapCraftHomeScreen(),
    );
  }
}

class SnapCraftHomeScreen extends StatefulWidget {
  const SnapCraftHomeScreen({super.key});

  @override
  State<SnapCraftHomeScreen> createState() => _SnapCraftHomeScreenState();
}

class _SnapCraftHomeScreenState extends State<SnapCraftHomeScreen>
    with WindowListener {
  final WorkspaceController _controller = WorkspaceController();

  bool _isPinned = false;
  Size? _savedWindowSize;
  Offset? _savedWindowPosition;
  String _appVersion = UpdateService.defaultVersion;
  ReleaseInfo? _latestReleaseInfo;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initServices();
    _controller.loadExportSettings();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _controller.dispose();
    TrayService.instance.dispose();
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (!_controller.isCapturing) {
      if (TrayService.instance.closeToTray) {
        await windowManager.hide();
      } else {
        exit(0);
      }
    }
  }

  Future<void> _showAppWindow() async {
    final isMinimized = await windowManager.isMinimized();
    if (isMinimized) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  Future<void> _initServices() async {
    unawaited(ExportService.instance.cleanStaleFiles());
    await StartupService.instance.init();
    await HotkeyService.instance.initialize((mode) {
      _controller.triggerCapture(mode);
    });
    await TrayService.instance.init(
      onShowWindow: _showAppWindow,
      onTriggerCapture: (mode) => _controller.triggerCapture(mode),
    );

    final ver = await UpdateService.instance.getCurrentVersion();
    if (mounted) {
      setState(() {
        _appVersion = ver;
      });
    }

    // 앱 시작 후 백그라운드에서 최신 릴리즈 자동 확인 (단위 테스트 환경 제외)
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkUpdateSilently();
      });
    }
  }

  Future<void> _checkUpdateSilently() async {
    final info = await UpdateService.instance.checkForUpdate();
    if (!mounted || info == null) return;

    setState(() {
      _latestReleaseInfo = info;
    });

    if (info.hasUpdate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '새 버전(v${info.latestVersion})이 출시되었습니다! 현재 버전: v${info.currentVersion}',
          ),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
          width: 460,
          action: SnackBarAction(label: '업데이트', onPressed: _openUpdateDialog),
        ),
      );
    }
  }

  Future<void> _extractText() async {
    final result = await _controller.extractText();
    if (!mounted) return;
    if (result.emptyMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.emptyMessage!),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: 360,
        ),
      );
      return;
    }
    if (result.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage!),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          width: 420,
        ),
      );
      return;
    }
    final text = result.text;
    if (text == null) return;

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => OcrResultDialog(initialText: text),
    );
  }

  Future<void> _copyForAgent(String template) async {
    final ok = await _controller.copyForAgent(template);
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('에이전트용 프롬프트가 클립보드에 복사되었습니다!'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 380,
      ),
    );
  }

  Future<void> _copyToClipboard() async {
    final ok = await _controller.copyToClipboard();
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('클립보드에 복사되었습니다 (Cmd/Ctrl + V로 붙여넣기 가능)'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 420,
      ),
    );
  }

  Future<void> _saveToFile({bool chooseLocation = false}) async {
    final savedPath = await _controller.saveToFile(
      chooseLocation: chooseLocation,
    );
    if (!mounted || savedPath == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('PNG 저장 완료: $savedPath'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _togglePinMode() async {
    final current = _controller.selectedItem;
    if (current == null) return;

    if (_isPinned) {
      await windowManager.setAlwaysOnTop(false);
      if (_savedWindowSize != null) {
        await windowManager.setSize(_savedWindowSize!);
      }
      if (_savedWindowPosition != null) {
        await windowManager.setPosition(_savedWindowPosition!);
      }
      setState(() {
        _isPinned = false;
      });
      _controller.setStatusMessage('핀 고정 모드가 해제되었습니다.');
    } else {
      try {
        _savedWindowSize = await windowManager.getSize();
        _savedWindowPosition = await windowManager.getPosition();
      } catch (_) {}

      const targetW = 420.0;
      final ratio = current.height / current.width;
      final targetH = (targetW * ratio).clamp(200.0, 600.0) + 48.0;

      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(Size(targetW, targetH));
      setState(() {
        _isPinned = true;
      });
      _controller.setStatusMessage('화면 핀 고정 모드 (항상 최상단)');
    }
  }

  void _handlePasteShortcut() {
    final focusWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusWidget is EditableText) return;
    unawaited(_controller.importFromClipboard());
  }

  void _handleDeleteKey() {
    final focusWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusWidget is EditableText) return;
    if (_controller.isCropping) return;
    if (_controller.selectedAnnotationId != null) {
      _controller.deleteSelectedAnnotation();
    }
  }

  Future<void> _openShortcutSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => ShortcutSettingsDialog(
        onShortcutsUpdated: () {
          unawaited(TrayService.instance.updateContextMenu());
          _controller.setStatusMessage('글로벌 단축키 설정이 업데이트되었습니다.');
        },
      ),
    );
  }

  Future<void> _openUpdateDialog() async {
    await showDialog<void>(
      context: context,
      builder: (_) => UpdateDialog(initialReleaseInfo: _latestReleaseInfo),
    );
    if (!mounted) return;
    setState(() {
      _latestReleaseInfo = UpdateService.instance.latestReleaseInfo;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final current = _controller.selectedItem;

        if (_isPinned && current != null) {
          return _buildPinnedView(current);
        }

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                _controller.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                _controller.undo,
            const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
              shift: true,
            ): _controller.redo,
            const SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: true,
              shift: true,
            ): _controller.redo,
            const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
                _copyToClipboard,
            const SingleActivator(LogicalKeyboardKey.keyC, control: true):
                _copyToClipboard,
            const SingleActivator(LogicalKeyboardKey.keyS, meta: true):
                _saveToFile,
            const SingleActivator(LogicalKeyboardKey.keyS, control: true):
                _saveToFile,
            const SingleActivator(LogicalKeyboardKey.keyO, meta: true):
                _controller.openImageFile,
            const SingleActivator(LogicalKeyboardKey.keyO, control: true):
                _controller.openImageFile,
            const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
                _handlePasteShortcut,
            const SingleActivator(LogicalKeyboardKey.keyV, control: true):
                _handlePasteShortcut,
            const SingleActivator(LogicalKeyboardKey.delete): _handleDeleteKey,
            const SingleActivator(LogicalKeyboardKey.backspace):
                _handleDeleteKey,
            const SingleActivator(LogicalKeyboardKey.escape):
                _controller.cancelCrop,
            const SingleActivator(LogicalKeyboardKey.enter):
                _controller.applyCrop,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: Column(
                children: [
                  TopToolbar(
                    hasActiveCapture: current != null,
                    isCapturing: _controller.isCapturing,
                    selectedTool: _controller.selectedTool,
                    selectedColor: _controller.selectedColor,
                    strokeWidth: _controller.strokeWidth,
                    canUndo: current != null && current.annotations.isNotEmpty,
                    canRedo: current != null && current.redoStack.isNotEmpty,
                    onTriggerCapture: _controller.triggerCapture,
                    onSelectTool: _controller.selectTool,
                    onSelectColor: _controller.selectColor,
                    onSelectStrokeWidth: _controller.selectStrokeWidth,
                    onUndo: _controller.undo,
                    onRedo: _controller.redo,
                    onClearAnnotations: _controller.clearAnnotations,
                    onCopyClipboard: _copyToClipboard,
                    onSaveFile: _saveToFile,
                    saveDirectory: _controller.saveDirectory,
                    autoSaveEnabled: _controller.autoSaveEnabled,
                    isExportBusy: _controller.isExportBusy,
                    onChooseSaveDirectory: _controller.changeSaveDirectory,
                    onClearSaveDirectory: () =>
                        _controller.changeSaveDirectory(clear: true),
                    onToggleAutoSave: _controller.toggleAutoSave,
                    onSaveFileAs: () => _saveToFile(chooseLocation: true),
                    onOpenShortcutSettings: _openShortcutSettings,
                    onOpenUpdateDialog: _openUpdateDialog,
                    availableUpdateVersion:
                        (_latestReleaseInfo?.hasUpdate ?? false)
                        ? _latestReleaseInfo?.latestVersion
                        : null,
                    isCropping: _controller.isCropping,
                    onToggleCrop: _controller.toggleCrop,
                    onExtractText: _extractText,
                    onCopyForAgent: _copyForAgent,
                    isPinned: _isPinned,
                    onTogglePin: _togglePinMode,
                    onOpenImageFile: _controller.openImageFile,
                    hasSelectedAnnotation:
                        _controller.selectedAnnotationId != null,
                    onDeleteSelectedAnnotation:
                        _controller.deleteSelectedAnnotation,
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        HistorySidebar(
                          items: _controller.history,
                          selectedItem: current,
                          onSelectItem: _controller.selectItem,
                          onDeleteItem: _controller.deleteCaptureItem,
                        ),
                        Expanded(
                          child: Container(
                            color: const Color(0xFF14161C),
                            child: current == null
                                ? EmptyWorkspaceView(
                                    onTriggerCapture:
                                        _controller.triggerCapture,
                                  )
                                : AnnotationCanvas(
                                    key: ValueKey(current.id),
                                    captureItem: current,
                                    selectedTool: _controller.selectedTool,
                                    selectedColor: _controller.selectedColor,
                                    strokeWidth: _controller.strokeWidth,
                                    onAddAnnotation: _controller.addAnnotation,
                                    selectedAnnotationId:
                                        _controller.selectedAnnotationId,
                                    onSelectAnnotation:
                                        _controller.selectAnnotation,
                                    onUpdateAnnotation:
                                        _controller.updateAnnotation,
                                    onDeleteAnnotation:
                                        _controller.deleteSelectedAnnotation,
                                    isCropping: _controller.isCropping,
                                    cropRect: _controller.cropRect,
                                    onCropRectChanged: _controller.setCropRect,
                                    onApplyCrop: _controller.applyCrop,
                                    onCancelCrop: _controller.cancelCrop,
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildBottomStatusBar(current),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPinnedView(CaptureItem current) {
    return Scaffold(
      backgroundColor: const Color(0xFF14161C),
      body: Column(
        children: [
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: const Color(0xFF1E2028),
            child: Row(
              children: [
                const Icon(
                  Icons.push_pin_rounded,
                  size: 16,
                  color: Color(0xFF60A5FA),
                ),
                const SizedBox(width: 8),
                Text(
                  '핀 고정 (${current.resolutionLabel})',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: _togglePinMode,
                  tooltip: '원래 크기로 복귀',
                  icon: const Icon(Icons.open_in_full_rounded, size: 16),
                  color: Colors.white70,
                ),
              ],
            ),
          ),
          Expanded(
            child: AnnotationCanvas(
              key: ValueKey(current.id),
              captureItem: current,
              selectedTool: _controller.selectedTool,
              selectedColor: _controller.selectedColor,
              strokeWidth: _controller.strokeWidth,
              onAddAnnotation: _controller.addAnnotation,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatusBar(CaptureItem? current) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFF191B22),
        border: Border(top: BorderSide(color: Color(0xFF2B2E3B), width: 1)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 14,
            color: Colors.white54,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              _controller.statusMessage,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (current != null) ...[
            Text(
              '해상도: ${current.resolutionLabel}  |  마크업: ${current.annotations.length}개',
              style: const TextStyle(fontSize: 11.5, color: Colors.white54),
            ),
            const SizedBox(width: 14),
          ],
          InkWell(
            onTap: _controller.toggleHideWindowDuringCapture,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _controller.hideWindowDuringCapture
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 15,
                    color: _controller.hideWindowDuringCapture
                        ? const Color(0xFF60A5FA)
                        : Colors.white54,
                  ),
                  const SizedBox(width: 5),
                  const Text(
                    '캡쳐 시 앱 창 자동 숨김',
                    style: TextStyle(fontSize: 11.5, color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'v$_appVersion',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.white38,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
