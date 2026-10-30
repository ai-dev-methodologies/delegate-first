# delegate-first v2 청사진

이 문서는 delegate-first v2의 구조(위임 흐름·작업 디렉터리·문서 분류·강제 장치)를 소유한다. 규칙 원문은 [규칙 파일](../../.claude/rules/subagent-model-routing.md)이, 훅의 판정은 `.claude/hooks/enforce-subagent-model.cjs`가 소유한다. 이 문서는 현재 구현에 더하는 것과 바꾸는 것만 적는다.

이 문서의 요소는 「결정」(사용자 결정 D1~D7) 또는 「제안」(이번 설계)으로 표시한다. 제안은 메인 판정 전에는 구현하지 않는다.

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
| 훅 B-19 형식 검사(무상태) | 사용자 D4 | 결정 D4. HQ 계약은 새 훅을 추가하지 않는다고 적어 이 지점에서 갈라진다: HQ `governance/HQ-TEAM-OPERATING-CONTRACT.md` 「사용 진입점」 2문단 |
| close 스크립트의 쓰기 범위 대조 | 사용자 D4·D5 + Youssef | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5 「Checker phase」 |
| 반환 첫 줄 「수신한 추가 지시 n건」 | 사용자 전역 규칙 | `~/.claude/CLAUDE.md` Lessons Scope 절 |
| 변이 게이트·M1·M2·M3 | 이 레포 점검 결과 | 이 문서 §9의 단계 P2~P5 |
| 측정 항목 | Ilyas | RI `integrated-insights.md` §3 ⑥ · RI `insights-and-application.md` 「한 번만 해볼 실험」 |
| 효과가 없으면 축소 | Ilyas | RI `insights-and-application.md` 「빠르게 배우는 읽기 경로」 4항 |
| CHANGELOG·릴리스 노트 | 사용자 D6 | 결정 D6 |
| 브랜치 적층 | 사용자 D7 | 결정 D7 |
| 보류: 5축 계측, 모델 평가 | HQ + Youssef 자료 B | HQ `governance/HQ-TEAM-OPERATING-CONTRACT.md` 항목 6 · HP Youssef 지시서 §0 자료 B |

## 2. 위임 흐름

### 단계

