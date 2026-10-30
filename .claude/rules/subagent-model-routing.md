# 서브에이전트 모델 라우팅 강제 (전 프로젝트, 2026-07-16 사용자 확정)

메인 세션이 고비용 모델(Fable 5 / Opus, max 추론)일 때의 **강제 규칙**:

## 원칙
1. **메인 세션은 결정·방향·판정 종합 전용이다.** 구현, 테스트 실행/수정, 탐색,
   문서 초안 등 실행 작업은 서브에이전트에 위임한다.
2. **모든 Agent(서브에이전트) 호출은 `model`을 명시한다 — 세션 모델 상속 금지.**
   추론강도(effort)를 지원하는 경로(Workflow `agent()` 등)에서는 effort도 명시한다.
   - (원칙 5로 폐지됨. 아래는 이력·하네스 동작 설명이다)
     **예외**: frontmatter에 `model`이 고정된 tier 에이전트를 `subagent_type`으로
     지정하는 호출은 `model` 생략이 원칙이었다 — 세션 상속이 아니라 정의값을
     쓰므로 규칙 목적(상속 금지)을 위반하지 않는다. 값을 명시하면 그 tier의
     고정값과 **정확히 일치**해야 통과하고, 불일치는 **exit 2 차단**이다(B-11).
     이 예외는 **등록된 모든 훅 사본**의 pinned 목록에 그 tier가 있을 때만
     성립하며, delegate-first **tier 6종**에 한한다 — 동명 에이전트는
     frontmatter 핀을 **직접 확인하기 전에는** 원칙(명시)대로 한다.
     `tools`·`disallowedTools`는 유지되고, `effort`는 일반 스폰에서만
     유지되며 named 스폰에서는 유지되지 않는다. 증거 상세는
     `~/.claude/skills/delegate-first/references/routing-matrix.md` §① 참조.
   - **fork 예외**: `subagent_type: fork`는 세션 모델과 대화 맥락 전체를 상속하고 `model`을 무시한다. 대화 맥락 자체가 입력일 때만 prompt에 한 줄 `FORK_REASON: conversation-context`를 넣어 쓴다 — 훅은 토큰이 없으면 model 유무와 무관하게 exit 2로 차단하고 어떤 break-glass로도 우회되지 않는다. 컨텍스트 크기 우회·모델 상향 목적 금지(`~/.claude/skills/delegate-first/references/routing-matrix.md` §fork와 컨텍스트 크기). 2026-10-06 사용자 요청으로 도입.
3. 라우팅 기준 (글로벌 CLAUDE.md OMO 정책과 동일):
   - 탐색·파일검색·단순집계·기계적 편집 → `haiku`/`sonnet`
   - 일반 구현·보통 디버깅·리뷰 1차·문서 구조화 → `sonnet`
   - 적대판정·batch-audit·돈·권한·동시성·보안 → `opus`
   - release-gate 최종 판정 → `fable`(1차 증거 수집은 opus 가능, 2026-10-07 사용자 확정)
   - delegate-first 스킬 호출 중에는 SKILL.md의 fable 강제 트리거 5종(적대 검증·돈·권한·보안 등)이 위 opus 기준보다 우선한다(2026-10-07 사용자 확정).
   - 라벨링·생성 "품질" 작업은 다운시프트 금지 (2026-07-15 확정 유지)
4. 판정·종합·보고는 메인이 한다. 서브에이전트 결과를 메인이 재검하지 않고
   그대로 신뢰하지 말 것(독립 검증 게이트는 별도 opus 에이전트 — release-gate 최종 판정은 fable).
