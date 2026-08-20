# Cody Usage Overlay 프로젝트 인수인계

최종 정리일: 2026-08-19 (Asia/Seoul)  
저장소: `https://github.com/prestige-kim/cody-usage-overlay.git`  
로컬 경로: `/Users/proudchris/Desktop/Project/cody-usage-overlay`  
기준 브랜치/커밋: `main` / `27519d1` (`Update ChatGPT desktop installation discovery (#7)`)

## 1. 문서 목적

이 문서는 이전 Codex 대화에서 진행한 Cody Usage Overlay 개발 내용을 새 프로젝트의 에이전트가 대화 기록 없이도 이어받을 수 있도록 정리한 것이다. 작업을 시작할 때 먼저 이 문서와 `README.md`, `CHANGELOG.md`, 최근 Git 기록을 읽는다.

이 프로젝트는 Cody 펫 자체가 아니다. 기존 Cody 펫 파일은 유지하고, 펫 주변에 Codex 사용 가능량을 표시하는 별도의 보조 앱이다.

## 2. 사용자가 확정한 제품 요구사항

- 계정의 주간 사용 가능량을 `Week`으로 표시한다.
- 5시간 한도가 Codex에서 제공될 때만 `5h`를 표시하고, 값이 없으면 자동으로 숨긴다.
- 현재 작업의 컨텍스트 창 잔여율을 `Context`로 표시한다.
- 상단 큰 글씨는 `5h`/`Week`, 하단 작은 글씨는 `Context`이다.
- 오른쪽에는 Codex 이미지와 `🧑🏻‍💻` 이미지를 표시한다.
- 왼쪽 위 `×`는 앱을 종료하지 않고 Usage 창만 숨긴다.
- 숨긴 Usage 창은 Codex에서 펫을 숨겼다가 다시 보이게 하면 복원한다.
- Cody가 보이는 동안 Usage 창은 작업 알림창과 반대편에 배치한다.
  - 작업 알림창이 펫 위에 있으면 Usage 창은 펫 아래에 둔다.
  - 작업 알림창이 펫 아래에 있으면 Usage 창은 펫 위에 둔다.
- Cody가 없거나 펫 창을 찾을 수 없으면 Usage 창을 독립 드래그 창으로 사용하고 마지막 위치를 보존한다.
- Cody 이동, 크기 변경, 화면/Space 전환을 따라가되 눈에 띄는 지연이나 흔들림이 없어야 한다.
- Cody 기본 버튼과 작업 알림창을 Usage 창이 가리지 않아야 한다.
- 기존 macOS 기능을 유지하면서 Windows 11 x64 버전도 제공한다.
- API 키나 별도 로그인을 요구하지 않고 ChatGPT 데스크톱 앱의 기존 Codex 인증을 사용한다.
- 사용량 숫자, 인증 토큰, 대화 본문을 저장하거나 외부 서버로 보내지 않는다.

사용자가 승인한 현재 시각 디자인과 위치 규칙을 임의로 다시 설계하지 않는다. UI/위치 변경은 명시적인 요청이 있을 때만 최소 범위로 수행한다.

## 3. 데이터 파이프라인

### 계정 사용량

로컬 Codex 실행 파일을 `app-server --stdio`로 실행하고 JSONL-RPC로 연결한다.

1. `initialize` 요청에 `experimentalApi: true` 전달
2. `initialized` 알림 전송
3. `account/rateLimits/read`로 최초 상태 취득
4. `account/rateLimits/updated` 알림을 기존 상태에 sparse merge
5. 장애 시 재연결하고 60초마다 전체 상태 재조회

`primary`와 `secondary`의 순서는 신뢰하지 않는다. `windowDurationMins`가 약 300이면 5시간, 약 10,080이면 주간 한도로 분류한다. 화면에는 `100 - usedPercent`를 반올림해 잔여율로 표시한다. 여러 bucket이 동시에 존재할 때는 canonical `codex` bucket을 우선한다. 같은 reset window에서 오래된 0% 사용 스냅샷이 더 최신 값을 덮어쓰지 않도록 방어 로직이 들어 있다.

### Context

사용자 홈의 `.codex/sessions` 아래 rollout JSONL을 감시한다. 루트 ChatGPT 데스크톱 Codex 세션을 선택하고 CLI 및 서브에이전트 rollout은 제외한다. 최신 `event_msg.payload.type == "token_count"` 이벤트에서 `last_token_usage.total_tokens`와 `model_context_window`를 읽는다.

계산식:

```text
Context remaining = max(0, 1 - last_total_tokens / model_context_window)
```

- `Context 100%`: 현재 작업의 컨텍스트가 거의 비어 있음
- `Context 0%`: 컨텍스트 한도에 근접했거나 도달함
- Context는 Week/5h 계정 한도와 별개의 지표다.
- 90초 이상 정상 상태를 확인하지 못하면 마지막 값에 지연/호환성 상태를 명시한다.

