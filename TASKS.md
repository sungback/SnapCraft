# SnapCraft 작업 현황 (TASKS.md)

진행 중/예정 작업만 관리합니다. 완료한 항목은 삭제하고, 릴리즈 시 `CHANGELOG.md`에 기록합니다.

## Todo & Backlog

## 최근 완료

- **v1.0.6 릴리스 (`c2ce318`)**: 캡쳐 실패 복구, 업데이트 백업·실패 시 복원, macOS 서명 검증 강화, 캡쳐 메모리·임시 파일 정리를 적용하고 macOS DMG/ZIP 및 Windows ZIP을 공개했습니다.
- **검증**: 로컬 `flutter analyze` 및 `flutter test` 통과, Windows CI 테스트·Release ZIP 빌드 통과. macOS 앱은 로컬 Apple Development 인증서로 서명했습니다.
- **후속 확인**: macOS CI 서명 Secrets가 없어 CI 자동 배포는 실패했습니다. GitHub Secrets 설정과 실제 설치 환경에서 업데이트·화면 기록 권한 검증을 Todo에 남겼습니다.

- [ ] **배포 경로 검증**
  - [ ] Secrets 없는 Ad-hoc 서명 Release CI 실행 확인 (main push)
  - [ ] 실제 macOS/Windows 설치본에서 업데이트 성공·실패 복원 및 화면 기록 권한 유지 확인

- [ ] **Windows 환경 빌드 및 패키징 검증**
  - [ ] Windows에서 `flutter build windows --release` 테스트 및 설치 파일(`.exe` / `.msix`) 생성
  - [ ] Windows 멀티 포맷 클립보드 동작 점검
- [ ] **편집 및 편의 기능 고도화 (필요 시)**
  - [ ] 캡쳐 이미지 자르기(Crop) 도구 추가
  - [ ] 번호 매기기(Step Counter: ①, ②, ③) 스탬프 마크업 도구 추가
  - [ ] 자동 저장 폴더 지정 옵션 (캡쳐 시 지정된 폴더에 자동 파일 저장)
  - [ ] 시스템 트레이(macOS 상단 메뉴바 / Windows 트레이 아이콘) 상주 모드 옵션 추가
