# AGENTS.md — SnapCraft 프로젝트 에이전트 가이드

이 문서는 AI 코딩 에이전트(Claude Code, Codex, Antigravity 등)가 **SnapCraft** 프로젝트를 이해하고 수정·빌드·배포할 때 반드시 준수해야 할 아키텍처 규칙과 플랫폼별 주의사항을 정의합니다.

---

## 1. 프로젝트 개요

* **프로젝트명**: SnapCraft (`snap_craft`, Bundle ID: `com.example.snapCraft`)
* **목적**: macOS 및 Windows를 지원하는 크로스플랫폼 화면 캡쳐 및 마크업(주석) 편집 데스크톱 앱
* **프레임워크**: Flutter Desktop (Dart 3.x / Flutter 3.47+)
* **패키지/버전**: `pubspec.yaml` 참조. 클립보드 이미지·파일 경로 복사는 `pasteboard`와 네이티브 채널(`snap_craft/clipboard`)을 함께 사용합니다.

---

## 2. 디렉터리 및 코드 아키텍처

구조는 `lib/{models,services,widgets}`와 `lib/main.dart`를 직접 확인하세요. 코드만으로 드러나지 않는 불변 조건만 적습니다.

* **좌표계**: `AnnotationItem.points`는 화면 위젯 크기가 아닌 **원본 이미지 픽셀 좌표(`0..width`, `0..height`)**로 저장합니다. `annotation_canvas.dart`가 화면 좌표를 변환합니다.
* **렌더링 공용화**: `export_service.dart`의 `paintCaptureScene()`은 실시간 캔버스와 PNG 내보내기가 공유합니다. 렌더링을 바꾸면 양쪽에 모두 반영됩니다.
* **자동 업데이트**: `update_service.dart`가 GitHub Releases(`sungback/SnapCraft`)를 조회하고, macOS는 `.app` 교체 전 `_resignMacBundleForTcc`로 재서명(아래 3번 규칙), Windows는 `xcopy`로 교체합니다.
* **Windows 창 캡쳐**: `CaptureMode.window`는 `windows/runner/flutter_window.cpp`의 네이티브 Win32 창 선택기를 사용합니다.

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
     # 인증서 이름은 문서에 고정하지 않습니다(public 저장소).
     # 아래 명령 결과의 실제 이름을 <YOUR_NAME> (<TEAM_ID>) 자리에 사용하세요.
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
* **작업 이력 관리**:
  * `TASKS.md`: 진행 중/예정 작업(Backlog)만 관리합니다. 작업을 끝내면 해당 항목을 삭제합니다.
  * `CHANGELOG.md`: 릴리즈(`pubspec.yaml` 버전 상승)마다 버전별 변경 사항을 한두 줄로 추가합니다.
