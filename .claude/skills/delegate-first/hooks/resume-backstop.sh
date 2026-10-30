#!/usr/bin/env bash
#
# resume-backstop.sh — 전역 ~/.claude/settings.json에 등록한 resume 백스톱의 래퍼.
#
# 전역 등록은 모든 세션의 Agent 호출에서 돈다. 그래서 이 래퍼는 $HOME 사본
# resume-backstop.cjs 하나만 실행하고 프로젝트 경로는 보지 않는다. 프로젝트 경로를
# 보면 그 파일을 둔 아무 레포의 JS가 모든 세션에서 실행된다.
#
# 등록 command는 이 파일을 `bash <경로>`로 실행한다(`#!` 직접 실행이 아니다).
# - cjs가 없으면(스킬 미설치) 조용히 exit 0이다.
# - node가 없으면 stderr에 경고 한 줄을 내고 exit 0이다.
# - cjs의 종료 코드는 0·2만 그대로 넘긴다. 나머지는 경고 한 줄과 함께 2다(fail-closed).
# bash 3.2와 set -e·set -u에서 동작한다. 정본 등록 항목은 resume-backstop.settings.json이다.
#
set -eu

f="${HOME:-}/.claude/skills/delegate-first/hooks/resume-backstop.cjs"
[ -n "${HOME:-}" ] && [ -f "$f" ] || exit 0
command -v node >/dev/null 2>&1 || {
  echo "[delegate-first] resume 백스톱: node를 찾지 못해 검사를 건너뛴다." >&2
  exit 0
}
node "$f" && rc=0 || rc=$?
case "$rc" in
  0 | 2) exit "$rc" ;;
esac
echo "[delegate-first] resume 백스톱이 예상 밖 종료 코드 ${rc}로 끝났다. Agent 호출을 막는다(fail-closed)." >&2
exit 2
