#!/usr/bin/env bash
#
# scripts/smoke-hook.sh — 재실행 가능한 enforce-subagent-model.cjs 회귀 스모크.
#
# 목적: .claude/skills/delegate-first/hooks/enforce-subagent-model.cjs를 건드리는 PR의 회귀 게이트.
#   "사람이 diff를 읽는다"가 이 훅의 유일한 공급망 게이트라, 이 스크립트가
#   최소한 알려진 케이스(pinned 목록, whitespace, 타입 변형, prototype
#   pollution 시도, fail-open/fail-closed 경계)의 exit code 회귀를 잡는다.
#
# 부작용: 없음. stdin으로 JSON을 훅에 주입하고 exit code만 관찰한다 —
#   설정 변경, 네트워크 접근을 하지 않는다. 스킬 frontmatter 절만 mktemp -d
#   샌드박스에 훅 사본을 만들고 종료 시 지운다(레포 파일은 수정하지 않는다).
#
# 실행법:
#   bash scripts/smoke-hook.sh                # 이 레포의 훅을 검사
#   bash scripts/smoke-hook.sh /path/to/other-version.cjs   # 다른 버전과 비교
#
set -u

HOOK_PATH="${1:-$(cd "$(dirname "$0")/.." && pwd)/.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs}"

if [ ! -f "$HOOK_PATH" ]; then
  echo "smoke-hook: hook 파일을 찾을 수 없음: $HOOK_PATH" >&2
  exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0
FAILED_DESCRIPTIONS=""

