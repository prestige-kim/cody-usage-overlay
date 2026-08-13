# Cody Usage Overlay

[![CI](https://github.com/prestige-kim/cody-usage-overlay/actions/workflows/ci.yml/badge.svg)](https://github.com/prestige-kim/cody-usage-overlay/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/prestige-kim/cody-usage-overlay?include_prereleases)](https://github.com/prestige-kim/cody-usage-overlay/releases)
[![Platforms](https://img.shields.io/badge/platforms-macOS%20%7C%20Windows-blue)](https://github.com/prestige-kim/cody-usage-overlay/releases)

Codex Desktop의 사용량을 Cody 펫 주변에 표시하는 macOS·Windows용 데스크톱 오버레이입니다.

- 계정의 **주간(Week) 사용 가능량** 표시
- Codex가 제공할 때만 **5시간(5h) 사용 가능량** 표시
- 현재 작업의 **Context 잔여율** 표시
- Cody 펫과 작업 알림창을 따라 자동으로 위치 조정
- 펫이 없을 때 자유롭게 드래그 가능한 독립 상태창
- OpenAI API 키와 별도 로그인 불필요

> [!WARNING]
> OpenAI가 공식 배포하거나 보증하는 앱이 아닙니다. 실험적인 로컬 Codex 인터페이스를 사용하므로 Codex 업데이트에 따라 일부 기능이 달라질 수 있습니다.

## 화면에 표시되는 값

| 항목 | 의미 |
| --- | --- |
| **Week** | 주간 사용 한도에서 현재 남아 있는 비율 |
| **5h** | 5시간 사용 한도가 제공될 때 남아 있는 비율. 값이 없으면 자동으로 숨김 |
| **Context** | 가장 최근에 활동한 Codex Desktop 작업의 컨텍스트 창 추정 잔여율 |

`Context 100%`는 현재 작업의 컨텍스트가 거의 비어 있다는 뜻입니다. `0%`에 가까워질수록 대화가 모델의 컨텍스트 한도에 가까워집니다. Context는 계정의 Week·5h 사용 한도와 별개의 값입니다.

## 지원 환경

| 운영체제 | 지원 대상 | 배포 형식 |
| --- | --- | --- |
| macOS | macOS 14 이상, Apple Silicon (`arm64`) | `.app`이 포함된 ZIP |
| Windows | Windows 11, x64 | .NET 8 self-contained 실행 파일이 포함된 ZIP |

두 플랫폼 모두 설치 및 로그인된 Codex Desktop이 필요합니다. Intel Mac, Windows 10, Windows ARM64는 현재 공개 빌드에서 지원하지 않습니다.

## 설치

### macOS

1. [Releases](https://github.com/prestige-kim/cody-usage-overlay/releases)에서 최신 `CodyUsageOverlay-*-arm64.zip`을 받습니다.
2. 압축을 풀고 `Install.command`를 실행합니다.
3. macOS가 실행을 차단하면 Finder에서 `Install.command`를 Control-클릭한 뒤 **열기**를 선택합니다.

설치 위치와 자동 실행 설정:

- 앱: `~/Applications/CodyUsageOverlay.app`
- 자동 실행: `~/Library/LaunchAgents/com.proudchris.cody-usage-overlay.plist`
- 설정: `~/Library/Application Support/CodyUsageOverlay/config.json`
- 로그: `~/Library/Logs/CodyUsageOverlay/`

### Windows 11

PowerShell에서 다음 명령을 실행하면 최신 Windows x64 prerelease를 내려받아 체크섬을 검증하고 설치한 뒤 즉시 실행합니다.

```powershell
irm https://raw.githubusercontent.com/prestige-kim/cody-usage-overlay/main/windows/scripts/install.ps1 | iex
```

또는 [Releases](https://github.com/prestige-kim/cody-usage-overlay/releases)에서 `CodyUsageOverlay-*-windows-x64.zip`을 직접 받아 압축을 풀고 `install.ps1`을 실행할 수 있습니다.

설치 위치와 자동 실행 설정:

- 앱: `%LOCALAPPDATA%\CodyUsageOverlay\CodyUsageOverlay.exe`
- 자동 실행: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- 설정: `%LOCALAPPDATA%\CodyUsageOverlayData\config.json`

관리자 권한은 필요하지 않습니다. SmartScreen 또는 PowerShell 실행 정책이 차단하면 파일 속성에서 **차단 해제**를 선택하거나 현재 PowerShell 창에만 다음 설정을 적용하세요.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

## 사용법

- Cody가 보이면 Usage 창은 작업 알림창의 반대편에 배치됩니다.
  - 작업 알림이 Cody 위에 있으면 Usage 창은 아래로 이동합니다.
  - 작업 알림이 Cody 아래에 있으면 Usage 창은 위로 이동합니다.
- Cody가 없거나 펫 창을 찾지 못하면 Usage 창을 마우스로 자유롭게 옮길 수 있습니다.
- 왼쪽 위 **×**를 누르면 Usage 창만 숨깁니다.
- 다시 표시하려면 Codex에서 **펫 숨기기** 후 **펫 보이기**를 누릅니다. 펫이 이미 숨겨져 있었다면 **펫 보이기**만 누르면 됩니다.
- Usage 창을 우클릭하면 새로고침, 위치 재탐색, 항상 위, 진단 정보 복사, 종료 기능을 사용할 수 있습니다. Windows에서는 로그인 자동 시작도 전환할 수 있습니다.

## 삭제

### macOS

Release 폴더의 `Uninstall.command`를 실행하거나 소스 저장소에서 다음 명령을 사용합니다.

```bash
./scripts/uninstall.sh
./scripts/uninstall.sh --purge  # 설정과 로그까지 삭제
```

### Windows

Release 폴더에서 다음 명령을 실행합니다.

```powershell
./uninstall.ps1
./uninstall.ps1 -Purge  # 설정 데이터까지 삭제
```

`Purge` 옵션을 사용하지 않으면 다시 설치할 때 사용할 수 있도록 설정과 로그를 보존합니다.

## 작동 방식과 개인정보

앱은 로컬 `codex app-server --stdio` 프로세스에 JSONL-RPC로 연결해 `account/rateLimits/read`와 사용량 갱신 알림을 읽습니다. Context 값은 사용자 홈의 `.codex/sessions`에 기록된 Codex Desktop 토큰 이벤트에서 계산합니다.

- OpenAI API 키가 필요하지 않습니다.
- 기존 Codex 로그인을 그대로 사용합니다.
- 로그인 토큰과 대화 본문을 읽거나 저장하지 않습니다.
- 사용량 숫자를 디스크에 저장하지 않습니다.
- 외부 분석·추적 서버로 데이터를 보내지 않습니다.

사용량 파이프라인은 [GiantForestStudio/codex-weekly-usage-indicator](https://github.com/GiantForestStudio/codex-weekly-usage-indicator)의 구조를 참고했습니다. 자세한 내용은 [PRIVACY.md](PRIVACY.md)와 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)를 확인하세요.

## 진단과 문제 해결

### macOS

- Release 폴더의 `Doctor.command` 또는 소스의 `./scripts/doctor.sh`를 실행합니다.
- Usage 값이 `—`로 남으면 Codex 실행 파일, app-server 응답, Desktop 세션 접근 여부를 확인합니다.
- Cody 위치가 잡히지 않으면 우클릭 메뉴의 **진단 정보 복사**에서 `Matched windows`와 `Pet` 항목을 확인합니다.
- macOS가 창 정보 접근을 제한하면 화면 기록 권한이 필요할 수 있습니다.

### Windows

- Release 폴더에서 `./doctor.ps1`을 실행합니다.
- 진단 결과에는 Windows·아키텍처, Codex 실행 파일과 버전, app-server 응답, rollout 경로, Codex 프로세스 및 HWND 정보가 포함됩니다.
- Cody를 찾지 못해도 앱은 종료되지 않고 독립 드래그 모드로 동작합니다.
- 문제를 제보할 때에는 사용자 이름 등 민감한 경로를 가린 진단 결과를 첨부해 주세요.

## 소스에서 빌드

### macOS

Swift 6와 Xcode Command Line Tools가 필요합니다.

```bash
git clone https://github.com/prestige-kim/cody-usage-overlay.git
cd cody-usage-overlay
./scripts/check.sh
./scripts/build.sh
./scripts/install.sh
```

### Windows

Windows 11과 .NET 8 SDK가 필요합니다.

```powershell
git clone https://github.com/prestige-kim/cody-usage-overlay.git
cd cody-usage-overlay
dotnet build windows/CodyUsageOverlay.Windows.sln -c Release
dotnet run --project windows/tests/CodyUsageOverlay.Checks/CodyUsageOverlay.Checks.csproj -c Release
./windows/scripts/package.ps1
```

## 개발과 배포

- macOS 앱은 Swift 6·AppKit으로 구현되어 있습니다.
- Windows 앱은 C#·.NET 8·WPF와 Win32 API로 구현되어 있습니다.
- Pull Request와 `main` 브랜치에서 macOS 및 Windows 빌드를 모두 검사합니다.
- 태그 릴리스는 두 플랫폼의 ZIP과 SHA-256 체크섬을 함께 게시합니다.
- Windows 빌드는 .NET 런타임 설치가 필요 없는 self-contained x64 패키지입니다.

## 알려진 제한 사항

- Codex app-server와 rollout JSONL은 안정성이 보장된 공개 API가 아닙니다.
- 활성 Context는 가장 최근에 갱신된 루트 Codex Desktop rollout을 기준으로 선택합니다.
- Codex 업데이트로 펫 창 구조가 바뀌면 Cody 위치 탐지가 영향을 받을 수 있습니다.
- Windows 펫 창 연동은 실제 Windows 11 환경 검증이 진행 중인 실험 기능입니다.
- macOS 앱은 Developer ID 서명과 Apple 공증을 받지 않았습니다.
- Windows 앱은 코드 서명되지 않아 SmartScreen 경고가 표시될 수 있습니다.

## 프로젝트 문서

- [변경 기록](CHANGELOG.md)
- [기여 안내](CONTRIBUTING.md)
- [개인정보 처리](PRIVACY.md)
- [보안 정책](SECURITY.md)
- [서드파티 고지](THIRD_PARTY_NOTICES.md)

## 라이선스

[MIT License](LICENSE)
