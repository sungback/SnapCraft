import 'package:flutter/material.dart';
import '../services/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final ReleaseInfo? initialReleaseInfo;

  const UpdateDialog({
    super.key,
    this.initialReleaseInfo,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  ReleaseInfo? _releaseInfo;
  bool _isChecking = false;
  bool _isInstalling = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialReleaseInfo != null) {
      _releaseInfo = widget.initialReleaseInfo;
    } else {
      _checkUpdate();
    }
  }

  Future<void> _checkUpdate() async {
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    final info = await UpdateService.instance.checkForUpdate();
    if (!mounted) return;

    setState(() {
      _isChecking = false;
      _releaseInfo = info;
      if (info == null) {
        _errorMessage =
            'GitHub 서버에서 버전 정보를 가져오지 못했습니다. 네트워크 연결을 확인해 주세요.';
      }
    });
  }

  Future<void> _startUpdate() async {
    final info = _releaseInfo;
    if (info == null || _isInstalling) return;

    setState(() {
      _isInstalling = true;
      _progress = 0.02;
      _statusText = '업데이트 준비 중...';
      _errorMessage = null;
    });

    try {
      await UpdateService.instance.downloadAndInstallUpdate(
        info,
        onProgress: (progress, status) {
          if (!mounted) return;
          setState(() {
            _progress = progress;
            _statusText = status;
          });
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isInstalling = false;
        _errorMessage = '자동 설치 중 오류가 발생했습니다: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = _releaseInfo;
    final hasUpdate = info?.hasUpdate ?? false;

    return Dialog(
      backgroundColor: const Color(0xFF1E212B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF323646)),
      ),
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: hasUpdate
                          ? const Color(0xFF10B981).withValues(alpha: 0.16)
                          : const Color(0xFF3B82F6).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasUpdate
                          ? Icons.system_update_alt_rounded
                          : Icons.verified_rounded,
                      color: hasUpdate
                          ? const Color(0xFF34D399)
                          : const Color(0xFF60A5FA),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasUpdate ? '새 업데이트가 있습니다!' : '소프트웨어 업데이트',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          info != null
                              ? '현재 버전: v${info.currentVersion}  ·  최신 버전: v${info.latestVersion}'
                              : '버전 정보를 확인하고 있습니다...',
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Colors.white60,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isInstalling)
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: Colors.white54,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              if (_isChecking)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(strokeWidth: 2.5),
                        SizedBox(height: 12),
                        Text(
                          'GitHub Releases에서 최신 버전을 확인하는 중...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white70,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFFFCA5A5),
                      height: 1.4,
                    ),
                  ),
                )
              else if (info != null) ...[
                Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 180),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14161C),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF2B2F3C)),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasUpdate
                              ? '${info.releaseTitle} 변경 사항'
                              : '현재 최신 버전(v${info.currentVersion})을 사용 중입니다.',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        if (hasUpdate) ...[
                          const SizedBox(height: 8),
                          Text(
                            info.releaseNotes.replaceAll('**', ''),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Colors.white70,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              if (_isInstalling) ...[
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 8,
                    backgroundColor: const Color(0xFF14161C),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Color(0xFF10B981),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _statusText,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFF6EE7B7),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (info != null && !_isInstalling)
                    TextButton.icon(
                      onPressed: () =>
                          UpdateService.instance.openUrl(info.htmlUrl),
                      icon: const Icon(Icons.open_in_new_rounded, size: 15),
                      label: const Text(
                        'GitHub 릴리즈 보기',
                        style: TextStyle(fontSize: 12.5),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                  Flexible(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!_isInstalling && !_isChecking)
                          OutlinedButton.icon(
                            onPressed: _checkUpdate,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: const Text(
                              '다시 확인',
                              style: TextStyle(fontSize: 12.5),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: const BorderSide(color: Color(0xFF383C4C)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        if (hasUpdate && !_isInstalling)
                          FilledButton.icon(
                            onPressed: _startUpdate,
                            icon: const Icon(
                              Icons.downloading_rounded,
                              size: 17,
                            ),
                            label: const Text(
                              '지금 업데이트 및 재시작',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                      ],
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
