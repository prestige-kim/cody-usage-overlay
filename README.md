# Cody Usage Overlay

[![CI](https://github.com/prestige-kim/cody-usage-overlay/actions/workflows/ci.yml/badge.svg)](https://github.com/prestige-kim/cody-usage-overlay/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/prestige-kim/cody-usage-overlay?include_prereleases)](https://github.com/prestige-kim/cody-usage-overlay/releases)

Codex Desktop의 사용량을 Cody 펫 아래에 보여주는 macOS용 오버레이입니다.
Cody가 화면에 있으면 발밑을 따라다니고, 펫을 숨기면 상태창을 마우스로 자유롭게 옮길 수 있습니다.

> [!WARNING]
> OpenAI가 공식 배포하거나 보증하는 앱이 아닙니다. 실험적인 로컬 Codex 인터페이스를 사용하므로 Codex 업데이트 후 일부 기능이 달라질 수 있습니다.

## 표시 항목

- **Week**: 주간 사용 한도의 남은 비율
- **5h**: Codex가 5시간 한도를 제공할 때만 표시되는 남은 비율
- **Context**: 가장 최근에 활동한 Codex Desktop 작업의 컨텍스트 창 추정 잔여율

`Context 100%`는 현재 컨텍스트가 거의 비어 있다는 뜻이고, `0%`에 가까워질수록 대화가 컨텍스트 한도에 가까워졌다는 뜻입니다. 계정 사용 한도와는 별개의 값입니다.

## 요구 사항

- macOS 13 이상
- Apple Silicon Mac (`arm64`)
- 설치 및 로그인된 Codex Desktop

## 설치

### GitHub Release에서 설치

1. [Releases](https://github.com/prestige-kim/cody-usage-overlay/releases)에서 최신 `CodyUsageOverlay-*.zip`을 받습니다.
2. 압축을 풀고 폴더 안의 `Install.command`를 실행합니다.
3. macOS가 실행을 차단하면 Finder에서 `Install.command`를 Control-클릭한 뒤 **열기**를 선택합니다.

설치 명령은 앱을 `~/Applications/CodyUsageOverlay.app`에 복사하고 로그인 시 자동 실행되는 LaunchAgent를 등록합니다. 삭제할 때는 같은 폴더의 `Uninstall.command`를 실행하세요. 설정과 로그는 기본적으로 보존됩니다.

현재 배포 파일은 Developer ID 서명과 Apple 공증을 거치지 않은 시험판입니다. 다운로드한 파일은 함께 제공되는 `.sha256` 체크섬으로 확인할 수 있습니다.

### 소스에서 설치

Swift 6와 Xcode Command Line Tools가 필요합니다.

```bash
git clone https://github.com/prestige-kim/cody-usage-overlay.git
cd cody-usage-overlay
./scripts/check.sh
./scripts/install.sh
```

이 방식은 앱을 `~/Applications/CodyUsageOverlay.app`에 설치하고 로그인 시 자동 실행되는 LaunchAgent도 등록합니다. 기존 설정은 유지됩니다.

## 삭제

소스 저장소에서 다음 명령을 실행합니다.

```bash
./scripts/uninstall.sh
./scripts/uninstall.sh --purge  # 앱과 함께 설정·로그도 삭제
```

`--purge`를 사용하지 않으면 설정과 로그는 보존됩니다.

## 사용법

- Codex Pet이 보이면 상태창이 Pet의 발 바로 아래에 고정됩니다.
- Pet이 없으면 상태창을 드래그해 원하는 곳으로 이동할 수 있습니다.
- 상태창 왼쪽 위의 **×**를 누르면 상태창만 숨길 수 있습니다. 다시 표시하려면 Codex에서 **펫 숨기기** 후 **펫 보이기**를 누르세요. 펫이 이미 숨겨진 상태에서 ×를 눌렀다면 **펫 보이기**만 누르면 됩니다.
- 상태창을 우클릭하면 새로고침, 위치 재탐색, 항상 위, 진단 정보 복사, 종료 메뉴를 사용할 수 있습니다.
- 설정은 `~/Library/Application Support/CodyUsageOverlay/config.json`에 저장됩니다.

## 데이터 처리 방식

앱은 로컬 `codex app-server --stdio`를 실행해 `account/rateLimits/read`와 갱신 알림을 읽습니다. Context 값은 `~/.codex/sessions`의 Codex Desktop rollout에 기록된 토큰 이벤트에서 계산합니다.

- OpenAI API 키가 필요하지 않습니다.
- 로그인 토큰이나 대화 본문을 읽거나 저장하지 않습니다.
- 사용량 숫자는 디스크에 저장하지 않습니다.
- 외부 분석·추적 서버로 데이터를 보내지 않습니다.

사용량 파이프라인은 [GiantForestStudio/codex-weekly-usage-indicator](https://github.com/GiantForestStudio/codex-weekly-usage-indicator)의 구조를 참고했습니다. 자세한 내용은 [PRIVACY.md](PRIVACY.md)와 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 확인하세요.

## 개발 및 진단

```bash
./scripts/check.sh   # 코어 로직 검사
./scripts/build.sh   # dist/CodyUsageOverlay.app 생성
./scripts/doctor.sh  # 로컬 Codex 연결과 세션 접근 진단
```

`main` 브랜치와 Pull Request는 GitHub Actions에서 Apple Silicon macOS 빌드, 코어 검사, 앱 번들 및 ad-hoc 서명을 자동 검증합니다.

## 알려진 제한 사항

- Codex app-server와 rollout JSONL 형식은 안정성이 보장된 공개 API가 아닙니다.
- 활성 Context는 가장 최근에 수정된 루트 Codex Desktop rollout을 기준으로 선택합니다.
- 현재 빌드 대상은 Apple Silicon Mac뿐입니다.
- Cody 창 탐지는 Codex Desktop의 창 동작이 바뀌면 영향을 받을 수 있습니다.
- 앱이 비정상 종료되면 LaunchAgent가 자동으로 다시 실행합니다. **×**는 앱을 종료하지 않고 상태창만 숨깁니다.
- Release 앱은 아직 Developer ID 서명 및 Apple 공증을 받지 않았습니다.

Codex 업데이트 후 문제가 생기면 `./scripts/doctor.sh`를 실행하고 민감한 경로를 가린 결과와 함께 이슈를 등록해 주세요.

## 프로젝트 문서

- [변경 기록](CHANGELOG.md)
- [기여 안내](CONTRIBUTING.md)
- [개인정보 처리](PRIVACY.md)
- [보안 정책](SECURITY.md)
- [서드파티 고지](THIRD_PARTY_NOTICES.md)

## 라이선스

[MIT License](LICENSE)
