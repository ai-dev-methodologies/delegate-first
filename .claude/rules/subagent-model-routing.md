# 서브에이전트 모델 라우팅 강제 (전 프로젝트, 2026-07-16 사용자 확정)

메인 세션이 고비용 모델(Fable 5 / Opus, max 추론)일 때의 **강제 규칙**:

## 원칙
1. **메인 세션은 결정·방향·판정 종합 전용이다.** 구현, 테스트 실행/수정, 탐색,
   문서 초안 등 실행 작업은 서브에이전트에 위임한다.
2. **모든 Agent(서브에이전트) 호출은 `model`을 명시한다 — 세션 모델 상속 금지.**
   추론강도(effort)를 지원하는 경로(Workflow `agent()` 등)에서는 effort도 명시한다.
   - **예외**: frontmatter에 `model`이 고정된 tier 에이전트를 `subagent_type`으로
     지정하는 호출은 `model` **생략이 원칙**이다 — 세션 상속이 아니라 정의값을
     쓰므로 규칙 목적(상속 금지)을 위반하지 않는다. 값을 명시하면 그 tier의
     고정값과 **정확히 일치**해야 통과하고, 불일치는 **exit 2 차단**이다(B-11).
     이 예외는 **등록된 모든 훅 사본**의 pinned 목록에 그 tier가 있을 때만
     성립하며, delegate-first **tier 6종**에 한한다 — 동명 에이전트는
     frontmatter 핀을 **직접 확인하기 전에는** 원칙(명시)대로 한다.
     `tools`·`disallowedTools`는 유지되고, `effort`는 일반 스폰에서만
     유지되며 named 스폰에서는 유지되지 않는다. 증거 상세는
     `~/.claude/skills/delegate-first/references/routing-matrix.md` §① 참조.
   - **fork 예외**: `subagent_type: fork`는 세션 모델과 대화 맥락 전체를 상속하고 `model`을 무시한다. 대화 맥락 자체가 입력일 때만 prompt에 한 줄 `FORK_REASON: conversation-context`를 넣어 쓴다 — 훅은 토큰이 없으면 model 유무와 무관하게 exit 2로 차단하고 어떤 break-glass로도 우회되지 않는다. 컨텍스트 크기 우회·모델 상향 목적 금지(`~/.claude/skills/delegate-first/references/routing-matrix.md` §fork와 컨텍스트 크기). 2026-10-06 사용자 요청으로 도입.
   - **이름은 기본적으로 붙이지 않는다**: Agent 호출에는 `name`을 주지 않는 것이 기본이다. named 스폰은 팀원 방식으로 떠서 완료 알림이 오지 않고, 실행 기록의 실행자 유형 칸이 이름으로 덮이며, 정의에 없는 SendMessage 능력이 생긴다(2026-10 실측). 또 frontmatter의 effort 핀도 호출 `effort`도 적용되지 않고 세션값을 상속한다(2026-08-18 tier 실측: `executor-med` medium → high, `~/.claude/skills/delegate-first/references/routing-matrix.md` §①. 2026-10-30 전사 실측 2건: effort 핀이 없는 타입(`codex:*`·`oh-my-claudecode:*`·`general-purpose` 등)에서 호출 low → 실제 xhigh).
   - **이름을 붙여야 할 때의 규약**: SendMessage로 이어 받아야 해서 `name`을 붙일 때는 `<작업>-<model>-<effort>`로 짓는다(예 `auth-fix-opus-high`). effort가 결과를 좌우하는 위임에는 이름을 붙이지 않는다. 토큰에는 의도한 값을 적고, 실제값은 아래 「반환 뒤 대조」로 확인한다.
   - **반환 뒤 대조**: 서브에이전트가 반환할 때마다 전사에서 실제값을 읽어 의도한 값(이름이 있으면 이름 토큰)과 대조한다. 실제값은 `.jsonl` assistant 레코드의 `message.model`과 `effort`다. `subagents/agent-*.meta.json`의 `model`은 요청값 기록이며, tier를 model 없이 부르면 이 키가 없다 — 그때 의도한 값은 frontmatter 핀이다. haiku처럼 `effort` 키가 없는 레코드는 불일치가 아니라 「effort 판정 불가」로 적는다. 불일치는 구조 이슈로 기록하고, 원인(핀 드리프트·named 상속)을 닫은 뒤 다음 위임을 낸다.
3. 라우팅 기준 (글로벌 CLAUDE.md OMO 정책과 동일):
   - 탐색·파일검색·단순집계·기계적 편집 → `haiku`/`sonnet`
   - 일반 구현·보통 디버깅·리뷰 1차·문서 구조화 → `sonnet`
   - **상향 경로**: 구현 기본은 `executor-med`/`executor-high`(sonnet)다. 다음 중 하나에 해당하면 `executor-opus`(opus·high)로 올리고, 위임 프롬프트(프로젝트에 위임 기록이 있으면 그 기록)에 `상향 근거: <기준 번호>` 1줄을 적는다. ① 여러 모듈에 걸친 상태 전이 변경(드라이버·게이트 등 — 틀리면 게이트가 조용히 열리거나 모든 단계가 막힘) ② 같은 위임 작업의 수정 패스가 한 번 실패한 뒤의 재수정 ③ 리뷰에서 HIGH 이상으로 나온 설계 결함(배선 누락·경계 오판)의 수정 ④ 아래 opus 행(돈·권한·동시성·보안)에 해당하는 구현. 이 밖에는 상향하지 않으며, 상향 여부를 사용자에게 묻지 않는다. delegate-first 스킬 호출 중의 fable 강제 트리거는 그대로 우선한다(판정은 fable, 구현은 `executor-opus`). `executor-opus`에서도 같은 원인으로 다시 실패하면 더 올릴 쓰기 tier가 없으므로 프롬프트를 보강하거나 작업을 쪼개 재위임하고, 그래도 실패하면 사용자에게 보고한다.
   - 적대판정·batch-audit·돈·권한·동시성·보안 → `opus`
   - release-gate 최종 판정 → `fable`(1차 증거 수집은 opus 가능, 2026-10-07 사용자 확정)
   - delegate-first 스킬 호출 중에는 SKILL.md의 fable 강제 트리거 5종(적대 검증·돈·권한·보안 등)이 위 opus 기준보다 우선한다(2026-10-07 사용자 확정).
   - 라벨링·생성 "품질" 작업은 다운시프트 금지 (2026-07-15 확정 유지)
