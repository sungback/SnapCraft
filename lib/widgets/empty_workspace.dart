import 'package:flutter/material.dart';
import 'package:screen_capturer/screen_capturer.dart';

import '../services/hotkey_service.dart';

class EmptyWorkspaceView extends StatelessWidget {
  final ValueChanged<CaptureMode> onTriggerCapture;

  const EmptyWorkspaceView({super.key, required this.onTriggerCapture});

  @override
  Widget build(BuildContext context) {
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
                  Icons.screenshot_monitor_rounded,
                  size: 34,
                  color: Color(0xFF60A5FA),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'SnapCraft 화면 캡쳐 & 마크업',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '캡쳐한 화면 위에 펜·형광펜·화살표·텍스트를 표시하고,\n'
                '보안이 필요한 영역은 검은색 가림으로 가린 뒤 클립보드로 복사하세요.',
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
                    child: _QuickStartCard(
                      icon: Icons.crop_free_rounded,
                      title: '영역 지정 캡쳐',
                      shortcut: hotkeyService.formatHotKey(CaptureMode.region),
                      description: '원하는 영역을 드래그하여\n정확히 캡쳐합니다.',
                      onTap: () => onTriggerCapture(CaptureMode.region),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickStartCard(
                      icon: Icons.fullscreen_rounded,
                      title: '전체 화면 캡쳐',
                      shortcut: hotkeyService.formatHotKey(CaptureMode.screen),
                      description: '현재 모니터 전체를\n즉시 캡쳐합니다.',
                      onTap: () => onTriggerCapture(CaptureMode.screen),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _QuickStartCard(
                      icon: Icons.web_asset_rounded,
                      title: '창 선택 캡쳐',
                      shortcut: hotkeyService.formatHotKey(CaptureMode.window),
                      description: '특정 앱 창만 깔끔하게\n선택해 캡쳐합니다.',
                      onTap: () => onTriggerCapture(CaptureMode.window),
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
}

class _QuickStartCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String shortcut;
  final String description;
  final VoidCallback onTap;

  const _QuickStartCard({
    required this.icon,
    required this.title,
    required this.shortcut,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
}