# run_case <설명> <stdin JSON> <기대 exit code> [env NAME=VALUE]
run_case() {
  desc="$1"
  input="$2"
  expected="$3"
  extra_env="${4:-}"

  if [ -n "$extra_env" ]; then
    actual=$(printf '%s' "$input" | env "$extra_env" node "$HOOK_PATH" >/dev/null 2>&1; echo $?)
  else
    actual=$(printf '%s' "$input" | node "$HOOK_PATH" >/dev/null 2>&1; echo $?)
  fi

  if [ "$actual" = "$expected" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_DESCRIPTIONS="${FAILED_DESCRIPTIONS}
  - ${desc} (기대 exit ${expected}, 실제 exit ${actual})"
  fi
}

# --- 원칙 5: tier도 model 생략 금지 — model 없이 호출 → 차단 (exit 2) ---
# 주의: 이 6건은 원칙 5 이전엔 exit 0(pinned 목록 통과)을 기대했었다. 세션
# 중에 추가된 정의를 하네스가 아직 모르면 생략한 호출이 세션 모델·effort를
# 상속했기 때문에(실측: executor-max 첫 스폰 → fable·xhigh) 생략 통과를
# 폐지했다 — 이 exit 2로의 전환은 의도된 동작 변경이지 회귀가 아니다.
run_case "tier explorer-low, model 없음" '{"tool_input":{"subagent_type":"explorer-low"}}' 2
run_case "tier executor-med, model 없음" '{"tool_input":{"subagent_type":"executor-med"}}' 2
run_case "tier executor-high, model 없음" '{"tool_input":{"subagent_type":"executor-high"}}' 2
run_case "tier reviewer-high, model 없음" '{"tool_input":{"subagent_type":"reviewer-high"}}' 2
run_case "tier judge-max, model 없음" '{"tool_input":{"subagent_type":"judge-max"}}' 2
run_case "tier executor-max, model 없음" '{"tool_input":{"subagent_type":"executor-max"}}' 2

# --- general-purpose: pinned 아님 → model 없으면 차단 ---
run_case "general-purpose, model 없음" '{"tool_input":{"subagent_type":"general-purpose"}}' 2
run_case "general-purpose, model 공백 문자열" '{"tool_input":{"subagent_type":"general-purpose","model":"   "}}' 2
run_case "general-purpose, model haiku + effort low" '{"tool_input":{"subagent_type":"general-purpose","model":"haiku","effort":"low"}}' 0

# --- 플러그인 정의형 pinned 타입: 원칙 5로 생략 통과 폐지, 기대 model 맵 적용 ---
run_case "oh-my-claudecode:writer, model 없음(원칙 5 → 차단)" '{"tool_input":{"subagent_type":"oh-my-claudecode:writer"}}' 2
run_case "oh-my-claudecode:writer + model haiku + effort low" '{"tool_input":{"subagent_type":"oh-my-claudecode:writer","model":"haiku","effort":"low"}}' 0
run_case "oh-my-claudecode:writer + model sonnet(기대 model 불일치 → 차단)" '{"tool_input":{"subagent_type":"oh-my-claudecode:writer","model":"sonnet","effort":"low"}}' 2
run_case "oh-my-claudecode:planner + model opus + effort medium(effort 핀 없음 → 값 자유)" '{"tool_input":{"subagent_type":"oh-my-claudecode:planner","model":"opus","effort":"medium"}}' 0

# --- 빌트인 statusline-setup: 기대값을 모르므로 유일한 생략 허용 타입 ---
run_case "statusline-setup, model·effort 없음" '{"tool_input":{"subagent_type":"statusline-setup"}}' 0

# --- B-11: tier + model 명시, 기대값과 일치(+ effort 핀 일치) → 통과 (exit 0) ---
# 주의: 이 6건과 아래 tier 통과 케이스 4건(B-12 " high", B-12 override,
# B-11 override, C10 " fable")의 name은 훅이 B-18을 검사하던 때 넣은 것이다.
# 지금 훅은 name을 보지 않는다(결정 D8, 아래 「이름은 훅이 보지 않는다」 절).
run_case "tier explorer-low + model haiku(기대값 일치)" '{"tool_input":{"subagent_type":"explorer-low","model":"haiku","effort":"low","name":"t-haiku-low"}}' 0
run_case "tier executor-med + model sonnet(기대값 일치)" '{"tool_input":{"subagent_type":"executor-med","model":"sonnet","effort":"medium","name":"t-sonnet-medium"}}' 0
run_case "tier executor-high + model sonnet(기대값 일치)" '{"tool_input":{"subagent_type":"executor-high","model":"sonnet","effort":"high","name":"t-sonnet-high"}}' 0
run_case "tier reviewer-high + model opus(기대값 일치)" '{"tool_input":{"subagent_type":"reviewer-high","model":"opus","effort":"high","name":"t-opus-high"}}' 0
run_case "tier judge-max + model fable(기대값 일치)" '{"tool_input":{"subagent_type":"judge-max","model":"fable","effort":"max","name":"t-fable-max"}}' 0
run_case "E③ tier executor-max + model opus + effort high(기대값 일치)" '{"tool_input":{"subagent_type":"executor-max","model":"opus","effort":"high","name":"t-opus-high"}}' 0

# --- B-12: effort 검증 — 모든 호출에 effort 필수, tier는 핀과 같은 값 ---
run_case "E① tier executor-high + model sonnet, effort 없음 → 차단" '{"tool_input":{"subagent_type":"executor-high","model":"sonnet"}}' 2
run_case "E② tier executor-med + model sonnet + effort high(핀 medium과 불일치) → 차단" '{"tool_input":{"subagent_type":"executor-med","model":"sonnet","effort":"high"}}' 2
run_case "E⑤ 비핀 general-purpose + model sonnet + effort medium → 통과" '{"tool_input":{"subagent_type":"general-purpose","model":"sonnet","effort":"medium"}}' 0
run_case "B-12: 비핀 general-purpose + model sonnet, effort 없음 → 차단" '{"tool_input":{"subagent_type":"general-purpose","model":"sonnet"}}' 2
run_case "B-12: effort 허용 밖 값 \"ultra\" → 차단" '{"tool_input":{"subagent_type":"general-purpose","model":"sonnet","effort":"ultra"}}' 2
run_case "B-12: effort 숫자 → 차단" '{"tool_input":{"subagent_type":"general-purpose","model":"sonnet","effort":3}}' 2
run_case "B-12: tier effort \" high\"(앞 공백, trim 후 일치 → 통과)" '{"tool_input":{"subagent_type":"executor-high","model":"sonnet","effort":" high","name":"t-sonnet-high"}}' 0
run_case "B-12: tier effort HIGH(대문자, 허용값 밖 → 차단)" '{"tool_input":{"subagent_type":"executor-high","model":"sonnet","effort":"HIGH"}}' 2
run_case "B-12: ALLOW_TIER_MODEL_OVERRIDE=1 + executor-med effort high(불일치 → 통과)" \
  '{"tool_input":{"subagent_type":"executor-med","model":"sonnet","effort":"high","name":"t-sonnet-high"}}' 0 \
  "ALLOW_TIER_MODEL_OVERRIDE=1"
run_case "B-12: ALLOW_INHERITED_SUBAGENT_MODEL=1 + executor-med effort high(불일치 → 여전히 차단)" \
  '{"tool_input":{"subagent_type":"executor-med","model":"sonnet","effort":"high"}}' 2 \
  "ALLOW_INHERITED_SUBAGENT_MODEL=1"
run_case "B-12: ALLOW_INHERITED_SUBAGENT_MODEL=1 + general-purpose effort 없음(부재 우회 → 통과)" \
  '{"tool_input":{"subagent_type":"general-purpose","model":"sonnet"}}' 0 \
  "ALLOW_INHERITED_SUBAGENT_MODEL=1"

# --- B-11: tier + model 명시, 기대값과 불일치 → 차단 (exit 2, 조용한 강등/승급 봉인) ---
# 주의: 이 두 케이스는 B-11 이전엔 "tier executor-high + model opus 명시"가
# exit 0(통과)을 기대했었다 — 구버전 훅은 model 값을 전혀 검증하지 않고
# 비어있지 않은 문자열이면 무조건 통과시켰기 때문이다. B-11이 바로 이
# 조용한 강등/승급(예: judge-max에 opus를 넘겨 최고 검증 게이트를 저비용
# 모델로 몰래 낮추는 것)을 막는 것이 목적이므로, 이 exit 2로의 전환은
# 의도된 동작 변경이지 회귀가 아니다.
run_case "tier executor-high + model opus(기대값 불일치 → 차단)" '{"tool_input":{"subagent_type":"executor-high","model":"opus"}}' 2
run_case "tier judge-max + model opus(강등 시도 → 차단)" '{"tool_input":{"subagent_type":"judge-max","model":"opus"}}' 2
run_case "E④ tier executor-max + model sonnet(기대값 불일치 → 차단, B-11)" '{"tool_input":{"subagent_type":"executor-max","model":"sonnet","effort":"high"}}' 2

# --- B-11: break-glass ALLOW_TIER_MODEL_OVERRIDE=1 → 불일치도 통과 ---
run_case "ALLOW_TIER_MODEL_OVERRIDE=1 + judge-max + model opus(불일치)" \
  '{"tool_input":{"subagent_type":"judge-max","model":"opus","name":"t-opus-max"}}' 0 \
  "ALLOW_TIER_MODEL_OVERRIDE=1"

# --- B-11: ALLOW_TIER_MODEL_OVERRIDE=1은 "model 미지정 + non-pinned 차단" 경로엔 적용 안 됨(범위 한정 확인) ---
run_case "ALLOW_TIER_MODEL_OVERRIDE=1 + general-purpose, model 없음(여전히 차단)" \
  '{"tool_input":{"subagent_type":"general-purpose"}}' 2 \
  "ALLOW_TIER_MODEL_OVERRIDE=1"

# --- F-5: ALLOW_INHERITED_SUBAGENT_MODEL=1은 "model 미지정" 경로에만 적용된다 —
# tier 값 불일치(위 B-11 차단)까지 우회해서는 안 된다. 이전엔 이 검사가
# 함수 최상단에서 무조건 exit 0 했기 때문에 이 케이스가 (잘못) 0을
# 반환했다 — 지금은 2여야 한다(두 break-glass가 실제로 분리돼 있음을
# 회귀로 고정).
run_case "ALLOW_INHERITED_SUBAGENT_MODEL=1 + judge-max + model opus(불일치 → 여전히 차단, F-5)" \
  '{"tool_input":{"subagent_type":"judge-max","model":"opus"}}' 2 \
  "ALLOW_INHERITED_SUBAGENT_MODEL=1"

# --- subagent_type 자체가 없음 ---
run_case "subagent_type 없음, model 없음" '{"tool_input":{}}' 2

# --- 대소문자/공백 변형: 문자열 정확 일치만 통과 ---
run_case "대소문자 변형 Executor-High" '{"tool_input":{"subagent_type":"Executor-High"}}' 2
run_case "앞 공백 \" executor-high\"" '{"tool_input":{"subagent_type":" executor-high"}}' 2
run_case "뒤 공백 \"executor-high \"" '{"tool_input":{"subagent_type":"executor-high "}}' 2

# --- subagent_type 타입 변형 ---
run_case "subagent_type 배열" '{"tool_input":{"subagent_type":["executor-high"]}}' 2
run_case "subagent_type 숫자" '{"tool_input":{"subagent_type":123}}' 2
run_case "subagent_type null" '{"tool_input":{"subagent_type":null}}' 2

# --- prototype pollution 시도 ---
run_case "__proto__ 프로토타입 오염 시도" '{"tool_input":{"__proto__":{"model":"sonnet"}}}' 2

# --- model 타입 변형 ---
run_case "model 숫자" '{"tool_input":{"subagent_type":"general-purpose","model":123}}' 2
run_case "model 배열" '{"tool_input":{"subagent_type":"general-purpose","model":["sonnet"]}}' 2
run_case "model bool" '{"tool_input":{"subagent_type":"general-purpose","model":true}}' 2

# --- C10: tier + model 형식 변형 — 별칭 exact match(대소문자·전체 ID
# 불일치는 차단), trim은 적용(앞뒤 공백은 제거 후 비교)됨을 회귀로 고정 ---
run_case "C10: judge-max + model FABLE(대문자, 불일치 → 차단)" \
  '{"tool_input":{"subagent_type":"judge-max","model":"FABLE"}}' 2
run_case "C10: judge-max + model claude-fable-5(전체 ID, 불일치 → 차단)" \
  '{"tool_input":{"subagent_type":"judge-max","model":"claude-fable-5"}}' 2
run_case "C10: judge-max + model \" fable\"(앞 공백, trim 후 일치 → 통과)" \
  '{"tool_input":{"subagent_type":"judge-max","model":" fable","effort":"max","name":"t-fable-max"}}' 0

# --- fork 전용 분기: fork는 세션(메인) 모델을 상속하고 model 파라미터를
# 무시한다 — 사유 토큰(prompt의 독립된 한 줄 `FORK_REASON: conversation-context`)이
# 없으면 model 유무와 무관하게 차단. 어떤 ALLOW_* break-glass도 이 게이트를
# 우회하지 못한다. 토큰은 자기 선언이라 강제가 아니라 의식적 선언 장치다. ---
run_case "fork, 사유 토큰 없음, model 없음 → 차단" \
  '{"tool_input":{"subagent_type":"fork","prompt":"대형 파일 분석해줘"}}' 2
run_case "fork, 사유 토큰 없음, model opus → 차단(model이 있어도 새던 구멍)" \
  '{"tool_input":{"subagent_type":"fork","model":"opus","prompt":"대형 파일 분석해줘"}}' 2
run_case "fork, 사유 토큰 있음, model 없음 → 통과" \
  '{"tool_input":{"subagent_type":"fork","prompt":"FORK_REASON: conversation-context\n이어서 정리해줘"}}' 0
run_case "fork, 사유 토큰 있음 + model opus → 통과" \
  '{"tool_input":{"subagent_type":"fork","model":"opus","prompt":"FORK_REASON: conversation-context\n이어서 정리해줘"}}' 0
run_case "fork, 허용 안 된 사유 FORK_REASON: large-file → 차단" \
  '{"tool_input":{"subagent_type":"fork","prompt":"FORK_REASON: large-file\n분석"}}' 2
run_case "fork, 토큰이 줄 중간(\"참고 FORK_REASON: ...\") → 차단" \
  '{"tool_input":{"subagent_type":"fork","prompt":"참고 FORK_REASON: conversation-context"}}' 2
run_case "fork, 토큰 줄 끝 CRLF → 통과" \
  '{"tool_input":{"subagent_type":"fork","prompt":"FORK_REASON: conversation-context\r\n작업"}}' 0
run_case "fork, 토큰 뒤 추가 텍스트 → 차단" \
  '{"tool_input":{"subagent_type":"fork","prompt":"FORK_REASON: conversation-context please"}}' 2
run_case "fork, 전각 콜론 → 차단" \
  '{"tool_input":{"subagent_type":"fork","prompt":"FORK_REASON： conversation-context"}}' 2
run_case "fork, prompt 숫자 → 차단" '{"tool_input":{"subagent_type":"fork","prompt":123}}' 2
run_case "fork, prompt 배열 → 차단" \
  '{"tool_input":{"subagent_type":"fork","prompt":["FORK_REASON: conversation-context"]}}' 2
run_case "fork, prompt 없음 → 차단" '{"tool_input":{"subagent_type":"fork"}}' 2
run_case "fork, 사유 없음 + ALLOW_INHERITED_SUBAGENT_MODEL=1 → 여전히 차단" \
  '{"tool_input":{"subagent_type":"fork","prompt":"분석"}}' 2 \
  "ALLOW_INHERITED_SUBAGENT_MODEL=1"
run_case "fork, 사유 없음 + ALLOW_TIER_MODEL_OVERRIDE=1 → 여전히 차단" \
  '{"tool_input":{"subagent_type":"fork","model":"opus","prompt":"분석"}}' 2 \
  "ALLOW_TIER_MODEL_OVERRIDE=1"

# --- 이름은 훅이 보지 않는다(B-18 제거, 결정 D8) ---
# 이름 규약 `<작업>-<model>-<effort>`은 close-task.sh가 사후에 검사한다. 훅은
# name 유무·형식과 무관하게 model·effort·fork 판정만 한다. 아래 케이스는 예전
# B-18 절에서 차단(exit 2)을 기대하던 입력이 이제 통과하는지, 그리고 이름이
# B-11·B-12·부재 차단을 우회하지 않는지를 고정한다.
run_case "D8: tier executor-high + 규약 이름 → 통과" \
  '{"tool_input":{"subagent_type":"executor-high","model":"sonnet","effort":"high","name":"p5-fix-sonnet-high"}}' 0
run_case "D8: tier + 이름 없음 → 통과" \
  '{"tool_input":{"subagent_type":"executor-max","model":"opus","effort":"high"}}' 0
run_case "D8: tier + 토큰 불일치 이름(x-opus-high, 핀 sonnet) → 통과" \
  '{"tool_input":{"subagent_type":"executor-high","model":"sonnet","effort":"high","name":"x-opus-high"}}' 0
run_case "D8: tier + name 숫자 → 통과" \
  '{"tool_input":{"subagent_type":"executor-max","model":"opus","effort":"high","name":123}}' 0
run_case "D8: general-purpose + 이름 → 통과" \
  '{"tool_input":{"subagent_type":"general-purpose","model":"sonnet","effort":"medium","name":"x-sonnet-medium"}}' 0
run_case "D8: oh-my-claudecode:executor + 이름 → 통과" \
  '{"tool_input":{"subagent_type":"oh-my-claudecode:executor","model":"sonnet","effort":"high","name":"x-sonnet-high"}}' 0
run_case "D8: codex:codex-rescue + 이름 → 통과" \
  '{"tool_input":{"subagent_type":"codex:codex-rescue","model":"sonnet","effort":"high","name":"x-sonnet-high"}}' 0
run_case "D8: fork + FORK_REASON + 이름 → 통과(fork 판정 그대로)" \
  '{"tool_input":{"subagent_type":"fork","name":"x-opus-high","prompt":"FORK_REASON: conversation-context\n작업"}}' 0
run_case "D8: fork + 사유 없음 + 이름 → 차단(fork 판정 그대로)" \
  '{"tool_input":{"subagent_type":"fork","name":"x-opus-high","prompt":"작업"}}' 2
run_case "D8: tier + 규약 이름 + model 없음 → 차단(이름이 부재 차단을 우회하지 않는다)" \
  '{"tool_input":{"subagent_type":"explorer-low","name":"x-haiku-low"}}' 2
run_case "D8: tier + 규약 이름 + model 불일치 → 차단(B-11)" \
  '{"tool_input":{"subagent_type":"judge-max","model":"opus","effort":"max","name":"x-fable-max"}}' 2
run_case "D8: tier + 규약 이름 + effort 불일치 → 차단(B-12)" \
  '{"tool_input":{"subagent_type":"executor-med","model":"sonnet","effort":"high","name":"x-sonnet-medium"}}' 2
run_case "D8: OVERRIDE + executor-med effort high + 핀값 이름 → 통과" \
  '{"tool_input":{"subagent_type":"executor-med","model":"sonnet","effort":"high","name":"x-sonnet-medium"}}' 0 \
  "ALLOW_TIER_MODEL_OVERRIDE=1"
run_case "D8: INHERITED + general-purpose model 없음 + 이름 → 통과" \
  '{"tool_input":{"subagent_type":"general-purpose","name":"x-sonnet-high"}}' 0 \
  "ALLOW_INHERITED_SUBAGENT_MODEL=1"
run_case "D8: INHERITED + tier model 없음 + 이름 없음 → 통과" \
  '{"tool_input":{"subagent_type":"explorer-low"}}' 0 \
  "ALLOW_INHERITED_SUBAGENT_MODEL=1"

# --- 파싱 불가/빈 stdin: 설계된 fail-open ---
run_case "비JSON stdin" 'not json {' 0
run_case "빈 stdin" '' 0

# --- break-glass env ---
run_case "ALLOW_INHERITED_SUBAGENT_MODEL=1 + general-purpose model 없음" \
  '{"tool_input":{"subagent_type":"general-purpose"}}' 0 \
  "ALLOW_INHERITED_SUBAGENT_MODEL=1"

# --- fork 통과 케이스의 stderr 안내 검사 (run_case는 exit code만 보므로 별도 캡처) ---
# debug log 전용 출력의 문구 회귀 검사 — exit 0의 stderr는 Claude에게 보이지 않으므로
# 가시화 수단이 아니라 안내 문구가 유지되는지만 본다.
fork_stderr=$(printf '%s' '{"tool_input":{"subagent_type":"fork","model":"opus","prompt":"FORK_REASON: conversation-context"}}' | node "$HOOK_PATH" 2>&1 >/dev/null)
if printf '%s' "$fork_stderr" | grep -q "effective model"; then
  PASS_COUNT=$((PASS_COUNT + 1))
else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_DESCRIPTIONS="${FAILED_DESCRIPTIONS}
  - fork 통과 케이스 stderr에 'effective model' 안내 없음 (실제 stderr: ${fork_stderr:-<비어있음>})"
fi

# --- 스킬 frontmatter 등록(결정 ③): 훅은 delegate-first를 호출한 세션에서만 켜진다 ---
# SKILL.md frontmatter의 PreToolUse matcher "Agent" command를 꺼내 /bin/sh로
# 실행한다. 레포 설치(${CLAUDE_PROJECT_DIR} 쪽)와 전역 설치($HOME 쪽) 모두에서
# 스크립트를 찾아야 하고, 둘 다 없거나 node가 없으면 exit 2(fail-closed)여야
# 한다. 샌드박스는 mktemp -d 아래에만 만들고 끝나면 지운다.
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_MD="$REPO_ROOT/.claude/skills/delegate-first/SKILL.md"
SKILL_HOOK_REL=".claude/skills/delegate-first/hooks/enforce-subagent-model.cjs"
PASS_INPUT='{"tool_input":{"subagent_type":"executor-high","model":"sonnet","effort":"high"}}'
BLOCK_INPUT='{"tool_input":{"subagent_type":"executor-high"}}'

fm_pass() { PASS_COUNT=$((PASS_COUNT + 1)); }
fm_fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_DESCRIPTIONS="${FAILED_DESCRIPTIONS}
  - $1"
}

