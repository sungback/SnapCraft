import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_capturer/screen_capturer.dart';
import '../services/hotkey_service.dart';

class ShortcutSettingsDialog extends StatefulWidget {
  final VoidCallback onShortcutsUpdated;

  const ShortcutSettingsDialog({
    super.key,
    required this.onShortcutsUpdated,
  });

  @override
  State<ShortcutSettingsDialog> createState() => _ShortcutSettingsDialogState();
}

class _ShortcutSettingsDialogState extends State<ShortcutSettingsDialog> {
  final HotkeyService _hotkeyService = HotkeyService.instance;
  CaptureMode? _recordingMode;
  HotKey? _recordedHotKey;

  Future<void> _startRecording(CaptureMode mode) async {
    setState(() {
      _recordingMode = mode;
      _recordedHotKey = _hotkeyService.hotKeys[mode];
    });
  }

  Future<void> _saveRecordedHotKey() async {
    final mode = _recordingMode;
    final hotKey = _recordedHotKey;
    if (mode != null && hotKey != null) {
      await _hotkeyService.updateHotKey(mode, hotKey);
      widget.onShortcutsUpdated();
    }
    setState(() {
      _recordingMode = null;
      _recordedHotKey = null;
    });
  }

  Future<void> _resetDefaults() async {
    await _hotkeyService.resetToDefaults();
    widget.onShortcutsUpdated();
    setState(() {
      _recordingMode = null;
      _recordedHotKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1E212B),
      title: const Row(
        children: [
          Icon(Icons.keyboard_rounded, size: 22, color: Color(0xFF60A5FA)),
          SizedBox(width: 10),
          Text(
            '글로벌 단축키 설정',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
        ],
      ),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '앱이 백그라운드에 있을 때도 아래 단축키를 눌러 즉시 캡쳐할 수 있습니다.',
              style: TextStyle(fontSize: 12.5, color: Colors.white60),
            ),
            const SizedBox(height: 16),
            _buildShortcutRow(
              mode: CaptureMode.region,
              title: '영역 지정 캡쳐',
              subtitle: '마우스 드래그로 영역 선택',
              icon: Icons.crop_free_rounded,
            ),
            const SizedBox(height: 10),
            _buildShortcutRow(
              mode: CaptureMode.screen,
              title: '전체 화면 캡쳐',
              subtitle: '현재 모니터 전체 화면 즉시 캡쳐',
              icon: Icons.fullscreen_rounded,
            ),
            const SizedBox(height: 10),
            _buildShortcutRow(
              mode: CaptureMode.window,
              title: '창 선택 캡쳐',
              subtitle: '특정 실행 중인 창 선택 캡쳐',
              icon: Icons.web_asset_rounded,
            ),
            if (_recordingMode != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF282C3A),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF60A5FA)),
                ),
                child: Column(
                  children: [
                    const Text(
                      '원하는 새 단축키 조합을 키보드에서 눌러주세요',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    HotKeyRecorder(
                      initalHotKey: _recordedHotKey,
                      onHotKeyRecorded: (hotKey) {
                        setState(() {
                          _recordedHotKey = hotKey;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _recordingMode = null;
                              _recordedHotKey = null;
                            });
                          },
                          child: const Text('취소'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _saveRecordedHotKey,
                          child: const Text('단축키 적용'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _resetDefaults,
          icon: const Icon(Icons.restore_rounded, size: 17),
          label: const Text('기본값 복원'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  Widget _buildShortcutRow({
    required CaptureMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isRecordingThis = _recordingMode == mode;
    final shortcutLabel = _hotkeyService.formatHotKey(mode);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF252834),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isRecordingThis
              ? const Color(0xFF60A5FA)
              : const Color(0xFF323646),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.white70),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Colors.white54,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF191B22),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              shortcutLabel,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF93C5FD),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(
            onPressed: () => _startRecording(mode),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              minimumSize: Size.zero,
            ),
            child: const Text('변경', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