```
메인 결정(TASK·REFS)
  → 발주(orders/NN + CONTRACT 줄)
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
| 2. 발주 | 메인 | 발주문 파일을 쓰고 Agent 호출 prompt에 `CONTRACT:` 줄을 넣는다. 훅이 형식을 검사한다 | `orders/NN-<name>.md` |
| 3. 실행 | 구현 tier | 발주문과 거기 적힌 입력만 읽고 쓰기 범위 안에서 작업한다 | 변경 파일, `outputs/NN-<name>.md` |
| 4. 반환 | 구현 tier | 요구 ID별 done/incomplete/unverified와 증거를 돌려준다 | 반환문 |
| 5. 판정 1 | 메인 | 반환의 핵심 주장을 직접 재현한다. 파일 grep, 테스트 실행, diff 확인이 해당한다 | 재현 결과 |
| 6. 판정 2 | reviewer-high | `TASK.md`의 ID 집합 전체를 독립적으로 판정한다. 반환문의 ID 목록이 아니라 `TASK.md`를 기준으로 삼는다 | 요구 ID별 pass/fail |
| 7. 판정 3 | judge-max | 리뷰 트리거가 걸리면 최종 판정을 한다 | 판정문 |
| 8. 기록 | 메인 | `PROGRESS.md` 회차 행·`Do Not Repeat`·시도 카운터를 갱신하고 위임 로그에 1행을 더한다 | `PROGRESS.md`, 위임 로그 |
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

Youssef 자료는 같은 검사가 두 번 실패하면 정지하라고 적는다. 이 레포의 사다리(`SKILL.md` §Escalation ladder)는 두 번째 실패에서 상향하고 세 번째에서 멈춘다. 이 설계는 두 규칙을 합쳐 「두 번째 실패에서 자동 재시도를 멈추고 상향을 판정한다」로 둔다. 이 결합은 제안이다.

## 3. 작업 디렉터리 규격

결정 D2다. 작업 디렉터리는 `<프로젝트>/.delegate/<YYYYMMDD-kebab-slug>/`이고 slug는 메인이 착수 때 정한다. slug 형식은 `^[0-9]{8}-[a-z0-9]+(-[a-z0-9]+)*$`다.

### 파일별 규격

| 파일 | 작성자 | 읽는 사람 | 필수 절 | 갱신 시점 |
|---|---|---|---|---|
| `TASK.md` | 메인 | 메인, 검수자 | 목표, 기준 커밋, 요구 ID와 수용 기준, 쓰기 범위, 금지, 정지 조건, 검사자 pass/fail 기준, 리뷰 트리거 | 착수 때. 범위가 바뀌면 메인이 고치고 `PROGRESS.md`에 사유를 적는다 |
| `REFS.md` | 메인 | 메인, 발주문 작성 시 | 표: 번호, 경로@sha, 분류(R/G/S/H), 절, 사용처 | 참고 문서를 더할 때 |
| `PROGRESS.md` | 메인 | 메인 | 현재 상태, 회차 표, Open Items, Blockers, 사람 검토 필요, 다음 회차, Decisions Made, `Do Not Repeat`, 시도 카운터, 측정 | 판정 직후마다 |
| `orders/NN-<name>.md` | 메인 | 해당 서브에이전트 | 발주 정보와 6칸(목표, 입력, 유효 결정, 쓰기 범위, 금지, 완료 증거) | 발주 직전에 1회. 발주 뒤에는 고치지 않는다 |
| `outputs/NN-<name>.md` | 서브에이전트 | 메인, 검수자 | 요구 ID별 상태 표, 변경 파일, 검증 명령과 종료 코드, 한계 | 반환 때 |

`NN`은 발주 순번 2자리다. `<name>`은 Agent `name`과 같다. `PROGRESS.md`는 짧게 유지한다. 해소된 `Do Not Repeat` 항목은 지우고 해소 위치를 Decisions Made에 남긴다.

메인이 `TASK.md`·`REFS.md`·`PROGRESS.md`·발주문을 직접 쓰는 것은 「메인은 Edit/Write를 위임한다」 원칙의 명시적 예외다. 이 문서들은 결정 내용 자체라서 서브에이전트에게 옮겨 쓰게 하면 낭비다. 훅은 메인의 직접 쓰기를 막지 않으므로 이 예외는 규약이다.

Write 도구가 없는 tier(`explorer-low`, `reviewer-high`, `judge-max`)는 `outputs/` 파일을 만들 수 없다. 제안: 이 세 tier의 반환은 메시지로 받고, 메인이 요구 ID별 판정을 `PROGRESS.md` 회차 행에 옮긴다. 이 제안은 D2의 「outputs는 서브에이전트가 쓴다」와 어긋나므로 메인 판정이 필요하다.

### 템플릿 골격

`new-task.sh`가 아래 골격으로 파일을 만든다. 골격 파일은 스킬 디렉터리의 `templates/`에 둔다.

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

### CONTRACT 줄

tier 호출의 prompt에는 아래 형식의 독립된 한 줄이 있어야 한다. 줄 앞뒤 공백과 탭은 허용한다.

```
CONTRACT: .delegate/<YYYYMMDD-slug>/orders/NN-<name>.md
```

- `<name>`은 Agent `name`과 같아야 한다.
- 파일 경로는 호출 시점의 작업 디렉터리 기준 상대 경로다.
- 훅은 형식과 이름 일치만 본다. 파일의 존재와 6칸 충족은 보지 않는다.

호출 예시:

```
Agent(subagent_type: "executor-high", model: "sonnet", effort: "high",
      name: "hook-b19-sonnet-high",
      prompt: "CONTRACT: .delegate/20261030-delegate-first-v2/orders/03-hook-b19-sonnet-high.md\n이 파일을 읽고 그 계약대로 수행한다. 반환은 outputs/03-hook-b19-sonnet-high.md에 쓴다.")