# frontmatter(첫 두 '---' 사이)만 본다.
FRONTMATTER="$(awk 'NR==1 && $0=="---"{f=1; next} f && $0=="---"{exit} f' "$SKILL_MD" 2>/dev/null)"
if printf '%s\n' "$FRONTMATTER" | grep -q '^hooks:$' &&
   printf '%s\n' "$FRONTMATTER" | grep -q '^  PreToolUse:$' &&
   printf '%s\n' "$FRONTMATTER" | grep -q '^    - matcher: "Agent"$'; then
  fm_pass
else
  fm_fail "①: SKILL.md frontmatter에 hooks.PreToolUse matcher \"Agent\" 등록이 없음"
fi

# command는 YAML 작은따옴표 스칼라 한 줄이다('' → ').
CMD_LINES="$(printf '%s\n' "$FRONTMATTER" | grep -c "^          command: '.*'$")"
HOOK_CMD="$(printf '%s\n' "$FRONTMATTER" | sed -n "s/^          command: '\(.*\)'$/\1/p" | sed "s/''/'/g")"
if [ "$CMD_LINES" = "1" ] && printf '%s' "$HOOK_CMD" | grep -qF "$SKILL_HOOK_REL"; then
  fm_pass
else
  fm_fail "①: frontmatter command가 1줄이 아니거나 $SKILL_HOOK_REL 를 가리키지 않음 (줄 수: $CMD_LINES)"
