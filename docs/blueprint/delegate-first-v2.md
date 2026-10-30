# delegate-first v2 청사진

이 문서는 delegate-first v2의 구조(위임 흐름·작업 디렉터리·문서 분류·강제 장치)를 소유한다. 규칙 원문은 [규칙 파일](../../.claude/rules/subagent-model-routing.md)이, 훅의 판정은 `.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs`가 소유한다. 이 문서는 현재 구현에 더하는 것과 바꾸는 것만 적는다.

이 문서의 요소는 「결정」(사용자 결정 D1~D7, 청사진 검토 결정 D8~D15) 또는 「제안」(이번 설계)으로 표시한다. 제안은 메인 판정 전에는 구현하지 않는다.

### 청사진 검토 결정

| ID | 결정 | 대체 |
|---|---|---|
| D8 | 훅은 최소 범위로 둔다. 훅에 남는 것은 model·effort 부재 차단, tier 핀 불일치(B-11 model·B-12 effort), fork 사유 줄이다. 이름 규약(B-18)은 훅에서 빼고 `close-task.sh`와 위임 로그 lint의 사후 검사로 옮긴다. 발주 계약 줄 훅(B-19)과 `ALLOW_NO_CONTRACT`는 만들지 않는다. 발주문·반환물 짝 검사는 `close-task.sh`가 맡는다 | D4 |
| D9 | 에이전트·스킬은 모두 delegate-first 레포 하나에 둔다. 별도 구성물(work-contract) 안은 폐기한다. `doc-reviewer` 에이전트와 `doc-refine` 스킬도 이 레포로 옮긴다 | - |
| D10 | 작업 디렉터리 스크립트와 템플릿은 스킬 디렉터리 `.claude/skills/delegate-first/` 안에 둔다 | - |
| D11 | `reviewer-high`·`judge-max`·`explorer-low`는 `outputs/`에 쓰지 않는다. 반환은 메시지로 받고 메인이 `PROGRESS.md`에 옮긴다 | D2의 「outputs는 서브에이전트가 쓴다」를 이 세 tier에 한해 대체 |
| D12 | 실패 정책은 「두 번째 실패에서 자동 재시도를 중단하고 상향을 판정한다」로 합친다 | - |
| D13 | 위임 로그의 소급 행, role 칸 문구, 「전사 기준 사후 기록」 표시는 그대로 둔다 | - |
| D14 | 훅의 활성화 범위는 delegate-first 스킬을 호출한 세션으로 한정한다(활성화 범위 ③). 훅은 `SKILL.md` frontmatter `hooks`로 등록하고 레포 `.claude/settings.json` 등록은 없앤다(`{}`). 근거는 스킬 호출 세션에서 Agent 호출에 PreToolUse 훅이 발동하고 exit 2 차단이 적용된 프로브 실측 1·2·3 PASS다. 프로브에서 command 안의 `${CLAUDE_SKILL_DIR}`은 빈 문자열이고 `${CLAUDE_PROJECT_DIR}`은 값이 있었으며, `${CLAUDE_SKILL_DIR}` 기반 command는 스크립트를 찾지 못해 127로 끝나 fail-open이 됐다. 그래서 command는 `${CLAUDE_PROJECT_DIR}` 기반으로 두고 스크립트나 node가 없으면 exit 2로 막는다(fail-closed) | - |
| D15 | 규칙 범위는 B안으로 한다. 전역 규칙 제목의 「전 프로젝트」를 유지한다. 자동 차단은 스킬 호출 세션에서만 하고, 스킬 밖 세션에서는 모델이 지키는 규약이다. 근거는 서브에이전트가 메인 모델을 상속하는 사고가 스킬 밖에서도 똑같이 생긴다는 점이다. A안(규칙 범위를 스킬 호출 세션으로 줄임)은 강제를 늘리지 않고 스킬 밖의 보호만 없앤다. 2026-10-30 사용자 선택 | - |

훅의 활성화 범위는 결정 D14로 정했다. 현재 사실은 §7에, 남은 위험은 §10 항목 14에 적는다.

## 1. 설계 원칙과 출처 표

### 설계 원칙

| # | 원칙 | 뜻 |
|---|---|---|
| P1 | 계약 우선 | 위임은 입력·범위·증거가 계약으로 정해진 뒤에만 한다. 필요가 드러난 작업에만 위임·리뷰를 더한다 |
| P2 | 요구 ID별 증거 | 완료는 파일 존재가 아니라 요구 ID마다 붙은 증거로 판정한다 |
| P3 | 작성과 검사의 분리 | 검사자는 작성자와 다른 에이전트이고, pass/fail 기준을 착수 전에 받는다 |
| P4 | 규칙은 전역, 상태는 프로젝트 | 스킬·훅·규칙·tier는 전역에 두고 작업 문서는 프로젝트 안에서만 관리한다 |
| P5 | 결정적 검사 우선 | 형식·범위·집합 일치는 훅과 스크립트가 판정하고 의미 판단은 검수자와 fable이 한다 |
| P6 | 효과는 가설 | 도입 효과는 측정 전까지 가설이다. 측정에서 효과가 없으면 규칙을 줄이거나 폐기한다 |
| P7 | 저자 수치 비수입 | 저자 자체 평가 수치와 반복 한도 숫자를 기본값으로 복사하지 않는다 |

### 자료 표기

| 약칭 | 저장소 @ 기준 SHA | 범위 |
|---|---|---|
| RI | research @ 949bf5619e3cf19d00f216ad808bc782909fb2af | `docs/ilyas-agent-memory-series-20261026/` |
| RY | research @ 30962a60380ba43a27e933337858752d906a4716 | `docs/` 아래 루프 자료 4건 |
| HQ | HQ @ 5c4b54af9a49a0849a6c71711dbdeebddc688734 | `docs/guides/hq-team/`, `governance/`, `scripts/check_delivery.py` |
| HP | HQ @ 385c873d27e68a682ce6e309d339ffbb1ea59c37 | `coordination/handoffs/` 지시서 2건 |

### 출처 표

출처 열의 `+`는 두 자료를 결합한 요소다. 「이 레포」는 이 레포의 현재 파일과 점검 결과에서 온 것이다.

