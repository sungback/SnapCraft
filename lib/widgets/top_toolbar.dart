import 'package:flutter/material.dart';
import 'package:screen_capturer/screen_capturer.dart';

import '../models/annotation.dart';
import '../services/hotkey_service.dart';

enum _SaveAction { chooseDirectory, clearDirectory, toggleAutoSave, saveAs }

class TopToolbar extends StatelessWidget {
  final bool hasActiveCapture;
  final bool isCapturing;
  final AnnotationTool selectedTool;
  final Color selectedColor;
  final double strokeWidth;
  final bool canUndo;
  final bool canRedo;
  final ValueChanged<CaptureMode> onTriggerCapture;
  final ValueChanged<AnnotationTool> onSelectTool;
  final ValueChanged<Color> onSelectColor;
  final ValueChanged<double> onSelectStrokeWidth;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onClearAnnotations;
  final VoidCallback onCopyClipboard;
  final VoidCallback onSaveFile;
  final String? saveDirectory;
  final bool autoSaveEnabled;
  final bool isExportBusy;
  final VoidCallback onChooseSaveDirectory;
  final VoidCallback onClearSaveDirectory;
  final VoidCallback? onToggleAutoSave;
  final VoidCallback onSaveFileAs;
  final VoidCallback onOpenShortcutSettings;
  final VoidCallback onOpenUpdateDialog;
  final String? availableUpdateVersion;
  final bool isCropping;
  final VoidCallback? onToggleCrop;
  final VoidCallback? onExtractText;
  final ValueChanged<String>? onCopyForAgent;
  final bool isPinned;
  final VoidCallback? onTogglePin;
  final VoidCallback? onOpenImageFile;
  final bool hasSelectedAnnotation;
  final VoidCallback? onDeleteSelectedAnnotation;

  const TopToolbar({
    super.key,
    required this.hasActiveCapture,
    required this.isCapturing,
    required this.selectedTool,
    required this.selectedColor,
    required this.strokeWidth,
    required this.canUndo,
    required this.canRedo,
    required this.onTriggerCapture,
    required this.onSelectTool,
    required this.onSelectColor,
    required this.onSelectStrokeWidth,
    required this.onUndo,
    required this.onRedo,
    required this.onClearAnnotations,
    required this.onCopyClipboard,
    required this.onSaveFile,
    required this.saveDirectory,
    this.autoSaveEnabled = false,
    required this.isExportBusy,
    required this.onChooseSaveDirectory,
    required this.onClearSaveDirectory,
    this.onToggleAutoSave,
    required this.onSaveFileAs,
    required this.onOpenShortcutSettings,
    required this.onOpenUpdateDialog,
    this.availableUpdateVersion,
    this.isCropping = false,
    this.onToggleCrop,
    this.onExtractText,
    this.onCopyForAgent,
    this.isPinned = false,
    this.onTogglePin,
    this.onOpenImageFile,
    this.hasSelectedAnnotation = false,
    this.onDeleteSelectedAnnotation,
  });

  static const List<Color> paletteColors = [
    Color(0xFFFF3B30), // Red
    Color(0xFFFF9500), // Orange
    Color(0xFFFFCC00), // Yellow
    Color(0xFF34C759), // Green
    Color(0xFF00C7BE), // Teal
    Color(0xFF007AFF), // Blue
    Color(0xFFAF52DE), // Purple
    Color(0xFFFFFFFF), // White
  ];

