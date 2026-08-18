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
     성립하며, delegate-first **tier 5종**에 한한다 — 동명 에이전트는
     frontmatter 핀을 **직접 확인하기 전에는** 원칙(명시)대로 한다.
     `tools`·`disallowedTools`는 유지되고, `effort`는 일반 스폰에서만
     유지되며 named 스폰에서는 유지되지 않는다. 증거 상세는
     `references/routing-matrix.md` §① 참조.
3. 라우팅 기준 (글로벌 CLAUDE.md OMO 정책과 동일):
   - 탐색·파일검색·단순집계·기계적 편집 → `haiku`/`sonnet`
   - 일반 구현·보통 디버깅·리뷰 1차·문서 구조화 → `sonnet`
   - 적대판정·batch-audit·돈·권한·동시성·release-gate·보안 → `opus`
   - 라벨링·생성 "품질" 작업은 다운시프트 금지 (2026-07-15 확정 유지)
4. 판정·종합·보고는 메인이 한다. 서브에이전트 결과를 메인이 재검하지 않고
   그대로 신뢰하지 말 것(독립 검증 게이트는 별도 opus 에이전트).

## 강제 장치
- PreToolUse 훅 `~/.claude/hooks/enforce-subagent-model.cjs` (matcher: Agent)가
  `model` 미지정 호출을 차단한다 (자체 model 고정 에이전트 타입은 예외 목록이며,
  거기에 delegate-first tier 5종: explorer-low·executor-med·executor-high·
  reviewer-high·judge-max가 **포함된다** — 목록에는 이 외에도 `oh-my-claudecode:*`
  계열 7종 + `statusline-setup`이 있다. 목록이 `.claude/agents/`와 갈라지지
  않게 **정본 레포 사본에 한해** `scripts/lint-delegate-first.py`가 대조
  검사한다 — 전파된 전역 훅 사본과 각 설치 프로젝트 `agents/` 사이의
  드리프트를 잡는 자동 검사는 없다).
- break-glass는 사람 전용 2종: `ALLOW_INHERITED_SUBAGENT_MODEL=1`(model 미지정
  차단을 우회) / `ALLOW_TIER_MODEL_OVERRIDE=1`(tier 값 불일치 차단을 우회, B-11).
  Claude는 이 변수들을 스스로 설정하지 않는다.

## 근거
- 2026-07-16 사용자 지시: "메인은 fable5 max 추론이라 엄청난 토큰 사용 —
  결정사항과 방향결정만 메인에서, 나머지는 모두 서브에이전트에 위임하고
  모델·추론강도를 목적에 맞게. 세션 상속 금지. 정책을 문서화하고 강제 구현."
