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
