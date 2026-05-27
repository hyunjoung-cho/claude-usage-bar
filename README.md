# Claude Usage Bar

macOS 메뉴바에서 Claude.ai 사용량을 실시간으로 추적하는 위젯. 한도 임박 시 캐릭터가 펄쩍펄쩍 뛴다.

---

## 무엇을 하나

- **메뉴바 위젯** : 상단 우측에 `🌟 42% · 3h 12m` 형태로 사용량 표시
- **5단계 애니메이션** : 사용률에 따라 정적 → 꿈틀 → 펄쩍 → 격렬 단계별 캐릭터 애니메이션
- **실시간 동기화** : 설정된 주기(기본 60초)마다 **WKWebView로 claude.ai 페이지 직접 scrape** (진짜 데이터)
- **5시간 윈도우 / 7일 윈도우 / Opus 전용 윈도우** 각각 표시
- Cloudflare bot challenge 자동 통과 — 진짜 브라우저(WKWebView)를 사용하므로 차단 없음
- **자동 실행** : LaunchAgent 등록 후 로그인할 때마다 자동 기동
- **커스터마이징** : 캐릭터셋 변경, 애니메이션 단계별 컷오프 조정 가능

---

## 🦀 팀원 설치 — Claude Code 한 줄

Claude Code 헤비유저라면 터미널에서 Claude Code에게 이렇게 시키세요 :

> github.com/hyunjoung-cho/claude-usage-bar 클론해서 `make bundle install autostart`로 설치해줘. 끝나면 메뉴바에 뜰 거야.

Claude가 알아서 clone → 빌드 → ~/Applications 설치 → 자동시작 등록까지 합니다.

**왜 코드 서명/Gatekeeper 경고가 없나?** 본인 맥에서 직접 빌드한 .app은 quarantine 속성이 안 붙어서 "확인되지 않은 개발자" 차단을 안 만납니다. Apple Developer 계정 불필요.

### 설치 후 첫 실행
1. 메뉴바 우상단에 `🔑 로그인` 표시 + claude.ai 로그인 창 자동 등장
2. 본인 claude.ai 계정으로 로그인 (Google/이메일) — 쿠키는 본인 맥에만 영구 저장
3. 60초 내 사용량 % 표시 시작
4. 메뉴바 우클릭 → 🎭 캐릭터셋 → **claude** 선택하면 클로드가 메뉴바에서 꿈틀거림

### 요구사항
- macOS 14 (Sonoma) 이상
- Xcode Command Line Tools (`xcode-select --install` — Claude Code가 없으면 안내)
- claude.ai 언어 설정이 **한국어**여야 사용량 셀렉터가 정확 (영어는 fallback, 검증 미완)

---

## 빠른 설치

```bash
git clone https://github.com/hyunjoung-cho/claude-usage-bar.git
cd claude-usage-bar
make bundle install autostart
```

한 줄로 완료 : 빌드 → .app 번들 생성 → ~/Applications 복사 → LaunchAgent 등록

---

## 첫 실행

1. `make bundle install autostart` 한 줄로 메뉴바에 등장
2. **🔑 로그인 윈도우 자동 등장** → Google 또는 이메일로 claude.ai 로그인
3. 로그인 완료 후 윈도우 닫으면 다음 polling에서 자동으로 사용량 표시 시작
4. 이후 세션은 영구 저장 — 재시작해도 다시 로그인 불필요

---

## 우클릭 메뉴

```
📊 사용량
  5h 세션 : 67% (2h 14m 남음)
  주간    : 42% (3d 8h 남음)
  Opus    : 12%

🎭 캐릭터셋
  ● emoji-faces
  ○ emoji-stars
  ○ emoji-animals

🔄 지금 새로고침   (⌘R)
⚙️ 설정…           (⌘,)
🌐 claude.ai/settings/usage 열기

ℹ️ 정보
❌ 종료             (⌘Q)
```

---

## 5단계 애니메이션 (기본값)

| 단계 | 사용률 | 슬롯 | 애니메이션 |
|---|---|---|---|
| 여유 | 0–40% | chill | 정적 (변화 없음) |
| 보통 | 40–70% | normal | 정적 (변화 없음) |
| 임박 | 70–85% | busy | 2초마다 꿈틀 |
| 위험 | 85–95% | danger | 1초마다 펄쩍 |
| 불탐 | 95–100% | burn | 0.5초마다 격렬 |

> 컷오프 값은 우클릭 → **설정**에서 조정 가능

---

## 캐릭터셋 추가하기

### Emoji 세트 (가장 간단함)

1. 다음 경로에 새 폴더 생성 :
   ```
   ~/Library/Application Support/ClaudeUsageBar/sets/my-pets/
   ```

2. `set.json` 파일 작성 :
   ```json
   {
     "name": "my-pets",
     "type": "emoji",
     "frames": {
       "chill":  "🐶",
       "normal": "🐕",
       "busy":   "😼",
       "danger": "🙀",
       "burn":   "🔥"
     }
   }
   ```

3. 메뉴바 우클릭 → **🎭 캐릭터셋** → 새 세트 선택

### PNG 세트 (고급)

