#!/usr/bin/env node
/**
 * PreToolUse hook (matcher: Agent) — 서브에이전트 모델 라우팅 강제.
 *
 * 정책 (~/.claude/rules/subagent-model-routing.md):
 *   메인 세션이 고비용 모델(Fable/Opus, max 추론)일 때 Agent 호출이 model을
 *   생략하면 세션 모델을 그대로 상속해 토큰이 폭증한다. 따라서 모든 Agent
 *   호출은 목적에 맞는 model을 **명시**해야 한다 (세션 상속 금지).
 *
 * 동작:
 *   - tool_input.model 이 있으면 통과.
 *   - subagent_type 이 자체 model 을 고정한 정의형 에이전트(플러그인 정의에
 *     model frontmatter 보유)는 알 수 없으므로, 알려진 고정 모델 타입 목록은
 *     통과시킨다 (아래 MODEL_PINNED_TYPES).
 *   - 그 외 model 미지정 → exit 2 로 차단하고 라우팅 지침을 돌려준다.
 *   - break-glass(사람 전용): env ALLOW_INHERITED_SUBAGENT_MODEL=1
 *
 * 공급망 서약 (README.md "훅 공급망 고지"와 동일 계약):
 *   이 훅은 레포에 커밋되어 배포되고, 헤드리스(-p/SDK) 세션에서는 workspace
 *   trust 다이얼로그 없이 즉시 실행된다 — 대화형 세션의 trust 게이트가 없다.
 *   그러므로 이 파일을 변경하는 모든 PR은 **사람이 diff를 직접 읽는다**
 *   (리뷰 없이 머지하지 않는다).
 *   불변식: 이 스크립트는 stdin을 읽고 stderr에 쓰고 exit code를 반환하는
 *   것 외에는 아무 동작도 하지 않는다 — require/fs/네트워크/child_process/
 *   eval을 쓰지 않는다. 이 불변식을 깨는 변경(예: 파일 시스템 스캔, 외부
 *   프로세스 실행 추가)은 이 서약 자체에 대한 별도 판단이 필요하다.
 */
const MODEL_PINNED_TYPES = new Set([
  // 플러그인 정의에 model이 고정된 타입들 — 상속 위험 없음
  "oh-my-claudecode:writer", // haiku
  "oh-my-claudecode:designer", // sonnet
  "oh-my-claudecode:executor", // sonnet
  "oh-my-claudecode:analyst", // opus
  "oh-my-claudecode:architect", // opus
  "oh-my-claudecode:critic", // opus
  "oh-my-claudecode:planner", // opus
  "statusline-setup",

  // delegate-first tier 에이전트 5종 (.claude/agents/*.md frontmatter 고정값)
  // — 값은 각 파일의 frontmatter를 직접 읽어 확인한 것이며 추측이 아니다.
  "explorer-low", // haiku/low
  "executor-med", // sonnet/medium
  "executor-high", // sonnet/high
  "reviewer-high", // opus/high
  "judge-max", // fable/max

  // ⚠ 드리프트 주의: 이 목록은 정적 하드코딩이다 — .claude/agents/ 를 동적
  // 스캔하지 않는다(이 훅은 require/fs 접근 0건이 감사 특성이자 공급망
  // 신뢰의 근거이므로, 그 특성을 지키기 위해 동적 스캔을 의도적으로
  // 도입하지 않았다). 드리프트는 4방향이고 이 중 3가지(추가 후 목록
  // 미갱신 → exit 2 오차단, 정의 삭제 후 목록 잔존 → 스폰 hard error,
  // 개명 후 목록 미갱신 → 신규명 오차단)는 모두 fail-closed(불편할
  // 뿐 안전)다. 그러나 **정의는 그대로 두고 frontmatter의 model을
  // 제거하거나 inherit로 바꾸는데 목록에 이름이 남아 있는 경우**는
  // fail-OPEN이다 — 화이트리스트가 그대로 통과시켜 세션 모델 상속이
  // 조용히 재개된다. tier 에이전트 frontmatter의 model을 제거·
  // inherit로 바꾸는 변경은 **이 목록에서 해당 항목 제거를 반드시
  // 동반**해야 한다(잔존 시 상속 통과 구멍). `.claude/agents/*.md`는
  // README "훅 공급망 고지"의 사람-diff-리뷰 서약 대상이 **아니고**,
  // 이 레포에는 이 드리프트(목록 ↔ agents/ 실제 내용)를 기계적으로
  // 잡는 CI·테스트가 현재 없다(B-07 참고).
  //
  // 이 훅이 전역(~/.claude/settings.json)에 등록되면 아래 pinned 이름은
  // **머신 전역 예약어**가 된다 — 다른 프로젝트가 model 없는 동명
  // 에이전트(예: 다른 목적의 executor-high)를 정의하면 그 프로젝트에서
  // 상속이 통과해버린다. 기존 pinned 항목(oh-my-claudecode:* 계열,
  // statusline-setup)은 전부 네임스페이스가 붙었거나 빌트인이었고,
  // 이 PR(tier 5종 추가)이 처음으로 **비수식 일반명**을 pinned 목록에
  // 넣는다. 실측(2026-08-18): 현재 이 머신에서 이 5개 이름으로 정의된
  // 곳은 이 레포(정본)와 /Users/plletdata/dev/goone-rest 2곳뿐이며,
  // 둘 다 frontmatter에 model이 고정돼 있다(둘 다 문제없음 확인됨) —
  // 그러나 세 번째 동명 정의가 model 없이 생기면 위 fail-open이 발동한다.
  // tier 에이전트를 추가·개명·삭제하면 이 목록도
  // 반드시 함께 고쳐야 한다 — 자동 동기화 수단이 없다.
]);

let raw = "";
process.stdin.on("data", (chunk) => (raw += chunk));
process.stdin.on("end", () => {
  if (process.env.ALLOW_INHERITED_SUBAGENT_MODEL === "1") process.exit(0);
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    process.exit(0); // 파싱 불가 시 차단하지 않음 (fail-open: 훅 자체 결함으로 작업 정지 방지)
  }
  const toolInput = (input && input.tool_input) || {};
  const model = toolInput.model;
  const subagentType = toolInput.subagent_type || "";
  if (typeof model === "string" && model.trim()) process.exit(0);
  if (MODEL_PINNED_TYPES.has(subagentType)) process.exit(0);
  process.stderr.write(
    [
      "[subagent-model-routing] Agent 호출에 model 명시가 없습니다 — 세션 모델 상속 금지.",
      "메인 세션은 결정/방향/판정 전용입니다. 실행 위임 시 목적에 맞는 model을 명시하세요:",
      "  - 탐색/파일검색/단순집계/기계적 편집: model: 'haiku' 또는 'sonnet'",
      "  - 일반 구현/디버깅/리뷰 1차: model: 'sonnet'",
      "  - 적대판정/돈/권한/동시성/release-gate/보안: model: 'opus'",
      "model 파라미터를 추가해 다시 호출하세요.",
    ].join("\n")
  );
  process.exit(2);
});
