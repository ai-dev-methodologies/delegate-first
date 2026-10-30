#!/usr/bin/env bash
#
# scripts/test-resume-backstop.sh — resume 백스톱 훅(resume-backstop.cjs)과
# 그 래퍼(resume-backstop.sh), 전역 등록 항목(resume-backstop.settings.json)의 회귀망.
#
# 백스톱은 SKILL.md frontmatter 훅이 resume 뒤 꺼지는 결함을 메운다. 전사에
# delegate-first 호출 기록이 있을 때만 enforce-subagent-model.cjs를 실행하고,
# 기록이 없으면 통과시킨다. 이 스위트는 그 판정(기록 인정·오탐 거부), 종료
# 코드 전달, 경로 해석, 등록 command의 exit 0 경계, 큰 전사 성능을 본다.
# 전역 등록은 모든 세션에서 돌므로 프로젝트 경로의 파일(미끼)을 실행하지 않는지도 본다.
#
# 부작용: 없음. 모든 케이스는 mktemp -d 샌드박스의 가짜 HOME·프로젝트·전사를
# 쓴다. 실제 $HOME/.claude는 읽지도 쓰지도 않는다. 샌드박스는 종료 시 지운다.
#
# 실행법: bash scripts/test-resume-backstop.sh
#
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOK_DIR="$REPO_ROOT/.claude/skills/delegate-first/hooks"
BACKSTOP="$HOOK_DIR/resume-backstop.cjs"
ENFORCE="$HOOK_DIR/enforce-subagent-model.cjs"
ENTRY="$HOOK_DIR/resume-backstop.settings.json"
WRAPPER="$HOOK_DIR/resume-backstop.sh"
NODE_BIN="$(command -v node)"

SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/test-resume-backstop.XXXXXX")"
trap 'rm -rf "$SANDBOX"' EXIT