fi

FM_SANDBOX="$(mktemp -d)"
trap 'rm -rf "$FM_SANDBOX"' EXIT
mkdir -p "$FM_SANDBOX/proj/$(dirname "$SKILL_HOOK_REL")" "$FM_SANDBOX/home/$(dirname "$SKILL_HOOK_REL")" \
  "$FM_SANDBOX/emptyproj" "$FM_SANDBOX/emptyhome"
cp "$HOOK_PATH" "$FM_SANDBOX/proj/$SKILL_HOOK_REL"
cp "$HOOK_PATH" "$FM_SANDBOX/home/$SKILL_HOOK_REL"

# run_cmd <CLAUDE_PROJECT_DIR 또는 -(미설정)> <HOME 또는 -(미설정)> <PATH> <stdin> → FM_RC, FM_ERR
# 셸은 FM_SH(기본 /bin/sh), 셸 옵션은 FM_SH_OPT(예 -e·-u, 기본 없음)로 바꾼다.
FM_SH=/bin/sh
FM_SH_OPT=""
run_cmd() {
  fm_in="$4"; fm_path="$3"; fm_p="$1"; fm_h="$2"
  set --
  [ "$fm_p" = "-" ] || set -- "$@" "CLAUDE_PROJECT_DIR=$fm_p"
  [ "$fm_h" = "-" ] || set -- "$@" "HOME=$fm_h"
  FM_ERR=$(printf '%s' "$fm_in" | env -u CLAUDE_PROJECT_DIR -u HOME "$@" PATH="$fm_path" \
    "$FM_SH" ${FM_SH_OPT:+"$FM_SH_OPT"} -c "$HOOK_CMD" 2>&1 >/dev/null)
  FM_RC=$?
}