app-server 및 rollout 형식은 변경될 수 있다. 파싱 실패 시 앱을 죽이거나 오래된 숫자를 새 값처럼 표시하지 말고 `호환성 확인 필요` 또는 `지연됨` 상태를 유지한다.

## 4. macOS 구현 상태

- 언어/UI: Swift 6, AppKit
- 지원: macOS 14+, Apple Silicon arm64
- 핵심 코드:
  - `Sources/CodyUsageCore/AppServerClient.swift`
  - `Sources/CodyUsageCore/RateLimitParser.swift`
  - `Sources/CodyUsageCore/RolloutReader.swift`
  - `Sources/CodyUsageCore/SessionEventMonitor.swift`
  - `Sources/CodyUsageCore/UsageCoordinator.swift`
  - `Sources/CodyUsageCore/OverlayGeometry.swift`
  - `Sources/CodyUsageOverlay/main.swift`
- 테스트/체크: `Sources/CodyUsageCoreChecks/main.swift`, `scripts/check.sh`
- 설치 위치: `~/Applications/CodyUsageOverlay.app`
- 설정: `~/Library/Application Support/CodyUsageOverlay/config.json`
- 로그: `~/Library/Logs/CodyUsageOverlay/`
- 자동 실행: `~/Library/LaunchAgents/com.proudchris.cody-usage-overlay.plist`

앱은 투명 `NSPanel`을 사용한다. 펫 감지 시 앵커 모드, 미감지 시 드래그 모드로 전환한다. 사용자가 여러 번 설치해도 같은 앱/LaunchAgent 위치를 덮어쓰므로 설치본이 계속 중복해서 쌓이는 구조가 아니다. 중복 창 문제를 막는 단일 실행 처리도 유지해야 한다.

Codex 실행 파일 탐색은 통합 ChatGPT 앱의 번들 실행 파일을 우선하고 공식 Codex CLI 경로를 fallback으로 사용한다. 현재 코드는 `/Applications/ChatGPT.app/Contents/Resources/codex`, 사용자 Applications의 ChatGPT 앱, 관련 bundle identifier 검색, `~/.local/bin`, `~/.codex/bin`, Homebrew 및 PATH를 확인한다. 예전 독립 Codex Desktop 경로는 최근 정책 변경에 맞춰 제거했다.

별도로 제작한 Cody 펫 원본은 이 저장소에 포함되지 않는다. 로컬 펫은 일반적으로 `/Users/proudchris/.codex/pets/cody`에 있으며, 이 오버레이 작업에서 펫 스프라이트를 다시 수정하지 않는다.

## 5. Windows 구현 상태

- 언어/UI: C#, .NET 8, WPF + Win32/DWM API
- 지원 목표: Windows 11 x64
- 솔루션: `windows/CodyUsageOverlay.Windows.sln`
- Core: `windows/src/CodyUsageOverlay.Core/`
- UI: `windows/src/CodyUsageOverlay.App/`
- 체크 프로젝트: `windows/tests/CodyUsageOverlay.Checks/`
- 관리 스크립트: `windows/scripts/`
- 설치 위치: `%LOCALAPPDATA%\CodyUsageOverlay\CodyUsageOverlay.exe`
- 설정: `%LOCALAPPDATA%\CodyUsageOverlayData\config.json`
- 자동 시작: `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`

배포본은 .NET 런타임을 별도 설치하지 않는 self-contained x64 ZIP으로 설계했다. README의 PowerShell 한 줄 설치 명령은 최신 Windows prerelease를 내려받고 SHA-256을 검증한 뒤 같은 위치에 덮어쓰고 즉시 실행한다.

```powershell
irm https://raw.githubusercontent.com/prestige-kim/cody-usage-overlay/main/windows/scripts/install.ps1 | iex
```

Windows Codex/ChatGPT가 Microsoft Store MSIX로 설치되는 상황을 반영했다. 초기 친구 PC 진단에서는 기존 후보 경로에 `codex.exe`가 없어 app-server가 실패했다. 확인된 ChatGPT 프로세스는 대략 다음 구조였다.

```text
C:\Program Files\WindowsApps\OpenAI.Codex_<version>_x64__<publisher-id>\app\ChatGPT.exe
```

그 후 다음 탐색을 구현했다.

- 실행 중 `ChatGPT.exe`/`codex.exe` 프로세스 경로
- App Paths registry
- `Get-AppxPackage`의 `OpenAI.Codex` 및 `OpenAI.ChatGPT` 설치 위치
- package root와 `app` 하위의 알려진 resource/bin 구조 및 제한된 recursive 검색
- `~/.local/bin`, `~/.codex/bin`, PATH의 공식 CLI fallback

