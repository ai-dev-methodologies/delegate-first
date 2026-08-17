#!/usr/bin/env bash
#
# scripts/smoke-hook.sh — 재실행 가능한 enforce-subagent-model.cjs 회귀 스모크.
#
# 목적: .claude/hooks/enforce-subagent-model.cjs를 건드리는 PR의 회귀 게이트.
#   "사람이 diff를 읽는다"가 이 훅의 유일한 공급망 게이트라, 이 스크립트가
#   최소한 알려진 케이스(pinned 목록, whitespace, 타입 변형, prototype
#   pollution 시도, fail-open/fail-closed 경계)의 exit code 회귀를 잡는다.
#
# 부작용: 없음. stdin으로 JSON을 훅에 주입하고 exit code만 관찰한다 —
#   파일 생성/수정, 설정 변경, 네트워크 접근을 하지 않는다.
#
# 실행법:
#   bash scripts/smoke-hook.sh                # 이 레포의 훅을 검사
#   bash scripts/smoke-hook.sh /path/to/other-version.cjs   # 다른 버전과 비교
#
set -u

HOOK_PATH="${1:-$(cd "$(dirname "$0")/.." && pwd)/.claude/hooks/enforce-subagent-model.cjs}"

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

# --- tier 5종: model 없이 호출 → pinned 목록 통과 (exit 0) ---
run_case "tier explorer-low, model 없음" '{"tool_input":{"subagent_type":"explorer-low"}}' 0
run_case "tier executor-med, model 없음" '{"tool_input":{"subagent_type":"executor-med"}}' 0
run_case "tier executor-high, model 없음" '{"tool_input":{"subagent_type":"executor-high"}}' 0
run_case "tier reviewer-high, model 없음" '{"tool_input":{"subagent_type":"reviewer-high"}}' 0
run_case "tier judge-max, model 없음" '{"tool_input":{"subagent_type":"judge-max"}}' 0

# --- general-purpose: pinned 아님 → model 없으면 차단 ---
run_case "general-purpose, model 없음" '{"tool_input":{"subagent_type":"general-purpose"}}' 2
run_case "general-purpose, model 공백 문자열" '{"tool_input":{"subagent_type":"general-purpose","model":"   "}}' 2
run_case "general-purpose, model haiku" '{"tool_input":{"subagent_type":"general-purpose","model":"haiku"}}' 0

# --- 플러그인 정의형 pinned 타입 ---
run_case "oh-my-claudecode:writer, model 없음" '{"tool_input":{"subagent_type":"oh-my-claudecode:writer"}}' 0

# --- tier + model 명시 (덮어쓰기 허용 경로) ---
run_case "tier executor-high + model opus 명시" '{"tool_input":{"subagent_type":"executor-high","model":"opus"}}' 0

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

# --- 파싱 불가/빈 stdin: 설계된 fail-open ---
run_case "비JSON stdin" 'not json {' 0
run_case "빈 stdin" '' 0

# --- break-glass env ---
run_case "ALLOW_INHERITED_SUBAGENT_MODEL=1 + general-purpose model 없음" \
  '{"tool_input":{"subagent_type":"general-purpose"}}' 0 \
  "ALLOW_INHERITED_SUBAGENT_MODEL=1"

TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "PASS ${PASS_COUNT}/${TOTAL}"
  exit 0
else
  echo "FAIL ${FAIL_COUNT}/${TOTAL} — 실패 케이스:${FAILED_DESCRIPTIONS}"
  exit 1
fi