# fm_case <설명> <기대 exit> <stderr에 있어야 할 문구 또는 빈 값> <run_cmd 인자 4개>
fm_case() {
  desc="$1"; expected="$2"; needle="$3"; shift 3
  run_cmd "$@"
  if [ "$FM_RC" = "$expected" ] && { [ -z "$needle" ] || printf '%s' "$FM_ERR" | grep -qF -- "$needle"; }; then
    fm_pass
  else
    fm_fail "${desc} (기대 exit ${expected}, 실제 exit ${FM_RC}, stderr: ${FM_ERR:-<비어있음>})"
  fi
}

fm_case "②: 레포 설치 — 통과 입력 → exit 0" 0 "" \
  "$FM_SANDBOX/proj" "$FM_SANDBOX/emptyhome" "$PATH" "$PASS_INPUT"
fm_case "②: 레포 설치 — 차단 입력 → 훅 판정 exit 2" 2 "[subagent-model-routing]" \
  "$FM_SANDBOX/proj" "$FM_SANDBOX/emptyhome" "$PATH" "$BLOCK_INPUT"
fm_case "②: 전역 설치(프로젝트에 사본 없음) — 통과 입력 → exit 0" 0 "" \
  "$FM_SANDBOX/emptyproj" "$FM_SANDBOX/home" "$PATH" "$PASS_INPUT"