| 요소 | 출처 | 경로 + 절 |
|---|---|---|
| 발주 계약 6칸 | Ilyas + HQ 운영 계약 | RI `integrated-insights.md` §3 ③ · HQ `docs/guides/hq-team/PORTING.md` 「실제 작업 방법」 · HQ `docs/guides/hq-team/README.md` 「일반 실행」 1·2 |
| 요구 ID별 done/incomplete/unverified | Ilyas + HQ 도구 개념 | RI `integrated-insights.md` §3 ②·§5 · HQ `scripts/check_delivery.py` L101 |
| 검수자의 같은 ID 집합 독립 판정 | HQ 도구 개념 | HQ `scripts/check_delivery.py` L125-126 · HQ `governance/HQ-TEAM-OPERATING-CONTRACT.md` 항목 5 |
| 활성 결정 색인 `docs/decisions.md` | Ilyas + HQ | RI `integrated-insights.md` §3 ①·§4 표 · HQ `governance/HQ-TEAM-OPERATING-CONTRACT.md` 항목 3 · HQ `docs/guides/hq-team/README.md` 「Archive와 맥락 절약」 |
| 참고 문서 분류 R/G/S/H | 이 레포 + Ilyas | RI `integrated-insights.md` §3 ①·④ |
| 조건부 리뷰 트리거 | HQ 운영 계약 + 이 레포 | HQ `governance/HQ-TEAM-OPERATING-CONTRACT.md` 「검수 단계」 · 이 레포 `SKILL.md` §Mandatory top-tier-model triggers |
| 위임하지 않는 경우 | Ilyas + HQ + 이 레포 | RI `integrated-insights.md` §2·§4 「보류」 행 · HQ `docs/guides/hq-team/PORTING.md` 「실제 작업 방법」 끝 문장 · 이 레포 `SKILL.md` §Principle |
| `PROGRESS.md`와 `Do Not Repeat` | Youssef | RY `docs/CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §4 · RY `docs/JAVA21-HARNESS-LOOP-GUARDRAILS-2026-09.md` 「가드레일 2」 |
| 검사자에게 pass/fail 기준 제공 | Youssef | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5 · RY `JAVA21-HARNESS-LOOP-GUARDRAILS-2026-09.md` 「가드레일 1」 |
| 실패 정책 Retry/Escalate/Stop | Youssef + 이 레포 | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5 「검증 실패 시 정책」·「반복 한도」 · 이 레포 `SKILL.md` §Escalation ladder |
| 시도 횟수 4필드 표기 | Youssef 후속 조사 | RY `docs/loop-harness-rules-2026-09/REPORT.md` §2 Q4 「반드시 해소할 모호성」 |
| 작업 디렉터리 구성 | 사용자 D2 + Youssef | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §4 「최소 루프 구조」 |
| 전역 배치와 프로젝트 상태 분리 | 사용자 D1 | 결정 D1 |
| ignore 기본과 승격 | 사용자 D3 + HQ | HQ `docs/guides/hq-team/PORTING.md` 「구조와 책임」 이력 행 · 이 레포 `gotchas.md` 마지막 절 |
| 최소 훅과 발주 계약의 사후 검사 | 결정 D8 + HQ | 결정 D8(D4 대체). HQ 계약도 새 훅을 추가하지 않는다: HQ `governance/HQ-TEAM-OPERATING-CONTRACT.md` 「사용 진입점」 2문단 |
| close 스크립트의 쓰기 범위 대조 | 사용자 D4·D5 + Youssef | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5 「Checker phase」 |
| 반환 첫 줄 「수신한 추가 지시 n건」 | 사용자 전역 규칙 | `~/.claude/CLAUDE.md` Lessons Scope 절 |
| 변이 게이트·M1·M2·M3 | 이 레포 점검 결과 | 이 문서 §9의 단계 P6~P9 |
| 측정 항목 | Ilyas | RI `integrated-insights.md` §3 ⑥ · RI `insights-and-application.md` 「한 번만 해볼 실험」 |
| 효과가 없으면 축소 | Ilyas | RI `insights-and-application.md` 「빠르게 배우는 읽기 경로」 4항 |
| CHANGELOG·릴리스 노트 | 사용자 D6 | 결정 D6 |
| 브랜치 적층 | 사용자 D7 | 결정 D7 |
| 보류: 5축 계측, 모델 평가 | HQ + Youssef 자료 B | HQ `governance/HQ-TEAM-OPERATING-CONTRACT.md` 항목 6 · HP Youssef 지시서 §0 자료 B |

## 2. 위임 흐름

### 단계

```
메인 결정(TASK·REFS)
  → 발주(orders/NN)
  → 구현 tier 실행 → 반환(요구 ID별 상태 + 증거)
  → 판정 1 재현(메인)
  → 판정 2 독립 검수(reviewer-high, 같은 ID 집합)
  → 판정 3 트리거 시 judge-max(fable)
  → PROGRESS 갱신 + 위임 로그 1행
  → close-task.sh → 승격
