import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:screen_capturer/screen_capturer.dart';

import '../services/hotkey_service.dart';
import '../services/tray_service.dart';

class ShortcutSettingsDialog extends StatefulWidget {
  final VoidCallback onShortcutsUpdated;

  const ShortcutSettingsDialog({super.key, required this.onShortcutsUpdated});

  @override
  State<ShortcutSettingsDialog> createState() => _ShortcutSettingsDialogState();
}

class _ShortcutSettingsDialogState extends State<ShortcutSettingsDialog> {
  final HotkeyService _hotkeyService = HotkeyService.instance;
  CaptureMode? _recordingMode;
  HotKey? _recordedHotKey;
  String? _errorMessage;

  Future<void> _startRecording(CaptureMode mode) async {
    setState(() {
      _recordingMode = mode;
      _recordedHotKey = _hotkeyService.hotKeys[mode];
    });
  }

  Future<void> _saveRecordedHotKey() async {
    final mode = _recordingMode;
    final hotKey = _recordedHotKey;
    String? error;
    if (mode != null && hotKey != null) {
      error = await _apply(() => _hotkeyService.updateHotKey(mode, hotKey));
    }
    if (!mounted) return;
    setState(() {
      _errorMessage = error;
      _recordingMode = null;
      _recordedHotKey = null;
    });
  }

  Future<void> _resetDefaults() async {
    final error = await _apply(_hotkeyService.resetToDefaults);
    if (!mounted) return;
    setState(() {
      _errorMessage = error;
      _recordingMode = null;
      _recordedHotKey = null;
    });
  }

  /// 단축키 변경을 적용하고, 등록 실패 시 사용자에게 보여줄 메시지를 반환한다.
  Future<String?> _apply(Future<void> Function() change) async {
    try {
      await change();
      widget.onShortcutsUpdated();
      return null;
    } on StateError catch (error) {
      widget.onShortcutsUpdated();
      return error.message;
    }
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
            '단축키 및 시스템 설정',
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF252834),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF323646)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.vertical_align_bottom_rounded,
                    size: 20,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '창 닫기 시 시스템 트레이로 숨기기',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '닫기(X) 버튼 클릭 시 앱이 종료되지 않고 메뉴바에 상주합니다.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: TrayService.instance.closeToTray,
                    activeThumbColor: const Color(0xFF60A5FA),
                    onChanged: (val) async {
                      await TrayService.instance.setCloseToTray(val);
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12.5, color: Colors.redAccent),
              ),
            ],
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
                  style: const TextStyle(fontSize: 11.5, color: Colors.white54),
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