fm_case "②: 전역 설치(CLAUDE_PROJECT_DIR 미설정) — 통과 입력 → exit 0" 0 "" \
  - "$FM_SANDBOX/home" "$PATH" "$PASS_INPUT"
fm_case "②: 전역 설치 — 차단 입력 → 훅 판정 exit 2" 2 "[subagent-model-routing]" \
  "$FM_SANDBOX/emptyproj" "$FM_SANDBOX/home" "$PATH" "$BLOCK_INPUT"
fm_case "③: 스크립트가 어디에도 없음 → exit 2 + 안내" 2 "훅 스크립트를 찾지 못했다" \
  "$FM_SANDBOX/emptyproj" "$FM_SANDBOX/emptyhome" "$PATH" "$PASS_INPUT"
fm_case "③: node 없음 → exit 2 + 안내" 2 "node를 찾지 못했다" \
  "$FM_SANDBOX/proj" "$FM_SANDBOX/emptyhome" "/nonexistent" "$PASS_INPUT"

# ⑥: 스크립트를 찾았어도 node·스크립트가 0·2가 아닌 코드(1·127·신호 등)로
# 끝나면 command가 2로 바꾼다(fail-closed). 빈 stdin의 0(설계된 fail-open)은 유지한다.
mkdir -p "$FM_SANDBOX/badsyntax/$(dirname "$SKILL_HOOK_REL")" "$FM_SANDBOX/noperm/$(dirname "$SKILL_HOOK_REL")" \
  "$FM_SANDBOX/shim127"