4. 판정·종합·보고는 메인이 한다. 서브에이전트 결과를 메인이 재검하지 않고
   그대로 신뢰하지 말 것(독립 검증 게이트는 별도 opus 에이전트 — release-gate 최종 판정은 fable).

## 강제 장치
> ⚠️ **훅 등록 확인이 먼저다.** 아래 훅은 `settings.json`의 `hooks.PreToolUse`에 matcher `Agent`로 등록돼 있을 때만 작동한다. 파일만 있고 등록이 없으면 자동 강제는 없고, 아래 서술은 모델이 지키는 규약이다. OMC `pre-tool-enforcer.mjs`의 model-routing deny 분기는 Bedrock/Vertex/프록시 환경 전용이라 표준 Anthropic 계정에서는 대신하지 못한다(2026-09-22 실측 사례: 훅 파일은 있으나 전역 `settings.json`에 등록되지 않은 환경이 있었다).

- PreToolUse 훅 `~/.claude/hooks/enforce-subagent-model.cjs` (matcher: Agent)가
  `model` 미지정 호출을 차단한다 (자체 model 고정 에이전트 타입은 예외 목록이며,
  거기에 delegate-first tier 6종: explorer-low·executor-med·executor-high·executor-opus·
  reviewer-high·judge-max가 **포함된다** — 목록에는 이 외에도 `oh-my-claudecode:*`
  계열 7종 + `statusline-setup`이 있다. 목록이 `.claude/agents/`와 갈라지지
  않게 **정본 레포 사본에 한해** `scripts/lint-delegate-first.py`가 대조
  검사한다 — 전파된 전역 훅 사본과 각 설치 프로젝트 `agents/` 사이의
  드리프트를 잡는 자동 검사는 없다). `subagent_type: fork`는 별도 분기로,
  prompt의 `FORK_REASON: conversation-context` 줄 유무만 본다.
- break-glass는 사람 전용 2종: `ALLOW_INHERITED_SUBAGENT_MODEL=1`(model 미지정
  차단을 우회) / `ALLOW_TIER_MODEL_OVERRIDE=1`(tier 값 불일치 차단을 우회, B-11).
  Claude는 이 변수들을 스스로 설정하지 않는다.

## 근거
- 2026-07-16 사용자 지시: "메인은 fable5 max 추론이라 엄청난 토큰 사용 —
  결정사항과 방향결정만 메인에서, 나머지는 모두 서브에이전트에 위임하고
  모델·추론강도를 목적에 맞게. 세션 상속 금지. 정책을 문서화하고 강제 구현."

## 세션 effort 상속 실측 (2026-09-27)
- (2026-09-27 당시) `Agent` 도구에는 effort 인자가 없었다(허용: `model` 별칭 4종뿐). 로컬 서브에이전트의 effort는 **정의 파일 frontmatter의 `effort:`**에서 오고, 정의에 없으면 **세션 effort를 그대로 물려받는다**. 메인이 max면 정의 없는 타입은 전부 max로 돈다.
- transcript의 `"effort"` 필드로 확인했다: 정의에 effort가 있는 타입(`loop-worker` high·`loop-checker` high·`loop-verifier` medium)은 그 값이었고, 정의에 effort가 없는 OMC `architect`와 `general-purpose`는 세션 값(max)이었다. OMC `planner`는 medium이었는데 그때 세션 effort가 medium이었다. `critic`·`codex-rescue`는 정의에 effort가 없다는 것만 확인했고 실제 값은 재지 않았다(같은 경로라 상속으로 추정).
- 따라서 **effort가 고정된 정의가 있는 타입으로만 위임한다.** 필요한 조합(예: opus+high 쓰기)이 없으면 정의를 새로 만들고(세션 재시작 뒤 로드) 그 전에는 고정되지 않은 타입으로 대신하지 않는다. Codex는 `codex exec -c model_reasoning_effort=<값>`로 직접 부른다.
- (2026-10-30 갱신) 현재 Agent 도구 스키마에는 `effort` 인자가 있다(2026-10-30 세션 도구 정의로 확인). named 스폰에서는 호출 `effort`가 적용되지 않는다(원칙 2 「이름은 기본적으로 붙이지 않는다」). 무명 스폰에서 호출 `effort`가 실제로 적용되는지는 **아직 실측하지 않았다** — 실측 전까지 위 「effort가 고정된 정의가 있는 타입으로만 위임한다」를 유지하고, 호출 `effort`를 넘겼다면 「반환 뒤 대조」로 실제값을 확인한다.
