# Changelog

버전별 주요 변경 사항. 진행 중/예정 작업은 `TASKS.md`를 참조하세요.

## v1.0.6
- 캡쳐 오류 후 재시도 및 업데이트 백업·실패 복원 지원, macOS 배포 서명 검증 강화
- 이미지 리소스·임시 파일 정리 및 최근 캡쳐 보관 한도 적용, 클립보드 파일 독립 보존

## v1.0.5
- SnapCraft 전용 앱 아이콘 적용 (macOS `AppIcon.appiconset` 전 해상도, Windows `app_icon.ico` 멀티 해상도)

## v1.0.4
- Windows 창 캡쳐 시 가려진 영역/테두리 여백이 찍히는 문제 해결 (네이티브 Win32 창 선택기, 자동 전면화, `DWMWA_EXTENDED_FRAME_BOUNDS` 크롭)

## v1.0.3
- macOS 인앱 업데이트 후 화면 기록 권한(TCC) 팝업이 재발하는 문제 해결 (`UpdateService._resignMacBundleForTcc` 재서명)

## v1.0.2
- `UpdateDialog` 하단 버튼 레이아웃 오버플로우 수정
- GitHub Actions 빌드 속도 최적화 (macOS arm64 전용, CocoaPods 캐싱, 병렬 패키징, Windows `7z` 멀티스레드 압축)

## v1.0.1
- Windows 타이틀바 최소화/최대화 버튼 누락 수정

## 초기 구현 (v1.0.1 이전)
- 3가지 캡쳐 모드(영역/전체/창), 캡쳐 시 앱 창 자동 숨김·복원
- 글로벌 단축키 및 변경 다이얼로그
- 6종 마크업 도구(펜, 형광펜, 사각형, 화살표, 텍스트, 모자이크), 8색 팔레트, 3단계 굵기, Undo/Redo/전체 지우기
- 최근 캡쳐 히스토리 사이드바
- macOS 안정화: 창 숨김 시 종료 방지, FilePicker 권한, Developer ID 서명, 멀티 포맷 클립보드 채널
- 배포: GitHub Actions 빌드, `pubspec.yaml` 버전 상승 시 자동 Release 생성, 인앱 자동 업데이트