```

### 이름 규약

결정 사항이 아니라 현행 규칙이다. Agent `name`은 `<작업>-<model>-<effort>`로 짓고 두 토큰은 tier 핀과 같다(B-18). 이 규약에서 tier 6종 밖의 타입에는 `name`을 붙이지 않는다. 이 타입들은 발주문 파일을 쓰지 않는다.

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
| `.claude/hooks/enforce-subagent-model.cjs` | R | |
| `.claude/settings.json` | R | 훅 등록 |
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

훅은 `settings.json`의 `hooks.PreToolUse`에 matcher `Agent`로 등록돼 있을 때만 작동한다. 등록이 없으면 아래 훅 행은 규약이다.

| 규칙 | 강제 수단 | 강제 시점 | 우회(break-glass) |
|---|---|---|---|
| 모든 호출에 model·effort 명시 | 훅 | Agent 호출 | `ALLOW_INHERITED_SUBAGENT_MODEL=1`(사람 전용) |
| tier model 핀 일치(B-11) | 훅 | Agent 호출 | `ALLOW_TIER_MODEL_OVERRIDE=1`(사람 전용) |
| tier effort 핀 일치(B-12) | 훅 | Agent 호출 | `ALLOW_TIER_MODEL_OVERRIDE=1`(사람 전용) |
| tier 이름 필수, 그 밖 타입 이름 금지(B-18) | 훅 | Agent 호출 | 없음 |
| fork 사유 줄 | 훅 | Agent 호출 | 없음 |
| tier 발주문 `CONTRACT:` 줄(B-19, 제안) | 훅 | Agent 호출 | 제안: `ALLOW_NO_CONTRACT=1`(사람 전용) |
| tier 정의와 훅 map 일치 | `lint-delegate-first.py` Check A | 커밋 | 없음. `git commit --no-verify`는 사람 전용 |
| 위임 로그 7열 스키마 | `lint-delegate-first.py` Check B | 커밋 | 같음 |
| 훅 판정 회귀 | `scripts/smoke-hook.sh` | 커밋 | 같음 |
| smoke 음성 케이스의 비공허성(제안) | `scripts/test-smoke-nonvacuous.sh` 변이 게이트 | 커밋 | 같음 |
| 작업 쓰기 범위 | `close-task.sh`의 `git diff --name-only` 대조 | 작업 종료 | 없음. 사후 검사다 |
| 요구 ID 집합·증거·H 분류 금지·`[promote]` 승격 | `close-task.sh` | 작업 종료 | 없음 |
| 리뷰 트리거 충족 시 검수 행 존재 | `close-task.sh` | 작업 종료 | 없음 |
| 설치본 정합 | `scripts/test-reinstall.sh` | 커밋 | 같음 |

### close-task.sh

| 항목 | 내용 |
|---|---|
| 호출 | `close-task.sh <slug> [--dry-run]` |
| 종료 코드 | 0 통과, 1 검사 실패, 2 구조 오류 또는 잘못된 사용 |
| 출력 | 실패 한 건당 한 줄 `FAIL <검사명> <상세>` |
| 쓰기 범위 대조 | `git diff --name-only <기준 커밋>` 과 `git ls-files --others --exclude-standard`의 합집합이 `TASK.md` 쓰기 범위와 `.delegate/<slug>/**`에 속해야 한다 |
| 집합 일치 | `TASK.md` ID 집합, `PROGRESS.md` 최종 회차의 ID 집합, 검수 판정의 ID 집합이 같아야 한다 |
| 완료 | 모든 ID가 `done`이고 증거 칸이 비어 있지 않아야 한다 |
| 짝 검사 | 구현 tier 발주문마다 반환물이 있어야 한다. Write 없는 tier는 면제한다 |
| 시도 카운터 | `attempts_total`이 `max_attempts_total`을 넘지 않아야 한다 |
| `--dry-run` | 작업 도중 같은 검사를 실행해 보고 파일은 바꾸지 않는다 |

### B-19 적용 대상 결정안

B-19는 훅이 파일을 읽지 않는 무상태 검사다. 적용 대상은 아래 네 안이 있다.

| 안 | 내용 | 규칙과의 관계 | 영향 |
|---|---|---|---|
| A | 전역 훅이 tier 5종(`explorer-low` 면제)에 전면 적용 | D1·D4와 일치 | 다른 프로젝트에서 tier를 쓰려면 `.delegate/`가 필요해진다 |
| B | cwd에 `.delegate/`가 있을 때만 강제 | D4의 「파일을 읽지 않음」을 완화해야 한다 | 디렉터리를 만들지 않으면 강제가 꺼진다 |
| C | 프로젝트 훅 사본에만 적용 | D1(훅은 전역)에 어긋난다 | 전역 호출은 강제되지 않는다 |
| D | 환경변수로 프로젝트별 옵트인 | 무상태는 지키지만 | 변수 누락 시 조용히 꺼진다 |

권고는 A다. `explorer-low`는 읽기 전용 단건 조회이고 발주문 파일을 쓸 수 없는 tier라 면제한다.

A의 영향은 세 가지다.

- 설치되지 않은 프로젝트에서도 tier 호출이 차단된다. 차단 안내문이 `new-task.sh` 경로를 알려 준다.
- 다른 프로젝트의 기존 워크플로가 한 번 멈춘다. 전역 전파 전에 사용자가 영향 범위를 확인해야 한다.
- 우회는 사람 전용 `ALLOW_NO_CONTRACT=1` 하나다. 이 변수는 제안이며 B-18과 달리 우회 가능하게 둔다. 이유는 전역 적용의 사고 시 복구 수단이 필요해서다.

B, D는 조용한 비강제 경로가 생겨 P5에 어긋난다고 보아 제외한다.

### 변이 게이트

smoke의 음성 케이스는 훅의 차단 로직을 꺼도 통과할 수 있다. 재현: B-12 분기의 조건을 `false`로 바꾼 훅 사본에 `smoke-hook.sh <사본>`을 실행하면 104/104로 통과한다. 변이 게이트는 훅 사본에서 차단 분기를 하나씩 끈 변이본을 만들고, 각 변이본에 `smoke-hook.sh <변이본>`을 실행해 실패를 확인한다. 변이가 실제로 적용됐는지(치환 전후 diff)도 스크립트가 스스로 확인한다.

## 8. 위임하지 않는 경우

메인이 직접 하거나 하지 않는 경우를 정한다. 근거는 RI `integrated-insights.md` §2다. 저자의 자체 평가에서 단일 컨텍스트에 들어가는 작업은 위임 이득이 입증되지 않았다.

| 경우 | 처리 | 근거 |
|---|---|---|
| 단건 읽기, 단일 검증 명령 | 메인이 직접 한다 | 이 레포 `SKILL.md` §Principle |
| `TASK.md`·`REFS.md`·`PROGRESS.md`·발주문 작성 | 메인이 직접 쓴다 | 결정 D2의 예외 |
| 수정 없는 단건 조사 | `explorer-low`로 위임하고 발주문 파일은 쓰지 않는다 | B-19 면제 |
| 사용자 지시가 위임을 제한함 | 메인이 직접 한다. 필요한 독립 검수는 그 권한 안에서 구성한다 | HQ `docs/guides/hq-team/PORTING.md` 「실제 작업 방법」 끝 문장 |
| 쓰기 범위가 겹치는 레인 | 한 발주문에 묶거나 순차로 한다. 병렬 발주하지 않는다 | RI `insights-and-application.md` 「인사이트」 3항 |
| 소규모 문서 수정 | 구현 tier 1건과 재현 판정으로 끝낸다. 독립 검수는 리뷰 트리거가 걸릴 때만 붙인다 | HQ `governance/HQ-TEAM-OPERATING-CONTRACT.md` 항목 2 |
| 의사결정 자체 | 메인이 판정한다. 위임하지 않는다 | 규칙 원칙 1·4 |

그 밖의 구현·편집은 메인이 하지 않고 위임한다. 이 표는 위임 면제의 한도를 정할 뿐 면제를 넓히지 않는다.

## 9. 재구축 계획

단계마다 테스트를 먼저 쓰고 실패를 확인한 뒤 구현한다. 기계적 문서 편집은 예외다. 상향 기준(규칙 원칙 5)에 해당하는 단계는 없다고 판단해 구현 tier는 `executor-high`로 시작한다. P2·P6·P7은 실패 패스가 나오면 기준 ②로 `executor-max`에 올린다.

| 단계 | 내용 | 담당 | 완료 기준 | 검증 명령 |
|---|---|---|---|---|
| P0 | 기준선 확인 | `executor-med` | 네 검사가 모두 통과한다 | `bash scripts/smoke-hook.sh` · `bash scripts/test-lint.sh` · `python3 scripts/lint-delegate-first.py --strict` · `bash scripts/test-reinstall.sh` |
| P1 | `.gitignore`에 `.delegate/` 추가. 이 재구축의 작업 디렉터리 `.delegate/20261030-delegate-first-v2/`를 손으로 만든다 | `executor-med`(`.gitignore`), 메인(작업 문서) | 디렉터리가 추적되지 않는다 | `git check-ignore -v .delegate/20261030-delegate-first-v2/TASK.md`가 0으로 끝난다 · `git status --short`에 `.delegate`가 없다 |
| P2 | H1: 변이 게이트 `scripts/test-smoke-nonvacuous.sh`를 만들고 pre-commit에 등록한다 | `executor-high` | B-11·B-12·B-18·fork 분기를 끈 변이본이 각각 smoke 실패를 낸다. 정상 훅은 통과한다 | `bash scripts/test-smoke-nonvacuous.sh` · `grep -n test-smoke-nonvacuous .githooks/pre-commit` |
| P3 | M1: `ALLOW_TIER_MODEL_OVERRIDE=1` 경로에서 effort 부재가 통과하는 결함을 고친다. smoke 케이스를 먼저 추가한다 | `executor-high` | 신규 케이스가 수정 전 훅에서 실패하고 수정 후 통과한다 | `git show HEAD:.claude/hooks/enforce-subagent-model.cjs > /tmp/hook-old.cjs` 후 `bash scripts/smoke-hook.sh /tmp/hook-old.cjs`(실패 기대) · `bash scripts/smoke-hook.sh`(통과 기대) |
| P4 | M2: 「핀 없는 타입」을 「tier 6종 밖(훅이 핀을 모르는 타입)」으로 정정한다. 규칙 파일·BACKLOG·훅 안내문·README가 대상이다 | `executor-med` | 옛 표현이 남지 않는다. smoke가 안내문을 검사하면 같은 커밋에서 함께 고친다 | `grep -rn '핀 없는 타입' .claude BACKLOG.md README.md scripts` · `bash scripts/smoke-hook.sh` |
| P5 | M3: 규칙 파일 원칙 2 이력 블록과 `routing-matrix.md` 「★ 실측」의 named effort 서술을 관측 범위로 한정한다 | `executor-med` | 서술이 표본 수와 판별 불가 범위를 함께 적는다 | `grep -n 'named' .claude/rules/subagent-model-routing.md .claude/skills/delegate-first/references/routing-matrix.md` |
| P6 | B-19: 훅 케이스(smoke)를 먼저 쓰고 구현한다. 형식 불일치·이름 불일치·`explorer-low` 면제·정상 통과를 포함한다 | `executor-high` | smoke가 통과하고 변이 게이트가 B-19 변이본에서 실패한다 | `bash scripts/smoke-hook.sh` · `bash scripts/test-smoke-nonvacuous.sh` |
| P7 | `new-task.sh`·`close-task.sh`와 샌드박스 테스트 `scripts/test-delegate-scripts.sh` | `executor-high` | 임시 git 저장소에서 정상·쓰기 범위 위반·집합 불일치·H 참조·미승격 케이스가 각각 기대 종료 코드를 낸다. 각 케이스가 실제로 실패를 재현한다 | `bash scripts/test-delegate-scripts.sh` · `bash .claude/skills/delegate-first/scripts/new-task.sh x-test` |
| P8 | 템플릿 5종을 스킬 `templates/`에 만든다 | `executor-med` | `new-task.sh`가 5종으로 디렉터리를 만든다 | `bash scripts/test-delegate-scripts.sh` |
| P9 | `SKILL.md` 체크리스트에 「발주 작성」 단계를 더한다. `routing-matrix.md`·`prompt-templates.md`를 6칸과 `CONTRACT:` 줄로 갱신한다 | `executor-high` | 세 문서가 §4와 같은 칸 구성을 말한다 | `python3 scripts/lint-delegate-first.py --strict` · `grep -n 'CONTRACT' .claude/skills/delegate-first/SKILL.md .claude/skills/delegate-first/references/*.md` |
| P10 | 규칙 파일에 발주 계약 원칙을 더하고 강제 장치 절에 B-19를 적는다 | `executor-high` | 규칙 파일이 B-19와 우회 변수를 말한다. 항목별 diff 검토를 거친다 | `git diff .claude/rules/subagent-model-routing.md` |
| P11 | README 호출 규약 절과 작업 디렉터리 절을 갱신한다. `docs/decisions.md`를 신설해 D1~D7을 `DEC-NNN`으로 올린다. `BACKLOG.md`에 B-19 항목을 더하고 미룬 항목에 「재개 조건」을 보강한다 | `executor-med` | 세 파일이 서로 모순되지 않는다 | `grep -n 'B-19' README.md BACKLOG.md` · `grep -c '| active |' docs/decisions.md` |
| P12 | 문서 검사: `doc-refine` 흐름(검토 → 개선안 승인 → 적용)을 README·청사진·판정표에 돌린다. 지침 파일은 항목별로 diff를 검토한다 | `doc-reviewer`, `executor-med` | 지적 건수·적용 건수·보류 사유가 보고된다 | `~/.claude/rules/doc-writing.md`의 완료 조건 |
| P13 | 독립 적대 리뷰. 훅·scripts·.githooks 변경이 있으므로 보안 트리거로 필수다 | `reviewer-high` | 미해소 H가 0이다 | 리뷰 보고서의 H 목록과 재현 명령 |
| P14 | 이 재구축을 `close-task.sh`로 닫는다. 작업 문서는 P1에서 손으로 만든 것을 쓴다 | 메인 | 종료 코드 0. 쓰기 범위 대조에 위반이 없다 | `bash .claude/skills/delegate-first/scripts/close-task.sh 20261030-delegate-first-v2` |
| P15 | fable 출하 게이트 | `judge-max` | 판정이 MERGE 계열이다 | 판정문 |
| P16 | `CHANGELOG.md`와 `docs/release/v2.md`를 쓴다 | `executor-med` | 두 파일이 승격 대상 변경을 모두 담는다 | `python3 scripts/lint-delegate-first.py --strict` · `git diff --stat` |
| P17 | 승인 뒤 commit·push·PR을 낸다. 머지는 사용자가 한다. 전역 전파는 훅 → 규칙 → 실측 → 재설치 순서(BACKLOG B-08 절차)로 한다 | 메인과 사용자 | push 뒤 원격 SHA가 로컬 HEAD와 같다. 전역 사본이 정본과 같다 | `git ls-remote origin <브랜치>` · `cmp .claude/hooks/enforce-subagent-model.cjs ~/.claude/hooks/enforce-subagent-model.cjs` |
| P18 | 측정 기록: 재설명 횟수·누락 요구·재요청·시간·토큰을 이 작업의 `PROGRESS.md`에 남긴다 | 메인 | 항목마다 값 또는 「계측 수단 없음」이 적힌다 | `PROGRESS.md` 확인 |

P7의 `close-task.sh`는 틀리면 게이트가 조용히 열리는 스크립트다. 규칙 원칙 5 기준 ①에 해당하는지는 메인이 판정한다.

## 10. 미검증·위험

| # | 항목 | 내용 | 확인 방법 |
|---|---|---|---|
| 1 | 호출자 식별자 | PreToolUse 입력에 호출자(메인인지 서브에이전트인지)를 구별할 값이 있는지 확인하지 않았다. B-19는 호출자와 무관하게 적용한다는 전제로 설계했다 | 훅이 받는 stdin JSON 전체를 기록해 필드를 확인한다 |
| 2 | Bash 경유 쓰기 | 훅은 Agent 호출만 본다. tier 서브에이전트가 Bash로 쓰기 범위 밖 파일을 바꾸는 것은 종료 시 diff로만 잡힌다. 사후 탐지이고 차단이 아니다 | P7 샌드박스 테스트에서 범위 밖 변경을 재현한다 |
| 3 | diff의 사각지대 | `git diff --name-only`는 gitignore된 파일과 레포 밖 쓰기를 보지 못한다. 이름 변경과 기준 커밋 이후의 커밋은 별도 확인이 필요하다 | 같은 테스트에 ignored 파일 케이스를 추가한다 |
| 4 | 저자 수치 | MetaEnsemble 자체 평가 수치는 저자 평가이고 이 레포에서 재현하지 않았다. 설계 근거로 쓰지 않았다 | 재현 계획 없음 |
| 5 | 효과 미측정 | 재설명·재요청 감소와 토큰 증가는 측정 전 가설이다. 모든 tier 호출에 발주문 파일을 강제하는 비용이 작은 작업에서 이득을 넘을 수 있다 | P18 측정. 효과가 없으면 규칙을 줄인다 |
| 6 | B-19의 형식 한계 | 훅은 존재하지 않는 파일을 가리키는 `CONTRACT:` 줄도 통과시킨다. 짝 검사는 `close-task.sh`가 사후에 한다 | P7에서 위장 줄 케이스를 확인한다 |
| 7 | Write 없는 tier의 반환물 | `reviewer-high`·`judge-max`·`explorer-low`는 `outputs/` 파일을 만들 수 없다. D2와 충돌하며 §3의 제안이 메인 판정을 기다린다 | 메인 판정 |
| 8 | worktree 시드 | gitignore된 디렉터리가 worktree에 없다. 시드 옵션과 반환물 복사 절차를 구현하거나 실측하지 않았다 | P7 범위에 시드 케이스를 넣을지 메인이 판정한다 |
| 9 | 스크립트 실행 권한 | 스킬 디렉터리의 스크립트가 `reinstall.sh`의 `cp -R` 뒤에도 실행 비트를 유지하는지 확인하지 않았다 | `test-reinstall.sh`에 모드 확인 케이스를 더한다 |
| 10 | 훅 강제의 실효 | 공식 사양상 차단되는 PreToolUse 동작이 현장에서 무시된다는 보고가 있다(RY `REPORT.md` §5 경고 1). Stop 훅의 연속 차단 상한은 Stop 훅 한정이라 이 설계에 직접 걸리지 않는다. 그래도 하네스 경로의 end-to-end 실측은 smoke가 대신하지 못한다 | 전파 뒤 B-08의 4단계 실측을 B-19에도 적용한다 |
| 11 | tier 6종 밖 타입의 이름 처리 | 정의에 핀이 있지만 tier 6종 밖인 타입(`doc-reviewer` 등)에 이름을 붙이면 레포 훅이 exit 2로 차단한다(입력 재현). 전역 훅 사본에는 B-18이 없다(grep 0건). 이름 붙은 `doc-reviewer` 호출이 통과한 경위는 이 차이로 추정하고 실측하지 않았다. M2의 정정 방향도 이 타입의 처리 규칙을 정해야 닫힌다 | 전역 전파 전후에 같은 입력으로 비교한다 |
| 12 | 메인 직접 쓰기 예외 | D2의 직접 쓰기 예외는 훅이 막지 못하는 규약이다. 범위를 넘는 직접 쓰기는 사람이 발견해야 한다 | 위임 로그와 diff 대조 |
| 13 | 활성 결정 색인의 부패 | `docs/decisions.md`가 실제 규칙과 어긋나도 잡는 검사가 없다. `close-task.sh`는 `[promote]` 누락만 본다 | 색인 항목의 근거 경로 존재를 lint에 더할지 메인이 판정한다 |
| 14 | 전역 전파의 영향 | 훅·규칙 전파는 모든 프로젝트의 tier 호출에 영향을 준다. 설치되지 않은 프로젝트의 워크플로가 멈춘다 | §7의 A안 영향 3항을 사용자에게 보이고 승인을 받는다 |
| 15 | tier 밖 타입의 계약 우회 | B-19는 tier 호출만 본다. `general-purpose`·`codex:*`·`oh-my-claudecode:*` 호출은 발주문 없이 나간다. 계약 없는 위임 경로가 남는다 | tier 밖 타입의 사용 조건을 `routing-matrix.md`의 out-of-table 절차와 맞출지 메인이 판정한다 |