printf '%s\n' 'this is not ( valid javascript' > "$FM_SANDBOX/badsyntax/$SKILL_HOOK_REL"
cp "$HOOK_PATH" "$FM_SANDBOX/noperm/$SKILL_HOOK_REL"
chmod 000 "$FM_SANDBOX/noperm/$SKILL_HOOK_REL"
printf '%s\n' '#!/bin/sh' 'exit 127' > "$FM_SANDBOX/shim127/node"
chmod +x "$FM_SANDBOX/shim127/node"
fm_case "⑥: 문법 오류 훅(node exit 1) → exit 2 + 안내" 2 "예상 밖 종료 코드" \
  "$FM_SANDBOX/badsyntax" "$FM_SANDBOX/emptyhome" "$PATH" "$PASS_INPUT"
fm_case "⑥: chmod 000 훅(읽기 불가) → exit 2 + 안내" 2 "예상 밖 종료 코드" \
  "$FM_SANDBOX/noperm" "$FM_SANDBOX/emptyhome" "$PATH" "$PASS_INPUT"
fm_case "⑥: exit 127 node shim → exit 2 + 안내" 2 "예상 밖 종료 코드" \
  "$FM_SANDBOX/proj" "$FM_SANDBOX/emptyhome" "$FM_SANDBOX/shim127:/usr/bin:/bin" "$PASS_INPUT"
fm_case "⑥: 빈 stdin → exit 0(설계된 fail-open 유지)" 0 "" \
  "$FM_SANDBOX/proj" "$FM_SANDBOX/emptyhome" "$PATH" ""

# ⑥: 셸 옵션(-e·-u)이 켜져 있어도 같은 매핑이어야 한다. -e는 node의 비0 종료에서
# 매핑 전에 셸을 끝내고, -u는 미설정 CLAUDE_PROJECT_DIR·HOME 참조에서 셸을 끝낸다.
mkdir -p "$FM_SANDBOX/shim1"
printf '%s\n' '#!/bin/sh' 'exit 1' > "$FM_SANDBOX/shim1/node"
chmod +x "$FM_SANDBOX/shim1/node"
for fm_mode in "/bin/sh -e" "/bin/bash -e" "/bin/sh -u"; do
  FM_SH="${fm_mode%% *}"; FM_SH_OPT="${fm_mode#* }"
  fm_case "⑥: ${fm_mode} — 문법 오류 훅 → exit 2 + 안내" 2 "예상 밖 종료 코드" \
    "$FM_SANDBOX/badsyntax" "$FM_SANDBOX/emptyhome" "$PATH" "$PASS_INPUT"
  fm_case "⑥: ${fm_mode} — exit 1 node shim → exit 2 + 안내" 2 "예상 밖 종료 코드" \
    "$FM_SANDBOX/proj" "$FM_SANDBOX/emptyhome" "$FM_SANDBOX/shim1:/usr/bin:/bin" "$PASS_INPUT"
  fm_case "⑥: ${fm_mode} — 통과 입력 → exit 0" 0 "" \
    "$FM_SANDBOX/proj" "$FM_SANDBOX/emptyhome" "$PATH" "$PASS_INPUT"
  fm_case "⑥: ${fm_mode} — 차단 입력 → 훅 판정 exit 2" 2 "[subagent-model-routing]" \
    "$FM_SANDBOX/proj" "$FM_SANDBOX/emptyhome" "$PATH" "$BLOCK_INPUT"
  fm_case "⑥: ${fm_mode} — 빈 stdin → exit 0" 0 "" \
    "$FM_SANDBOX/proj" "$FM_SANDBOX/emptyhome" "$PATH" ""
  fm_case "⑥: ${fm_mode} — CLAUDE_PROJECT_DIR 미설정·전역 문법 오류 훅 → exit 2 + 안내" 2 "예상 밖 종료 코드" \
    - "$FM_SANDBOX/badsyntax" "$PATH" "$PASS_INPUT"
  fm_case "⑥: ${fm_mode} — HOME 미설정·어디에도 없음 → exit 2 + 안내" 2 "훅 스크립트를 찾지 못했다" \
    "$FM_SANDBOX/emptyproj" - "$PATH" "$PASS_INPUT"
done
FM_SH=/bin/sh; FM_SH_OPT=""

# ④: 레포 settings.json에는 이 훅 등록이 없다(스킬 frontmatter가 유일한 등록처).
if grep -q "enforce-subagent-model" "$REPO_ROOT/.claude/settings.json" 2>/dev/null; then
  fm_fail "④: .claude/settings.json에 enforce-subagent-model 등록이 남아 있음"
else
  fm_pass
fi

# ⑤: 훅에 B-18(이름 검사) 분기가 없다.
# 주석 줄(/** */ 본문·//)은 제외하고 코드에서만 찾는다.
B18_LEFT="$(grep -nE 'B-18|passWithNameCheck|NAME_TASK_RE|toolInput\.name' "$HOOK_PATH" | grep -vE '^[0-9]+:[[:space:]]*(\*|//)' | head -3 | tr '\n' ' ')"
if [ -n "$B18_LEFT" ]; then
  fm_fail "⑤: 훅 코드에 B-18 이름 검사 흔적이 남아 있음 ($B18_LEFT)"
else
  fm_pass
fi

