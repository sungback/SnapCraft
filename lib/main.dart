import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:window_manager/window_manager.dart';

import 'models/annotation.dart';
import 'models/capture_item.dart';
import 'services/capture_service.dart';
import 'services/capture_files.dart';
import 'services/export_service.dart';
import 'services/hotkey_service.dart';
import 'services/update_service.dart';
import 'widgets/annotation_canvas.dart';
import 'widgets/history_sidebar.dart';
import 'widgets/shortcut_settings_dialog.dart';
import 'widgets/top_toolbar.dart';
import 'widgets/update_dialog.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
    await windowManager.show();
    await windowManager.focus();
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
  static const _maxHistoryItems = 20;
  static const _maxHistoryBytes = 256 * 1024 * 1024;
  final List<CaptureItem> _history = [];

  void _releaseCapture(CaptureItem item) {
    // Painters from the previous frame must finish before their image is released.
    WidgetsBinding.instance.addPostFrameCallback((_) => item.dispose());
    unawaited(CaptureFiles.deleteOriginal(item.filePath));
  }

  bool _trimHistory() {
    int size(CaptureItem item) =>
        item.originalBytes.length + item.width * item.height * 4;
    var bytes = _history.fold<int>(0, (total, item) => total + size(item));
    var trimmed = false;
    while (_history.length > 1 &&
        (_history.length > _maxHistoryItems || bytes > _maxHistoryBytes)) {
      final oldest = _history.removeLast();
      bytes -= size(oldest);
      _releaseCapture(oldest);
      trimmed = true;
    }
    return trimmed;
  }

  CaptureItem? _selectedItem;

  AnnotationTool _selectedTool = AnnotationTool.pen;
  Color _selectedColor = TopToolbar.paletteColors.first;
  double _strokeWidth = 5.0;

  bool _isCapturing = false;
  bool _hideWindowDuringCapture = true;
  String _appVersion = UpdateService.defaultVersion;
  ReleaseInfo? _latestReleaseInfo;
  String _statusMessage = '준비됨 · 상단 버튼 또는 글로벌 단축키로 화면을 캡쳐하세요.';

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initServices();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    for (final item in _history) {
      _releaseCapture(item);
    }
    super.dispose();
  }

  @override
  Future<void> onWindowClose() async {
    if (!_isCapturing) {
      exit(0);
    }
  }

  Future<void> _initServices() async {
    unawaited(ExportService.instance.cleanStaleFiles());
    await HotkeyService.instance.initialize((mode) {
      _triggerCapture(mode);
    });

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

  Future<void> _triggerCapture(CaptureMode mode) async {
    if (_isCapturing) return;

    setState(() {
      _isCapturing = true;
      _statusMessage = '화면 캡쳐 진행 중... (ESC 키를 누르면 취소됩니다)';
    });

    try {
      final item = await CaptureService.instance.capture(
        mode,
        hideAppWindow: _hideWindowDuringCapture,
      );
      if (!mounted) {
        item?.dispose();
        if (item != null) unawaited(CaptureFiles.deleteOriginal(item.filePath));
        return;
      }
      setState(() {
        if (item == null) {
          _statusMessage = '캡쳐가 취소되었습니다.';
        } else {
          _history.insert(0, item);
          _selectedItem = item;
          final trimmed = _trimHistory();
          _statusMessage =
              '${item.modeLabel} 완료 (${item.resolutionLabel}) · '
              '${item.copiedToClipboard ? '클립보드에 자동 복사되었습니다.' : '클립보드 복사에 실패했습니다. 복사 버튼으로 다시 시도하세요.'}'
              '${trimmed ? ' · 보관 한도에 도달해 오래된 캡쳐를 정리했습니다.' : ''}';
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _statusMessage = '캡쳐에 실패했습니다. 화면 기록 권한을 확인한 후 다시 시도하세요. ($error)';
        });
      }
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  void _addAnnotation(AnnotationItem annotation) {
    final current = _selectedItem;
    if (current == null) return;
    setState(() {
      current.annotations.add(annotation);
      current.redoStack.clear();
      _statusMessage = '${annotation.tool.label} 주석이 추가되었습니다.';
    });
  }

  void _undo() {
    final current = _selectedItem;
    if (current == null || current.annotations.isEmpty) return;
    setState(() {
      final last = current.annotations.removeLast();
      current.redoStack.add(last);
      _statusMessage = '실행 취소됨 (${last.tool.label})';
    });
  }

  void _redo() {
    final current = _selectedItem;
    if (current == null || current.redoStack.isEmpty) return;
    setState(() {
      final restored = current.redoStack.removeLast();
      current.annotations.add(restored);
      _statusMessage = '다시 실행됨 (${restored.tool.label})';
    });
  }

  void _clearAnnotations() {
    final current = _selectedItem;
    if (current == null || current.annotations.isEmpty) return;
    setState(() {
      current.annotations.clear();
      current.redoStack.clear();
      _statusMessage = '모든 마크업 주석을 초기화했습니다.';
    });
  }

  Future<void> _copyToClipboard() async {
    final current = _selectedItem;
    if (current == null) return;

    setState(() {
      _statusMessage = '클립보드에 이미지 복사 중...';
    });

    final ok = await ExportService.instance.copyToClipboard(current);
    if (!mounted) return;

    setState(() {
      _statusMessage = ok ? '마크업이 반영된 이미지를 클립보드에 복사했습니다!' : '클립보드 복사에 실패했습니다.';
    });

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('클립보드에 복사되었습니다 (Cmd/Ctrl + V로 붙여넣기 가능)'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          width: 420,
        ),
      );
    }
  }

  Future<void> _saveToFile() async {
    final current = _selectedItem;
    if (current == null) return;

    try {
      final savedPath = await ExportService.instance.saveToFile(current);
      if (!mounted || savedPath == null) return;

      setState(() {
        _statusMessage = '파일 저장 완료: $savedPath';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PNG 저장 완료: $savedPath'),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = '파일 저장 중 오류 발생: $e';
      });
    }
  }

  void _deleteCaptureItem(CaptureItem item) {
    setState(() {
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
    });
    _releaseCapture(item);
  }

  Future<void> _openShortcutSettings() async {
    await showDialog<void>(
      context: context,
      builder: (_) => ShortcutSettingsDialog(
        onShortcutsUpdated: () {
          setState(() {
            _statusMessage = '글로벌 단축키 설정이 업데이트되었습니다.';
          });
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
    final current = _selectedItem;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
            _copyToClipboard,
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _copyToClipboard,
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _saveToFile,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true):
            _saveToFile,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: Column(
            children: [
              TopToolbar(
                hasActiveCapture: current != null,
                isCapturing: _isCapturing,
                selectedTool: _selectedTool,
                selectedColor: _selectedColor,
                strokeWidth: _strokeWidth,
                canUndo: current != null && current.annotations.isNotEmpty,
                canRedo: current != null && current.redoStack.isNotEmpty,
                onTriggerCapture: _triggerCapture,
                onSelectTool: (tool) => setState(() => _selectedTool = tool),
                onSelectColor: (color) =>
                    setState(() => _selectedColor = color),
                onSelectStrokeWidth: (w) => setState(() => _strokeWidth = w),
                onUndo: _undo,
                onRedo: _redo,
                onClearAnnotations: _clearAnnotations,
                onCopyClipboard: _copyToClipboard,
                onSaveFile: _saveToFile,
                onOpenShortcutSettings: _openShortcutSettings,
                onOpenUpdateDialog: _openUpdateDialog,
                availableUpdateVersion: (_latestReleaseInfo?.hasUpdate ?? false)
                    ? _latestReleaseInfo?.latestVersion
                    : null,
              ),
              Expanded(
                child: Row(
                  children: [
                    HistorySidebar(
                      items: _history,
                      selectedItem: current,
                      onSelectItem: (item) =>
                          setState(() => _selectedItem = item),
                      onDeleteItem: _deleteCaptureItem,
                    ),
                    Expanded(
                      child: Container(
                        color: const Color(0xFF14161C),
                        child: current == null
                            ? _buildEmptyState()
                            : AnnotationCanvas(
                                key: ValueKey(current.id),
                                captureItem: current,
                                selectedTool: _selectedTool,
                                selectedColor: _selectedColor,
                                strokeWidth: _strokeWidth,
                                onAddAnnotation: _addAnnotation,
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
  }

  Widget _buildEmptyState() {
    final hotkeyService = HotkeyService.instance;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                  ),
                ),
                child: const Icon(
                  Icons.camera_enhance_rounded,
                  size: 34,
                  color: Color(0xFF60A5FA),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                '원하는 캡쳐 모드를 선택해 시작하세요',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '캡쳐 즉시 클립보드에 자동 복사되며, 펜·형광펜·사각형·화살표·텍스트·모자이크로\n빠르게 마크업한 뒤 재복사하거나 PNG 파일로 저장할 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.white60,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 26),
              Row(
                children: [
                  Expanded(
                    child: _buildQuickStartCard(
                      icon: Icons.crop_free_rounded,
                      title: '영역 지정 캡쳐',
                      shortcut: hotkeyService.formatHotKey(CaptureMode.region),
                      description: '원하는 영역만 마우스로 드래그하여 캡쳐',
                      onTap: () => _triggerCapture(CaptureMode.region),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickStartCard(
                      icon: Icons.fullscreen_rounded,
                      title: '전체 화면 캡쳐',
                      shortcut: hotkeyService.formatHotKey(CaptureMode.screen),
                      description: '현재 모니터 전체 화면을 즉시 캡쳐',
                      onTap: () => _triggerCapture(CaptureMode.screen),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildQuickStartCard(
                      icon: Icons.web_asset_rounded,
                      title: '창 선택 캡쳐',
                      shortcut: hotkeyService.formatHotKey(CaptureMode.window),
                      description: '특정 애플리케이션 창만 깔끔하게 캡쳐',
                      onTap: () => _triggerCapture(CaptureMode.window),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStartCard({
    required IconData icon,
    required String title,
    required String shortcut,
    required String description,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E212B),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF2E3240)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Icon(icon, size: 22, color: const Color(0xFF60A5FA)),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14161C),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    shortcut,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF93C5FD),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              description,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white54,
                height: 1.4,
              ),
            ),
          ],
        ),
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
              _statusMessage,
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
            onTap: () {
              setState(() {
                _hideWindowDuringCapture = !_hideWindowDuringCapture;
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _hideWindowDuringCapture
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    size: 15,
                    color: _hideWindowDuringCapture
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
