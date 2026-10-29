# SnapCraft (화면 캡쳐 & 마크업 앱)

**SnapCraft**는 **macOS**와 **Windows**에서 모두 동작하는 크로스플랫폼 화면 캡쳐 및 마크업(주석) 편집 데스크톱 애플리케이션입니다.

---

## 주요 기능

1. **3가지 화면 캡쳐 모드 (`screen_capturer`)**
   * **영역 지정 캡쳐 (`CaptureMode.region`)**: 마우스 드래그로 원하는 영역만 선택하여 캡쳐
   * **전체 화면 캡쳐 (`CaptureMode.screen`)**: 현재 모니터 전체 화면 즉시 캡쳐
   * **창 선택 캡쳐 (`CaptureMode.window`)**: 특정 실행 중인 애플리케이션 창만 깔끔하게 캡쳐
   * 캡쳐 시 앱 창이 화면을 가리지 않도록 자동으로 숨겼다가(`hide`), 캡쳐 완료 후 복원 및 포커스(`show` & `focus`)

2. **글로벌 단축키 및 커스터마이징 (`hotkey_manager`)**
   * 백그라운드 상태에서도 단축키로 즉시 캡쳐 실행
   * 기본 단축키:
     * 영역 캡쳐: `Cmd(Ctrl) + Shift + A`
     * 전체 화면 캡쳐: `Cmd(Ctrl) + Shift + S`
     * 창 선택 캡쳐: `Cmd(Ctrl) + Shift + W`
   * 상단 키보드 설정 아이콘을 눌러 원하는 단축키 조합으로 직접 변경 및 영구 저장 가능

3. **6종 마크업(주석) 편집기**
   * **펜 (`Pen`)**: 자유 곡선 그리기
   * **형광펜 (`Highlighter`)**: 반투명 형광펜 강조
   * **사각형 (`Rectangle`)**: 테두리 박스로 영역 강조
   * **화살표 (`Arrow`)**: 방향 지시 화살표 그리기
   * **텍스트 (`Text`)**: 원하는 위치를 클릭해 텍스트 라벨 추가
   * **모자이크 (`Mosaic`)**: 민감한 개인정보 영역 가우시안 블러 + 픽셀 격자 차폐
   * 8종 색상 팔레트, 3단계 굵기(세밀/보통/굵게), **실행 취소(`Cmd/Ctrl + Z`) / 다시 실행(`Cmd/Ctrl + Shift + Z`) / 전체 지우기** 지원

4. **멀티 포맷 클립보드 복사 및 PNG 저장**
   * 캡쳐 직후 및 **[클립보드 복사(`Cmd/Ctrl + C`)]** 클릭 시:
     * **일반 앱(카카오톡, 슬랙, 노션, Claude Code 등)**: 고해상도 PNG/TIFF 이미지가 그대로 붙여넣어짐
     * **터미널 CLI(`agy`, Ghostty 등)**: 마크업이 반영된 이미지 파일 경로(`fileURL` / `string`)가 자동으로 붙여넣어져 멀티모달 에이전트가 즉시 인식
   * **[PNG 저장(`Cmd/Ctrl + S`)]**: 원하는 폴더에 원본 해상도 PNG 파일로 저장
   * 좌측 **최근 캡쳐 목록 사이드바**에서 여러 캡쳐본 간 전환 및 재편집 지원

5. **인앱 자동 업데이트 (`UpdateService`)**
   * 앱 시작 시 GitHub Releases(`sungback/SnapCraft`)의 최신 버전을 확인하고, 새 버전이 있으면 상단에 업데이트 배지 표시
   * 원클릭으로 다운로드 → 설치 파일 교체 → 앱 재실행 (macOS `.app` 교체 / Windows `xcopy` 교체)

---

## 프로젝트 구조

```text
lib/
├── main.dart                          # 앱 초기화 및 메인 워크스페이스 화면
├── models/
│   ├── annotation.dart                # 6종 마크업 도구 및 주석 데이터 모델
│   └── capture_item.dart              # 캡쳐 이미지 메타데이터 및 Undo/Redo 히스토리
├── services/
│   ├── capture_service.dart           # 창 자동 숨김/복원 및 OS 네이티브 캡쳐 연동
│   ├── export_service.dart            # 마크업 캔버스 렌더링, 멀티 포맷 클립보드, PNG 저장
│   ├── hotkey_service.dart            # 글로벌 단축키 등록 및 설정 저장
│   └── update_service.dart            # GitHub Releases 기반 버전 확인 및 자동 설치
└── widgets/
    ├── annotation_canvas.dart         # 원본 해상도 좌표계 기반 인터랙티브 드로잉 캔버스
    ├── history_sidebar.dart           # 최근 캡쳐 썸네일 히스토리 사이드바
    ├── shortcut_settings_dialog.dart  # 글로벌 단축키 변경 모달
    ├── top_toolbar.dart               # 캡쳐 모드 및 마크업 도구 상단 툴바
    └── update_dialog.dart             # 업데이트 확인/진행 다이얼로그
```

---

## 실행 및 빌드 방법

### 1. 개발 모드 실행
```bash
# 패키지 설치
flutter pub get

# macOS 실행
flutter run -d macos

# Windows 실행
flutter run -d windows
```

### 2. 정식 배포용(Release) 빌드
```bash
# macOS Release 빌드
flutter build macos --release

# Windows Release 빌드
flutter build windows --release
```