PASS_COUNT=0
FAIL_COUNT=0
FAILED=""
record() { # record <이름> PASS|FAIL [상세]
  if [ "$2" = PASS ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED="${FAILED}
  - $1: ${3:-}"
  fi
}

# 실제 enforce 사본을 둔 프로젝트, 스킬이 없는 HOME
PROJ="$SANDBOX/proj"
EMPTY_HOME="$SANDBOX/home-empty"
mkdir -p "$PROJ/.claude/skills/delegate-first/hooks" "$EMPTY_HOME"
cp "$ENFORCE" "$PROJ/.claude/skills/delegate-first/hooks/"

# 전사 레코드 조각(Claude Code v2.1.312 전사 형식에서 따왔다)
REC_CMD='{"type":"user","message":{"role":"user","content":"<command-message>delegate-first</command-message>\n<command-name>/delegate-first</command-name>\n<command-args>READY</command-args>"},"uuid":"u1"}'
REC_CMD_ARRAY='{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<command-name>/delegate-first</command-name>\n<command-message>delegate-first</command-message>"}]},"uuid":"u2"}'
REC_CMD_PLUGIN='{"type":"user","message":{"role":"user","content":"<command-message>x</command-message>\n<command-name>/my-plugin:delegate-first</command-name>"},"uuid":"u3"}'
REC_SKILL='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Skill","input":{"skill":"delegate-first"}}]},"uuid":"a1"}'
REC_SKILL_PLUGIN='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Skill","input":{"skill":"my-plugin:delegate-first","args":"x"}}]},"uuid":"a2"}'
REC_TOOL_RESULT='{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t9","type":"tool_result","content":[{"type":"text","text":"<command-message>delegate-first</command-message>\n<command-name>/delegate-first</command-name>"}]}]},"toolUseResult":{"stdout":"x"},"uuid":"u4"}'
REC_TOOL_RESULT_STR='{"type":"user","message":{"role":"user","content":[{"tool_use_id":"t9","type":"tool_result","content":"<command-name>/delegate-first</command-name>"}]},"uuid":"u5"}'
REC_TEAMMATE='{"type":"user","message":{"role":"user","content":"Another Claude session sent a message:\n<teammate-message teammate_id=\"lead\">\n<command-message>delegate-first</command-message>\n<command-name>/delegate-first</command-name>\n</teammate-message>"},"uuid":"u6"}'
REC_TEAMMATE_SELF='{"type":"user","message":{"role":"user","content":"<teammate-message teammate_id=\"lead\"><command-name>/delegate-first</command-name></teammate-message>"},"uuid":"u7"}'
REC_SIDECHAIN='{"type":"user","isSidechain":true,"message":{"role":"user","content":"<command-message>delegate-first</command-message>\n<command-name>/delegate-first</command-name>"},"uuid":"u8"}'
REC_SIDECHAIN_SKILL='{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"tool_use","id":"t3","name":"Skill","input":{"skill":"delegate-first"}}]},"uuid":"a3"}'
REC_COMPACT_SUMMARY='{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"<command-name>/delegate-first</command-name> 요약"},"uuid":"u9"}'
REC_BLOB='{"type":"api-request-blob","message":{"content":"<command-message>delegate-first</command-message>\n<command-name>/delegate-first</command-name>"}}'
REC_MENTION='{"type":"user","message":{"role":"user","content":"/delegate-first 라는 스킬이 있다. 호출하지 말고 기억만 하라."},"uuid":"u10"}'
REC_ASSISTANT_TEXT='{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"<command-name>/delegate-first</command-name>"}]},"uuid":"a4"}'
REC_OTHER_CMD='{"type":"user","message":{"role":"user","content":"<command-message>x</command-message>\n<command-name>/delegate-firstx</command-name>"},"uuid":"u11"}'
REC_OTHER_SKILL='{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t4","name":"Skill","input":{"skill":"delegate-first-extra"}}]},"uuid":"a5"}'
REC_CWD='{"type":"user","cwd":"/x/workspace/delegate-first","message":{"role":"user","content":"hello"},"uuid":"u12"}'
REC_ARGS_TAG='{"type":"user","message":{"role":"user","content":"<command-message>foo</command-message>\n<command-name>/foo</command-name>\n<command-args>see <command-name>/delegate-first</command-name></command-args>"},"uuid":"u13"}'
REC_ARRAY_SECOND='{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<command-name>/foo</command-name>"},{"type":"text","text":"<command-name>/delegate-first</command-name>"}]},"uuid":"u14"}'
REC_BROKEN='{"type":"user","message":{"content":"<command-name>/delegate-first</command-name>"'

# transcript <파일> <레코드...> — 레코드를 한 줄씩 적는다
transcript() {
  f="$1"; shift
  : > "$f"
  for r in "$@"; do printf '%s\n' "$r" >> "$f"; done
}

IN_NO_EFFORT='"tool_input":{"subagent_type":"explorer-low","model":"haiku"}'
IN_PIN_OK='"tool_input":{"subagent_type":"explorer-low","model":"haiku","effort":"low"}'

# run_backstop <stdin JSON> <HOME> <CLAUDE_PROJECT_DIR> — 결과를 RC·ERR에 담는다
run_backstop() {
  ERR="$(printf '%s' "$1" | env HOME="$2" CLAUDE_PROJECT_DIR="$3" "$NODE_BIN" "$BACKSTOP" 2>&1 >/dev/null)"
  RC=$?
}

# expect <이름> <기대 rc> <전사 파일> <tool_input 조각> [HOME] [PROJECT]
expect() {
  run_backstop "{\"transcript_path\":\"$3\",$4}" "${5:-$EMPTY_HOME}" "${6:-$PROJ}"
  if [ "$RC" = "$2" ]; then record "$1" PASS; else record "$1" FAIL "기대 rc=$2 실제 rc=$RC err=[$ERR]"; fi
}

T="$SANDBOX/t"
mkdir -p "$T"

# --- 기록 인정: (가) 슬래시 명령 레코드, (나) Skill tool_use ---
transcript "$T/cmd.jsonl" "$REC_CWD" "$REC_CMD" "$REC_CWD"
expect "기록(가) 문자열 content + effort 누락 → 2" 2 "$T/cmd.jsonl" "$IN_NO_EFFORT"
expect "기록(가) + 핀 일치 → 0" 0 "$T/cmd.jsonl" "$IN_PIN_OK"
transcript "$T/cmd-array.jsonl" "$REC_CMD_ARRAY"
expect "기록(가) text 블록 content + effort 누락 → 2" 2 "$T/cmd-array.jsonl" "$IN_NO_EFFORT"
transcript "$T/cmd-plugin.jsonl" "$REC_CMD_PLUGIN"
expect "기록(가) 플러그인 접두 + effort 누락 → 2" 2 "$T/cmd-plugin.jsonl" "$IN_NO_EFFORT"
transcript "$T/skill.jsonl" "$REC_SKILL"
expect "기록(나) Skill tool_use + effort 누락 → 2" 2 "$T/skill.jsonl" "$IN_NO_EFFORT"
expect "기록(나) + 핀 일치 → 0" 0 "$T/skill.jsonl" "$IN_PIN_OK"
transcript "$T/skill-plugin.jsonl" "$REC_SKILL_PLUGIN"
expect "기록(나) 플러그인 접두 + effort 누락 → 2" 2 "$T/skill-plugin.jsonl" "$IN_NO_EFFORT"
transcript "$T/broken-then-cmd.jsonl" "$REC_BROKEN" "not json" "$REC_CMD"
expect "깨진 줄 뒤의 기록(가) + effort 누락 → 2" 2 "$T/broken-then-cmd.jsonl" "$IN_NO_EFFORT"

# --- 기록 없음과 오탐 거부: 인용·요약·사이드체인은 기록이 아니다 ---
transcript "$T/none.jsonl" "$REC_CWD" "$REC_MENTION"
expect "기록 없음(/delegate-first 언급만) + effort 누락 → 0" 0 "$T/none.jsonl" "$IN_NO_EFFORT"
transcript "$T/empty.jsonl"
expect "빈 전사 → 0" 0 "$T/empty.jsonl" "$IN_NO_EFFORT"
transcript "$T/tr.jsonl" "$REC_TOOL_RESULT" "$REC_TOOL_RESULT_STR"
expect "tool_result 안 인용만 → 0" 0 "$T/tr.jsonl" "$IN_NO_EFFORT"
transcript "$T/tm.jsonl" "$REC_TEAMMATE" "$REC_TEAMMATE_SELF"
expect "팀메이트 메시지 안 인용만 → 0" 0 "$T/tm.jsonl" "$IN_NO_EFFORT"
transcript "$T/side.jsonl" "$REC_SIDECHAIN" "$REC_SIDECHAIN_SKILL"
expect "사이드체인(서브에이전트) 레코드만 → 0" 0 "$T/side.jsonl" "$IN_NO_EFFORT"
transcript "$T/cs.jsonl" "$REC_COMPACT_SUMMARY"
expect "compact 요약 안 인용만 → 0" 0 "$T/cs.jsonl" "$IN_NO_EFFORT"
transcript "$T/misc.jsonl" "$REC_BLOB" "$REC_ASSISTANT_TEXT" "$REC_OTHER_CMD" "$REC_OTHER_SKILL" "$REC_BROKEN"
expect "api-request-blob·assistant 텍스트·다른 명령·다른 스킬·깨진 줄만 → 0" 0 "$T/misc.jsonl" "$IN_NO_EFFORT"
# 첫 <command-name> 값만 본다: 다른 명령의 args·뒤 블록에 든 태그는 기록이 아니다
transcript "$T/args-tag.jsonl" "$REC_ARGS_TAG"
expect "다른 명령의 args 안 <command-name> 태그 → 0" 0 "$T/args-tag.jsonl" "$IN_NO_EFFORT"
transcript "$T/array-second.jsonl" "$REC_ARRAY_SECOND"
expect "첫 text 블록이 다른 명령, 둘째 블록에 태그 → 0" 0 "$T/array-second.jsonl" "$IN_NO_EFFORT"

# --- 전사를 읽지 못함 → 0과 경고 한 줄 ---
expect "transcript 파일 없음 → 0" 0 "$T/missing.jsonl" "$IN_NO_EFFORT"
if [ -n "$ERR" ]; then record "transcript 파일 없음 → 경고" PASS; else record "transcript 파일 없음 → 경고" FAIL "stderr가 비었다"; fi
run_backstop "{$IN_NO_EFFORT}" "$EMPTY_HOME" "$PROJ"
if [ "$RC" = 0 ] && [ -n "$ERR" ]; then record "transcript_path 키 없음 → 0과 경고" PASS; else record "transcript_path 키 없음 → 0과 경고" FAIL "rc=$RC err=[$ERR]"; fi
run_backstop "not json" "$EMPTY_HOME" "$PROJ"
if [ "$RC" = 0 ] && [ -n "$ERR" ]; then record "stdin JSON 아님 → 0과 경고" PASS; else record "stdin JSON 아님 → 0과 경고" FAIL "rc=$RC err=[$ERR]"; fi

# --- 경로 해석: 프로젝트 사본 → $HOME 사본, 둘 다 없으면 2 ---
SKILL_HOME="$SANDBOX/home-skill"
mkdir -p "$SKILL_HOME/.claude/skills/delegate-first/hooks" "$SANDBOX/proj-empty"
cp "$ENFORCE" "$SKILL_HOME/.claude/skills/delegate-first/hooks/"
expect "프로젝트 사본 없음 → \$HOME 사본으로 차단 2" 2 "$T/cmd.jsonl" "$IN_NO_EFFORT" "$SKILL_HOME" "$SANDBOX/proj-empty"
expect "CLAUDE_PROJECT_DIR 빈 값 → \$HOME 사본으로 차단 2" 2 "$T/cmd.jsonl" "$IN_NO_EFFORT" "$SKILL_HOME" ""
expect "기록 있음 + 스크립트 없음(프로젝트·HOME) → 2" 2 "$T/cmd.jsonl" "$IN_PIN_OK" "$EMPTY_HOME" "$SANDBOX/proj-empty"
expect "기록 없음 + 스크립트 없음 → 0" 0 "$T/none.jsonl" "$IN_NO_EFFORT" "$EMPTY_HOME" "$SANDBOX/proj-empty"

# --- 두 사본이 있으면 $HOME 사본을 실행하고, 해시가 다르면 경고한다 ---
MARK_ENF="$SANDBOX/ENFORCE_PWNED"
PROJ_ODD="$SANDBOX/proj-odd"
mkdir -p "$PROJ_ODD/.claude/skills/delegate-first/hooks"
printf '%s\n' "require('fs').writeFileSync('$MARK_ENF', 'x'); process.exit(0);" \
  > "$PROJ_ODD/.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs"
run_backstop "{\"transcript_path\":\"$T/cmd.jsonl\",$IN_NO_EFFORT}" "$SKILL_HOME" "$PROJ_ODD"
if [ "$RC" = 2 ] && [ ! -e "$MARK_ENF" ] && printf '%s' "$ERR" | grep -q "sha256"; then
  record "두 사본 해시 불일치 → \$HOME 사본으로 차단 2, 프로젝트 사본 미실행, 경고" PASS
else
  record "두 사본 해시 불일치 → \$HOME 사본으로 차단 2, 프로젝트 사본 미실행, 경고" FAIL "rc=$RC mark=$([ -e "$MARK_ENF" ] && echo 생김 || echo 없음) err=[$ERR]"
fi
rm -f "$MARK_ENF"
run_backstop "{\"transcript_path\":\"$T/cmd.jsonl\",$IN_PIN_OK}" "$SKILL_HOME" "$PROJ"
if [ "$RC" = 0 ] && [ -z "$ERR" ]; then
  record "두 사본 해시 일치 → 경고 없음" PASS
else
  record "두 사본 해시 일치 → 경고 없음" FAIL "rc=$RC err=[$ERR]"
fi

# --- 종료 코드 전달: stub enforce가 rc를 돌려주고 받은 stdin을 적는다 ---
for code in 0 2 1 127 3; do
  stub="$SANDBOX/stub-$code"
  mkdir -p "$stub/.claude/skills/delegate-first/hooks"
  printf '%s\n' "require('fs').writeFileSync(process.env.STUB_LOG, require('fs').readFileSync(0)); process.exit($code);" \
    > "$stub/.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs"
  want=2; [ "$code" = 0 ] && want=0
  input="{\"transcript_path\":\"$T/cmd.jsonl\",$IN_PIN_OK}"
  got_err="$(printf '%s' "$input" | env HOME="$EMPTY_HOME" CLAUDE_PROJECT_DIR="$stub" STUB_LOG="$stub/stdin.log" "$NODE_BIN" "$BACKSTOP" 2>&1 >/dev/null)"
  got=$?
  if [ "$got" = "$want" ] && [ "$(cat "$stub/stdin.log" 2>/dev/null)" = "$input" ]; then
    record "enforce 종료 코드 $code → $want, stdin 그대로 전달" PASS
  else
    record "enforce 종료 코드 $code → $want, stdin 그대로 전달" FAIL "rc=$got stdin=[$(cat "$stub/stdin.log" 2>/dev/null)] err=[$got_err]"
  fi
done

# --- 큰 전사 성능: 약 40MB, 경로에 delegate-first가 든 줄이 대부분 ---
BIG="$T/big.jsonl"
"$NODE_BIN" -e '
  const fs = require("fs");
  const pad = "x".repeat(2000);
  const fd = fs.openSync(process.argv[1], "w");
  for (let i = 0; i < 20000; i++) {
    fs.writeSync(fd, JSON.stringify({ type: i % 2 ? "user" : "assistant", cwd: "/x/workspace/delegate-first",
      message: { role: "user", content: [{ type: "tool_result", content: "delegate-first " + pad }] } }) + "\n");
  }
  fs.closeSync(fd);' "$BIG"
cp "$BIG" "$T/big-hit.jsonl"
printf '%s\n' "$REC_CMD" >> "$T/big-hit.jsonl"
for kind in big big-hit; do
  want=0; [ "$kind" = big-hit ] && want=2
  start="$("$NODE_BIN" -e 'console.log(Date.now())')"
  run_backstop "{\"transcript_path\":\"$T/$kind.jsonl\",$IN_NO_EFFORT}" "$EMPTY_HOME" "$PROJ"
  ms=$(( $("$NODE_BIN" -e 'console.log(Date.now())') - start ))
  echo "  [성능] $kind.jsonl $(($(wc -c < "$T/$kind.jsonl") / 1048576))MB → rc=$RC ${ms}ms"
  if [ "$RC" = "$want" ] && [ "$ms" -lt 3000 ]; then
    record "큰 전사($kind) rc=$want, 3초 미만" PASS
  else
    record "큰 전사($kind) rc=$want, 3초 미만" FAIL "rc=$RC ${ms}ms err=[$ERR]"
  fi
done

# --- 전역 등록 항목: command는 스킬 미설치·node 없음에서 exit 0이다 ---
CMD="$("$NODE_BIN" -e '
  const e = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
  if (e.matcher !== "Agent" || !Array.isArray(e.hooks) || e.hooks.length !== 1 || e.hooks[0].type !== "command") process.exit(1);
  process.stdout.write(e.hooks[0].command);' "$ENTRY" 2>/dev/null)"
if [ -n "$CMD" ]; then record "등록 항목 형식(matcher Agent, command 1개)" PASS; else record "등록 항목 형식(matcher Agent, command 1개)" FAIL "$ENTRY 를 읽지 못했거나 형식이 다르다"; fi
case "$CMD" in
  *enforce-subagent-model*) record "등록 command에 enforce-subagent-model 없음(reinstall.sh 옛 등록 탐지와 겹침 방지)" FAIL "command=[$CMD]" ;;
  *) record "등록 command에 enforce-subagent-model 없음(reinstall.sh 옛 등록 탐지와 겹침 방지)" PASS ;;
