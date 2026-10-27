import 'package:flutter/material.dart';
import 'package:screen_capturer/screen_capturer.dart';
import '../models/annotation.dart';
import '../services/hotkey_service.dart';

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
  final VoidCallback onOpenShortcutSettings;

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
    required this.onOpenShortcutSettings,
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
        border: Border(
          bottom: BorderSide(color: Color(0xFF2E323E), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1단: 캡쳐 실행 버튼 그룹 + 단축키 설정 + 복사/저장 액션
          Row(
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
              const Spacer(),
              // 우측 내보내기 버튼들
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
                onPressed: hasActiveCapture ? onSaveFile : null,
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
            ],
          ),
          const SizedBox(height: 10),
          // 2단: 마크업 편집 도구 바 (펜, 형광펜, 사각형, 화살표, 텍스트, 모자이크 + 색상/굵기 + Undo/Redo)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
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
                  tool: AnnotationTool.mosaic,
                  icon: Icons.blur_on_rounded,
                ),
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
                IconButton(
                  onPressed:
                      hasActiveCapture && canUndo ? onClearAnnotations : null,
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
        backgroundColor:
            primary ? const Color(0xFF4F46E5) : const Color(0xFF282C37),
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
