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
 *   - subagent_type 이 "fork" 면 아래 모든 분기보다 **먼저** 평가한다.
 *     fork는 세션(메인) 모델을 상속하고 model 파라미터를 무시한다 —
 *     {subagent_type:"fork", model:"opus"}가 아래 "model 있음" 분기를 통과해
 *     실제로는 세션 모델(예: Fable)로 도는 사각지대가 있었다. 그래서 fork는
 *     prompt에 독립된 한 줄 `FORK_REASON: conversation-context` 가 있을 때만
 *     통과하고, 없으면 model 유무와 무관하게 exit 2 로 차단한다. 어떤 ALLOW_*
 *     break-glass도 이 분기를 우회하지 못한다. exit 0의 stderr는 debug log에만
 *     남고 Claude는 보지 못한다(https://code.claude.com/docs/en/hooks) —
 *     실제 가시화는 위임 로그의 effective model 기록이 맡는다. 한계: 토큰은
 *     자기 선언이라 강제가 아니라 의식적 선언 장치다(호출자가 거짓으로 적어도
 *     훅은 알 수 없다).
 *   - subagent_type 이 statusline-setup(빌트인, 기대값 미상)이면 통과시킨다
 *     (아래 OMIT_ALLOWED_TYPES — 유일한 생략 허용 타입).
 *   - tool_input.model 이 있고, subagent_type 이 아래 TIER_EXPECTED_MODEL
 *     (tier 6종 + oh-my-claudecode:* 7종)에 있으면 그 값이 고정값과 **일치할
 *     때만** 통과시킨다 — 불일치는 exit 2 로 차단한다(B-11: 조용한 강등/승급
 *     봉인. 예: judge-max에 opus를 넘겨 최고 검증 단계를 저비용 모델로 몰래
 *     낮추는 시도). map에 없는 subagent_type은(기대값을 알 수 없으므로)
 *     model 값 검증 없이 다음 단계로 간다.
 *   - 이어서 tool_input.effort 가 허용값(low·medium·high·xhigh·max) 중
 *     하나여야 한다 — 없거나 허용값 밖이면 exit 2(세션 effort 상속 금지).
 *     tier 6종은 그 값이 아래 TIER_EXPECTED_EFFORT 고정값과 **일치할
 *     때만** 통과시킨다(B-12).
 *   - tool_input.model 이 없으면 → pinned 타입이라도 exit 2 로 차단하고
 *     라우팅 지침을 돌려준다(2026-10-30 원칙 5: 생략 통과 폐지 — 아래
 *     OMIT_ALLOWED_TYPES 주석 참조).
 *   - break-glass(사람 전용): env ALLOW_INHERITED_SUBAGENT_MODEL=1
 *     (model 미지정·effort 미지정을 허용 — 기존 동작). 이 스위치는 "model이
 *     없는" 경로와 effort 부재 판정에서만 평가된다 — model이 있는데 tier 기대값과 다른
 *     경우(아래 ALLOW_TIER_MODEL_OVERRIDE의 영역)는 이 스위치로 우회되지
 *     않는다(F-5: 예전엔 이 검사가 함수 진입 직후 최상단에 있어 두
 *     break-glass가 사실상 하나로 합쳐져 있었다 — B-11 값 검증까지 통째로
 *     무력화했다. 지금은 아래 "model 없음" 분기 안에서만 평가한다).
 *   - break-glass(사람 전용, B-11 신설): env ALLOW_TIER_MODEL_OVERRIDE=1
 *     (tier의 model·effort 값 불일치만 허용 — 의도적으로 다른 값을 쓰고 싶은
 *     경우, 예: judge-max를 실험적으로 opus로 낮춰 비용 비교). 이 값은
 *     Claude가 스스로 설정하지 않는다.
 *   - 이름(name)은 보지 않는다. 이름 규약 검사(B-18)는 결정 D8로 훅에서 빠져
 *     close-task.sh의 사후 검사로 옮겼다.
 *   - 등록: 이 훅을 직접 등록하는 곳은 delegate-first SKILL.md frontmatter
 *     `hooks` 하나다. 스킬을 호출한 세션의 Agent 호출에서 실행된다.
 *     전역 settings.json의 resume 백스톱(resume-backstop.cjs)도 이 스크립트를
 *     실행한다. 전사에 스킬 호출 기록이 있는 세션에서만 실행하고, resume 뒤
 *     frontmatter 훅이 꺼지는 틈을 메운다.
 *
 * 공급망 서약 (README.md "훅 공급망 고지"와 동일 계약, 범위 .claude/skills/delegate-first/hooks/*.cjs):
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
  // 플러그인 정의에 model이 고정된 타입들 — 2026-10-30 원칙 5 이후 이 목록은
  // 통과 여부를 정하지 않는다(생략 통과 폐지). 차단 안내문 문구와 lint 대조에만 쓴다.
  "oh-my-claudecode:writer", // haiku
  "oh-my-claudecode:designer", // sonnet
  "oh-my-claudecode:executor", // sonnet
  "oh-my-claudecode:analyst", // opus
  "oh-my-claudecode:architect", // opus
  "oh-my-claudecode:critic", // opus
  "oh-my-claudecode:planner", // opus
  "statusline-setup",

  // delegate-first tier 에이전트 6종 (.claude/agents/*.md frontmatter 고정값)
  // — 값은 각 파일의 frontmatter를 직접 읽어 확인한 것이며 추측이 아니다.
  "explorer-low", // haiku/low
  "executor-med", // sonnet/medium
  "executor-high", // sonnet/high
  "reviewer-high", // opus/high
  "judge-max", // fable/max
  "executor-max", // opus/high — 상향 tier(발주문에 「상향 근거」 줄 필수)

  // ⚠ 드리프트 주의: 이 목록은 정적 하드코딩이다 — .claude/agents/ 를 동적
  // 스캔하지 않는다(이 훅은 require/fs 접근 0건이 감사 특성이자 공급망
  // 신뢰의 근거이므로, 그 특성을 지키기 위해 동적 스캔을 의도적으로
  // 도입하지 않았다). 2026-10-30 원칙 5로 생략 통과가 폐지돼 이 목록은
  // 통과 여부를 정하지 않는다 — 모든 호출이 model·effort를 명시해야 하고
  // 통과 판정은 TIER_EXPECTED_MODEL·TIER_EXPECTED_EFFORT가 맡는다. 그래서
  // 예전의 fail-OPEN 시나리오(frontmatter의 model을 제거·inherit로 바꿨는데
  // 목록에 이름이 남아 화이트리스트가 상속을 통과시킴)는 더 이상 성립하지
  // 않는다. 목록이 agents/ 실제 내용과 갈라지면 남는 영향은 차단 안내문의
  // 부정확뿐이다. `.claude/agents/*.md`는 README "훅 공급망 고지"의
  // 사람-diff-리뷰 서약 대상이 **아니고**, 이 드리프트(목록 ↔ agents/ 실제
  // 내용)는 `scripts/lint-delegate-first.py` Check A가 검출한다(B-07). 다만 이 린터는 옵트인 pre-commit
  // (`.githooks/pre-commit`) 또는 수동 실행에 의존하며 CI 게이트는 아직
  // 없다 — 그리고 이 훅이 설치 프로젝트로 전파될 때 린터가 함께 가지
  // 않으면 그 프로젝트에는 이 드리프트를 잡는 검사가 전혀 없는 상태가
  // 된다.
  //
  // 이 훅이 전역(~/.claude/settings.json)에 등록되면 아래 pinned 이름은
  // **머신 전역 예약어**가 된다 — 다른 프로젝트가 다른 model·effort 핀의
  // 동명 에이전트(예: 다른 목적의 executor-high)를 정의하면, 훅이 이
  // 레포의 기대값으로 판정해 그 프로젝트의 정상 호출이 exit 2로 막힐 수
  // 있다(fail-closed — 상속 통과 구멍은 아니다). 기존 pinned 항목(oh-my-claudecode:* 계열,
  // statusline-setup)은 전부 네임스페이스가 붙었거나 빌트인이었고,
  // 이 PR(tier 5종 추가)이 처음으로 **비수식 일반명**을 pinned 목록에
  // 넣는다. 실측(2026-08-18): 현재 이 머신에서 이 5개 이름으로 정의된
  // 곳은 이 레포(정본)와 /Users/plletdata/dev/goone-rest 2곳뿐이며,
  // 둘 다 frontmatter에 model이 고정돼 있다(둘 다 문제없음 확인됨).
  // tier 에이전트를 추가·개명·삭제하면 이 목록도
  // 반드시 함께 고쳐야 한다 — 자동 동기화 수단이 없다.
]);

// tier 6종 → 기대 model 값 (B-11). 값은 각 .claude/agents/*.md frontmatter를
// 직접 읽어 확인한 것이며 추측이 아니다(2026-08-18 재확인, executor-max는 2026-10-30 추가 시 확인, 위
// MODEL_PINNED_TYPES 주석의 tier 6종 출처와 동일):
//   explorer-low → haiku, executor-med → sonnet, executor-high → sonnet,
//   reviewer-high → opus, judge-max → fable, executor-max → opus.
// oh-my-claudecode:* 7종은 이 레포 밖 플러그인 정의다 — 값은 MODEL_PINNED_TYPES
// 주석과 같고(2026-10-30 플러그인 5.7.19 agents/*.md frontmatter로 확인),
// scripts/lint-delegate-first.py는 이 레포 agents/에 없는 이 항목들의 값을
// 검사하지 않는다. statusline-setup은 빌트인이라 기대값을 몰라 제외한다.
//
// ⚠ 드리프트 주의: 이 map도 MODEL_PINNED_TYPES와 마찬가지로 정적
// 하드코딩이다 — tier 에이전트 frontmatter의 model이 바뀌면 이 map도 같이
// 고쳐야 한다(자동 동기화 수단 없음). scripts/lint-delegate-first.py Check A가
// 이 map ↔ MODEL_PINNED_TYPES Set ↔ agents/*.md frontmatter 3자 정합성을
// 검사한다(B-09).
const TIER_EXPECTED_MODEL = {
  "explorer-low": "haiku",
  "executor-med": "sonnet",
  "executor-high": "sonnet",
  "reviewer-high": "opus",
  "judge-max": "fable",
  "executor-max": "opus",
  // 플러그인 정의형(값은 MODEL_PINNED_TYPES 주석과 같다). statusline-setup은
  // 빌트인이라 기대값을 모르므로 제외한다.
  "oh-my-claudecode:writer": "haiku",
  "oh-my-claudecode:designer": "sonnet",
  "oh-my-claudecode:executor": "sonnet",
  "oh-my-claudecode:analyst": "opus",
  "oh-my-claudecode:architect": "opus",
  "oh-my-claudecode:critic": "opus",
  "oh-my-claudecode:planner": "opus",
};

// tier → 기대 effort 값(2026-10-30 추가, B-12). 값은 각 .claude/agents/*.md
// frontmatter의 effort를 직접 읽어 확인한 것이다. 플러그인 정의형은 effort
// 핀을 모르므로 제외한다(존재만 요구). TIER_EXPECTED_MODEL과 같은 정적
// 하드코딩이라 scripts/lint-delegate-first.py Check A가 이 map ↔ agents/*.md
// frontmatter effort 정합성을 검사한다.
const TIER_EXPECTED_EFFORT = {
  "explorer-low": "low",
  "executor-med": "medium",
  "executor-high": "high",
  "reviewer-high": "high",
  "judge-max": "max",
  "executor-max": "high",
};
const EFFORT_VALUES = new Set(["low", "medium", "high", "xhigh", "max"]);

// 2026-10-30 정책 변경(사용자 지시 「fallback으로 메인 세션을 inherit 하게 절대
// 두면 안 된다」): pinned 타입이라도 model 생략을 허용하지 않는다. 세션 중에
// 추가된 정의를 하네스가 아직 모르면 pinned 목록만 보고 통과시킨 호출이
// 세션 모델·effort를 그대로 상속했다(실측: executor-max 첫 스폰 → fable·xhigh).
// 그래서 모든 호출은 model·effort를 명시하고, tier는 핀과 같은 값이어야 한다.
// 유일한 예외는 statusline-setup(빌트인, 값 미상)뿐이다.
const OMIT_ALLOWED_TYPES = new Set(["statusline-setup"]);

// fork 호출의 유일한 허용 사유 — prompt 안에서 독립된 한 줄(줄 앞뒤 공백/탭만
// 허용)이어야 한다. 줄 중간 언급·다른 사유 값은 매치하지 않는다.
const FORK_REASON_RE = /^[ \t]*FORK_REASON:[ \t]*conversation-context[ \t]*$/m;

let raw = "";
process.stdin.on("data", (chunk) => (raw += chunk));
process.stdin.on("end", () => {
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    process.exit(0); // 파싱 불가 시 차단하지 않음 (fail-open: 훅 자체 결함으로 작업 정지 방지)
  }
  const toolInput = (input && input.tool_input) || {};
  const model = toolInput.model;
  const subagentType = toolInput.subagent_type || "";
  const hasModel = typeof model === "string" && model.trim();

  // fork 전용 분기 — hasModel 분기보다 앞. 어떤 ALLOW_* break-glass도
  // 이 분기를 우회하지 않는다(여기서는 env를 평가하지 않는다).
  if (subagentType === "fork") {
    const prompt = toolInput.prompt;
    if (typeof prompt === "string" && FORK_REASON_RE.test(prompt)) {
      const passed = hasModel
        ? ` 넘긴 model('${model.trim()}')은 적용되지 않습니다.`
        : "";
      process.stderr.write(
        [
          "[subagent-model-routing] fork 통과 (FORK_REASON: conversation-context 확인).",
          "  effective model = 세션(메인) 모델 — fork는 model 파라미터를 무시하고 세션 모델을 그대로 상속합니다." +
            passed,
        ].join("\n")
      );
      process.exit(0);
    }
    process.stderr.write(
      [
        "[subagent-model-routing] fork 호출 차단 — 사유 토큰(FORK_REASON)이 없습니다.",
        "  fork는 세션(메인) 모델을 상속하고 model 파라미터를 무시합니다(예: model 'opus'를 넘겨도 세션 모델로 실행).",
        "  fork는 대화 맥락 자체가 입력일 때만 쓰세요. 컨텍스트 크기 우회·모델 상향 수단으로는 금지입니다.",
        "  대형 파일 레인: executor-high + 파일·함수 단위 분할 + 부분 Read/줄 예산으로 처리하세요.",
        "  상향이 필요하면(같은 레인 2회 실패 또는 규칙의 상향 기준 ①~④) subagent_type 'executor-max'로 상향하세요.",
        "  정말 대화 맥락이 입력이라면 prompt에 한 줄로 `FORK_REASON: conversation-context` 를 넣어 다시 호출하세요.",
        "  이 차단은 ALLOW_INHERITED_SUBAGENT_MODEL / ALLOW_TIER_MODEL_OVERRIDE 로도 우회되지 않습니다.",
      ].join("\n")
    );
    process.exit(2);
  }

  const effort = toolInput.effort;
  const hasEffort = typeof effort === "string" && EFFORT_VALUES.has(effort.trim());

  if (OMIT_ALLOWED_TYPES.has(subagentType)) process.exit(0);

  if (hasModel) {
    const isTier = Object.prototype.hasOwnProperty.call(
      TIER_EXPECTED_MODEL,
      subagentType
    );
    if (isTier) {
      const expected = TIER_EXPECTED_MODEL[subagentType];
      const requested = model.trim();
      if (requested !== expected) {
        if (process.env.ALLOW_TIER_MODEL_OVERRIDE === "1") process.exit(0);
        process.stderr.write(
          [
            `[subagent-model-routing] tier '${subagentType}' 호출의 model 값이 이 tier의 고정값과 다릅니다 — 조용한 강등/승급 차단(B-11).`,
            `  요청한 값: ${requested}`,
            `  이 tier의 고정값: ${expected}`,
            "  tier 호출은 model·effort를 핀과 같은 값으로 명시합니다(생략 금지 — 정의 미로드 fallback 상속 차단).",
            "  강등 위험: 예를 들어 judge-max(fable/max, 최고 검증 게이트)에 opus를 넘기면 릴리스 게이트가 조용히 저비용 모델로 낮아질 수 있습니다.",
            "  의도적 override라면 사람이 직접 ALLOW_TIER_MODEL_OVERRIDE=1을 설정하세요 (Claude는 이 변수를 스스로 설정하지 않습니다).",
          ].join("\n")
        );
        process.exit(2);
      }
    }
    // effort — 모든 호출에 필수(세션 effort 상속 금지). tier는 핀과 같은 값(B-12).
    if (!hasEffort) {
      if (process.env.ALLOW_INHERITED_SUBAGENT_MODEL === "1") process.exit(0);
      process.stderr.write(
        [
          "[subagent-model-routing] Agent 호출에 effort 명시가 없습니다 — 세션 effort 상속 금지.",
          "  effort: 'low' | 'medium' | 'high' | 'xhigh' | 'max' 중 하나를 넣어 다시 호출하세요.",
          "  tier(explorer-low low · executor-med medium · executor-high high · reviewer-high high · executor-max high · judge-max max)는 핀과 같은 값입니다.",
          "  핀 없는 타입(codex:*·oh-my-claudecode:*·general-purpose)은 name 없이 띄워야 effort가 적용됩니다.",
        ].join("\n")
      );
      process.exit(2);
    }
    const hasEffortPin = Object.prototype.hasOwnProperty.call(
      TIER_EXPECTED_EFFORT,
      subagentType
    );
    if (hasEffortPin && effort.trim() !== TIER_EXPECTED_EFFORT[subagentType]) {
      if (process.env.ALLOW_TIER_MODEL_OVERRIDE === "1") process.exit(0);
      process.stderr.write(
        [
          `[subagent-model-routing] tier '${subagentType}' 호출의 effort 값이 이 tier의 고정값과 다릅니다(B-12).`,
          `  요청한 값: ${effort.trim()}`,
          `  이 tier의 고정값: ${TIER_EXPECTED_EFFORT[subagentType]}`,
          "  tier 호출은 model·effort를 핀과 같은 값으로 명시합니다. 다른 effort가 필요하면 다른 tier를 쓰세요(상향은 executor-max + 발주문 「상향 근거」 줄).",
        ].join("\n")
      );
      process.exit(2);
    }
    process.exit(0);
  }

  // model 미지정 경로 — pinned 타입 예외는 2026-10-30에 폐지했다(위 정책 변경
  // 주석). ALLOW_INHERITED_SUBAGENT_MODEL은 여기서만 평가한다(F-5: tier 값
  // 불일치 차단은 위 분기에서 이미 끝났으므로 이 break-glass가 B-11을
  // 우회할 수 없다).
  if (process.env.ALLOW_INHERITED_SUBAGENT_MODEL === "1") process.exit(0);
  process.stderr.write(
    [
      "[subagent-model-routing] Agent 호출에 model 명시가 없습니다 — 세션 모델 상속 금지(pinned tier도 예외 없음).",
      "메인 세션은 결정/방향/판정 전용입니다. 실행 위임 시 model과 effort를 함께 명시하세요:",
      "  - tier: explorer-low(haiku·low) · executor-med(sonnet·medium) · executor-high(sonnet·high) · reviewer-high(opus·high) · executor-max(opus·high, 상향 근거 필요) · judge-max(fable·max)",
      "  - 핀 없는 타입은 목적에 맞는 model·effort를 명시하고 name 없이 띄웁니다.",
      MODEL_PINNED_TYPES.has(subagentType)
        ? "  (이 타입은 정의에 핀이 있지만, 정의가 아직 로드되지 않은 세션에서는 생략이 세션 모델 상속으로 이어집니다 — 그래서 명시를 요구합니다.)"
        : "",
      "model·effort 파라미터를 추가해 다시 호출하세요.",
    ].join("\n")
  );
  process.exit(2);
});