esac

case "$CMD" in
  *CLAUDE_PROJECT_DIR*) record "등록 command에 CLAUDE_PROJECT_DIR 없음(프로젝트 경로 실행 금지)" FAIL "command=[$CMD]" ;;
  *) record "등록 command에 CLAUDE_PROJECT_DIR 없음(프로젝트 경로 실행 금지)" PASS ;;
esac
case "$CMD" in
  *'$HOME/.claude/skills/delegate-first/hooks/resume-backstop.sh'*'bash "$f"'*) record "등록 command는 \$HOME 래퍼를 bash로 실행" PASS ;;
  *) record "등록 command는 \$HOME 래퍼를 bash로 실행" FAIL "command=[$CMD]" ;;
esac
if [ -f "$WRAPPER" ] && ! grep -v '^[[:space:]]*#' "$WRAPPER" | grep -q CLAUDE_PROJECT_DIR; then
  record "래퍼 코드에 CLAUDE_PROJECT_DIR 없음" PASS
else
  record "래퍼 코드에 CLAUDE_PROJECT_DIR 없음" FAIL "$WRAPPER 가 없거나 주석 밖에서 CLAUDE_PROJECT_DIR를 쓴다"
fi

# run_cmd <PATH> <HOME> <PROJECT> <stdin> — 등록 command를 /bin/sh로 실행한다
# PATH의 bash는 /bin/bash(macOS 3.2)다. node 디렉터리에는 bash가 없다.
run_cmd() {
  ERR="$(printf '%s' "$4" | env -i PATH="$1" HOME="$2" CLAUDE_PROJECT_DIR="$3" /bin/sh -c "$CMD" 2>&1 >/dev/null)"
  RC=$?
}
NODE_PATH_DIR="$(dirname "$NODE_BIN"):/usr/bin:/bin"
# home_with <디렉터리> <파일...> — 가짜 HOME의 스킬 hooks 디렉터리에 파일을 둔다
home_with() {
  h="$1"; shift
  mkdir -p "$h/.claude/skills/delegate-first/hooks"
  [ "$#" -eq 0 ] || cp "$@" "$h/.claude/skills/delegate-first/hooks/"
}
INSTALLED_HOME="$SANDBOX/home-installed"
home_with "$INSTALLED_HOME" "$BACKSTOP" "$ENFORCE" "$WRAPPER"
HIT="{\"transcript_path\":\"$T/cmd.jsonl\",$IN_NO_EFFORT}"
MISS="{\"transcript_path\":\"$T/none.jsonl\",$IN_NO_EFFORT}"

