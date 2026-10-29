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

### 배포 서명 설정

GitHub Actions의 macOS 배포에는 다음 Repository Secrets가 필요합니다.

| Secret | 값 |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | 개인 키를 포함한 개발자 인증서 `.p12` 파일의 Base64 문자열 |
| `MACOS_CERTIFICATE_PASSWORD` | `.p12` 내보내기 암호 |
| `MACOS_KEYCHAIN_PASSWORD` | CI 임시 키체인용 암호 |
| `MACOS_SIGNING_IDENTITY` | 인증서의 전체 이름 (`Developer ID Application: …` 또는 `Apple Development: …`) |

인증서 이름은 `security find-identity -v -p codesigning`으로 확인합니다. Secrets가 없거나 서명 검증이 실패하면 macOS 배포를 중단합니다. PR에서는 분석과 테스트를 실행하며, 인증서를 요구하는 macOS Release 빌드·패키징은 수행하지 않습니다. 이 설정은 코드 서명을 다루며 Apple 공증(notarization)은 포함하지 않습니다.

### 업데이트 복구와 임시 파일

- 업데이트는 기존 앱 옆에 새 앱을 준비한 뒤 기존 앱을 백업하고 교체합니다. 이동 또는 실행 명령이 실패하면 백업을 복원합니다. 실행 명령 성공 후 발생하는 앱 내부 크래시까지 감지하지는 않습니다.
- macOS 백업은 기존 앱 경로 뒤의 `.snapcraft-previous.app`, Windows 백업은 설치 폴더 뒤의 `.snapcraft-previous`에 보관하며 다음 교체 시 갱신합니다. 복구가 필요하면 앱을 종료하고 백업을 원래 이름으로 되돌립니다.
- 설치 폴더와 그 상위 폴더에 쓰기 권한이 필요합니다. Windows ZIP은 다른 사용자 파일과 섞지 말고 전용 SnapCraft 폴더에 압축 해제하세요.
- 설치 결과는 앱 지원 폴더의 `update-install.log`에 기록합니다. macOS에서는 일반적으로 `~/Library/Application Support/com.example.snapCraft/` 아래에 있습니다.
- 최근 캡쳐는 최대 20개 또는 원본 PNG와 디코딩 이미지의 추정 합계 256MB까지 보관합니다. 최신 한 개는 크기에 관계없이 유지하며, 한도를 넘으면 오래된 항목과 해당 편집 내용을 정리합니다. 필요한 이미지는 PNG로 저장하세요.
- 캡쳐 삭제 시 원본 임시 파일과 이미지 리소스를 해제합니다. 클립보드용 PNG는 독립 파일로 보관하므로 목록에서 삭제해도 붙여넣을 수 있습니다. 시작 시 7일 지난 임시 파일을 정리하며 현재 macOS 클립보드가 참조하는 파일은 보존합니다.
