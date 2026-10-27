# AGENTS.md — SnapCraft 프로젝트 에이전트 가이드

이 문서는 AI 코딩 에이전트(Antigravity, Claude Code 등)가 **SnapCraft** 프로젝트를 이해하고 수정·빌드·배포할 때 반드시 준수해야 할 아키텍처 규칙과 플랫폼별 주의사항을 정의합니다.

---

## 1. 프로젝트 개요

* **프로젝트명**: SnapCraft (`snap_craft`, Bundle ID: `com.example.snapCraft`)
* **목적**: macOS 및 Windows를 지원하는 크로스플랫폼 화면 캡쳐 및 마크업(주석) 편집 데스크톱 앱
* **프레임워크**: Flutter Desktop (Dart 3.x / Flutter 3.47+)
* **핵심 패키지**:
  * `screen_capturer`: OS 네이티브 영역/전체화면/창 캡쳐
  * `window_manager`: 캡쳐 전 앱 창 자동 숨김(`hide`) 및 완료 후 복원(`show`/`focus`)
  * `hotkey_manager`: 시스템 글로벌 단축키 등록 및 변경(`HotKeyRecorder`)
  * `pasteboard` + 네이티브 채널(`snap_craft/clipboard`): 클립보드 이미지 및 파일 경로 복사
  * `file_picker`: PNG 파일 다른 이름으로 저장
  * `shared_preferences`: 사용자 정의 단축키 설정 영구 저장

---

## 2. 디렉터리 및 코드 아키텍처

* `lib/main.dart`: 앱 초기화(`windowManager`), 단축키 바인딩(`CallbackShortcuts`), 메인 화면(`SnapCraftHomeScreen`) 상태 관리
* `lib/models/`
  * `annotation.dart`: `AnnotationTool` 열거형(`pen`, `highlighter`, `rectangle`, `arrow`, `text`, `mosaic`) 및 `AnnotationItem` 모델. **모든 좌표(`points`)는 화면 위젯 크기가 아닌 원본 이미지 픽셀 좌표계(`0..width`, `0..height`)로 저장**됩니다.
  * `capture_item.dart`: 캡쳐된 원본 바이트, 디코딩된 `ui.Image`, 마크업 리스트(`annotations`) 및 `redoStack` 관리
* `lib/services/`
  * `capture_service.dart`: 창 숨김/복원, 임시 파일 생성, `screenCapturer.capture()` 호출 및 캡쳐 직후 자동 클립보드 복사
  * `export_service.dart`: `paintCaptureScene()`(실시간 캔버스와 PNG 내보내기 공용 렌더링 로직), `renderAnnotatedPng()`, 멀티 포맷 클립보드 복사, PNG 파일 저장
  * `hotkey_service.dart`: 3가지 캡쳐 모드의 글로벌 단축키 등록/수정/초기화
  * `update_service.dart`: GitHub Releases(`sungback/SnapCraft`) 최신 버전 조회, 원클릭 패키지 다운로드 및 macOS(`.app` 교체)/Windows(`xcopy` 교체) 자동 설치·재시작
* `lib/widgets/`
  * `top_toolbar.dart`: 상단 2단 툴바 (캡쳐 모드 버튼, 단축키 설정, 업데이트 알림 배지/버튼, 마크업 도구, 색상/굵기, Undo/Redo, 복사/저장)
  * `annotation_canvas.dart`: 원본 비율 유지 뷰포트 계산 및 마우스 드래그/탭 이벤트를 원본 픽셀 좌표로 변환하여 드로잉
  * `history_sidebar.dart`: 좌측 최근 캡쳐 썸네일 목록 및 전환/삭제 UI
  * `shortcut_settings_dialog.dart`: 글로벌 단축키 변경 다이얼로그
  * `update_dialog.dart`: 최신 버전 확인, 릴리즈 노트 표시, 원클릭 다운로드 및 자동 재시작 모달 다이얼로그

---

## 3. 중요 플랫폼별 규칙 (절대 깨뜨리지 말 것)

1. **macOS 창 숨김 시 앱 종료 방지 (`macos/Runner/AppDelegate.swift`)**
   * `applicationShouldTerminateAfterLastWindowClosed`는 반드시 `false`를 반환해야 합니다. `true`로 변경하면 캡쳐 시 `windowManager.hide()`가 호출될 때 macOS가 앱을 강제 종료시킵니다.
   * 사용자가 창 닫기(`X`) 버튼을 눌렀을 때의 종료 처리는 `lib/main.dart`의 `WindowListener.onWindowClose()`에서 담당합니다.

2. **macOS 멀티 포맷 클립보드 채널 (`macos/Runner/MainFlutterWindow.swift`)**
   * `FlutterMethodChannel(name: "snap_craft/clipboard")`의 `copyImageAndFile` 메서드는 `NSPasteboardItem`에 `.png`, `.tiff`, `.fileURL`, `.string` 4가지 포맷을 동시에 기록합니다.
   * 이를 통해 GUI 앱/Claude Code에서는 **이미지**가 붙여넣어지고, Ghostty/`agy` 같은 터미널 에이전트에서는 **파일 경로**가 붙여넣어집니다.

3. **macOS 코드 서명 및 화면 기록 권한 (`TCC`) 유지**
   * Ad-hoc 서명(`-`)으로 빌드하면 바이너리 해시(`cdhash`)가 매번 바뀌어 macOS '화면 및 시스템 오디오 녹음' 권한 팝업이 반복해서 발생합니다.
   * macOS 빌드 후에는 반드시 아래 명령으로 키체인에 등록된 정식 개발자 인증서(`Developer ID Application` 또는 `Apple Development`) 서명을 적용하세요:
     ```bash
     # 키체인에 등록된 서명 인증서 확인
     security find-identity -v -p codesigning

     # Debug 빌드 서명
     codesign --force --deep --entitlements macos/Runner/DebugProfile.entitlements \
       --sign "Developer ID Application: <YOUR_NAME> (<TEAM_ID>)" \
       build/macos/Build/Products/Debug/snap_craft.app

     # Release 빌드 서명
     codesign --force --deep --options runtime --entitlements macos/Runner/Release.entitlements \
       --sign "Developer ID Application: <YOUR_NAME> (<TEAM_ID>)" \
       build/macos/Build/Products/Release/snap_craft.app
     ```

4. **macOS 샌드박스 및 FilePicker Entitlements (`DebugProfile.entitlements`, `Release.entitlements`)**
   * `/usr/sbin/screencapture` 실행을 위해 `com.apple.security.app-sandbox`는 `<false/>`여야 합니다.
   * `file_picker`의 저장 다이얼로그(`NSSavePanel`) 동작을 위해 `com.apple.security.files.user-selected.read-write` `<true/>`와 `FilePicker.skipEntitlementsChecks()` 호출을 유지해야 합니다.

---

## 4. 개발 및 배포 워크플로우

* **정적 분석 및 테스트**: 코드 변경 후 항상 `flutter analyze`와 `flutter test`가 경고/오류 없이 통과하는지 확인합니다.
* **배포 파일 생성 (`dist/`)**:
  * 설치 파일은 `/dist/SnapCraft-macOS.dmg` 및 `/dist/SnapCraft-macOS.zip`으로 생성하며, `/dist/` 폴더는 `.gitignore`에 의해 Git 커밋에서 제외됩니다.
* **작업 이력 관리 (`TASKS.md`)**:
  * 새로운 기능을 구현하거나 버그를 수정할 때는 반드시 루트의 `TASKS.md`에 진행 상태와 완료 내역을 함께 업데이트합니다.