run_cmd "$NODE_PATH_DIR" "$EMPTY_HOME" "$SANDBOX/proj-empty" "$HIT"
if [ "$RC" = 0 ] && [ -z "$ERR" ]; then record "command: 스킬 미설치 → 0(조용히)" PASS; else record "command: 스킬 미설치 → 0(조용히)" FAIL "rc=$RC err=[$ERR]"; fi
NOWRAP_HOME="$SANDBOX/home-nowrap"
home_with "$NOWRAP_HOME" "$BACKSTOP" "$ENFORCE"
run_cmd "$NODE_PATH_DIR" "$NOWRAP_HOME" "$SANDBOX/proj-empty" "$HIT"
if [ "$RC" = 0 ] && [ -z "$ERR" ]; then record "command: 래퍼 없음(cjs만 있음) → 0(조용히)" PASS; else record "command: 래퍼 없음(cjs만 있음) → 0(조용히)" FAIL "rc=$RC err=[$ERR]"; fi
WRAPONLY_HOME="$SANDBOX/home-wraponly"
home_with "$WRAPONLY_HOME" "$WRAPPER"
run_cmd "$NODE_PATH_DIR" "$WRAPONLY_HOME" "$SANDBOX/proj-empty" "$HIT"
if [ "$RC" = 0 ] && [ -z "$ERR" ]; then record "command: 래퍼만 있고 cjs 없음 → 0(조용히)" PASS; else record "command: 래퍼만 있고 cjs 없음 → 0(조용히)" FAIL "rc=$RC err=[$ERR]"; fi
run_cmd "/usr/bin:/bin" "$INSTALLED_HOME" "$SANDBOX/proj-empty" "$HIT"
if [ "$RC" = 0 ] && [ -n "$ERR" ]; then record "command: node 없음 → 0과 경고" PASS; else record "command: node 없음 → 0과 경고" FAIL "rc=$RC err=[$ERR]"; fi
run_cmd "$NODE_PATH_DIR" "$INSTALLED_HOME" "$SANDBOX/proj-empty" "$HIT"
if [ "$RC" = 2 ]; then record "command: \$HOME 설치 + 기록 + effort 누락 → 2" PASS; else record "command: \$HOME 설치 + 기록 + effort 누락 → 2" FAIL "rc=$RC err=[$ERR]"; fi
run_cmd "$NODE_PATH_DIR" "$INSTALLED_HOME" "$SANDBOX/proj-empty" "$MISS"
if [ "$RC" = 0 ]; then record "command: \$HOME 설치 + 기록 없음 → 0" PASS; else record "command: \$HOME 설치 + 기록 없음 → 0" FAIL "rc=$RC err=[$ERR]"; fi