5. 이름·상향·대조(2026-10-30 사용자 지시):
   - **tier도 생략 금지(원칙 2의 「생략이 원칙」 예외를 폐지)**: 모든 Agent 호출은 `model`과 `effort`를 명시하고, tier는 frontmatter 핀과 같은 값을 적는다. 이유: 세션 중에 추가된 정의를 하네스가 아직 모르면 pinned 목록만 보고 통과한 호출이 세션 모델·effort를 상속한다(2026-10-30 실측: `executor-max` 첫 스폰 → fable·xhigh). 훅이 model·effort 부재와 tier 값 불일치(B-11·B-12)를 exit 2로 차단한다. 「fallback으로 메인 세션을 상속하게 두지 않는다」가 원칙이다.
   - **이름 규약**: Agent `name`은 `<작업>-<model>-<effort>`로 짓는다(예 `k289rr-opus-high`). CLI 서브에이전트 화면·ListAgents는 메인 세션의 model·effort를 보여 주므로 이름으로 즉시 보이게 한다. 토큰 값은 실제 적용값(tier면 frontmatter 핀, 비핀이면 호출 인자)과 같아야 한다. 훅은 이름을 강제하지 않는다. `close-task.sh`는 작업 종료 때 `orders/NN-<name>.md` 발주문 파일 이름의 토큰 형식과 `- tier:` 핀 일치만 검사한다. 실제 Agent `name` 인자와의 대조와 핀 없는 타입의 이름 금지는 기계 검사가 없고 「반환 뒤 대조」(전사 확인)가 맡는다.
   - **핀 없는 에이전트는 이름 없이 띄운다**: frontmatter에 model·effort 핀이 없는 타입(`codex:*`·`oh-my-claudecode:*`·`general-purpose` 등)은 `name`을 붙이면 호출 `effort`가 유실되어 세션값을 상속한다(2026-10-30 전사 실측 2건: 호출 low → 실제 xhigh). 이름이 필요하면 핀 tier를 쓴다.
   - **상향 경로**: 구현 기본은 `executor-high`(sonnet·high)다. 다음 중 하나면 `executor-max`(opus·high)로 올리고 발주문 「발주 정보」에 `- 상향 근거: <기준 번호>` 1줄을 적는다. ① 여러 모듈에 걸친 드라이버·게이트 상태 전이 변경(틀리면 게이트가 조용히 열리거나 모든 단계가 막힘) ② 같은 WU의 수정 패스가 한 번 실패한 뒤의 재수정 ③ 검수 H가 설계 결함(배선 누락·경계 오판)으로 나온 뒤의 수정 ④ 원칙 3의 opus 행(돈·권한·동시성·보안)에 해당하는 구현. 기준에 해당하지 않으면 상향하지 않고, 사용자에게 상향 여부를 묻지 않는다. `executor-max`에서도 같은 원인으로 다시 실패하면 더 올릴 쓰기 tier가 없으므로 프롬프트를 보강하거나 작업을 쪼개 재위임하고, 그래도 실패하면 사용자에게 보고한다.
   - **반환 뒤 대조**: 서브에이전트 반환마다 전사(`subagents/agent-*.meta.json`의 `model`, `.jsonl` assistant 레코드의 `effort`·`message.model`)로 이름 토큰과 실제값을 대조한다. 불일치는 구조 이슈로 기록하고 원인(핀 드리프트·named 상속)을 닫은 뒤 다음 발주를 낸다. `meta.json`의 `model`은 요청값 기록이라 실제값은 `.jsonl`로 판정하고, haiku처럼 `effort` 키가 없는 레코드는 불일치가 아니라 「effort 판정 불가」로 적는다.

## 강제 장치
> ⚠️ **훅은 delegate-first 스킬을 호출한 세션에서만 켜진다.** 아래 훅은 `SKILL.md` frontmatter `hooks`(PreToolUse, matcher `Agent`)로 등록되며 레포 `settings.json` 등록은 없다. 이 등록은 같은 프로세스의 `/compact` 뒤에는 유지되지만 `claude --resume` 뒤에는 꺼진다. 재개 세션은 전역 `~/.claude/settings.json`에 등록한 resume 백스톱(`hooks/resume-backstop.cjs`)이 지킨다. 백스톱은 전사에 `/delegate-first` 호출 기록이 있을 때만 같은 훅을 실행한다. 스킬을 호출하지 않은 세션에는 자동 강제가 없고, 아래 서술은 모델이 지키는 규약이다. OMC `pre-tool-enforcer.mjs`의 model-routing deny 분기는 Bedrock/Vertex/프록시 환경 전용이라 표준 Anthropic 계정에서는 대신하지 못한다.

