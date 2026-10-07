# Routing Matrix

## Contents
- Task type → model → effort → execution path → tier agent
- Execution path constraints (Agent tool / Workflow `agent()` / `codex exec`)
- Fallback rules for cases not covered by the table (표 밖 에이전트 타입 호출 시 판단 절차 포함)
- fork와 컨텍스트 크기 (실행 경로 ① 하위 소절: fork 사용 조건 · 대형 파일 레인 · opus 상향 · 서브에이전트 model 제약)

## Table

| 작업 유형 | 권장 모델 | effort | 실행 경로 | tier 에이전트 |
|---|---|---|---|---|
| 탐색·추출 (파일 검색, grep, 단순 집계) | haiku / sonnet | low~medium | Agent 툴 | `explorer-low` |
| 문서 편집·구조화 | sonnet | medium | Agent 툴 | `executor-med` |
| 일반 구현 | sonnet | medium~high | Agent 툴 또는 Workflow `agent()` | `executor-med`(medium) / `executor-high`(high) |
| 리뷰 1차 | sonnet | medium | Agent 툴 | 정확 매치 없음 — 낮은 리스크면 `executor-med`로 첫 패스, 결과가 걸리는 리뷰면 `reviewer-high`로 상향 |
| 적대 검증·판정 | opus / fable | high~max | Workflow `agent()` (effort 필요) 또는 Agent 툴(tier 에이전트 사용 시) | `reviewer-high`(opus) / `judge-max`(fable, 5종 트리거 해당 시) |
| 아키텍처·법·돈·권한·보안 | fable | max | Workflow `agent()` 또는 Agent 툴(tier 에이전트 사용 시) | `judge-max` |
| fork — 대화 맥락 자체가 입력인 곁가지 작업 | 세션 모델(지정 불가) | 세션 값(문서 미명시) | Agent 툴 `subagent_type: fork` + prompt에 `FORK_REASON: conversation-context` 한 줄 | 없음 — 대형 파일 구현은 `executor-high` |

보안 키워드가 걸린 탐색 서브에이전트는 위 표의 "탐색·추출"이라도 Hard(opus 이상)로 상향한다 — 이 경우 `explorer-low`를 쓰지 않는다.

릴리스 게이트 최종 판정은 fable(`judge-max`, 메인이 fable이면 메인)이 한다 — 1차 증거 수집은 `reviewer-high` 가능(2026-10-07 사용자 확정).

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

