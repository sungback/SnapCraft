# SnapCraft 작업 진행 현황 (TASKS.md)

이 문서는 **SnapCraft** (macOS & Windows 크로스플랫폼 화면 캡쳐 및 마크업 앱) 프로젝트의 작업 이력과 향후 할 일(Backlog)을 관리합니다.

---

## 완료된 작업 (Completed)

### Phase 1. 프로젝트 설계 및 환경 구축
- [x] 요구사항 정의 (`/grill-me` 인터뷰 기반 기술 스택, 캡쳐 모드, 마크업 도구, 단축키 확정)
- [x] Flutter SDK 설치 및 macOS / Windows 데스크톱 타겟 활성화
- [x] 프로젝트 초기화 (`snap_craft`) 및 필수 패키지(`screen_capturer`, `window_manager`, `hotkey_manager`, `pasteboard`, `file_picker`, `path_provider`, `shared_preferences`) 구성

### Phase 2. 핵심 캡쳐 및 마크업 기능 구현
- [x] 3가지 캡쳐 모드 구현 (`CaptureMode.region`, `CaptureMode.screen`, `CaptureMode.window`)
- [x] 캡쳐 시 앱 창 자동 숨김(`hide`) 및 완료 후 자동 복원(`show` & `focus`) 처리
- [x] 글로벌 단축키 기본값(`Cmd/Ctrl + Shift + A/S/W`) 등록 및 사용자 정의 단축키 변경 모달(`ShortcutSettingsDialog`) 구현
- [x] 6종 마크업 편집기 구현 (`AnnotationCanvas` & `ExportService`)
  - [x] 자유 곡선 펜 (`pen`)
  - [x] 반투명 형광펜 (`highlighter`)
  - [x] 사각형 박스 (`rectangle`)
  - [x] 방향 화살표 (`arrow`)
  - [x] 텍스트 라벨 입력 (`text`)
  - [x] 개인정보 보호용 모자이크/블러 (`mosaic`)
  - [x] 색상 팔레트(8종), 선 굵기(3단계), Undo / Redo / 전체 지우기
- [x] 최근 캡쳐 썸네일 히스토리 사이드바 (`HistorySidebar`) 구현

### Phase 3. macOS 네이티브 안정화 및 클립보드 개선
- [x] `AppDelegate.swift`의 `applicationShouldTerminateAfterLastWindowClosed`를 `false`로 설정하여 창 숨김 시 앱 종료 방지
- [x] `FilePicker` macOS 저장 시 `com.apple.security.files.user-selected.read-write` 권한 및 `skipEntitlementsChecks()` 적용
- [x] `Developer ID Application` 정식 인증서 서명 적용으로 재시작/재빌드 시 macOS 화면 기록 권한(TCC) 팝업 반복 문제 해결
- [x] `MainFlutterWindow.swift`에 멀티 포맷 클립보드 채널(`snap_craft/clipboard`) 구현
  - 일반 앱/Claude Code에는 `PNG`/`TIFF` 이미지로, `agy`/Ghostty 등 터미널에는 파일 경로(`fileURL`/`string`)로 동시 붙여넣기 지원

### Phase 4. 배포 패키징, Git 및 자동 업데이트 구성
- [x] macOS Release 빌드 및 코드 서명된 설치 파일(`dist/SnapCraft-macOS.dmg`, `dist/SnapCraft-macOS.zip`) 생성
- [x] `.gitignore`, `.gitattributes`, `README.md`, `AGENTS.md`, `TASKS.md` 구성 및 Git 저장소(`main`) 초기화
- [x] GitHub Actions (`.github/workflows/build.yml`) macOS/Windows 자동 빌드 설정 및 Windows CMake(`jni` 및 MSVC `/WX` 이슈) 방어 코드 적용
- [x] `pubspec.yaml` 버전 상승 시 GitHub Actions에서 자동으로 `v<version>` GitHub Release 생성 및 macOS/Windows 설치 파일 업로드 파이프라인(`publish-release`) 구축
- [x] GitHub Releases 연동 인앱 자동 업데이트(`UpdateService` & `UpdateDialog`) 구현 (앱 시작 시 자동 확인, 상단 업데이트 배지, 원클릭 다운로드 후 자동 교체 설치 및 재실행)

---

## 진행 중 / 예정 작업 (Todo & Backlog)

- [ ] **Windows 환경 빌드 및 패키징 검증**
  - [ ] Windows에서 `flutter build windows --release` 테스트 및 설치 파일(`.exe` / `.msix`) 생성
  - [ ] Windows 멀티 포맷 클립보드 동작 점검
- [ ] **편집 및 편의 기능 고도화 (필요 시)**
  - [ ] 캡쳐 이미지 자르기(Crop) 도구 추가
  - [ ] 번호 매기기(Step Counter: ①, ②, ③) 스탬프 마크업 도구 추가
  - [ ] 자동 저장 폴더 지정 옵션 (캡쳐 시 지정된 폴더에 자동 파일 저장)
  - [ ] 시스템 트레이(macOS 상단 메뉴바 / Windows 트레이 아이콘) 상주 모드 옵션 추가