```

| 단계 | 담당 | 하는 일 | 남기는 것 |
|---|---|---|---|
| 0. 착수 판정 | 메인 | §8로 위임 여부를 먼저 정한다. 위임하면 slug를 짓고 `new-task.sh`를 실행한다 | `.delegate/<slug>/` |
| 1. 결정 | 메인 | 목표·요구 ID·쓰기 범위·금지·정지 조건·검사자 기준을 쓴다. 참고 문서를 R/G/S/H로 분류한다 | `TASK.md`, `REFS.md` |
| 2. 발주 | 메인 | 발주문 파일을 쓰고 Agent 호출 prompt에 그 경로를 적는다. 훅은 발주문을 검사하지 않는다(결정 D8) | `orders/NN-<name>.md` |
| 3. 실행 | 구현 tier | 발주문과 거기 적힌 입력만 읽고 쓰기 범위 안에서 작업한다 | 변경 파일, `outputs/NN-<name>.md`(구현 tier만, 결정 D11) |
| 4. 반환 | 구현 tier | 요구 ID별 done/incomplete/unverified와 증거를 돌려준다 | 반환문 |
| 5. 판정 1 | 메인 | 반환의 핵심 주장을 직접 재현한다. 파일 grep, 테스트 실행, diff 확인이 해당한다 | 재현 결과 |
| 6. 판정 2 | reviewer-high | `TASK.md`의 ID 집합 전체를 독립적으로 판정한다. 반환문의 ID 목록이 아니라 `TASK.md`를 기준으로 삼는다 | 요구 ID별 pass/fail |
| 7. 판정 3 | judge-max | 리뷰 트리거가 걸리면 최종 판정을 한다 | 판정문 |
| 8. 기록 | 메인 | `PROGRESS.md` 회차 행·`Do Not Repeat`·시도 카운터를 갱신하고 위임 로그에 1행을 더한다. `reviewer-high`·`judge-max`·`explorer-low`의 반환 메시지는 요구 ID별 판정으로 회차 행에 옮긴다(결정 D11) | `PROGRESS.md`, 위임 로그 |
| 9. 종료 | 메인 | `close-task.sh`를 실행하고 남길 결정·변경을 승격한다 | 승격 문서 |

6단계의 집합 일치 규칙은 이렇다. 검수 결과의 ID 집합이 `TASK.md`의 ID 집합과 다르면 그 검수를 무효로 보고 다시 발주한다.

### 서브에이전트가 받는 맥락 범위

| 수신자 | 받는 것 | 받지 않는 것 |
|---|---|---|
| 구현 tier | 자기 발주문, 발주문 「입력」에 적힌 R·S 문서, 필요하면 G 문서, 해당 `Do Not Repeat` 항목(발주문에 복사) | `TASK.md` 전체, `PROGRESS.md` 전체, 다른 발주문·반환물, H 문서, 메인 대화 |
| reviewer-high | `TASK.md`의 요구 ID·수용 기준·검사자 기준, 기준 커밋, 구현 tier의 반환 경로, 변경 diff | 작성자의 결론을 증거로 쓰라는 지시. 검수 발주문에 「자기 보고는 증거가 아니다」를 적는다 |
| judge-max | 검수 반환, `TASK.md`, diff, 트리거 사유 | 구현 과정의 대화 |
| explorer-low | 질문 1건과 읽을 경로. 발주문 파일은 없다 | 쓰기 권한 |

### 실패 정책

시도 횟수는 4필드로 적는다. 필드 이름은 RY `REPORT.md` §2 Q4를 따르고 값은 `TASK.md`가 정한다. 기본 숫자를 이 문서가 정하지 않는다.

| 필드 | 뜻 |
|---|---|
| `attempts_total` | 실제 시도 수 |
| `max_attempts_total` | 최초 시도를 포함한 상한 |
| `retries_max` | 최초를 제외한 추가 시도 상한 |
| `stop_on` | 상한보다 이른 종료 조건. 기본은 `same_check_failed_twice` |

| 상황 | 정책 | 조치 |
|---|---|---|
| 같은 검사 항목이 처음 실패 | Retry | 발주문을 보강해 같은 tier에 한 번 다시 발주한다. 실패 접근을 `Do Not Repeat`에 적는다 |
| 같은 검사 항목이 두 번째 실패 | Escalate | 자동 재시도를 멈추고 상향 기준(규칙 원칙 5) 또는 범위 분할을 메인이 판정한다 |
| 상향 뒤에도 같은 원인으로 실패, 쓰기 범위·금지 경로 위반, 한도 도달 | Stop | 위임을 멈추고 사용자에게 보고한다 |

Youssef 자료는 같은 검사가 두 번 실패하면 정지하라고 적는다. 이 레포의 사다리(`SKILL.md` §Escalation ladder)는 두 번째 실패에서 상향하고 세 번째에서 멈춘다. 이 설계는 두 규칙을 합쳐 「두 번째 실패에서 자동 재시도를 멈추고 상향을 판정한다」로 둔다. 이 결합은 결정 D12다.

## 3. 작업 디렉터리 규격

결정 D2다. 작업 디렉터리는 `<프로젝트>/.delegate/<YYYYMMDD-kebab-slug>/`이고 slug는 메인이 착수 때 정한다. slug 형식은 `^[0-9]{8}-[a-z0-9]+(-[a-z0-9]+)*$`다.

### 파일별 규격

| 파일 | 작성자 | 읽는 사람 | 필수 절 | 갱신 시점 |
|---|---|---|---|---|
| `TASK.md` | 메인 | 메인, 검수자 | 목표, 기준 커밋, 요구 ID와 수용 기준, 쓰기 범위, 금지, 정지 조건, 검사자 pass/fail 기준, 리뷰 트리거 | 착수 때. 범위가 바뀌면 메인이 고치고 `PROGRESS.md`에 사유를 적는다 |
| `REFS.md` | 메인 | 메인, 발주문 작성 시 | 표: 번호, 경로@sha, 분류(R/G/S/H), 절, 사용처 | 참고 문서를 더할 때 |
| `PROGRESS.md` | 메인 | 메인 | 현재 상태, 회차 표, Open Items, Blockers, 사람 검토 필요, 다음 회차, Decisions Made, `Do Not Repeat`, 시도 카운터, 측정 | 판정 직후마다 |
| `orders/NN-<name>.md` | 메인 | 해당 서브에이전트 | 발주 정보와 6칸(목표, 입력, 유효 결정, 쓰기 범위, 금지, 완료 증거) | 발주 직전에 1회. 발주 뒤에는 고치지 않는다 |
| `outputs/NN-<name>.md` | 구현 tier(`executor-med`·`executor-high`·`executor-max`) | 메인, 검수자 | 요구 ID별 상태 표, 변경 파일, 검증 명령과 종료 코드, 한계 | 반환 때 |

`NN`은 발주 순번 2자리다. `<name>`은 Agent `name`과 같다. `PROGRESS.md`는 짧게 유지한다. 해소된 `Do Not Repeat` 항목은 지우고 해소 위치를 Decisions Made에 남긴다.

메인이 `TASK.md`·`REFS.md`·`PROGRESS.md`·발주문을 직접 쓰는 것은 「메인은 Edit/Write를 위임한다」 원칙의 명시적 예외다. 이 문서들은 결정 내용 자체라서 서브에이전트에게 옮겨 쓰게 하면 낭비다. 훅은 메인의 직접 쓰기를 막지 않으므로 이 예외는 규약이다.

Write 도구가 없는 tier(`explorer-low`, `reviewer-high`, `judge-max`)는 `outputs/`에 쓰지 않는다(결정 D11). 이 세 tier의 반환은 메시지로 받고, 메인이 요구 ID별 판정을 `PROGRESS.md` 회차 행에 옮긴다. `close-task.sh`의 짝 검사는 이 세 tier의 발주문을 면제한다. 면제는 `PROGRESS.md` 회차 표에서 그 발주문 stem 행의 반환 칸이 비어 있지 않을 때만 적용한다.

### 스크립트와 템플릿 위치

결정 D10이다. 스크립트와 템플릿은 스킬 디렉터리 안에 둔다.

| 경로 | 내용 |
|---|---|
| `.claude/skills/delegate-first/scripts/new-task.sh` | 작업 디렉터리 생성 |
| `.claude/skills/delegate-first/scripts/close-task.sh` | 작업 종료 검사 |
| `.claude/skills/delegate-first/templates/` | `TASK.md`·`REFS.md`·`PROGRESS.md`·`ORDER.md` 골격 |

### 템플릿 골격

`new-task.sh`가 아래 골격으로 `TASK.md`·`REFS.md`·`PROGRESS.md`를 만들고 `orders/`·`outputs/`를 비워 둔다. 메인은 발주할 때 `ORDER.md` 골격을 `orders/NN-<name>.md`로 복사해 채운다. 반환물 골격은 발주문 「반환」 절이 정하므로 템플릿 파일을 두지 않는다.

`TASK.md`

```markdown
# TASK <slug>

## 목표(끝상태)
<활동이 아니라 끝상태를 한 문단으로>

## 기준 커밋
<new-task.sh가 git rev-parse HEAD로 채운다>

## 요구 ID와 수용 기준
| ID | 수용 기준 | 증거 종류 |
|---|---|---|
| R1 | <관찰 가능한 조건> | 명령 출력 / 경로@sha / diff |

## 쓰기 범위
- <레포 상대 경로 글롭, 한 줄에 하나>

## 금지
- <경로·명령·행동>

## 정지 조건
- max_attempts_total: <n>
- retries_max: <n>
- stop_on: same_check_failed_twice

## 검사자 pass/fail 기준
- C1 (R1): <PASS 조건. 부분 점수 없음>