관련 코드:

- `windows/src/CodyUsageOverlay.Core/CodexExecutableLocator.cs`
- `windows/scripts/doctor.ps1`

Windows 펫 연동은 `EnumWindows`, PID, window class/title, DWM bounds와 WinEventHook을 사용한다. 실제 Windows 11에서 Cody HWND와 작업 알림 HWND를 안정적으로 구분하는 부분은 아직 실험적이다. 감지 실패 시 앱은 종료하지 않고 독립 드래그 모드로 동작해야 한다.

## 6. 설치·진단·배포 파일

macOS:

- `scripts/build.sh`
- `scripts/install.sh`
- `scripts/uninstall.sh`
- `scripts/doctor.sh` / `scripts/doctor.py`
- Release용 `Install.command`, `Uninstall.command`, `Doctor.command`

Windows:

- `windows/scripts/install.ps1`
- `windows/scripts/uninstall.ps1`
- `windows/scripts/doctor.ps1`
- `windows/scripts/package.ps1`

GitHub Actions:

- `.github/workflows/ci.yml`
- `.github/workflows/release.yml`

배포 시 macOS ZIP, Windows x64 ZIP, 각 SHA-256 파일을 함께 게시한다. 현재 macOS는 Developer ID 서명/공증이 없고 Windows도 코드 서명이 없어 Gatekeeper/SmartScreen 경고가 날 수 있다.

## 7. Git 및 릴리스 현재 상태

문서 작성 직전 확인 결과:

```text
branch: main
HEAD: 27519d1 Update ChatGPT desktop installation discovery (#7)
remote: origin https://github.com/prestige-kim/cody-usage-overlay.git
status: main...origin/main (추적 중, 기존 변경 없음)
```

중요한 이력:

- `96b657f`: 오버레이 가시성 복구 및 × 숨김 제어
- `5cb0765` / `v0.1.4`: 펫 작업 알림 반대편 배치
- `6b46825` / `v0.2.0`: Windows 11 버전 추가
- `91b8b69`: macOS/Windows README 전면 정리
- `f1eb8e9` / `v0.2.1`: Store 설치 ChatGPT Codex 탐색
- `27519d1`: 통합 ChatGPT 데스크톱 설치 탐색 문서/코드 정리

주의: 태그 `v0.2.1`은 `f1eb8e9`에 있고 `main`의 `27519d1`은 그보다 최신이다. 따라서 GitHub Release 자산이 `27519d1`의 변경까지 포함하는지는 별도로 확인해야 한다. `CHANGELOG.md`도 `0.2.1 - Unreleased`라고 표기되어 있어 실제 태그/릴리스 상태와 문서 정합성을 다음 릴리스 전에 정리해야 한다.

사용자가 `push`라고 말하면 단순히 브랜치만 올리고 끝내지 말고, 요청 범위가 PR 방식이라면 PR 생성 → CI 확인 → 병합 → 최종 `main`이 원격에 반영되었는지까지 확인해 보고한다. 다만 새 릴리스 발행이나 태그 생성은 사용자가 배포를 요청한 경우에만 수행한다.

## 8. 다음 우선 과업

### P0 — Windows Store 설치판 실기기 재검증

친구의 Windows 11 PC에서 최신 `main` 또는 이를 포함한 새 Release로 다시 설치하고 `doctor.ps1`을 실행한다. 다음을 반드시 확인한다.

- `codex` 경로가 실제 번들 `codex.exe`를 가리키는가
- `codexVersion`이 출력되는가
- `appServer: true`인가
- rate-limit 필드에서 Week 및 조건부 5h를 읽는가
- rollout을 읽고 Context를 계산하는가
- Cody HWND 및 작업 알림 HWND를 구분하는가
- 펫 이동/숨김/재표시와 × 복원이 동작하는가

초기 실패 당시 doctor 결과는 `codex`가 비어 있고 `appServer: false`였으므로, 경로 탐색 성공만으로 완료 처리하지 말고 app-server handshake까지 검증한다. 진단 결과 공유 시 사용자명과 민감한 경로는 가린다.

### P0 — 최신 main을 포함하는 배포 자산 확인

현재 최신 태그보다 `main`이 앞서 있다. GitHub Release의 Windows ZIP과 macOS ZIP이 어느 커밋으로 생성되었는지 확인한다. `27519d1`이 포함되지 않았다면 테스트 결과에 따라 다음 patch release를 만든다. 릴리스 전 CI, checksum, README 설치 명령의 실제 다운로드 대상을 함께 검증한다.

### P1 — macOS 회귀 테스트

통합 ChatGPT 데스크톱 앱 환경에서 다음을 확인한다.

