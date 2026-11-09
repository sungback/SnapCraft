# Changelog

버전별 주요 변경 사항. 진행 중/예정 작업은 `TASKS.md`를 참조하세요.

## v1.0.12
- 모자이크를 불투명 검정색 보안 가림으로 대체하고, 가림 완료 시 편집 이미지를 자동으로 클립보드에 복사
- 연속 복사의 최신 결과 우선 처리, 대기 요청 취소 및 복사 실패 후 재시도와 픽셀 차폐 회귀 테스트 추가

## v1.0.11
- macOS Ad-hoc 서명에 identifier 기반 designated requirement 적용: 업데이트마다 화면 기록 권한 팝업이 반복되던 문제 수정

## v1.0.10
- v1.0.9 macOS 빌드가 실행 직후 종료(HotKey.framework 라이브러리 검증 실패)되는 문제 수정: Ad-hoc 서명에서 hardened runtime 제거

## v1.0.9
- macOS 배포를 인증서·Secrets 없는 Ad-hoc 서명으로 전환하고, 인앱 업데이트는 서명 구조만 검증 (개발자 인증서가 있는 Mac은 설치 전 재서명 유지)

## v1.0.8
- PNG 일회성 저장과 저장 실패 복구 검증을 보강하고 테스트의 비동기 대기 안정성 개선

## v1.0.7
- PNG 저장 폴더 지정·변경·해제 및 재시작 후 설정 유지, 다른 위치에 일회성 저장 지원
- 직접 저장 시 파일명 충돌·중복 실행 방지, 사용할 수 없는 저장 폴더 변경 경로 개선

## v1.0.6
- 캡쳐 오류 후 재시도 및 업데이트 백업·실패 복원 지원, macOS 배포 서명 검증 강화
- 이미지·임시 파일 수명 관리 및 최근 캡쳐 보관 한도 적용, Windows 경로 비교·단축키 표시 수정

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