# ⑦: .githooks/pre-commit은 테스트 스위트를 부르기 전에 git이 hook에 넘긴 환경
# 변수(GIT_DIR·GIT_INDEX_FILE 등)를 지운다. 지우지 않으면 스위트 안의 샌드박스
# git 명령이 커밋 중인 레포의 공통 .git/config를 고친다. 재현은 /tmp 미끼 레포의
# linked worktree에서 커밋해 미끼 pre-commit(정본 사본)이 stub 스위트를 부르게
# 하는 방식으로만 한다. stub은 받은 GIT_* 이름을 적고 샌드박스에서 git config를 쓴다.
# 커밋은 `git -c core.hooksPath=<절대경로>`(GIT_CONFIG_PARAMETERS 주입)와
# GIT_CONFIG_COUNT·GIT_CONFIG_KEY_0·GIT_CONFIG_VALUE_0을 함께 넘긴다. 둘 다 지워지지
# 않으면 샌드박스 git이 그 설정을 물려받는다(core.hooksPath면 스위트의 샌드박스
# 커밋이 이 pre-commit을 다시 부른다). stub은 샌드박스에서 본 두 설정값도 적는다.
PC_SANDBOX="$(mktemp -d /tmp/smoke-precommit.XXXXXX)"
trap 'rm -rf "$FM_SANDBOX" "$PC_SANDBOX"' EXIT
PC_GIT_VARS="GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX GIT_NAMESPACE GIT_CEILING_DIRECTORIES GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0"
pc_run() (
  # 이 스크립트가 pre-commit 안에서 돌 때도 미끼 git 명령이 바깥 레포를 보지 않게 한다.
  for v in ${PC_GIT_VARS}; do unset "${v}"; done
  set -e
  bait="${PC_SANDBOX}/bait"
  mkdir -p "${bait}/scripts" "${bait}/.githooks"
  cp "${REPO_ROOT}/.githooks/pre-commit" "${bait}/.githooks/pre-commit"
  printf '%s\n' 'import sys' 'sys.exit(0)' > "${bait}/scripts/lint-delegate-first.py"
  for s in test-lint smoke-hook test-reinstall test-delegate-scripts; do
    printf '%s\n' \
      'echo "ran" >> "${BAIT_LOG}"' \
      'env | sed -n "s/^\(GIT_[A-Z0-9_]*\)=.*/\1/p" >> "${BAIT_LOG}"' \
      'inner="$(mktemp -d "${BAIT_LOG}.inner.XXXXXX")"' \
      'cd "${inner}" && git init -q && git config bait.poisoned yes' \
      'echo "seen hooksPath=$(git config --get core.hooksPath) env=$(git config --get bait.env)" >> "${BAIT_LOG}"' \
      'exit 0' > "${bait}/scripts/${s}.sh"
  done
  g() { git -c core.hooksPath=/dev/null -c user.name=smoke -c user.email=smoke@example.invalid -c commit.gpgsign=false "$@"; }
  g -C "${bait}" init -q
  g -C "${bait}" add -A
  g -C "${bait}" commit -q -m base
  g -C "${bait}" worktree add -q -b wt "${PC_SANDBOX}/wt"
  cd "${PC_SANDBOX}/wt"
  echo x > f
  g add f
  BAIT_LOG="${PC_SANDBOX}/env.log" GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=bait.env GIT_CONFIG_VALUE_0=yes \
    git -c core.hooksPath="${bait}/.githooks" -c user.name=smoke \
    -c user.email=smoke@example.invalid -c commit.gpgsign=false commit -q -m wt >/dev/null 2>&1
)
pc_run >/dev/null 2>&1
PC_RC=$?
PC_LEAKED=""
for v in ${PC_GIT_VARS}; do
  grep -qx "${v}" "${PC_SANDBOX}/env.log" 2>/dev/null && PC_LEAKED="${PC_LEAKED} ${v}"
done
PC_RAN="$(grep -c '^ran$' "${PC_SANDBOX}/env.log" 2>/dev/null || true)"
PC_POISONED=no
grep -q poisoned "${PC_SANDBOX}/bait/.git/config" 2>/dev/null && PC_POISONED=yes
PC_SEEN="$(grep -c '^seen hooksPath= env=$' "${PC_SANDBOX}/env.log" 2>/dev/null || true)"
if [ "${PC_RC}" = "0" ] && [ "${PC_RAN}" = "4" ] && [ -z "${PC_LEAKED}" ] && [ "${PC_POISONED}" = "no" ] &&
   [ "${PC_SEEN}" = "4" ]; then
  fm_pass
else
  fm_fail "⑦: pre-commit이 git 환경을 스위트에 넘김 (커밋 rc=${PC_RC}, stub 실행 ${PC_RAN:-0}/4, 누출:${PC_LEAKED:- 없음}, 미끼 .git/config 오염: ${PC_POISONED}, 샌드박스가 -c·GIT_CONFIG_COUNT 설정을 보지 않은 stub ${PC_SEEN:-0}/4)"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "PASS ${PASS_COUNT}/${TOTAL}"
  exit 0
else
  echo "FAIL ${FAIL_COUNT}/${TOTAL} — 실패 케이스:${FAILED_DESCRIPTIONS}"
  exit 1
fi