- PreToolUse 훅 `.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs` (matcher: Agent)가
  `model`·`effort` 미지정 호출과 tier 핀 불일치(B-11 model·B-12 effort)를 exit 2로
  차단한다. 훅 command는 `${CLAUDE_PROJECT_DIR}` 기반이며 스크립트나 node가
  없으면 exit 2로 막는다(fail-closed). 생략을 허용하는 타입은 `statusline-setup`(빌트인, 기대값 미상) 하나뿐이다
  (`OMIT_ALLOWED_TYPES`). pinned 목록(`MODEL_PINNED_TYPES`: delegate-first tier 6종:
  explorer-low·executor-med·executor-high·executor-max·reviewer-high·judge-max +
  `oh-my-claudecode:*` 계열 7종 + `statusline-setup`)은 차단 안내문과 lint 대조에만
  쓰이고 통과 여부를 정하지 않는다. 목록이 `.claude/agents/`와 갈라지지
  않게 **정본 레포 사본에 한해** `scripts/lint-delegate-first.py`가 대조
  검사한다 — 스킬 디렉터리에 설치된 훅 사본과 각 설치 프로젝트 `agents/` 사이의
  드리프트를 잡는 자동 검사는 없다. `subagent_type: fork`는 별도 분기로,
  prompt의 `FORK_REASON: conversation-context` 줄 유무만 본다.
- break-glass는 사람 전용 2종: `ALLOW_INHERITED_SUBAGENT_MODEL=1`(model 미지정과
  effort 미지정 차단을 우회) / `ALLOW_TIER_MODEL_OVERRIDE=1`(tier 값 불일치 차단을
  우회, model은 B-11·effort는 B-12). 그 밖의 우회 수단은 없다.
  Claude는 이 변수들을 스스로 설정하지 않는다.

## 근거
- 2026-07-16 사용자 지시: "메인은 fable5 max 추론이라 엄청난 토큰 사용 —
  결정사항과 방향결정만 메인에서, 나머지는 모두 서브에이전트에 위임하고
  모델·추론강도를 목적에 맞게. 세션 상속 금지. 정책을 문서화하고 강제 구현."

## 세션 effort 상속 실측 (2026-09-27)
- (2026-09-27 당시) `Agent` 도구에는 effort 인자가 없었다(허용: `model` 별칭 4종뿐). 로컬 서브에이전트의 effort는 **정의 파일 frontmatter의 `effort:`**에서 오고, 정의에 없으면 **세션 effort를 그대로 물려받는다**. 메인이 max면 정의 없는 타입은 전부 max로 돈다.
- transcript의 `"effort"` 필드로 확인했다: 정의에 effort가 있는 타입(`loop-worker` high·`loop-checker` high·`loop-verifier` medium)은 그 값이었고, 정의에 effort가 없는 OMC `architect`와 `general-purpose`는 세션 값(max)이었다. OMC `planner`는 medium이었는데 그때 세션 effort가 medium이었다. `critic`·`codex-rescue`는 정의에 effort가 없다는 것만 확인했고 실제 값은 재지 않았다(같은 경로라 상속으로 추정).
- 따라서 **effort가 고정된 정의가 있는 타입으로만 위임한다.** 필요한 조합(예: opus+high 쓰기)이 없으면 정의를 새로 만들고(세션 재시작 뒤 로드) 그 전에는 고정되지 않은 타입으로 대신하지 않는다. Codex는 `codex exec -c model_reasoning_effort=<값>`로 직접 부른다.
- (2026-10-30 갱신) 현재 Agent 도구 스키마에는 `effort` 인자가 있다(2026-10-30 세션 도구 정의로 확인). named 스폰에서는 호출 `effort`가 적용되지 않는다(원칙 5 「핀 없는 에이전트는 이름 없이 띄운다」). 무명 스폰에서 호출 `effort`가 실제로 적용되는지는 **아직 실측하지 않았다** — 실측 전까지 위 「effort가 고정된 정의가 있는 타입으로만 위임한다」를 유지하고, 호출 `effort`를 넘겼다면 「반환 뒤 대조」로 실제값을 확인한다.