## 리뷰 트리거
| 조건 | 해당 | 근거 |
|---|---|---|
| 훅·scripts·.githooks 변경(보안) | y/n | |
| 변경 200줄 초과 또는 새 인터페이스(구조) | y/n | |
| SKILL.md 5종 fable 트리거 | y/n | |
```

`REFS.md`

```markdown
# REFS <slug>
| # | 경로@sha | 분류 | 절 | 사용처 |
|---|---|---|---|---|
| 1 | .claude/rules/subagent-model-routing.md@<sha> | R | 원칙 5 | order 01 |
```

`PROGRESS.md`

```markdown
# PROGRESS <slug>
## 현재 상태
## 회차
| 회차 | order | 반환 | R1 | R2 | 판정 |
|---|---|---|---|---|---|
## Open Items
## Blockers
## 사람 검토 필요
## 다음 회차
## Decisions Made
- D-1 <결정> [promote]
## Do Not Repeat
- <시도한 접근> / <실패 이유> / <회차>
## 시도 카운터
attempts_total: 0
max_attempts_total: <n>
retries_max: <n>
stop_on: same_check_failed_twice
## 측정
재설명 횟수: 0
누락 요구 수: 0
재요청 횟수: 0
시간: <값 또는 계측 수단 없음>
토큰: <값 또는 계측 수단 없음>
```

`orders/NN-<name>.md`

```markdown
# ORDER NN <name>
## 발주 정보
- tier: <tier> (<model>·<effort>)
- 상향 근거: <기준 번호. 상향이 아니면 줄 삭제>
## 목표
## 입력
- REFS #<번호>, ...
## 유효 결정
- docs/decisions.md <ID>, ...
## 쓰기 범위
## 금지
## 완료 증거
| ID | 증거 |
|---|---|
## Do Not Repeat
## 반환
- outputs/NN-<name>.md
```

`outputs/NN-<name>.md`

```markdown
수신한 추가 지시 n건

| ID | 상태(done/incomplete/unverified) | 증거(경로·명령·출력 위치) |
|---|---|---|

## 변경 파일
## 실행한 검증 명령과 종료 코드
## 한계·모르는 것
```

## 4. 발주문 규격

### 필수 칸

| 칸 | 내용 | 기존 Template 2와의 대응 |
|---|---|---|
| 목표 | 끝상태와 산출물 | 「목표」 |
| 입력 | 읽을 문서와 절. `REFS.md` 행 번호로 적는다 | 대응 칸 없음 |
| 유효 결정 | 이 작업에 적용되는 활성 결정 ID | 대응 칸 없음 |
| 쓰기 범위 | 수정 가능한 경로 글롭 | 「경계」의 수정 가능 범위 |
| 금지 | 수정·실행 금지 경로와 명령 | 「경계」의 수정 금지, 「시스템 설정 명령 금지」, 「안전 경계」 |
| 완료 증거 | 요구 ID별 증거 | 「완료 기준」 |

기존 Template 2에는 참고 문서 칸과 유효 결정 칸이 없다. 정지 조건은 「안전 경계」가 부분적으로 맡고, 시도 횟수 상한은 없다. 이 설계는 정지 조건을 `TASK.md`로 올려 발주문이 참조하게 한다.

비어 있는 칸은 「해당 없음」과 사유를 적는다. 칸을 지우지 않는다.

`close-task.sh`는 발주문마다 「발주 정보」와 6칸 제목이 모두 있는지 검사한다. 발주 정보에는 `- tier:` 줄이 있어야 한다.

### 발주문 전달

Agent 호출 prompt에는 발주문 경로를 적는다. 경로는 호출 시점의 작업 디렉터리 기준 상대 경로다.

- 훅은 prompt의 발주문 경로를 검사하지 않는다. 발주 계약 줄 훅(B-19)은 만들지 않는다(결정 D8).
- 발주문과 반환물의 짝, 발주문 필수 칸, 이름 규약은 `close-task.sh`가 작업 종료 때 사후에 검사한다.
- 발주문 파일 이름의 `<name>`은 Agent `name`과 같다.

호출 예시:

```
Agent(subagent_type: "executor-high", model: "sonnet", effort: "high",
      name: "skeleton-sonnet-high",
      prompt: "발주문: .delegate/20261030-delegate-first-v2/orders/03-skeleton-sonnet-high.md\n이 파일을 읽고 그 계약대로 수행한다. 반환은 outputs/03-skeleton-sonnet-high.md에 쓴다.")