# 예상 밖 종료: 백스톱 cjs가 1로 끝나거나 enforce가 1로 끝나면 2(fail-closed)
CRASH_HOME="$SANDBOX/home-crash"
home_with "$CRASH_HOME" "$WRAPPER"
echo 'process.exit(1);' > "$CRASH_HOME/.claude/skills/delegate-first/hooks/resume-backstop.cjs"
run_cmd "$NODE_PATH_DIR" "$CRASH_HOME" "$SANDBOX/proj-empty" "$HIT"
if [ "$RC" = 2 ] && [ -n "$ERR" ]; then record "command: 백스톱 예상 밖 종료(1) → 2와 경고" PASS; else record "command: 백스톱 예상 밖 종료(1) → 2와 경고" FAIL "rc=$RC err=[$ERR]"; fi
ENF_CRASH_HOME="$SANDBOX/home-enforce-crash"
home_with "$ENF_CRASH_HOME" "$WRAPPER" "$BACKSTOP"
echo 'process.exit(1);' > "$ENF_CRASH_HOME/.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs"
run_cmd "$NODE_PATH_DIR" "$ENF_CRASH_HOME" "$SANDBOX/proj-empty" "$HIT"
if [ "$RC" = 2 ] && [ -n "$ERR" ]; then record "command: enforce 예상 밖 종료(1) → 2와 경고" PASS; else record "command: enforce 예상 밖 종료(1) → 2와 경고" FAIL "rc=$RC err=[$ERR]"; fi

