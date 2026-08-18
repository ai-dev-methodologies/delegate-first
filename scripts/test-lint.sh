#!/usr/bin/env bash
#
# scripts/test-lint.sh — scripts/lint-delegate-first.py의 회귀망.
#
# 목적: 린터 자신이 조용히 망가지는 것을 막는다("누가 린터를 검사하는가").
#   리뷰(reviewer-high)와 릴리스 게이트(judge-max)가 독립적으로 지목한
#   미탐(fail-open 의미군, 표 스캔 무신호 절단, 훅 Set 리터럴 파서 폭주,
#   영구 WARN, 파일 stem↔name 식별자 드리프트 등)이 실제로 검출되는지
#   양성 케이스로, 정상 입력을 오탐하지 않는지 음성 케이스로 확인한다.
#
# 부작용: 없음. mktemp -d로 만든 임시 디렉터리에 레포 파일을 **복사**한
#   뒤에만 변형한다 — 레포 파일 자체는 절대 건드리지 않는다. 종료 시
#   trap으로 임시 디렉터리를 정리한다.
#
# 실행법: bash scripts/test-lint.sh
#
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LINT_SCRIPT="$REPO_ROOT/scripts/lint-delegate-first.py"

SCRATCH="$(mktemp -d)"
cleanup() { rm -rf "$SCRATCH"; }
trap cleanup EXIT