```

### 이름 규약

결정 사항이 아니라 현행 규칙이다. Agent `name`은 `<작업>-<model>-<effort>`로 짓고 두 토큰은 tier 핀과 같다(B-18). 이 규약에서 tier 6종 밖의 타입에는 `name`을 붙이지 않는다. 이 타입들은 발주문 파일을 쓰지 않는다.

B-18은 훅에서 빠지고 사후 검사로 옮긴다(결정 D8). `close-task.sh`는 발주문 파일 이름의 `<name>`이 규약 형식인지, 두 토큰이 발주 정보 `- tier:` 줄의 핀과 같은지 본다. 위임 로그 lint는 role 칸 앞의 `[<name>]`이 같은 행의 model·effort 칸과 같은지 본다.

### 반환 형식

- 첫 줄은 「수신한 추가 지시 n건」이다.
- 이어서 요구 ID별 표(상태, 증거)를 둔다.
- 마지막에 변경 파일, 검증 명령과 종료 코드, 한계·모르는 것을 적는다.
- 증거 없는 `done`은 `unverified`로 취급한다.

## 5. 참고 문서 분류

### 분류 기준

| 분류 | 뜻 | 발주문 포함 규칙 |
|---|---|---|
| R | 규칙. 에이전트의 행동을 바꾼다 | 작업이 건드리는 R 문서는 반드시 적는다 |
| G | 절차 안내 | 필요할 때만 적는다 |
| S | 상태·결정. 활성 결정 색인 포함 | 해당하는 활성 결정은 반드시 적는다 |
| H | 이력 | 적지 않는다 |

H는 발주문 입력에 넣지 않는다. 이유는 낡은 가정이 작업자에게 현재 규칙처럼 전달되는 것을 막기 위해서다. 이 이유는 RI `integrated-insights.md` §3 ⑤에서 가져왔다.

### 현재 레포 파일 매핑

한 파일 안에 분류가 섞이면 절 단위로 분류하고 `REFS.md` 행에 절을 적는다.

| 파일 | 분류 | 비고 |
|---|---|---|
| `.claude/rules/subagent-model-routing.md` | R | 전역 사본과 동기 대상 |
| `.claude/skills/delegate-first/SKILL.md` | R | |
| `.claude/agents/*.md` | R | 훅 map과 lint가 대조한다 |
| `.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs` | R | |
| `.claude/settings.json` | R | 훅 등록 없음(`{}`, 결정 D14) |
| `.githooks/pre-commit`, `scripts/lint-delegate-first.py` | R | 강제 장치. 제안: R로 둔다 |
| `README.md` | G | |
| `docs/REINSTALL.md` | G | |
| `.claude/skills/delegate-first/references/prompt-templates.md` | G | |
| `.claude/skills/delegate-first/references/routing-matrix.md` | G | |
| `docs/blueprint/delegate-first-v2.md` | G | 동작은 R 파일이 바꾼다 |
| `BACKLOG.md` 미해결 항목 | S | |
| `docs/handoff/delegation-log.md` | S | |
| `gotchas.md` | S | |
| `docs/decisions.md` | S | 신설. 활성 결정 색인 |
| `docs/HANDOFF-*.md` | H | |
| `BACKLOG.md` 해결된 항목 | H | |
| `docs/adoption/*.md` | H | 활성이 되는 결정은 `docs/decisions.md`로 올린다 |
| `CHANGELOG.md`, `docs/release/*.md` | H | |
| 리뷰 보고서 | H | |

### 활성 결정 색인 형식

`docs/decisions.md`는 표 하나로 시작한다.

| 열 | 내용 |
|---|---|
| ID | `DEC-NNN` |
| 결정 | 한 문장 |
| 상태 | `active` 또는 `superseded` |
| 대체 | 대체한 결정 ID. 없으면 `-` |
| 근거 | 경로@sha |
| 적용 범위 | 경로 글롭 또는 작업 유형 |

검색 경로는 `grep -n '| active |' docs/decisions.md`다. 날짜 필터가 아니므로 오래된 활성 결정도 찾는다.

### 검증

`close-task.sh`는 발주문 「입력」이 가리키는 `REFS.md` 행 중 분류가 H인 것이 있으면 실패 처리한다.

## 6. 추적 정책

### 기본값

결정 D3다. `.delegate/`는 기본으로 gitignore한다. 프로젝트 `CLAUDE.md`에 한 줄로 결정을 기록한다.

```
delegate-workdir: ignore | track
```

- `new-task.sh`는 처음 생성할 때 `.gitignore` 추가를 제안만 한다. 직접 고치지 않는다.
- 줄이 없으면 `ignore`로 취급하고 제안을 출력한다.
- `track`을 고른 프로젝트는 커밋 전에 비밀과 원문 인용을 검사한다.

### 승격

작업을 닫을 때 남길 것만 추적 문서로 올린다.

| 남길 것 | 올리는 곳 | 분류 |
|---|---|---|
| 결정 | `docs/decisions.md` | S |
| 변경 | `CHANGELOG.md` | H |
| 결과 증거 | PR 본문 또는 커밋 메시지 | H |
| 위임 1행 | `docs/handoff/delegation-log.md` | S |
| 실패 교훈 | `gotchas.md` | S |
| 미룬 일과 재개 조건 | `BACKLOG.md` | S |

`PROGRESS.md`의 Decisions Made에서 `[promote]`가 붙은 항목이 `docs/decisions.md`에 없으면 `close-task.sh`가 실패 처리한다.

### track 프로젝트의 커밋 전 검사

- 비밀 검사: 토큰·키 패턴 정규식과 프로젝트가 지정한 금지 문자열 목록을 대조한다.
- 원문 인용 검사: 비공개 자료를 로컬에 가진 경우에만 5-gram 겹침을 본다. 그 외에는 `REFS.md`의 외부 자료 행을 사람이 확인한다.
- 한계: 원문 인용을 완전하게 탐지하지 못한다.

### worktree 시드

gitignore된 디렉터리는 `git worktree add`로 만든 작업 트리에 따라오지 않는다. 한 에이전트당 worktree 하나가 원칙이므로 시드 절차가 필요하다.

1. 메인이 worktree를 만든 뒤 `new-task.sh <slug> --seed-worktree <경로>`로 `TASK.md`·`REFS.md`와 해당 발주문만 복사한다. 제안: 이 옵션을 구현한다.
2. 서브에이전트는 worktree 안의 `outputs/`에 쓴다.
3. 메인이 반환 직후 `outputs/`를 정본 디렉터리로 복사한 뒤에 worktree를 정리한다.

이 절차는 구현과 실측 전이다.

### 다른 PC에서 이어 가기의 한계

ignore 모드에서는 진행 중인 작업 상태를 다른 PC로 옮기지 못한다. 다른 PC에서 볼 수 있는 것은 승격된 문서와 git 이력뿐이다. 진행 중 작업을 옮겨야 하면 그 작업만 `track`으로 임시 전환하거나 직접 복사한다. 동기화 기능은 만들지 않는다.

## 7. 강제 장치

### 강제 수단 표

훅은 delegate-first 스킬을 호출한 세션에서만 작동한다(결정 D14). 등록 위치는 `SKILL.md` frontmatter `hooks`(PreToolUse, matcher `Agent`) 하나이고 레포 `.claude/settings.json`에는 등록이 없다. 스킬을 호출하지 않은 세션에서는 아래 훅 행이 규약이다.

| 항목 | 내용 |
|---|---|
| 훅 파일 | `.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs`. 스킬 디렉터리에 들어 있어 `reinstall.sh`가 스킬과 함께 설치한다 |
| command 탐색 순서 | `${CLAUDE_PROJECT_DIR}/.claude/skills/delegate-first/hooks/`, 없으면 `$HOME/.claude/skills/delegate-first/hooks/` |
| 실패 방식 | 스크립트나 node를 찾지 못하면 exit 2로 막는다(fail-closed) |
| 사용 금지 | `${CLAUDE_SKILL_DIR}`은 command 안에서 빈 문자열이라 쓰지 않는다 |
| 설치 검증 | `reinstall.sh`가 설치된 `SKILL.md`의 frontmatter `hooks`와 스킬 디렉터리의 훅 파일을 확인한다 |

| 규칙 | 강제 수단 | 강제 시점 | 우회(break-glass) |
|---|---|---|---|
| 모든 호출에 model·effort 명시 | 훅 | Agent 호출 | `ALLOW_INHERITED_SUBAGENT_MODEL=1`(사람 전용) |
| tier model 핀 일치(B-11) | 훅 | Agent 호출 | `ALLOW_TIER_MODEL_OVERRIDE=1`(사람 전용) |
| tier effort 핀 일치(B-12) | 훅 | Agent 호출 | `ALLOW_TIER_MODEL_OVERRIDE=1`(사람 전용) |
| fork 사유 줄 | 훅 | Agent 호출 | 없음 |
| tier 이름 규약(B-18) | `close-task.sh`(발주문 이름)·위임 로그 lint(role 칸 이름, P4 미구현) | 작업 종료·커밋 | 없음. 사후 검사다(결정 D8) |
| 발주문·반환물 짝, 발주문 필수 칸 | `close-task.sh` | 작업 종료 | 없음. 사후 검사다(결정 D8) |
| tier 정의와 훅 map 일치 | `lint-delegate-first.py` Check A | 커밋 | 없음. `git commit --no-verify`는 사람 전용 |
| 위임 로그 7열 스키마 | `lint-delegate-first.py` Check B | 커밋 | 같음 |
| 훅 판정 회귀 | `scripts/smoke-hook.sh` | 커밋 | 같음 |
| smoke 음성 케이스의 비공허성(제안) | `scripts/test-smoke-nonvacuous.sh` 변이 게이트 | 커밋 | 같음 |
| 작업 쓰기 범위 | `close-task.sh`의 `git diff --name-only` 대조 | 작업 종료 | 없음. 사후 검사다 |
| 요구 ID 집합·증거·H 분류 금지·`[promote]` 승격 | `close-task.sh` | 작업 종료 | 없음 |
| 리뷰 트리거 충족 시 검수 행 존재 | `close-task.sh` | 작업 종료 | 없음 |
| 설치본 정합 | `scripts/test-reinstall.sh` | 커밋 | 같음 |

발주 계약 줄 훅(B-19)과 우회 변수 `ALLOW_NO_CONTRACT`는 만들지 않는다(결정 D8). 이 강제 수단 표에서 훅 행은 위의 네 행뿐이다.

### close-task.sh

| 항목 | 내용 |
|---|---|
| 호출 | `close-task.sh <slug> [--dry-run]` |
| 종료 코드 | 0 통과, 1 검사 실패, 2 구조 오류 또는 잘못된 사용 |
| 출력 | 실패 한 건당 한 줄 `FAIL <검사명> <상세>` |
| 쓰기 범위 대조 | `git diff --name-only <기준 커밋>` 과 `git ls-files --others --exclude-standard`의 합집합이 `TASK.md` 쓰기 범위와 `.delegate/<slug>/**`에 속해야 한다 |
| 집합 일치 | `TASK.md` ID 집합, `PROGRESS.md` 최종 회차의 ID 집합, 검수 판정의 ID 집합이 같아야 한다 |
| 완료 | 모든 ID가 `done`이고 증거 칸이 비어 있지 않아야 한다 |
| 짝 검사 | 발주문마다 같은 이름의 반환물이 있어야 한다. `- tier:` 줄이 `explorer-low`·`reviewer-high`·`judge-max`인 발주문은 `PROGRESS.md` 회차 표에서 그 발주문 stem 행의 반환 칸이 비어 있지 않을 때만 면제한다(결정 D11) |
| 필수 칸 | 발주문마다 「발주 정보」와 6칸(목표, 입력, 유효 결정, 쓰기 범위, 금지, 완료 증거) 제목, `- tier:` 줄이 있어야 한다 |
| 이름 규약 | 발주문 파일 이름의 `<name>`이 `<작업>-<model>-<effort>` 형식이고 두 토큰이 `- tier:` 줄의 핀과 같아야 한다(B-18 이전분) |
| 시도 카운터 | `attempts_total`이 `max_attempts_total`을 넘지 않아야 한다 |
| `--dry-run` | 작업 도중 같은 검사를 실행해 보고 파일은 바꾸지 않는다 |

뼈대 구현은 짝·필수 칸·이름 규약 세 검사와 종료 코드 규약을 갖춘다. 나머지 검사는 §9의 단계에서 더한다.

### 훅 범위

결정 D8이다. 훅은 Agent 호출 입력만 보는 무상태 검사로 남기고 파일을 읽지 않는다.

| 검사 | 위치 |
|---|---|
| model·effort 부재 | 훅 |
| tier 핀 불일치(B-11 model·B-12 effort) | 훅 |
| fork 사유 줄 | 훅 |
| 이름 규약(B-18) | 사후 검사로 이전 |
| 발주 계약 줄(B-19) | 만들지 않음 |
| 발주문·반환물 짝 | `close-task.sh` |

이름 규약을 훅에서 빼면 named 스폰에서 호출 effort가 유실되는 문제를 호출 시점에 막지 못한다. 이 위험은 반환 뒤 대조(규칙 원칙 5)와 위임 로그 lint가 사후에 잡는다.

### 변이 게이트

smoke의 음성 케이스는 훅의 차단 로직을 꺼도 통과할 수 있다. 재현: B-12 분기의 조건을 `false`로 바꾼 훅 사본에 `smoke-hook.sh <사본>`을 실행하면 104/104로 통과한다. 변이 게이트는 훅 사본에서 차단 분기를 하나씩 끈 변이본을 만들고, 각 변이본에 `smoke-hook.sh <변이본>`을 실행해 실패를 확인한다. 변이가 실제로 적용됐는지(치환 전후 diff)도 스크립트가 스스로 확인한다.

## 8. 위임하지 않는 경우

메인이 직접 하거나 하지 않는 경우를 정한다. 근거는 RI `integrated-insights.md` §2다. 저자의 자체 평가에서 단일 컨텍스트에 들어가는 작업은 위임 이득이 입증되지 않았다.

| 경우 | 처리 | 근거 |
|---|---|---|
| 단건 읽기, 단일 검증 명령 | 메인이 직접 한다 | 이 레포 `SKILL.md` §Principle |
| `TASK.md`·`REFS.md`·`PROGRESS.md`·발주문 작성 | 메인이 직접 쓴다 | 결정 D2의 예외 |
| 수정 없는 단건 조사 | `explorer-low`로 위임하고 발주문 파일은 쓰지 않는다 | §2 「서브에이전트가 받는 맥락 범위」 |
| 사용자 지시가 위임을 제한함 | 메인이 직접 한다. 필요한 독립 검수는 그 권한 안에서 구성한다 | HQ `docs/guides/hq-team/PORTING.md` 「실제 작업 방법」 끝 문장 |
| 쓰기 범위가 겹치는 레인 | 한 발주문에 묶거나 순차로 한다. 병렬 발주하지 않는다 | RI `insights-and-application.md` 「인사이트」 3항 |
| 소규모 문서 수정 | 구현 tier 1건과 재현 판정으로 끝낸다. 독립 검수는 리뷰 트리거가 걸릴 때만 붙인다 | HQ `governance/HQ-TEAM-OPERATING-CONTRACT.md` 항목 2 |
| 의사결정 자체 | 메인이 판정한다. 위임하지 않는다 | 규칙 원칙 1·4 |

그 밖의 구현·편집은 메인이 하지 않고 위임한다. 이 표는 위임 면제의 한도를 정할 뿐 면제를 넓히지 않는다.

## 9. 재구축 계획

단계마다 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다. 기계적 문서 편집은 예외다. 구현 tier는 `executor-high`로 시작한다. `close-task.sh`를 만들거나 넓히는 단계(P2·P5)는 틀리면 게이트가 조용히 열리므로 상향 기준 ①(규칙 원칙 5)로 `executor-max`에 둔다. P3·P4·P6·P7은 실패 패스가 나오면 기준 ②로 `executor-max`에 올린다.

| 단계 | 내용 | 담당 | 완료 기준 | 검증 명령 |
|---|---|---|---|---|
| P0 | 기준선 확인 | `executor-med` | 네 검사가 모두 통과한다 | `bash scripts/smoke-hook.sh` · `bash scripts/test-lint.sh` · `python3 scripts/lint-delegate-first.py --strict` · `bash scripts/test-reinstall.sh` |
| P1 | `.gitignore`에 `.delegate/` 추가. 이 재구축의 작업 디렉터리 `.delegate/20261030-delegate-first-v2/`를 만든다 | `executor-max`(`.gitignore`·디렉터리), 메인(작업 문서 내용) | 디렉터리가 추적되지 않는다 | `git check-ignore -v .delegate/20261030-delegate-first-v2/TASK.md`가 0으로 끝난다 · `git status --short`에 `.delegate`가 없다 |
| P2 | 작업 디렉터리 뼈대: `new-task.sh`, 짝·필수 칸·이름 규약을 검사하는 `close-task.sh`, 템플릿 4종(`TASK`·`REFS`·`PROGRESS`·`ORDER`), 샌드박스 테스트 `scripts/test-delegate-scripts.sh`(결정 D8·D10) | `executor-max`(기준 ①) | 임시 git 저장소에서 정상·짝 누락·필수 칸 누락·이름 규약 위반 케이스가 각각 기대 종료 코드를 낸다 | `bash scripts/test-delegate-scripts.sh` |
| P3 | B-18을 훅에서 뺀다(결정 D8). smoke의 B-18 케이스를 통과 기대로 바꾸거나 지우고, 훅 주석·안내문과 README 차단 코드 표를 맞춘다 | `executor-high` | 훅에 B-18 분기가 없고 smoke가 통과한다 | `grep -n 'B-18' .claude/skills/delegate-first/hooks/enforce-subagent-model.cjs`(0건 기대) · `bash scripts/smoke-hook.sh` |
| P4 | 위임 로그 lint에 이름 규약 검사를 더한다. role 칸 앞 `[<name>]`의 model·effort 토큰이 같은 행의 model·effort 칸과 같은지 본다. `test-lint.sh` 케이스를 먼저 쓴다 | `executor-high` | 신규 케이스가 구현 전 실패하고 구현 후 통과한다. 기존 로그가 `--strict`를 통과한다 | `bash scripts/test-lint.sh` · `python3 scripts/lint-delegate-first.py --strict` |
| P5 | `close-task.sh` 나머지 검사: 쓰기 범위 대조, 요구 ID 집합 일치, 완료·증거, H 분류 참조, `[promote]` 승격, 리뷰 트리거 검수 행, 시도 카운터, `--dry-run` | `executor-max`(기준 ①) | 검사마다 위반 케이스가 1을 내고 정상 케이스가 0을 낸다. 각 케이스가 실제로 실패를 재현한다 | `bash scripts/test-delegate-scripts.sh` |
| P6 | H1: 변이 게이트 `scripts/test-smoke-nonvacuous.sh`를 만들고 pre-commit에 등록한다 | `executor-high` | B-11·B-12·fork 분기를 끈 변이본이 각각 smoke 실패를 낸다. 정상 훅은 통과한다 | `bash scripts/test-smoke-nonvacuous.sh` · `grep -n test-smoke-nonvacuous .githooks/pre-commit` |
| P7 | M1: `ALLOW_TIER_MODEL_OVERRIDE=1` 경로에서 effort 부재가 통과하는 결함을 고친다. smoke 케이스를 먼저 추가한다 | `executor-high` | 신규 케이스가 수정 전 훅에서 실패하고 수정 후 통과한다 | `git show HEAD:.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs > /tmp/hook-old.cjs` 후 `bash scripts/smoke-hook.sh /tmp/hook-old.cjs`(실패 기대) · `bash scripts/smoke-hook.sh`(통과 기대) |
| P8 | M2: 「핀 없는 타입」을 「tier 6종 밖(훅이 핀을 모르는 타입)」으로 정정한다. 규칙 파일·BACKLOG·훅 안내문·README가 대상이다 | `executor-med` | 옛 표현이 남지 않는다. smoke가 안내문을 검사하면 같은 커밋에서 함께 고친다 | `grep -rn '핀 없는 타입' .claude BACKLOG.md README.md scripts` · `bash scripts/smoke-hook.sh` |
| P9 | M3: 규칙 파일 원칙 2 이력 블록과 `routing-matrix.md` 「★ 실측」의 named effort 서술을 관측 범위로 한정한다 | `executor-med` | 서술이 표본 수와 판별 불가 범위를 함께 적는다 | `grep -n 'named' .claude/rules/subagent-model-routing.md .claude/skills/delegate-first/references/routing-matrix.md` |
| P10 | `SKILL.md` 체크리스트에 「발주 작성」 단계를 더한다. `routing-matrix.md`·`prompt-templates.md`를 6칸과 발주문 경로 전달로 갱신한다 | `executor-high` | 세 문서가 §4와 같은 칸 구성을 말한다. `CONTRACT:` 줄을 요구하는 서술이 없다 | `python3 scripts/lint-delegate-first.py --strict` · `grep -n 'CONTRACT' .claude/skills/delegate-first/SKILL.md .claude/skills/delegate-first/references/*.md`(0건 기대) |
| P11 | 규칙 파일에 발주 계약 원칙(사후 검사)을 더하고, 강제 장치 절에서 B-18을 사후 검사로 옮겨 적는다 | `executor-high` | 규칙 파일이 훅 검사 세 가지와 사후 검사를 구분해 말한다. 항목별 diff 검토를 거친다 | `git diff .claude/rules/subagent-model-routing.md` |
| P12 | `doc-reviewer` 에이전트와 `doc-refine` 스킬을 이 레포로 옮긴다(결정 D9). `reinstall.sh` 설치 대상과 lint 대조 대상에 반영한다 | `executor-high` | 정본 두 경로가 레포에 있고 재설치 테스트가 두 경로를 다룬다 | `ls .claude/agents/doc-reviewer.md .claude/skills/doc-refine/SKILL.md` · `bash scripts/test-reinstall.sh` · `python3 scripts/lint-delegate-first.py --strict` |
| P13 | README 호출 규약 절과 작업 디렉터리 절을 갱신한다. `docs/decisions.md`를 신설해 D1~D13을 `DEC-NNN`으로 올린다. `BACKLOG.md`에 B-19를 만들지 않는다는 결정을 적고 미룬 항목에 「재개 조건」을 보강한다 | `executor-med` | 세 파일이 서로 모순되지 않는다 | `grep -n 'B-18\|B-19' README.md BACKLOG.md` · `grep -c '| active |' docs/decisions.md` |
| P14 | 문서 검사: `doc-refine` 흐름(검토 → 개선안 승인 → 적용)을 README·청사진·판정표에 돌린다. 지침 파일은 항목별로 diff를 검토한다 | `doc-reviewer`, `executor-med` | 지적 건수·적용 건수·보류 사유가 보고된다 | `~/.claude/rules/doc-writing.md`의 완료 조건 |
| P15 | 독립 적대 리뷰. 훅·scripts·.githooks 변경이 있으므로 보안 트리거로 필수다 | `reviewer-high` | 미해소 H가 0이다 | 리뷰 보고서의 H 목록과 재현 명령 |
| P16 | 이 재구축을 `close-task.sh`로 닫는다. 작업 문서는 P1에서 만든 것을 쓴다 | 메인 | 종료 코드 0. 쓰기 범위 대조에 위반이 없다 | `bash .claude/skills/delegate-first/scripts/close-task.sh 20261030-delegate-first-v2` |
| P17 | fable 출하 게이트 | `judge-max` | 판정이 MERGE 계열이다 | 판정문 |
| P18 | `CHANGELOG.md`와 `docs/release/v2.md`를 쓴다 | `executor-med` | 두 파일이 승격 대상 변경을 모두 담는다 | `python3 scripts/lint-delegate-first.py --strict` · `git diff --stat` |
| P19 | 승인 뒤 commit·push·PR을 낸다. 머지는 사용자가 한다. 전역 전파는 훅 → 규칙 → 실측 → 재설치 순서(BACKLOG B-08 절차)로 한다. 활성화 범위는 결정 D14로 정해졌고, 전역 `settings.json` 옛 등록의 처리(§10 항목 17)는 전파 전에 사용자가 정한다 | 메인과 사용자 | push 뒤 원격 SHA가 로컬 HEAD와 같다. 전역 사본이 정본과 같다 | `git ls-remote origin <브랜치>` · `cmp .claude/skills/delegate-first/hooks/enforce-subagent-model.cjs ~/.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs` |
| P20 | 측정 기록: 재설명 횟수·누락 요구·재요청·시간·토큰을 이 작업의 `PROGRESS.md`에 남긴다 | 메인 | 항목마다 값 또는 「계측 수단 없음」이 적힌다 | `PROGRESS.md` 확인 |

## 10. 미검증·위험

| # | 항목 | 내용 | 확인 방법 |
|---|---|---|---|
| 1 | Bash 경유 쓰기 | 훅은 Agent 호출만 본다. tier 서브에이전트가 Bash로 쓰기 범위 밖 파일을 바꾸는 것은 종료 시 diff로만 잡힌다. 사후 탐지이고 차단이 아니다 | P5 샌드박스 테스트에서 범위 밖 변경을 재현한다 |
| 2 | diff의 사각지대 | `git diff --name-only`는 gitignore된 파일과 레포 밖 쓰기를 보지 못한다. 이름 변경과 기준 커밋 이후의 커밋은 별도 확인이 필요하다 | 같은 테스트에 ignored 파일 케이스를 추가한다 |
| 3 | 저자 수치 | MetaEnsemble 자체 평가 수치는 저자 평가이고 이 레포에서 재현하지 않았다. 설계 근거로 쓰지 않았다 | 재현 계획 없음 |
| 4 | 효과 미측정 | 재설명·재요청 감소와 토큰 증가는 측정 전 가설이다. tier 호출마다 발주문 파일을 쓰는 비용이 작은 작업에서 이득을 넘을 수 있다 | P20 측정. 효과가 없으면 규칙을 줄인다 |
| 5 | 발주문 없는 호출 | 훅이 prompt를 보지 않으므로(결정 D8) 발주문 없이 tier를 호출해도 막지 못한다. `close-task.sh` 짝 검사는 `orders/`에 있는 발주문만 본다. 발주문 없이 나간 호출은 위임 로그와 `orders/`를 대조해야 잡힌다 | P5에서 위임 로그 행과 발주문 수의 대조를 넣을지 메인이 판정한다 |
| 6 | worktree 시드 | gitignore된 디렉터리가 worktree에 없다. 시드 옵션과 반환물 복사 절차를 구현하거나 실측하지 않았다 | P5 범위에 시드 케이스를 넣을지 메인이 판정한다 |
| 7 | 스크립트 실행 권한 | 스킬 디렉터리의 스크립트가 `reinstall.sh`의 `cp -R` 뒤에도 실행 비트를 유지하는지 확인하지 않았다. 문서의 호출 예시는 `bash <경로>`로 실행 비트에 기대지 않는다 | `test-reinstall.sh`에 모드 확인 케이스를 더한다 |
| 8 | 훅 강제의 실효 | 공식 사양상 차단되는 PreToolUse 동작이 현장에서 무시된다는 보고가 있다(RY `REPORT.md` §5 경고 1). Stop 훅의 연속 차단 상한은 Stop 훅 한정이라 이 설계에 직접 걸리지 않는다. 그래도 하네스 경로의 end-to-end 실측은 smoke가 대신하지 못한다 | 전파 뒤 B-08의 4단계 실측을 한다 |
| 9 | tier 6종 밖 타입의 이름 처리 | 정의에 핀이 있지만 tier 6종 밖인 타입(`doc-reviewer` 등)에 이름을 붙여도 레포 훅과 전역 훅 사본이 모두 통과시킨다. 레포 훅은 B-18을 뺐고 전역 사본에는 B-18이 없다. 결정 D9로 `doc-reviewer`가 이 레포에 들어올 때 tier로 취급할지와 사후 lint의 대상 타입을 정해야 이 항목이 닫힌다 | P12 착수 전 메인 판정 |
| 10 | 메인 직접 쓰기 예외 | D2의 직접 쓰기 예외는 훅이 막지 못하는 규약이다. 범위를 넘는 직접 쓰기는 사람이 발견해야 한다 | 위임 로그와 diff 대조 |
| 11 | 활성 결정 색인의 부패 | `docs/decisions.md`가 실제 규칙과 어긋나도 잡는 검사가 없다. `close-task.sh`는 `[promote]` 누락만 본다 | 색인 항목의 근거 경로 존재를 lint에 더할지 메인이 판정한다 |
| 12 | named 스폰 effort 유실의 사후 탐지 | 이름 규약이 훅에서 빠지면 tier 밖 타입에 이름을 붙인 호출이 나가고 호출 effort가 유실된다. 호출 시점에는 막지 못하고 반환 뒤 전사 대조와 위임 로그 lint로만 잡힌다 | P4 lint 케이스와 반환 뒤 대조 기록 |
| 13 | tier 밖 타입의 계약 우회 | `general-purpose`·`codex:*`·`oh-my-claudecode:*` 호출은 발주문 없이 나간다. 계약 없는 위임 경로가 남는다 | tier 밖 타입의 사용 조건을 `routing-matrix.md`의 out-of-table 절차와 맞출지 메인이 판정한다 |
| 14 | 훅 활성화 범위(결정 D14)의 사각지대 | 훅은 스킬을 호출한 세션에서만 켜진다. 스킬을 호출하지 않은 세션과 스킬이 설치되지 않은 프로젝트에는 강제가 없다. 전역 `~/.claude/settings.json`에 옛 등록이 남아 있으면 이 레포가 바꾸지 않으므로 별도로 정리해야 하고, 남아 있는 동안 스킬 호출 세션에서는 두 훅이 함께 돌 수 있다(미실측) | 전역 등록의 처리는 P19 전역 전파 전에 사용자가 정한다. 이중 등록 동작은 전파 뒤 B-08 실측에서 확인한다 |
| 15 | 위임 로그의 이름 위치 | 위임 로그 7열에는 이름 칸이 없다. P4 lint는 role 칸 앞 `[<name>]` 관례에 기댄다. 이 관례가 없는 과거 행(결정 D13으로 유지)을 lint가 어떻게 다룰지 정하지 않았다 | P4 착수 전 메인 판정 |
| 16 | 이름 인자의 기계 대조 부재 | `close-task.sh`는 `orders/NN-<name>.md` 발주문 파일 이름의 토큰만 본다. 실제 Agent 호출의 `name` 인자와 발주문 파일 이름을 기계로 대조하는 검사가 없다(리뷰 M5와 같다). 핀 없는 타입의 이름 금지도 기계 검사가 없다 | 반환 뒤 대조(규칙 원칙 5)의 전사 확인으로 잡는다. 기계 대조를 더할지 메인이 판정한다 |
| 17 | 전역 옛 등록이 남은 동안의 이중 실행 | 전역 `~/.claude/settings.json`에 옛 훅 등록이 남아 있으면 스킬 호출 세션에서 스킬 훅과 옛 등록이 함께 돈다. 낡은 사본도 판정에 참여한다. 프로젝트 사본이 없으면 command가 `$HOME/.claude/skills/delegate-first/hooks/`의 사본으로 fallback하므로 그 사본이 낡아도 판정한다. `reinstall.sh`는 옛 등록을 경고만 하고 지우지 않는다 | 전역 정리는 사용자 승인 대기다. 정리 뒤 B-08 실측으로 단일 실행을 확인한다 |
| 18 | 사고: pre-commit 경유 GIT_DIR 누출 | 17:11에 worktree 커밋이 원본 클론의 `.githooks/pre-commit`을 실행했다. pre-commit이 부른 테스트가 git이 넘긴 `GIT_DIR`을 물려받아 샌드박스의 git 명령이 공통 `.git/config`를 오염시켰다. 복구는 끝났다. 원인 수정 위치는 `.githooks/pre-commit`이다. 레포 루트를 구한 뒤 테스트 스위트 호출 전에 `GIT_DIR` 등 git 환경 변수를 unset한다 | `scripts/smoke-hook.sh`의 ⑦ 케이스가 `/tmp` 미끼 레포의 worktree 커밋으로 누출 여부를 검사한다 |