# 미끼: 프로젝트 경로의 백스톱·래퍼·enforce는 기록 유무와 무관하게 실행되지 않는다
MARK="$SANDBOX/PWNED"
DECOY="$SANDBOX/proj-decoy"
mkdir -p "$DECOY/.claude/skills/delegate-first/hooks"
for name in resume-backstop.cjs enforce-subagent-model.cjs; do
  printf '%s\n' "require('fs').writeFileSync('$MARK', '$name'); process.exit(0);" > "$DECOY/.claude/skills/delegate-first/hooks/$name"
done
printf '%s\n' "echo resume-backstop.sh > '$MARK'; exit 0" > "$DECOY/.claude/skills/delegate-first/hooks/resume-backstop.sh"
for home_kind in empty installed; do
  h="$EMPTY_HOME"; [ "$home_kind" = installed ] && h="$INSTALLED_HOME"
  for rec in hit miss; do
    input="$MISS"; want=0
    if [ "$rec" = hit ]; then input="$HIT"; [ "$home_kind" = installed ] && want=2; fi
    rm -f "$MARK"
    run_cmd "$NODE_PATH_DIR" "$h" "$DECOY" "$input"
    name="command: 미끼 프로젝트(HOME $home_kind, 기록 $rec) → $want, 미끼 미실행"
    if [ "$RC" = "$want" ] && [ ! -e "$MARK" ]; then record "$name" PASS; else record "$name" FAIL "rc=$RC mark=[$(cat "$MARK" 2>/dev/null)] err=[$ERR]"; fi
  done
done

# 래퍼 직접 실행: bash 3.2·set -eu 셸 옵션·HOME 미설정에서도 0이다
if [ -f "$WRAPPER" ]; then
  out="$(env -i PATH="$NODE_PATH_DIR" /bin/bash -eu "$WRAPPER" < /dev/null 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && [ -z "$out" ]; then record "래퍼: HOME 미설정(/bin/bash -eu) → 0(조용히)" PASS; else record "래퍼: HOME 미설정(/bin/bash -eu) → 0(조용히)" FAIL "rc=$rc out=[$out]"; fi
else
  record "래퍼: HOME 미설정(/bin/bash -eu) → 0(조용히)" FAIL "$WRAPPER 없음"
fi

TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "PASS ${PASS_COUNT}/${TOTAL}"
  exit 0
fi
echo "FAIL ${FAIL_COUNT}/${TOTAL} — 실패 케이스:${FAILED}"
exit 1