### fork와 컨텍스트 크기
- (a) fork는 **대화 맥락 자체가 입력일 때만** 쓴다. 컨텍스트 크기 우회나 모델 상향 수단으로는 금지 — fork는 세션 모델로 돌고 `model` override는 무시된다("always runs on your model — a `model` override is ignored", 2026-10-06 세션 Agent 툴 설명). 훅은 prompt에 `FORK_REASON: conversation-context` 한 줄이 없으면 exit 2로 차단한다. 통과 시 훅이 stderr에 쓰는 "effective model = 세션 모델"은 exit 0의 stderr라 debug log에만 가고 Claude는 보지 못한다("Stderr from a hook that exits 0 goes to the debug log only, never the transcript, and Claude never sees it" — https://code.claude.com/docs/en/hooks, 확인 2026-10-06) — 그래서 위임 로그 model 칸에 effective model을 직접 적는다.
- (b) 대형 파일 레인 = `executor-high` + 파일 1개·함수 단위 분할 + 부분 Read·줄 예산 명시 ([prompt-templates.md](prompt-templates.md) Template 3).
- (c) 같은 레인이 같은 원인으로 2회 실패하면 opus로 상향한다(프롬프트 강화 동반, [SKILL.md](../SKILL.md) 에스컬레이션 사다리). opus 쓰기 tier가 없으므로 Workflow `agent()`(opus, effort 지정)를 쓴다. Workflow `agent()`를 쓸 수 없으면 사용자에게 보고한다(effort 미고정 즉석 호출로 대신하지 않는다).
- (d) 서브에이전트 model 제약 (모두 확인일 2026-10-06):
  - Agent 툴 호출 `model` 파라미터 허용값은 별칭 4종 `haiku`·`sonnet`·`opus`·`fable`(툴 스키마 enum).
  - frontmatter `model`: "`sonnet`, `opus`, `haiku`, `fable`, a full model ID such as `claude-opus-5-5`, or `inherit`" — https://code.claude.com/docs/en/sub-agents#supported-frontmatter-fields . Full model ID는 "Accepts the same values as the `--model` flag" — https://code.claude.com/docs/en/sub-agents#choose-a-model
  - `--model`은 `[1m]` 접미사를 받는다(https://code.claude.com/docs/en/model-config). 그러나 frontmatter에 `[1m]`을 직접 넣는 경우는 문서 명시도 실측도 없다 — **미실측**.
  - 창 크기: "a subagent's context window is sized by its own model, not the parent's. Delegating to a model with a smaller window gives that subagent the smaller window." — https://code.claude.com/docs/en/sub-agents
  - "On the Anthropic API, Fable 5.1, Fable 5, Sonnet 5 and later, and Opus 4.7 and later run with the 1M window on every plan" — https://code.claude.com/docs/en/model-config#extended-context. 따라서 Anthropic API 직결 + 현행 모델에서는 sonnet/opus 서브에이전트도 1M 창이라 "1M이 필요해서 fork"는 근거가 없다. 게이트웨이·타 프로바이더·구모델은 다를 수 있다 — 그 환경에서 재확인.
  - family alias 예외: 메인 모델이 같은 family면 별칭이 메인의 정확한 모델(`[1m]` 접미사 포함)로 해석된다 — https://code.claude.com/docs/en/sub-agents#choose-a-model
  - fork 정의: "A fork is a subagent that inherits the entire conversation so far ... a fork sees the same system prompt, tools, model, and message history as the main session"; 비교표 Model 행 "Same as main session" — https://code.claude.com/docs/en/sub-agents#fork-the-current-conversation

### ② Workflow `agent()`
- `model` + `effort`(`'low'`~`'max'`) 모두 지정 가능.
- tier 에이전트로 커버되지 않는 조합, 또는 세션 종류가 Agent 툴을 지원하지 않을 때 이 경로로 effort를 직접 지정한다.

### ③ `codex exec`
- OpenAI 계열 전용 실행 경로. `codex exec -m <모델> -c model_reasoning_effort=<강도>`.
- 네트워크가 필요하면 `-c sandbox_workspace_write.network_access=true`를 추가한다.
- git 조작(커밋·푸시·브랜치 전환)은 샌드박스 제약이 있다 — 위임 전에 해당 세션의 git 권한 범위를 확인한다.

## 포함 안 되는 케이스 폴백 규칙

### 표 밖 에이전트 타입 — 호출 시 판단 절차

스킬 호출 시 메인이 표에 없는 `subagent_type`(내장·플러그인·프로젝트 정의)을 쓰려 하면, 매번 아래 절차로 판단한다.

1. **정의 확인** — 그 에이전트 정의 frontmatter의 `model`·`effort`·쓰기 도구(`tools`/`disallowedTools`) 여부를 읽는다. 정의 위치 우선순위는 공식 표를 따른다: Managed settings > `--agents` CLI 플래그 > 프로젝트 `.claude/agents/`(중첩 시 작업 디렉터리에 가장 가까운 것) > 사용자 `~/.claude/agents/` > 플러그인(`<플러그인>:<이름>` 이름공간). 같은 이름의 사용자·프로젝트 정의는 내장도 override한다(https://code.claude.com/docs/en/sub-agents). 내장은 같은 문서의 "Built-in subagents". 플러그인 활성 버전은 `~/.claude/plugins/installed_plugins.json`의 해당 플러그인 `installPath`로 판정하고(예: `jq '.plugins["<플러그인>@<마켓>"][].installPath' ~/.claude/plugins/installed_plugins.json`), `settings.json`의 `enabledPlugins`에서 활성 여부를 확인한다. 쓰기 도구 판정: Write/Edit/NotebookEdit 또는 Bash가 있으면 쓰기 가능으로 본다. 이 도구 판정은 표 밖 후보에만 적용한다 — tier 리뷰어 `reviewer-high`·`judge-max`는 Bash가 남아 도구상 읽기 전용이 아니며, 읽기 전용은 위임 프롬프트의 경계 계약으로 지킨다. 확인 못 하면 "미고정"으로 취급한다(추측 금지). 참고: general-purpose의 model은 `CLAUDE_CODE_SUBAGENT_MODEL`이 없으면 메인 모델을 상속한다.
2. **필요값 결정** — 작업을 위 표의 작업 유형 행에 대응시켜 필요한 model·effort를 정한다. 도구 범위도 맞춘다(읽기 전용 작업에 쓰기 가능 에이전트를 쓰지 않는다 등). 작업이 SKILL.md fable 강제 트리거나 보안 키워드 상향(위 표 아래 문단)에 해당하면 타입 이름과 무관하게 그 경로(`reviewer-high` 1차 증거 / fable 최종 판정, 또는 opus 이상)를 따른다.
3. **경로 결정** — 먼저 effort 고정 여부를 본다. 정의에 `effort`가 없으면 세션 effort를 물려받으므로(이 PC에 설치된 플러그인 에이전트 정의 81개 중 고정 0개, 2026-10-07 실측 — 현재는 사실상 전부 해당) 전역 규칙('effort가 고정된 정의가 있는 타입으로만 위임')에 따라 그 타입에는 위임하지 않고, 같은 작업 유형의 tier 에이전트(탐색은 `explorer-low`) 또는 Workflow `agent()`(model+effort 지정)로 대체한다. 원래 에이전트의 전문 체크리스트가 필요하면 그 정의 파일 경로를 위임 프롬프트에 넘겨 읽게 한다. effort가 고정된 표 밖 타입만 직접 호출하며, 이때 2단계의 필요 model을 `model` 파라미터로 항상 명시한다 — 호출 파라미터가 정의 frontmatter보다 우선하고(sub-agents 'Choose a model'), 대부분의 표 밖 타입은 훅의 pinned 목록에 없어 `model`을 생략하면 등록된 훅에서 차단될 수 있다.
4. **기록** — 위임 로그 effort 칸은 고정값, 또는 세션 상속이면 `(default)`([SKILL.md](../SKILL.md) 3번과 동일), model 칸은 [SKILL.md](../SKILL.md) Step 3 관례(`<요청> → <effective>`). 애매하면 비싼 쪽으로 반올림한다(아래 2번 규칙).

정적 매핑표를 두지 않는 이유: 설치된 플러그인·버전이 PC마다 다르므로 매번 정의를 읽는다.

위 표·tier 에이전트 어느 쪽에도 정확히 맞지 않는 작업이 나오면:

1. **티어 밖 조합** — Workflow `agent()`로 모델·effort를 직접 지정하는 범용 폴백을 쓴다. 5개 tier 에이전트에 없는 모델·effort 조합을 억지로 끼워 맞추지 않는다.
2. **완전히 새로운 유형** — 오류 비용(틀렸을 때 되돌리는 비용) × 탐색 공간(고려할 변수 수)으로 즉석 판정한다. 애매하면 **반올림은 위로**(더 비싼 쪽으로) 한다. 판정 직후 이 표에 행을 수기로 즉시 추가한다 — 다음에 같은 유형이 나오면 재판정하지 않는다.
3. **불확실하고 고위험** — SKILL.md의 fable 강제 트리거 5종에 해당하는지 먼저 확인해 승격하거나, 그래도 애매하면 사용자에게 직접 묻는다. 추측으로 낮은 티어에 배정하지 않는다.