- app-server 탐색/handshake
- `/status`와 Week/5h/Context 수치 수동 비교(목표 오차 1% 이내)
- 5h 미제공 시 자동 숨김
- Cody 이동 및 크기 변경 추적
- 작업 알림의 위/아래 전환 시 반대편 배치
- Cody 기본 버튼 비가림
- × 숨김 후 펫 hide/show로 복원
- 펫 미표시 시 자유 드래그와 위치 보존
- Space/다중 모니터 전환 시 잔상, 뿌연 배경, 느린 추적 재발 여부

### P1 — 릴리스/문서 정합성

- `CHANGELOG.md`의 v0.2.1 상태와 실제 태그/Release를 일치시킨다.
- README가 현재 공식 ChatGPT 설치 방식과 실제 탐색 코드를 정확히 설명하는지 확인한다.
- Windows 설치 한 줄 명령이 prerelease 선택과 checksum 검증을 정확히 수행하는지 깨끗한 사용자 프로필로 테스트한다.

### P2 — 배포 품질

- macOS Developer ID 서명 및 공증
- Windows 코드 서명으로 SmartScreen 경고 완화
- Windows 10/ARM64 및 Intel Mac 지원 여부는 별도 결정
- app-server/rollout 스키마 변경 fixture 추가

## 9. 검증 명령

macOS 소스 검증:

```bash
cd /Users/proudchris/Desktop/Project/cody-usage-overlay
./scripts/check.sh
```

이 저장소는 이전 폴더에서 `.build`까지 함께 이동되어, Swift module cache에 이전 절대 경로가 남아 있을 수 있다. `SwiftShims`의 module cache path mismatch가 나오면 소스 오류가 아니다. 새 위치에서 처음 빌드하기 전에 무시되는 파생 폴더 `.build`를 정리하고 다시 생성한다. 사용자 소스나 설정을 삭제하지 말고 `.build`만 대상으로 삼는다.

macOS 빌드/로컬 설치:

```bash
./scripts/build.sh
./scripts/install.sh
```

macOS 진단:

```bash
./scripts/doctor.sh
```

Windows 개발 PC:

```powershell
dotnet build windows/CodyUsageOverlay.Windows.sln -c Release
dotnet run --project windows/tests/CodyUsageOverlay.Checks/CodyUsageOverlay.Checks.csproj -c Release
./windows/scripts/doctor.ps1
./windows/scripts/package.ps1
```

Git 확인:

```bash
git status --short --branch
git log --oneline --decorate -15
git remote -v
```

## 10. 작업 원칙과 주의사항

- 기존 기능을 임의로 넓게 수정하지 않는다. 사용자는 반복적으로 “요청한 부분만” 수정해 달라고 했다.
- 위치 문제는 감으로 픽셀 상수를 계속 바꾸지 말고 펫 bounds, 작업 알림 bounds, 버튼/콘텐츠 inset, 화면 좌표계를 근거로 계산하고 실제 스크린샷으로 시각 검증한다.
- macOS와 Windows의 화면 좌표계, DPI, 다중 모니터 변환을 분리한다.
- Cody 펫 창의 흐릿한 배경/히트박스를 이미지의 실제 발 위치로 오인하지 않는다.
- 설치 스크립트는 기존 설정을 보존하고 같은 설치 위치를 덮어써야 한다.
- 제거는 기본적으로 앱과 자동 시작만 삭제하고 purge 옵션에서만 설정/로그까지 제거한다.
- app-server 프로토콜 변화가 의심되면 먼저 doctor 결과와 raw 필드 이름을 확인하고 인증정보나 대화 본문을 수집하지 않는다.
- 새 코드를 배포하기 전에 로컬/CI 테스트 결과와 실제 설치본 반영 여부를 구분해서 보고한다.
- 소스 수정, 로컬 설치, 원격 push, PR 병합, Release 발행은 서로 다른 단계다. 어느 단계까지 완료했는지 명확하게 말한다.

## 11. 새 에이전트의 첫 실행 순서

1. `git status --short --branch`로 사용자의 미커밋 변경이 있는지 확인한다.
2. 이 문서, `README.md`, `CHANGELOG.md`를 읽는다.
3. `git log --oneline --decorate -15`로 원격 반영 상태를 확인한다.
4. 사용자 요청이 버그 진단이면 먼저 재현/원인만 확인하고, 수정 요청이 있을 때만 코드를 바꾼다.
5. macOS 변경이면 `./scripts/check.sh`, Windows 변경이면 Core checks를 실행한다.
6. 로컬 설치 요청, 원격 반영 요청, Release 배포 요청을 서로 구분한다.

현재 가장 중요한 미완료 사항은 **최신 Store/MSIX 실행 파일 탐색 변경을 포함한 Windows 실기기 end-to-end 재검증과 그 변경이 포함된 Release 자산 확인**이다.