# --- 베이스라인 사본 (레포 원본은 절대 건드리지 않음) ---
BASE_AGENTS="$SCRATCH/base_agents"
BASE_HOOK="$SCRATCH/base_hook.cjs"
BASE_LOG="$SCRATCH/base_log.md"
mkdir -p "$BASE_AGENTS"
cp "$REPO_ROOT"/.claude/agents/*.md "$BASE_AGENTS"/
cp "$REPO_ROOT"/.claude/hooks/enforce-subagent-model.cjs "$BASE_HOOK"
cp "$REPO_ROOT"/docs/handoff/delegation-log.md "$BASE_LOG"

PASS_COUNT=0
FAIL_COUNT=0
FAILED_DESCRIPTIONS=""
CASE_NUM=0

# new_case — 베이스라인을 새 케이스 디렉터리로 복사하고 CASE_* 변수를 설정한다.
new_case() {
  CASE_NUM=$((CASE_NUM + 1))
  CASE_DIR="$SCRATCH/case_${CASE_NUM}"
  mkdir -p "$CASE_DIR/agents"
  cp -R "$BASE_AGENTS/." "$CASE_DIR/agents/"
  cp "$BASE_HOOK" "$CASE_DIR/hook.cjs"
  cp "$BASE_LOG" "$CASE_DIR/log.md"
}

# run_and_check <설명> <기대 exit code>
run_and_check() {
  desc="$1"
  expected="$2"
  actual=$(python3 "$LINT_SCRIPT" \
    --agents-dir "$CASE_DIR/agents" \
    --hook-path "$CASE_DIR/hook.cjs" \
    --log-path "$CASE_DIR/log.md" \
    >"$CASE_DIR/out.txt" 2>&1; echo $?)

  if [ "$actual" = "$expected" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_DESCRIPTIONS="${FAILED_DESCRIPTIONS}
  - ${desc} (기대 exit ${expected}, 실제 exit ${actual}, 출력: ${CASE_DIR}/out.txt)"
  fi
}

# run_dual <설명> <기본 모드 기대 exit> <--strict 기대 exit> [출력에 있어야 할 grep -E 패턴]
# B-10: 기본 모드와 --strict 모드를 각각 실행해 둘 다 기대 exit code인지
# 확인한다. grep 패턴이 주어지면 기본 모드 출력에 그 패턴(예: 클래스 태그
# [WARN:drift]/[WARN:workflow])이 실제로 나타나는지도 함께 확인한다.
run_dual() {
  desc="$1"
  expected_default="$2"
  expected_strict="$3"
  grep_pattern="${4:-}"

  actual_default=$(python3 "$LINT_SCRIPT" \
    --agents-dir "$CASE_DIR/agents" \
    --hook-path "$CASE_DIR/hook.cjs" \
    --log-path "$CASE_DIR/log.md" \
    >"$CASE_DIR/out_default.txt" 2>&1; echo $?)

  actual_strict=$(python3 "$LINT_SCRIPT" \
    --agents-dir "$CASE_DIR/agents" \
    --hook-path "$CASE_DIR/hook.cjs" \
    --log-path "$CASE_DIR/log.md" \
    --strict \
    >"$CASE_DIR/out_strict.txt" 2>&1; echo $?)

  ok=1
  reason=""
  if [ "$actual_default" != "$expected_default" ]; then
    ok=0
    reason="${reason} 기본 exit ${expected_default} 기대, 실제 ${actual_default}."
  fi
  if [ "$actual_strict" != "$expected_strict" ]; then
    ok=0
    reason="${reason} strict exit ${expected_strict} 기대, 실제 ${actual_strict}."
  fi
  if [ -n "$grep_pattern" ] && ! grep -E -q -- "$grep_pattern" "$CASE_DIR/out_default.txt"; then
    ok=0
    reason="${reason} 기본 출력에 패턴 '${grep_pattern}' 없음."
  fi

  if [ "$ok" -eq 1 ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    FAILED_DESCRIPTIONS="${FAILED_DESCRIPTIONS}
  - ${desc} (${reason} 출력: ${CASE_DIR}/out_default.txt / ${CASE_DIR}/out_strict.txt)"
  fi
}

# ===========================================================================
# 양성 케이스 (FAIL을 기대 — 종료코드 1)
# ===========================================================================

# 1. model 라인 삭제
new_case
python3 -c "
import re
p = '$CASE_DIR/agents/executor-high.md'
lines = open(p, encoding='utf-8').read().splitlines()
lines = [l for l in lines if not l.startswith('model:')]
open(p, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
"
run_and_check "model 라인 삭제" 1

# 2. model: inherit
new_case
python3 -c "
p = '$CASE_DIR/agents/executor-high.md'
t = open(p, encoding='utf-8').read().replace('model: sonnet', 'model: inherit')
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "model: inherit" 1

# 3. model: Inherit (대소문자 변형)
new_case
python3 -c "
p = '$CASE_DIR/agents/executor-high.md'
t = open(p, encoding='utf-8').read().replace('model: sonnet', 'model: Inherit')
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "model: Inherit" 1

# 4. model: (빈 값)
new_case
python3 -c "
p = '$CASE_DIR/agents/executor-high.md'
t = open(p, encoding='utf-8').read().replace('model: sonnet', 'model:')
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "model:(빈값)" 1

# 5. model: ""
new_case
python3 -c "
p = '$CASE_DIR/agents/executor-high.md'
t = open(p, encoding='utf-8').read().replace('model: sonnet', 'model: \"\"')
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check 'model: ""' 1

# 6. model: null
new_case
python3 -c "
p = '$CASE_DIR/agents/executor-high.md'
t = open(p, encoding='utf-8').read().replace('model: sonnet', 'model: null')
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "model: null" 1

# 7. model: ~
new_case
python3 -c "
p = '$CASE_DIR/agents/executor-high.md'
t = open(p, encoding='utf-8').read().replace('model: sonnet', 'model: ~')
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "model: ~" 1

# 8. 닫는 펜스 없는 frontmatter
new_case
python3 -c "
p = '$CASE_DIR/agents/executor-med.md'
lines = open(p, encoding='utf-8').read().splitlines()
# 첫 줄(인덱스 0)은 여는 '---'. 그 다음에 나오는 첫 '---'(닫는 펜스)를 제거한다.
closing_idx = next(i for i in range(1, len(lines)) if lines[i].strip() == '---')
del lines[closing_idx]
open(p, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
"
run_and_check "닫는 펜스 없는 frontmatter" 1

# 9. 훅 Set 리터럴을 한 줄로 포매팅 + model 제거 (동시 회귀)
new_case
python3 -c "
import re
p = '$CASE_DIR/hook.cjs'
text = open(p, encoding='utf-8').read()
m = re.search(r'const MODEL_PINNED_TYPES = new Set\(\[(.*?)\]\);', text, re.DOTALL)
items = re.findall(r'\"([^\"]+)\"', m.group(1))
oneline = 'const MODEL_PINNED_TYPES = new Set([' + ','.join('\"%s\"' % it for it in items) + ']);'
text2 = text[:m.start()] + oneline + text[m.end():]
open(p, 'w', encoding='utf-8').write(text2)
"
python3 -c "
p = '$CASE_DIR/agents/judge-max.md'
lines = open(p, encoding='utf-8').read().splitlines()
lines = [l for l in lines if not l.startswith('model:')]
open(p, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
"
run_and_check "훅 Set 한 줄 포매팅 + model 제거" 1

# 10. 훅 변수명 변경(파싱 실패)
# 주의: 새 이름이 원래 이름을 부분 문자열로 포함하면(예: 단순히 접미사만
# 붙이면) "MODEL_PINNED_TYPES" in code_line 판정이 여전히 참이 되어 파싱이
# 깨지지 않는다 — 원래 식별자를 부분 문자열로도 포함하지 않는 이름으로 바꿔야
# 실제로 "변수명이 바뀌어 린터가 못 찾는" 상황을 재현한다.
new_case
python3 -c "
p = '$CASE_DIR/hook.cjs'
t = open(p, encoding='utf-8').read().replace('MODEL_PINNED_TYPES', 'AGENT_MODEL_ALLOWLIST')
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "훅 변수명 변경(파싱 실패)" 1

# 11. 빈 agents 디렉터리
new_case
rm -f "$CASE_DIR"/agents/*.md
run_and_check "빈 agents 디렉터리" 1

# 12. 로그 행 컬럼 누락
new_case
python3 -c "
p = '$CASE_DIR/log.md'
lines = open(p, encoding='utf-8').read().splitlines()
idx = next(i for i, l in enumerate(lines) if 'blocked-as-designed' in l)
cells = [c.strip() for c in lines[idx].strip().strip('|').split('|')]
del cells[4]  # 컬럼 하나 제거 (7 -> 6컬럼)
lines[idx] = '| ' + ' | '.join(cells) + ' |'
open(p, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
"
run_and_check "로그 행 컬럼 누락" 1

# 13. 로그 구분선 삭제 + 첫 행 파손
new_case
python3 -c "
p = '$CASE_DIR/log.md'
lines = open(p, encoding='utf-8').read().splitlines()
header_idx = next(i for i, l in enumerate(lines) if l.strip().startswith('|') and '날짜' in l)
sep_idx = header_idx + 1
del lines[sep_idx]  # 구분선 삭제
# 이제 sep_idx 자리가 원래 첫 데이터 행이다 — 컬럼 하나를 제거해 파손시킨다.
cells = [c.strip() for c in lines[sep_idx].strip().strip('|').split('|')]
del cells[2]
lines[sep_idx] = '| ' + ' | '.join(cells) + ' |'
open(p, 'w', encoding='utf-8').write('\n'.join(lines) + '\n')
"
run_and_check "로그 구분선 삭제 + 첫 행 파손" 1

# 14. 표 뒤 빈 줄 다음 깨진 행 append
new_case
python3 -c "
p = '$CASE_DIR/log.md'
with open(p, 'a', encoding='utf-8') as f:
    f.write('\n')
    f.write('| 2026-08-19 | broken-agent | role만 있고 컬럼 부족 | model |\n')
"
run_and_check "표 뒤 빈 줄 다음 깨진 행 append" 1

# 15. 날짜 2026-13-45
new_case
python3 -c "
p = '$CASE_DIR/log.md'
t = open(p, encoding='utf-8').read().replace('| 2026-08-18 | explorer-low | 훅 차단', '| 2026-13-45 | explorer-low | 훅 차단', 1)
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "날짜 2026-13-45" 1

# 16. name이 파일 stem과 불일치
new_case
python3 -c "
p = '$CASE_DIR/agents/executor-high.md'
t = open(p, encoding='utf-8').read().replace('name: executor-high', 'name: executor-high-drift', 1)
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "name이 파일 stem과 불일치" 1

# 17. P-1 회귀 케이스 1: 1차 표 헤더 오타 + 그 표에 깨진 행(컬럼 부족) + 정상 2차 표.
# F1(헤더 판정을 부분문자열 → 전체 7컬럼 일치로 좁힌 수정)이 만든 미탐 —
# 1차 표 헤더가 깨지면 find_next_header가 파일 처음부터 스캔하다 그 표
# 전체(깨진 헤더+구분선+깨진 행)를 지나쳐 2차 표의 정상 헤더에서야 멈췄고,
# 1차 표는 어느 스캔에도 걸리지 않은 채 exit 0이 될 수 있었다.
new_case
python3 -c "
p = '$CASE_DIR/log.md'
content = '''| 날짜 | agnet | role | model | effort | 실행경로 | 결과 |
|---|---|---|---|---|---|---|
| 2026-08-19 | executor-high | 컬럼 부족 | sonnet |
두 번째 표는 아래 참고.
| 날짜 | agent | role | model | effort | 실행경로 | 결과 |
|---|---|---|---|---|---|---|
| 2026-08-19 | executor-high | 정상 행 | sonnet | high(frontmatter) | Agent(tier) | pass |
'''
open(p, 'w', encoding='utf-8').write(content)
"
run_and_check "P-1 회귀1: 1차 표 헤더 오타+깨진 행+정상 2차 표 (FAIL 기대)" 1

# 18. P-1 회귀 케이스 2: 2차 표 헤더 오타 + 잘못된 실행경로 행.
# 1차 표는 정상적으로 닫히고(텍스트 구분선), 2차 표는 헤더가 깨져 있어
# find_next_header가 2차 표를 아예 지나쳐 버리고(더 이상 헤더가 없으므로
# 스캔 종료), 2차 표의 '실행경로' 위반이 검출되지 않은 채 exit 0이 될 수
# 있었다.
new_case
python3 -c "
p = '$CASE_DIR/log.md'
content = '''| 날짜 | agent | role | model | effort | 실행경로 | 결과 |
|---|---|---|---|---|---|---|
| 2026-08-19 | executor-high | 정상 행 | sonnet | high(frontmatter) | Agent(tier) | pass |
두 번째 표는 아래 참고.
| 날짜 | agnet | role | model | effort | 실행경로 | 결과 |
|---|---|---|---|---|---|---|
| 2026-08-19 | executor-high | 잘못된 실행경로 | sonnet | high(frontmatter) | wrong-path | pass |
'''
open(p, 'w', encoding='utf-8').write(content)
"
run_and_check "P-1 회귀2: 2차 표 헤더 오타+잘못된 실행경로 행 (FAIL 기대)" 1

# 19. B-09: MODEL_PINNED_TYPES Set 항목에 문자열 연결(+) 사용 — model/map은
# 건드리지 않는다(순수 파싱 신호만 격리해서 확인). 구버전 린터는 이 항목을
# STRING_LITERAL_RE.finditer로 "executor-"와 "high" 두 개의 별개 유효 항목
# 으로 오추출해(둘 다 IDENT_RE 문자 집합을 통과) 원래 이름 "executor-high"가
# pinned 목록에서 조용히 "빠진 것"처럼 보이게 만들었다 — FAIL 없이 WARN만
# 발생해 기본 모드에서 exit 0이었다(BACKLOG B-09 실측과 동일 패턴).
new_case
python3 -c "
p = '$CASE_DIR/hook.cjs'
t = open(p, encoding='utf-8').read()
old = '  \"executor-high\", // sonnet/high\n'
new = '  \"executor-\" + \"high\", // sonnet/high\n'
assert old in t, 'fixture 문자열을 찾지 못함 — 훅 포매팅이 바뀌었을 수 있음'
t = t.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "B-09: Set 항목 문자열 연결(+) (FAIL 기대)" 1

# 20. B-09: MODEL_PINNED_TYPES Set 항목에 템플릿 리터럴 보간(\${...}) 사용.
new_case
python3 -c "
p = '$CASE_DIR/hook.cjs'
t = open(p, encoding='utf-8').read()
old = '  \"executor-high\", // sonnet/high\n'
new = '  \`executor-\${\"high\"}\`, // sonnet/high\n'
assert old in t, 'fixture 문자열을 찾지 못함 — 훅 포매팅이 바뀌었을 수 있음'
t = t.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "B-09: Set 항목 템플릿 리터럴 보간 (FAIL 기대)" 1

# 21. B-11: TIER_EXPECTED_MODEL map에서 tier 하나 누락(Set·frontmatter는
# 그대로) — pinned Set엔 'executor-high'가 있고 frontmatter도 정상인데 map
# 에서만 그 항목이 빠진 상태. 구버전 린터(TIER_EXPECTED_MODEL을 전혀 모름)
# 는 이 드리프트를 원리상 볼 수 없어 exit 0이다.
new_case
python3 -c "
p = '$CASE_DIR/hook.cjs'
t = open(p, encoding='utf-8').read()
old = '  \"executor-high\": \"sonnet\",\n'
assert old in t, 'fixture 문자열을 찾지 못함 — 훅 포매팅이 바뀌었을 수 있음'
t = t.replace(old, '', 1)
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "B-11: map에 tier 누락 (FAIL 기대)" 1

# 22. B-11: TIER_EXPECTED_MODEL map 값이 frontmatter와 불일치(Set은 그대로,
# frontmatter도 그대로 sonnet) — map만 'opus'로 드리프트된 상태. 구버전
# 린터는 map을 전혀 읽지 않으므로 이 드리프트도 원리상 볼 수 없어 exit 0.
new_case
python3 -c "
p = '$CASE_DIR/hook.cjs'
t = open(p, encoding='utf-8').read()
old = '  \"executor-high\": \"sonnet\",\n'
new = '  \"executor-high\": \"opus\",\n'
assert old in t, 'fixture 문자열을 찾지 못함 — 훅 포매팅이 바뀌었을 수 있음'
t = t.replace(old, new, 1)
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "B-11: map 값이 frontmatter와 불일치 (FAIL 기대)" 1

# ===========================================================================
# 음성 케이스 (PASS를 기대 — 종료코드 0)
# ===========================================================================

# N1. 무변형 사본
new_case
run_and_check "무변형 사본 (PASS 기대)" 0

# N2. 셀에 이스케이프 \| 포함
new_case
python3 -c "
p = '$CASE_DIR/log.md'
with open(p, 'a', encoding='utf-8') as f:
    f.write('| 2026-08-19 | executor-high | 이스케이프 파이프 테스트 A\\\\|B | sonnet | high(frontmatter) | Agent(tier) | pass |\n')
"
run_and_check "셀에 이스케이프 파이프 포함 (PASS 기대)" 0

# N3. 정상 행 추가
new_case
python3 -c "
p = '$CASE_DIR/log.md'
with open(p, 'a', encoding='utf-8') as f:
    f.write('| 2026-08-19 | executor-med | 정상 행 추가 회귀 확인 | sonnet | medium(frontmatter) | Agent(tier) | pass |\n')
"
run_and_check "정상 행 추가 (PASS 기대)" 0

# N4. role 셀에 "날짜" 부분문자열 포함된 정상 행 (F1 회귀 — 헤더 오인 방지)
new_case
python3 -c "
p = '$CASE_DIR/log.md'
with open(p, 'a', encoding='utf-8') as f:
    f.write('| 2026-08-19 | executor-high | 날짜 검증 로직 추가 | sonnet | high(frontmatter) | Agent(tier) | pass |\n')
"
run_and_check "role 셀에 '날짜' 부분문자열 포함 (PASS 기대, F1)" 0

# N5. C7: 훅이 Prettier semi:false 스타일(세미콜론 없음)로 포매팅됨 —
# MODEL_PINNED_TYPES의 종결자가 '])'(세미콜론 없음), TIER_EXPECTED_MODEL의
# 종결자가 '}'(세미콜론 없음)여야 정상 파싱된다. 구버전 린터는 리터럴
# "]);"/"};" 서브스트링만 찾아 이 스타일에서 종결자를 영원히 못 찾고 파일
# 나머지 전체(TIER_EXPECTED_MODEL과 그 뒤 함수 본문 전부)를 Set 항목으로
# 오추출해 FAIL 폭포(수십~백여 건)를 냈다(C7 실측). 내용은 원본과 동일하게
# 유지하고 종결자 포매팅만 바꿔, 파싱 로직만의 회귀인지 확인한다.
new_case
python3 -c "
import re
p = '$CASE_DIR/hook.cjs'
t = open(p, encoding='utf-8').read()
# 정확히 한 번씩만 나타나는 종결 줄(Set의 ']);'와 map의 '};')을 세미콜론
# 없는 형태로 바꾼다 — 내용은 그대로, 포매팅만 semi:false 스타일로.
assert t.count('\n]);\n') == 1, 'fixture: Set 종결 줄이 정확히 1개가 아님 — 훅 포매팅이 바뀌었을 수 있음'
t = t.replace('\n]);\n', '\n])\n', 1)
assert t.count('\n};\n') == 1, 'fixture: map 종결 줄이 정확히 1개가 아님 — 훅 포매팅이 바뀌었을 수 있음'
t = t.replace('\n};\n', '\n}\n', 1)
open(p, 'w', encoding='utf-8').write(t)
"
run_and_check "C7: 훅 세미콜론 없는(semi:false) 종결자 스타일 (PASS 기대)" 0

# ===========================================================================
# B-10: WARN 클래스 분리(drift/workflow) + --strict 승격 회귀
# ===========================================================================

# B10-a. 워크플로류: '(리뷰 대기)' 미마감 행이 임계(MAX_PENDING=2) 초과 —
# 결함이 아니라 정상 진행 중 작업 상태이므로 기본·--strict 모두 exit 0이어야
# 하고, 출력엔 [WARN:workflow]로 표시돼 사람이 볼 수는 있어야 한다.
new_case
python3 -c "
p = '$CASE_DIR/log.md'
with open(p, 'a', encoding='utf-8') as f:
    for i in range(1, 4):
        f.write('| 2026-08-19 | executor-high | B-10 워크플로류 회귀 대기 행 ' + str(i) +
                 ' | sonnet | high(frontmatter) | Agent(tier) | (리뷰 대기) |\n')
"
CASE_B10A_DIR="$CASE_DIR"
run_dual "B10-a: '(리뷰 대기)' 임계 초과 (워크플로류, 기본 0 / strict 0 기대)" 0 0 '\[WARN:workflow\]'

# B10-b. 드리프트류: agents/에 새 tier md 파일을 추가했지만 훅
# MODEL_PINNED_TYPES Set엔 없는 상태 — model/effort는 정상이라 다른
# FAIL/WARN을 유발하지 않고 이 드리프트 하나만 격리해서 확인한다. 기본은
# WARN(exit 0), --strict는 drift라서 exit 1이어야 한다.
new_case
python3 -c "
p_src = '$CASE_DIR/agents/executor-high.md'
p_dst = '$CASE_DIR/agents/executor-high-newtier.md'
t = open(p_src, encoding='utf-8').read().replace('name: executor-high', 'name: executor-high-newtier', 1)
open(p_dst, 'w', encoding='utf-8').write(t)
"
run_dual "B10-b: agents/에 있지만 훅 pinned Set엔 없는 tier (드리프트류, 기본 0 / strict 1 기대)" 0 1 '\[WARN:drift\]'

# B10-c. 현재 레포 상태(무변형 사본) — 기본·--strict 둘 다 exit 0이어야 한다.
new_case
run_dual "B10-c: 무변형 사본 (기본 0 / strict 0 기대)" 0 0

# B10-d. 워크플로류: 데이터 행이 0건인 로그(부트스트랩 상태 — 헤더까지는
# 있지만 아직 위임을 한 번도 기록하지 않은 신규 설치). 결함이 아니라 정상
# 작업 상태이므로 기본·--strict 모두 exit 0이어야 하고, 출력엔
# [WARN:workflow]로 표시돼야 한다(수정 전엔 kind="drift"라서 --strict가
# exit 1을 냈다 — 아래 비공허성 확인에서 그 되돌림을 재현한다).
new_case
python3 -c "
p = '$CASE_DIR/log.md'
lines = open(p, encoding='utf-8').read().splitlines(keepends=True)
header_idx = next(i for i, l in enumerate(lines) if l.strip().startswith('| 날짜'))
# 헤더 다음 구분선 줄(|---|...)까지 남겨야 Check B가 '구분선 없음' FAIL을
# 내지 않는다 — 데이터 행 0건만 격리해서 확인하려는 케이스이므로 구분선
# 형식 자체는 정상으로 둔다.
sep_idx = header_idx + 1
assert lines[sep_idx].strip().startswith('|---'), 'fixture: 헤더 다음 줄이 구분선이 아님'
open(p, 'w', encoding='utf-8').writelines(lines[:sep_idx + 1])
"
CASE_B10D_DIR="$CASE_DIR"
run_dual "B10-d: 데이터 행 0건(부트스트랩, 워크플로류) (기본 0 / strict 0 기대)" 0 0 '\[WARN:workflow\]'

# ---------------------------------------------------------------------------
# 비공허성: B10-d에서 되돌린 kind만 표적 복구한 사본(정정 전 상태 —
# 데이터 행 0건 Finding을 kind="drift"로 되돌림)에서 B10-d 픽스처를 다시
# 돌려, --strict가 exit 1로 뒤집히는지 확인한다. 뒤집히지 않으면(계속
# exit 0) B10-d가 이 정정과 무관하게 통과하는 공허한 테스트라는 뜻이므로
# 여기서 실패로 표시한다.
# ---------------------------------------------------------------------------
REVERTED_SCRIPT_B10D="$SCRATCH/lint_reverted_b10d.py"
python3 -c "
p_in = '$LINT_SCRIPT'
p_out = '$REVERTED_SCRIPT_B10D'
t = open(p_in, encoding='utf-8').read()
needle = '데이터 행이 0건 — 빈 로그\",\n                                 kind=\"workflow\"))'
assert t.count(needle) == 1, 'fixture: B10-d 되돌리기 대상 문자열이 정확히 1개가 아님 — 코드가 바뀌었을 수 있음'
t = t.replace(needle, '데이터 행이 0건 — 빈 로그\",\n                                 kind=\"drift\"))', 1)
open(p_out, 'w', encoding='utf-8').write(t)
"

if diff -q "$LINT_SCRIPT" "$REVERTED_SCRIPT_B10D" >/dev/null 2>&1; then
  REVERT_B10D_APPLIED=0
else
  REVERT_B10D_APPLIED=1
fi

NONVAC_B10D_EXIT=$(python3 "$REVERTED_SCRIPT_B10D" \
  --agents-dir "$CASE_B10D_DIR/agents" \
  --hook-path "$CASE_B10D_DIR/hook.cjs" \
  --log-path "$CASE_B10D_DIR/log.md" \
  --strict \
  >"$SCRATCH/nonvac_b10d_out.txt" 2>&1; echo $?)

echo
echo "=== B-10 비공허성 확인 (B10-d, kind만 drift로 되돌린 사본) ==="
echo "reverted script 실제로 원본과 다름: $([ "$REVERT_B10D_APPLIED" -eq 1 ] && echo yes || echo no)"
echo "B10-d 픽스처, 되돌린 스크립트, --strict → exit ${NONVAC_B10D_EXIT} (기대: 1 / 정정된 스크립트는 0이었음)"
if [ "$REVERT_B10D_APPLIED" -eq 1 ] && [ "$NONVAC_B10D_EXIT" = "1" ]; then
  echo "NON-VACUOUS: PASS (되돌리면 실제로 exit 1로 뒤집힘 — B-10 정정이 진짜 동작 중)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "NON-VACUOUS: FAIL (되돌려도 결과가 안 바뀜 — B10-d 테스트가 공허할 수 있음)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_DESCRIPTIONS="${FAILED_DESCRIPTIONS}
  - B-10(빈 로그) 비공허성 확인 실패 (revert_applied=${REVERT_B10D_APPLIED}, exit=${NONVAC_B10D_EXIT}, 출력: ${SCRATCH}/nonvac_b10d_out.txt)"
fi

# ---------------------------------------------------------------------------
# 비공허성: 클래스 분리를 되돌린 사본(--strict 승격 조건을 warn_drift_count
# 대신 warn_count로 되돌린 버전)에서 B10-a 픽스처를 다시 돌려, strict 모드가
# 워크플로류까지 승격해 exit 1로 뒤집히는지 확인한다. 뒤집히지 않으면(계속
# exit 0) B10-a가 애초에 분리 여부와 무관하게 통과하는 공허한 테스트라는
# 뜻이므로, 여기서 실패로 표시한다.
# ---------------------------------------------------------------------------
REVERTED_SCRIPT="$SCRATCH/lint_reverted.py"
sed 's/if warn_drift_count and args.strict:/if warn_count and args.strict:/' "$LINT_SCRIPT" > "$REVERTED_SCRIPT"

if diff -q "$LINT_SCRIPT" "$REVERTED_SCRIPT" >/dev/null 2>&1; then
  REVERT_APPLIED=0
else
  REVERT_APPLIED=1
fi

NONVAC_EXIT=$(python3 "$REVERTED_SCRIPT" \
  --agents-dir "$CASE_B10A_DIR/agents" \
  --hook-path "$CASE_B10A_DIR/hook.cjs" \
  --log-path "$CASE_B10A_DIR/log.md" \
  --strict \
  >"$SCRATCH/nonvac_out.txt" 2>&1; echo $?)

echo
echo "=== B-10 비공허성 확인 (클래스 분리를 되돌린 사본) ==="
echo "reverted script 실제로 원본과 다름: $([ "$REVERT_APPLIED" -eq 1 ] && echo yes || echo no)"
echo "B10-a 픽스처, 되돌린 스크립트, --strict → exit ${NONVAC_EXIT} (기대: 1 / 원본 스크립트는 0이었음)"
if [ "$REVERT_APPLIED" -eq 1 ] && [ "$NONVAC_EXIT" = "1" ]; then
  echo "NON-VACUOUS: PASS (되돌리면 실제로 exit 1로 뒤집힘 — 클래스 분리가 진짜 동작 중)"
  PASS_COUNT=$((PASS_COUNT + 1))
else
  echo "NON-VACUOUS: FAIL (되돌려도 결과가 안 바뀜 — B10-a 테스트가 공허할 수 있음)"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  FAILED_DESCRIPTIONS="${FAILED_DESCRIPTIONS}
  - B-10 비공허성 확인 실패 (revert_applied=${REVERT_APPLIED}, exit=${NONVAC_EXIT}, 출력: ${SCRATCH}/nonvac_out.txt)"
fi

# ===========================================================================
# 결과 집계
# ===========================================================================

TOTAL=$((PASS_COUNT + FAIL_COUNT))
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "PASS ${PASS_COUNT}/${TOTAL}"
  exit 0
else
  echo "FAIL ${FAIL_COUNT}/${TOTAL} — 실패 케이스:${FAILED_DESCRIPTIONS}"
  exit 1
fi