  @override
  Widget build(BuildContext context) {
    final hotkeyService = HotkeyService.instance;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1E2028),
        border: Border(bottom: BorderSide(color: Color(0xFF2E323E), width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1단: 캡쳐 실행 버튼 그룹 + 단축키 설정 + 복사/저장 액션
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              _buildCaptureButton(
                icon: Icons.crop_free_rounded,
                label: '영역 캡쳐',
                shortcut: hotkeyService.formatHotKey(CaptureMode.region),
                primary: true,
                onPressed: isCapturing
                    ? null
                    : () => onTriggerCapture(CaptureMode.region),
              ),
              const SizedBox(width: 8),
              _buildCaptureButton(
                icon: Icons.fullscreen_rounded,
                label: '전체 화면',
                shortcut: hotkeyService.formatHotKey(CaptureMode.screen),
                onPressed: isCapturing
                    ? null
                    : () => onTriggerCapture(CaptureMode.screen),
              ),
              const SizedBox(width: 8),
              _buildCaptureButton(
                icon: Icons.web_asset_rounded,
                label: '창 캡쳐',
                shortcut: hotkeyService.formatHotKey(CaptureMode.window),
                onPressed: isCapturing
                    ? null
                    : () => onTriggerCapture(CaptureMode.window),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: '이미지 파일 열기 (Cmd/Ctrl + O)',
                child: IconButton(
                  onPressed: isCapturing ? null : onOpenImageFile,
                  icon: const Icon(Icons.folder_open_rounded, size: 20),
                  color: Colors.white70,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF282B36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: '글로벌 단축키 설정',
                child: IconButton(
                  onPressed: onOpenShortcutSettings,
                  icon: const Icon(Icons.keyboard_alt_outlined, size: 20),
                  color: Colors.white70,
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF282B36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              if (availableUpdateVersion != null)
                FilledButton.tonalIcon(
                  onPressed: onOpenUpdateDialog,
                  icon: const Icon(
                    Icons.system_update_alt_rounded,
                    size: 16,
                    color: Color(0xFF34D399),
                  ),
                  label: Text(
                    'v$availableUpdateVersion 업데이트',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF6EE7B7),
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981)
                        .withValues(alpha: 0.16),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: const Color(0xFF10B981).withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                )
              else
                Tooltip(
                  message: '버전 및 업데이트 확인',
                  child: IconButton(
                    onPressed: onOpenUpdateDialog,
                    icon: const Icon(Icons.system_update_alt_rounded, size: 20),
                    color: Colors.white70,
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF282B36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 12),
              // 우측 내보내기 버튼들
              Tooltip(
                message: '화면 텍스트 추출 (로컬 OCR)',
                child: FilledButton.tonalIcon(
                  onPressed: hasActiveCapture ? onExtractText : null,
                  icon: const Icon(Icons.document_scanner_rounded, size: 17),
                  label: const Text('텍스트 추출'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF282B36),
                    foregroundColor: const Color(0xFF60A5FA),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: '에이전트용 템플릿 복사 (AI 프롬프트)',
                enabled: hasActiveCapture,
                onSelected: (template) => onCopyForAgent?.call(template),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: '[image: {path}] 이 스크린샷을 분석해서 문제를 설명해줘.',
                    child: Text('기본: 분석 및 문제 설명'),
                  ),
                  PopupMenuItem(
                    value: '[image: {path}] 이 화면에 보이는 내용을 상세히 설명해줘.',
                    child: Text('상세: 화면 내용 설명'),
                  ),
                  PopupMenuItem(
                    value: '![스크린샷]({path})',
                    child: Text('마크다운: ![스크린샷](경로)'),
                  ),
                  PopupMenuItem(
                    value: '{path}',
                    child: Text('경로만: 이미지 파일 절대경로'),
                  ),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF282B36),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF383C4A)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.smart_toy_outlined,
                        size: 17,
                        color: Color(0xFF34D399),
                      ),
                      SizedBox(width: 6),
                      Text(
                        '에이전트 복사',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Icon(
                        Icons.arrow_drop_down_rounded,
                        size: 18,
                        color: Colors.white70,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: isPinned ? '화면 핀 고정 해제' : '화면 최상단 핀 고정 (Always-on-Top)',
                child: IconButton(
                  onPressed: hasActiveCapture ? onTogglePin : null,
                  icon: Icon(
                    isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
                    size: 19,
                  ),
                  color: isPinned ? const Color(0xFF60A5FA) : Colors.white70,
                  style: IconButton.styleFrom(
                    backgroundColor: isPinned
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.25)
                        : const Color(0xFF282B36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: isPinned
                          ? const BorderSide(
                              color: Color(0xFF60A5FA),
                              width: 1.2,
                            )
                          : BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                onPressed: hasActiveCapture ? onCopyClipboard : null,
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: const Text('클립보드 복사'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF2B3040),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: hasActiveCapture && !isExportBusy
                    ? onSaveFile
                    : null,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('PNG 저장'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
              PopupMenuButton<_SaveAction>(
                tooltip: autoSaveEnabled
                    ? 'PNG 저장 옵션 (자동 저장 켜짐)'
                    : 'PNG 저장 옵션',
                enabled: !isExportBusy,
                icon: Icon(
                  Icons.arrow_drop_down_rounded,
                  color: autoSaveEnabled ? const Color(0xFF34D399) : null,
                ),
                onSelected: (action) {
                  switch (action) {
                    case _SaveAction.chooseDirectory:
                      onChooseSaveDirectory();
                    case _SaveAction.clearDirectory:
                      onClearSaveDirectory();
                    case _SaveAction.toggleAutoSave:
                      onToggleAutoSave?.call();
                    case _SaveAction.saveAs:
                      onSaveFileAs();
                  }
                },
                itemBuilder: (_) => [
                  if (saveDirectory != null)
                    PopupMenuItem<_SaveAction>(
                      enabled: false,
                      child: Tooltip(
                        message: saveDirectory!,
                        child: Text(
                          saveDirectory!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  PopupMenuItem(
                    value: _SaveAction.chooseDirectory,
                    child: Text(
                      saveDirectory == null ? '저장 폴더 지정…' : '저장 폴더 변경…',
                    ),
                  ),
                  PopupMenuItem(
                    value: _SaveAction.clearDirectory,
                    enabled: saveDirectory != null,
                    child: const Text('저장 폴더 지정 해제'),
                  ),
                  CheckedPopupMenuItem<_SaveAction>(
                    value: _SaveAction.toggleAutoSave,
                    checked: autoSaveEnabled,
                    child: const Text('캡쳐 시 자동 저장'),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: _SaveAction.saveAs,
                    enabled: hasActiveCapture,
                    child: const Text('다른 위치에 저장…'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 2단: 마크업 편집 도구 + 색상/굵기 + Undo/Redo
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildToolChip(
                  tool: AnnotationTool.select,
                  icon: Icons.near_me_rounded,
                ),
                _buildToolChip(
                  tool: AnnotationTool.pen,
                  icon: Icons.edit_rounded,
                ),
                _buildToolChip(
                  tool: AnnotationTool.highlighter,
                  icon: Icons.border_color_rounded,
                ),
                _buildToolChip(
                  tool: AnnotationTool.rectangle,
                  icon: Icons.crop_din_rounded,
                ),
                _buildToolChip(
                  tool: AnnotationTool.arrow,
                  icon: Icons.north_east_rounded,
                ),
                _buildToolChip(
                  tool: AnnotationTool.text,
                  icon: Icons.title_rounded,
                ),
                _buildToolChip(
                  tool: AnnotationTool.stepCounter,
                  icon: Icons.format_list_numbered_rounded,
                ),
                _buildToolChip(
                  tool: AnnotationTool.redaction,
                  icon: Icons.shield_rounded,
                ),
                _buildCropButton(),
                _buildVerticalDivider(),
                for (final color in paletteColors)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      onTap: () => onSelectColor(color),
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 140),
                        width: selectedColor == color ? 24 : 20,
                        height: selectedColor == color ? 24 : 20,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selectedColor == color
                                ? Colors.white
                                : Colors.white24,
                            width: selectedColor == color ? 2.5 : 1,
                          ),
                          boxShadow: selectedColor == color
                              ? [
                                  BoxShadow(
                                    color: color.withValues(alpha: 0.55),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                      ),
                    ),
                  ),
                _buildVerticalDivider(),
                _buildStrokeOption(label: '세밀', widthValue: 3.0),
                const SizedBox(width: 4),
                _buildStrokeOption(label: '보통', widthValue: 5.0),
                const SizedBox(width: 4),
                _buildStrokeOption(label: '굵게', widthValue: 9.0),
                _buildVerticalDivider(),
                IconButton(
                  onPressed: hasActiveCapture && canUndo ? onUndo : null,
                  tooltip: '실행 취소 (Cmd/Ctrl + Z)',
                  icon: const Icon(Icons.undo_rounded, size: 19),
                ),
                IconButton(
                  onPressed: hasActiveCapture && canRedo ? onRedo : null,
                  tooltip: '다시 실행 (Cmd/Ctrl + Shift + Z)',
                  icon: const Icon(Icons.redo_rounded, size: 19),
                ),
                if (onDeleteSelectedAnnotation != null)
                  IconButton(
                    onPressed: hasActiveCapture && hasSelectedAnnotation
                        ? onDeleteSelectedAnnotation
                        : null,
                    tooltip: '선택한 주석 삭제 (Delete)',
                    icon: const Icon(Icons.backspace_outlined, size: 18),
                  ),
                IconButton(
                  onPressed: hasActiveCapture && canUndo
                      ? onClearAnnotations
                      : null,
                  tooltip: '마크업 모두 지우기',
                  icon: const Icon(Icons.delete_sweep_outlined, size: 20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCaptureButton({
    required IconData icon,
    required String label,
    required String shortcut,
    required VoidCallback? onPressed,
    bool primary = false,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: primary
            ? const Color(0xFF4F46E5)
            : const Color(0xFF282C37),
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: primary ? const Color(0xFF6366F1) : const Color(0xFF363B49),
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          if (shortcut.isNotEmpty) ...[
            const SizedBox(width: 7),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                shortcut,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: Colors.white70,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildToolChip({
    required AnnotationTool tool,
    required IconData icon,
  }) {
    final isSelected = selectedTool == tool;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: '${tool.label} (${tool.tooltip})',
        child: InkWell(
          onTap: () => onSelectTool(tool),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.22)
                  : const Color(0xFF262934),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF323644),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected ? const Color(0xFF60A5FA) : Colors.white70,
                ),
                const SizedBox(width: 5),
                Text(
                  tool.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? Colors.white : Colors.white70,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCropButton() {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Tooltip(
        message: isCropping ? '자르기 취소 (ESC)' : '이미지 자르기 (Crop)',
        child: InkWell(
          onTap: hasActiveCapture ? onToggleCrop : null,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isCropping
                  ? const Color(0xFF3B82F6).withValues(alpha: 0.3)
                  : const Color(0xFF262934),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isCropping
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF323644),
                width: isCropping ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.crop_rounded,
                  size: 16,
                  color: isCropping
                      ? const Color(0xFF60A5FA)
                      : (hasActiveCapture ? Colors.white70 : Colors.white24),
                ),
                const SizedBox(width: 5),
                Text(
                  '자르기',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isCropping ? FontWeight.w600 : FontWeight.w400,
                    color: isCropping
                        ? Colors.white
                        : (hasActiveCapture ? Colors.white70 : Colors.white24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStrokeOption({
    required String label,
    required double widthValue,
  }) {
    final isSelected = (strokeWidth - widthValue).abs() < 0.5;
    return InkWell(
      onTap: () => onSelectStrokeWidth(widthValue),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.white38 : Colors.white12,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: isSelected ? Colors.white : Colors.white60,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 22,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: const Color(0xFF323644),
    );
  }
}