`type: "png"`으로 설정하고 같은 폴더에 이미지 5장 배치 :

```
sets/my-faces/
├── set.json        (type: "png" 설정)
├── chill.png       (16x16 또는 22x22 권장)
├── normal.png
├── busy.png
├── danger.png
└── burn.png
```

---

## 트러블슈팅

| 증상 | 원인 | 해결 방법 |
|---|---|---|
| 메뉴바 아이콘이 안 보임 | LaunchAgent 미등록 또는 .app 설치 실패 | `make install autostart` 다시 실행 |
| `🔑 로그인` 표시됨 | 첫 실행 또는 세션 만료 | 자동으로 뜨는 로그인 윈도우에서 Google/이메일로 로그인 |
| `❓ 페이지` 표시됨 | 페이지 구조가 selector와 다름 | 로그에서 page dump 500자 확인 : `tail -f ~/Library/Logs/ClaudeUsageBar.log` |
| `❓ DOM` 표시됨 | 페이지 로드됐으나 % 못 찾음 | 로그 page dump 확인 후 selector 조정 |
| `🔌 web` 표시됨 | 네트워크 오류 또는 JS 실행 실패 | 인터넷 연결 확인, 로그 확인 |
| `📂 데이터 없음` 표시됨 | (v2 fallback) `~/.claude/projects/` 부재 | WKWebView 모드에서는 발생 안 함 |
| `❓ 파싱` 표시됨 | (v2 fallback) JSONL 파싱 오류 | 로그 확인 : `tail -f ~/Library/Logs/ClaudeUsageBar.log` |
| 사용량이 업데이트 안 됨 | 폴링 주기 경과 전 또는 네트워크 문제 | 로그 확인 : `tail -f ~/Library/Logs/ClaudeUsageBar.log` |
| 캐릭터셋이 메뉴에 안 보임 | `set.json` 누락 또는 JSON 문법 오류 | `~/Library/Application Support/ClaudeUsageBar/sets/<폴더>/set.json` 점검 |
| 빌드 실패 (Swift version 오류) | Xcode Command Line Tools 구버전 | `xcode-select --install` 후 재시도 |
| LaunchAgent가 실행 안 됨 | .plist 경로 오류 또는 권한 부족 | `launchctl list \| grep claude-usage-bar` 확인, 필요 시 `make uninstall autostart` 재등록 |

### 로그 확인

```bash
tail -f ~/Library/Logs/ClaudeUsageBar.log
```

앱의 모든 stdout/stderr가 이 파일로 리다이렉트됨.

---

## 개발

### 빌드 명령어

```bash
make build      # Swift Package 컴파일
make test       # CoreTestRunner 단위 테스트 56개 실행
make bundle     # .app 번들 생성
make run        # 개발 모드로 즉시 실행 (.build/debug/...)
make clean      # 빌드 산출물 제거
```

### 테스트 시스템

XCTest 대신 **CoreTestRunner** 사용 (`Sources/CoreTestRunner/main.swift`) — Xcode 풀버전 없이 Command Line Tools만으로 검증 가능.

헬퍼 함수 :
- `suite("테스트 그룹명") { ... }` : 테스트 그룹 시작
- `check(expression, "설명")` : 단언(assertion)

```swift
suite("UsageData") {
  check(data.percentage == 42, "percentage should be 42")
}
```

---

## 디렉토리 구조

```
claude-usage-bar/
├── Package.swift                 Swift Package 매니페스트
├── Makefile                      빌드/설치/테스트 명령어
├── Info.plist                    .app 번들 메타데이터
├── Sources/
│   ├── ClaudeUsageBarCore/      순수 로직 라이브러리
│   │   └── *.swift              (공개 API, 테스트 대상)
│   ├── ClaudeUsageBarApp/        AppKit/SwiftUI UI 타겟
│   │   └── *.swift              (메뉴바 앱 구현)
│   └── CoreTestRunner/          커스텀 테스트 러너
│       └── main.swift           (XCTest 대체)
└── Scripts/
    ├── bundle.sh                 .app 번들 생성 스크립트
    ├── install.sh                ~/Applications 복사
    ├── autostart.sh              LaunchAgent 동적 생성 + 등록
    └── uninstall.sh              전체 제거
```

---

## 미해결 / 후순위 작업

- **[T18]** 5단계 애니메이션 시각 검증, IO 에러 사이클 처리
- **PNG 캐릭터셋** 5장 발주 (Nano Banana Pro 또는 fal.ai)
- **슬랙 알림** (90%, 95% 도달 시) — 후순위
- **selector 정확도** — 실제 claude.ai/settings/usage 페이지 구조에 따라 정규식 조정 필요할 수 있음. 로그 page dump 확인 후 `ClaudeWebScraper.swift` patterns 수정
- **시간 잔여 표시** — WKWebView scrape 시 timeLeftSec=0 전달 (페이지에서 파싱 미구현), 메뉴 "0m 남음" 표시됨

---

## 라이선스 및 크레딧

**GoldPlat 내부 도구**

조현정(브랜드 마케터) + Claude Code(subagent-driven-development) 협업 개발
