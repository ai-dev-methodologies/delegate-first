# Routing Matrix

## Contents
- Task type → model → effort → execution path → tier agent
- Execution path constraints (Agent tool / Workflow `agent()` / `codex exec`)
- Fallback rules for cases not covered by the table

## Table

| 작업 유형 | 권장 모델 | effort | 실행 경로 | tier 에이전트 |
|---|---|---|---|---|
| 탐색·추출 (파일 검색, grep, 단순 집계) | haiku / sonnet | low~medium | Agent 툴 | `explorer-low` |
| 문서 편집·구조화 | sonnet | medium | Agent 툴 | `executor-med` |
| 일반 구현 | sonnet | medium~high | Agent 툴 또는 Workflow `agent()` | `executor-med`(medium) / `executor-high`(high) |
| 리뷰 1차 | sonnet | medium | Agent 툴 | 정확 매치 없음 — 낮은 리스크면 `executor-med`로 첫 패스, 결과가 걸리는 리뷰면 `reviewer-high`로 상향 |
| 적대 검증·판정 | opus / fable | high~max | Workflow `agent()` (effort 필요) 또는 Agent 툴(tier 에이전트 사용 시) | `reviewer-high`(opus) / `judge-max`(fable, 5종 트리거 해당 시) |
| 아키텍처·법·돈·권한·보안 | fable | max | Workflow `agent()` 또는 Agent 툴(tier 에이전트 사용 시) | `judge-max` |

보안 키워드가 걸린 탐색 서브에이전트는 위 표의 "탐색·추출"이라도 Hard(opus 이상)로 상향한다 — 이 경우 `explorer-low`를 쓰지 않는다.

tier 에이전트 정의(`.claude/agents/*.md`)는 각 5종을 [SKILL.md](../SKILL.md)의 흐름과 연결한다: `explorer-low`(haiku/low, 읽기전용) · `executor-med`(sonnet/medium) · `executor-high`(sonnet/high) · `reviewer-high`(opus/high, Write/Edit 제외) · `judge-max`(fable/max, Write/Edit 제외, SKILL.md의 fable 강제 트리거 5종 전용).

## 실행 경로 3종

### ① Agent 툴
- 즉석 호출(`subagent_type`을 범용 에이전트로 지정)은 `model`만 지정 가능하고 effort는 지정 불가(기본값 사용).
- **tier 에이전트를 `subagent_type`으로 지정하면 예외다** — `.claude/agents/*.md` frontmatter에 `model`+`effort`가 이미 박혀 있어, Agent 툴 호출만으로 그 조합이 그대로 적용된다(예: `subagent_type: judge-max` → fable/max). effort가 필요한 작업은 우선 tier 에이전트가 있는지부터 확인한다. **전제**: 이 예외는 훅(`enforce-subagent-model.cjs`)의 `MODEL_PINNED_TYPES`에 그 tier 에이전트가 실제로 등록돼 있을 때만 성립한다 — 등록돼 있지 않으면 `model` 없는 호출은 exit 2로 차단되고, 우회로 `model`을 넘기면 호출 파라미터가 frontmatter의 `model`을 덮어써(`effort`·`tools`·`disallowedTools`는 유지) "pinned 조합 그대로"가 깨진다.
- 범용 위임 — 탐색·구현·리뷰 1차 대부분은 이 경로로 충분하다.
- 핀 누락으로 차단되면 폴백은 훅 stderr의 일반 안내가 아니라 **그 tier의 frontmatter model 값(위 표/문단의 값)을 그대로 명시**하는 것이다. 다른 값을 넘기면(B-11) 그 tier의 고정값과 정확히 일치하지 않는 한 훅이 exit 2로 **차단**한다 — 더 이상 조용한 강등이 아니다. 의도적 override는 사람 전용 break-glass `ALLOW_TIER_MODEL_OVERRIDE=1`이 필요하다.
- 등록된 훅이 여러 벌이면(전역·프로젝트) 모두 실행되고 그중 하나라도 차단하면 전체가 차단된다 — 실행 순서는 확인되지 않았으므로 전역·프로젝트 사본을 모두 갱신해야 한다.
- **★2026-08-18 실측**: `name` 파라미터를 동반한 named 스폰은 model은 frontmatter가 그대로 적용되지만 **effort는 frontmatter 값이 적용되지 않는다**(관측: `executor-med`의 medium 정의가 high로, `explorer-low`+override의 low 정의가 max로 나옴). effort가 결과를 좌우하는 위임에는 `name`을 붙이지 말 것 — 붙여야 한다면 effort를 직접 지정 가능한 경로(Workflow `agent()` 등)를 쓴다. haiku 계열은 transcript에 effort 키 자체가 없어 적용 여부 판정 불가. `low→max`(`explorer-low`) 관측은 model override가 동반돼 혼입 가능성이 있다 — **override 없는 clean 표본은 `executor-med`(medium→high) 1건뿐**이다.
  - `explorer-low`+override 관측은 **B-11(값 검증 훅) 도입 이전**에 수집됐다. B-11 이후 같은 프로브(model에 다른 값을 넘겨 explorer-low를 호출)를 재현하려면 그 호출 자체가 값 불일치로 차단되므로 `ALLOW_TIER_MODEL_OVERRIDE=1`이 필요하다 — 재현 불가는 증거 조작이 아니라 이 값 검증 게이트가 의도대로 작동한다는 뜻이다.

### ② Workflow `agent()`
- `model` + `effort`(`'low'`~`'max'`) 모두 지정 가능.
- tier 에이전트로 커버되지 않는 조합, 또는 세션 종류가 Agent 툴을 지원하지 않을 때 이 경로로 effort를 직접 지정한다.

### ③ `codex exec`
- OpenAI 계열 전용 실행 경로. `codex exec -m <모델> -c model_reasoning_effort=<강도>`.
- 네트워크가 필요하면 `-c sandbox_workspace_write.network_access=true`를 추가한다.
- git 조작(커밋·푸시·브랜치 전환)은 샌드박스 제약이 있다 — 위임 전에 해당 세션의 git 권한 범위를 확인한다.

## 포함 안 되는 케이스 폴백 규칙

위 표·tier 에이전트 어느 쪽에도 정확히 맞지 않는 작업이 나오면:

1. **티어 밖 조합** — Workflow `agent()`로 모델·effort를 직접 지정하는 범용 폴백을 쓴다. 5개 tier 에이전트에 없는 모델·effort 조합을 억지로 끼워 맞추지 않는다.
2. **완전히 새로운 유형** — 오류 비용(틀렸을 때 되돌리는 비용) × 탐색 공간(고려할 변수 수)으로 즉석 판정한다. 애매하면 **반올림은 위로**(더 비싼 쪽으로) 한다. 판정 직후 이 표에 행을 수기로 즉시 추가한다 — 다음에 같은 유형이 나오면 재판정하지 않는다.
3. **불확실하고 고위험** — SKILL.md의 fable 강제 트리거 5종에 해당하는지 먼저 확인해 승격하거나, 그래도 애매하면 사용자에게 직접 묻는다. 추측으로 낮은 티어에 배정하지 않는다.
