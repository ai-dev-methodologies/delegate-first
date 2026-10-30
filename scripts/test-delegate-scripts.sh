#!/usr/bin/env bash
# test-delegate-scripts.sh — sandboxed test suite for the work-directory
# scripts in .claude/skills/delegate-first/scripts/ (new-task.sh,
# close-task.sh). Blueprint: docs/blueprint/delegate-first-v2.md §3·§4·§7.
#
# Every case builds a throwaway git repo under one mktemp -d root and runs
# the scripts from there; nothing touches this repo's working tree. A trap
# removes the sandbox on exit.
#
# close-task.sh skeleton scope (decision D8): order/output pairing, order
# required sections, and the Agent name rule <작업>-<model>-<effort> moved
# out of the hook (B-18). Every failing case asserts the specific
# `FAIL <check>` line as well as exit 1, so a checker that always exits 1
# fails the valid cases and one that always exits 0 fails the rest.
#
# Must run on macOS stock bash 3.2 and BSD tools.

set -uo pipefail  # no -e: run every case and tally results

# isolate_git_env — drop the repo-locating variables a git hook exports
# (pre-commit sets GIT_DIR·GIT_INDEX_FILE). Inherited, they send every
# sandbox git init·config·add·commit into the caller's repo instead.
isolate_git_env() {
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY \
    GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_COMMON_DIR GIT_PREFIX \
    GIT_NAMESPACE GIT_CEILING_DIRECTORIES
}
isolate_git_env

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILL_DIR="$REPO_ROOT/.claude/skills/delegate-first"
NEW_TASK="${NEW_TASK_BIN:-$SKILL_DIR/scripts/new-task.sh}"
CLOSE_TASK="${CLOSE_TASK_BIN:-$SKILL_DIR/scripts/close-task.sh}"
TEMPLATES="$SKILL_DIR/templates"

SANDBOX_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-delegate-scripts.XXXXXX")"
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

record() {
  # record <case> PASS|FAIL [detail]
  if [ "$2" = "PASS" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "PASS $1"
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "FAIL $1 — ${3:-}"
  fi
}

SLUG="20261030-sample-task"

# new_repo <name> — fresh git repo with one commit; prints its path. It
# isolates again itself, since it is the one helper that writes to a repo.
new_repo() {
  local d="$SANDBOX_ROOT/$1"
  mkdir -p "$d"
  (
    isolate_git_env &&
    cd "$d" &&
      git init -q &&
      git config user.email t@example.invalid &&
      git config user.name t &&
      echo seed > seed.txt &&
      git add seed.txt &&
      git commit -q -m seed
  ) >/dev/null 2>&1
  echo "$d"
}

# write_order <file> <tier> [omit-section] — order with every required
# section; the optional third argument names one `## ` heading to leave out.
write_order() {
  local f="$1" tier="$2" omit="${3:-}" sec
  mkdir -p "$(dirname "$f")"
  {
    echo "# ORDER $(basename "$f" .md)"
    if [ "$omit" != "발주 정보" ]; then
      echo "## 발주 정보"
      if [ -n "$tier" ]; then echo "- tier: $tier"; fi
    fi
    for sec in "목표" "입력" "유효 결정" "쓰기 범위" "금지" "완료 증거"; do
      [ "$sec" = "$omit" ] && continue
      echo "## $sec"
      echo "- 내용"
    done
    echo "## 반환"
  } > "$f"
}

write_output() {
  mkdir -p "$(dirname "$1")"
  printf '수신한 추가 지시 0건\n\n| ID | 상태 | 증거 |\n|---|---|---|\n' > "$1"
}

# write_progress <file> <stem>... — PROGRESS.md whose 회차 table names each
# stem, the way main moves a read-only tier's returned message there (D11).
write_progress() {
  local f="$1" stem; shift
  mkdir -p "$(dirname "$f")"
  {
    echo "# PROGRESS $SLUG"
    echo "## 회차"
    echo "| 회차 | order | 반환 | R1 | R2 | 판정 |"
    echo "|---|---|---|---|---|---|"
    for stem in "$@"; do echo "| 1 | $stem | 반환 요약 | | | |"; done
  } > "$f"
}

# task_repo <name> — repo with an empty task dir (orders/, outputs/).
task_repo() {
  local d
  d="$(new_repo "$1")"
  mkdir -p "$d/.delegate/$SLUG/orders" "$d/.delegate/$SLUG/outputs"
  echo "$d"
}

run_close() {
  # run_close <repo> [args...] — sets RC and OUT
  local d="$1"; shift
  OUT="$(cd "$d" && bash "$CLOSE_TASK" "$@" 2>&1)"
  RC=$?
}

run_new() {
  local d="$1"; shift
  OUT="$(cd "$d" && bash "$NEW_TASK" "$@" 2>&1)"
  RC=$?
}

# expect <case> <rc> <grep-pattern-or-empty> [absent-pattern]
expect() {
  local name="$1" want_rc="$2" pat="$3" absent="${4:-}"
  if [ "$RC" -ne "$want_rc" ]; then
    record "$name" FAIL "exit=$RC want=$want_rc out=[$OUT]"; return
  fi
  if [ -n "$pat" ] && ! printf '%s\n' "$OUT" | grep -Eq -- "$pat"; then
    record "$name" FAIL "missing /$pat/ in out=[$OUT]"; return
  fi
  if [ -n "$absent" ] && printf '%s\n' "$OUT" | grep -Eq -- "$absent"; then
    record "$name" FAIL "unexpected /$absent/ in out=[$OUT]"; return
  fi
  record "$name" PASS
}

# ---------------------------------------------------------------- new-task

d="$(new_repo n1)"
run_new "$d" "$SLUG"
head_sha="$(cd "$d" && git rev-parse HEAD)"
t="$d/.delegate/$SLUG"
ok=1; detail=""
[ "$RC" -eq 0 ] || { ok=0; detail="exit=$RC out=[$OUT]"; }
for f in TASK.md REFS.md PROGRESS.md; do
  [ -f "$t/$f" ] || { ok=0; detail="$detail missing $f"; }
done
[ -d "$t/orders" ] && [ -d "$t/outputs" ] || { ok=0; detail="$detail missing orders/ or outputs/"; }
grep -q "^# TASK $SLUG\$" "$t/TASK.md" 2>/dev/null || { ok=0; detail="$detail TASK.md slug not filled"; }
grep -q "^# PROGRESS $SLUG\$" "$t/PROGRESS.md" 2>/dev/null || { ok=0; detail="$detail PROGRESS.md slug not filled"; }
grep -q "^# REFS $SLUG\$" "$t/REFS.md" 2>/dev/null || { ok=0; detail="$detail REFS.md slug not filled"; }
grep -qx "$head_sha" "$t/TASK.md" 2>/dev/null || { ok=0; detail="$detail TASK.md base commit != HEAD"; }
if [ "$ok" -eq 1 ]; then record new_creates_task_dir PASS; else record new_creates_task_dir FAIL "$detail"; fi

d="$(new_repo n2)"
for bad in "sample-task" "2026103-x" "20261030-Bad" "20261030-a--b" "20261030-" "20261030-a/../b" "20261330-x" "20260100-x" "20260132-x" "20260000-x"; do
  run_new "$d" "$bad"
  if [ "$RC" -ne 2 ] || [ -e "$d/.delegate" ]; then
    record "new_rejects_bad_slug[$bad]" FAIL "exit=$RC delegate-exists=$([ -e "$d/.delegate" ] && echo y || echo n)"
  else
    record "new_rejects_bad_slug[$bad]" PASS
  fi
done

d="$(new_repo n2b)"
# 20260229-x (no such day in 2026) is an accepted limit: the slug is an
# identifier and never used for date arithmetic. Switch to a date(1) check
# if that changes.
for ok in "20260101-x" "20261231-x" "20260131-x" "20260229-x"; do
  run_new "$d" "$ok"
  expect "new_accepts_date_slug[$ok]" 0 "생성:"
done

d="$(new_repo n3)"
mkdir -p "$d/.delegate/$SLUG"
echo keep > "$d/.delegate/$SLUG/TASK.md"
run_new "$d" "$SLUG"
if [ "$RC" -eq 2 ] && [ "$(cat "$d/.delegate/$SLUG/TASK.md")" = "keep" ]; then
  record new_refuses_existing_dir PASS
else
  record new_refuses_existing_dir FAIL "exit=$RC content=[$(cat "$d/.delegate/$SLUG/TASK.md")]"
fi

d="$(new_repo n4)"
run_new "$d" "$SLUG"
ok=1; detail=""
printf '%s\n' "$OUT" | grep -q '\.gitignore' || { ok=0; detail="no .gitignore suggestion out=[$OUT]"; }
[ ! -e "$d/.gitignore" ] || { ok=0; detail="$detail .gitignore was modified"; }
if [ "$ok" -eq 1 ]; then record new_suggests_gitignore_without_editing PASS; else record new_suggests_gitignore_without_editing FAIL "$detail"; fi

d="$(new_repo n5)"
printf '.delegate/\n' > "$d/.gitignore"
run_new "$d" "$SLUG"
expect new_quiet_when_ignored 0 "" '\.gitignore'

d="$(new_repo n6)"
printf 'delegate-workdir: track\n' > "$d/CLAUDE.md"
run_new "$d" "$SLUG"
expect new_quiet_when_track 0 "" '\.gitignore'

d="$SANDBOX_ROOT/n7-not-git"
mkdir -p "$d"
run_new "$d" "$SLUG"
expect new_rejects_non_git_dir 2 ""

run_new "$(new_repo n8)"
expect new_rejects_missing_slug 2 ""

# A git hook exports GIT_DIR·GIT_INDEX_FILE; new_repo must still build its
# repo in the sandbox, never in the repo those variables point at. The decoy
# stands in for the real repo, so a regression only ever damages the decoy.
DECOY="$(mktemp -d /tmp/test-delegate-decoy.XXXXXX)" || { echo "mktemp failed"; exit 2; }
trap 'rm -rf "$SANDBOX_ROOT" "$DECOY"' EXIT
(
  cd "$DECOY" &&
    git init -q &&
    echo decoy > decoy.txt &&
    git add decoy.txt &&
    git -c user.email=d@example.invalid -c user.name=d commit -q -m decoy
) >/dev/null 2>&1
decoy_state() {
  shasum "$DECOY/.git/config" "$DECOY/.git/index"
  git -C "$DECOY" rev-parse HEAD
}
before="$(decoy_state)"
d="$(GIT_DIR="$DECOY/.git" GIT_INDEX_FILE="$DECOY/.git/index" && export GIT_DIR GIT_INDEX_FILE && new_repo n11)"
after="$(decoy_state)"
if [ -n "$before" ] && [ "$before" = "$after" ] && git -C "$d" rev-parse -q --verify HEAD >/dev/null; then
  record new_repo_ignores_inherited_git_env PASS
else
  record new_repo_ignores_inherited_git_env FAIL "decoy before=[$before] after=[$after] sandbox-head=$(git -C "$d" rev-parse -q --verify HEAD)"
fi

# -------------------------------------------------------------- close-task

d="$(task_repo c1)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" executor-high
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
write_order "$d/.delegate/$SLUG/orders/02-review-opus-high.md" reviewer-high
write_order "$d/.delegate/$SLUG/orders/03-verdict-fable-max.md" judge-max
write_order "$d/.delegate/$SLUG/orders/04-scan-haiku-low.md" explorer-low
write_progress "$d/.delegate/$SLUG/PROGRESS.md" 02-review-opus-high 03-verdict-fable-max 04-scan-haiku-low
run_close "$d" "$SLUG"
expect close_valid_passes_and_exempts_readonly_tiers 0 "" '^FAIL'

d="$(task_repo c2)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" executor-high
run_close "$d" "$SLUG"
expect close_missing_output_fails 1 '^FAIL pair .*01-impl-sonnet-high'

d="$(task_repo c3)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" executor-high
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
write_output "$d/.delegate/$SLUG/outputs/02-ghost-sonnet-high.md"
run_close "$d" "$SLUG"
expect close_orphan_output_fails 1 '^FAIL pair .*02-ghost-sonnet-high'

for sec in "발주 정보" "목표" "입력" "유효 결정" "쓰기 범위" "금지" "완료 증거"; do
  d="$(task_repo "c4-$(printf '%s' "$sec" | cksum | cut -d' ' -f1)")"
  write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" executor-high "$sec"
  write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
  run_close "$d" "$SLUG"
  expect "close_missing_section_fails[$sec]" 1 "^FAIL order-section .*$sec"
done

d="$(task_repo c5)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" ""
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
run_close "$d" "$SLUG"
expect close_missing_tier_line_fails 1 '^FAIL order-tier '

d="$(task_repo c6)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" executor-turbo
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
run_close "$d" "$SLUG"
expect close_unknown_tier_fails 1 '^FAIL order-tier .*executor-turbo'

for bad in "impl-sonnet" "sonnet-high" "impl-sonnet-huge" "impl-gpt-high" "Impl-sonnet-high" "impl_x-sonnet-high"; do
  d="$(task_repo "c7-$bad")"
  write_order "$d/.delegate/$SLUG/orders/01-$bad.md" executor-high
  write_output "$d/.delegate/$SLUG/outputs/01-$bad.md"
  run_close "$d" "$SLUG"
  expect "close_name_format_fails[$bad]" 1 "^FAIL name-format .*$bad"
done

d="$(task_repo c8)"
write_order "$d/.delegate/$SLUG/orders/01-impl-opus-high.md" executor-high
write_output "$d/.delegate/$SLUG/outputs/01-impl-opus-high.md"
run_close "$d" "$SLUG"
expect close_name_model_pin_mismatch_fails 1 '^FAIL name-pin .*01-impl-opus-high'

d="$(task_repo c9)"
write_order "$d/.delegate/$SLUG/orders/01-review-opus-max.md" reviewer-high
run_close "$d" "$SLUG"
expect close_name_effort_pin_mismatch_fails 1 '^FAIL name-pin .*01-review-opus-max'

d="$(task_repo c10)"
write_order "$d/.delegate/$SLUG/orders/1-impl-sonnet-high.md" executor-high
run_close "$d" "$SLUG"
expect close_order_filename_fails 1 '^FAIL order-filename .*1-impl-sonnet-high'

d="$(task_repo c11)"
run_close "$d" "$SLUG"
expect close_no_orders_fails 1 '^FAIL orders-empty'

d="$(task_repo c12)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" executor-high
write_order "$d/.delegate/$SLUG/orders/02-fix-opus-high.md" executor-high "금지"
write_output "$d/.delegate/$SLUG/outputs/02-fix-opus-high.md"
run_close "$d" "$SLUG"
n_fail="$(printf '%s\n' "$OUT" | grep -c '^FAIL')"
if [ "$RC" -eq 1 ] && [ "$n_fail" -eq 3 ]; then
  record close_reports_every_failure PASS
else
  record close_reports_every_failure FAIL "exit=$RC FAIL-lines=$n_fail (want 3: pair 01, order-section 02, name-pin 02) out=[$OUT]"
fi

d="$(new_repo c13)"
run_close "$d" "$SLUG"
expect close_missing_task_dir_is_structural 2 ""
# Bad slugs must be rejected by the slug check itself. Each one points at a
# directory that really exists and holds a valid pair, so a close-task.sh
# without slug validation would exit 0 here instead of 2.
d="$(task_repo c13s)"
mkdir -p "$SANDBOX_ROOT/c13s-outside"
for tgt in "$d/.delegate/Bad_Slug" "$SANDBOX_ROOT/c13s-outside" \
  "$d/.delegate/20261330-x" "$d/.delegate/20260100-x" "$d/.delegate/20260132-x" "$d/.delegate/20260000-x"; do
  write_order "$tgt/orders/01-impl-sonnet-high.md" executor-high
  write_output "$tgt/outputs/01-impl-sonnet-high.md"
done
for bad in "Bad_Slug" "../../c13s-outside" "20261330-x" "20260100-x" "20260132-x" "20260000-x"; do
  run_close "$d" "$bad"
  expect "close_bad_slug_is_structural[$bad]" 2 "slug 형식 위반"
done
run_close "$d"
expect close_missing_arg_is_structural 2 ""
d="$(task_repo c13b)"
run_close "$d" "$SLUG" --bogus
expect close_unknown_option_is_structural 2 ""
rm -rf "$d/.delegate/$SLUG/orders"
run_close "$d" "$SLUG"
expect close_missing_orders_dir_is_structural 2 ""

d="$SANDBOX_ROOT/c14-not-git"
mkdir -p "$d/.delegate/$SLUG/orders"
run_close "$d" "$SLUG"
expect close_non_git_dir_is_structural 2 ""

# M1: a read-only order with no output is exempt only when PROGRESS.md's
# 회차 table has a row whose order cell equals the stem and whose 반환 cell is
# not empty (D11: main moves the returned message there). The `- tier:` line
# alone buys nothing. Accepted limit: an executor-max order written as
# `- tier: reviewer-high` with such a row passes, since both pin opus·high.
d="$(task_repo c17)"
write_order "$d/.delegate/$SLUG/orders/01-impl-opus-high.md" reviewer-high
run_close "$d" "$SLUG"
expect close_spoofed_readonly_tier_without_progress_fails 1 '^FAIL pair .*01-impl-opus-high'

d="$(task_repo c17b)"
write_order "$d/.delegate/$SLUG/orders/01-impl-opus-high.md" reviewer-high
write_progress "$d/.delegate/$SLUG/PROGRESS.md" 02-other-opus-high 101-impl-opus-high 01-impl-opus-high-x
run_close "$d" "$SLUG"
expect close_readonly_exemption_needs_exact_stem_in_progress 1 '^FAIL pair .*01-impl-opus-high'

d="$(task_repo c17c)"
write_order "$d/.delegate/$SLUG/orders/01-impl-opus-high.md" executor-max
write_progress "$d/.delegate/$SLUG/PROGRESS.md" 01-impl-opus-high
run_close "$d" "$SLUG"
expect close_write_tier_gets_no_exemption_from_progress 1 '^FAIL pair .*01-impl-opus-high'

d="$(task_repo c17d)"
write_order "$d/.delegate/$SLUG/orders/01-review-opus-high.md" reviewer-high
write_progress "$d/.delegate/$SLUG/PROGRESS.md" 01-review-opus-high
run_close "$d" "$SLUG"
expect close_readonly_with_stem_in_progress_passes 0 "" '^FAIL'

# progress_raw <dir> <text> — PROGRESS.md with the template's 회차 header
# followed by <text> (printf format).
progress_raw() {
  {
    echo "# PROGRESS $SLUG"
    echo "## 회차"
    echo "| 회차 | order | 반환 | R1 | R2 | 판정 |"
    echo "|---|---|---|---|---|---|"
    printf "$2"
  } > "$1/PROGRESS.md"
}

d="$(task_repo c17e)"
write_order "$d/.delegate/$SLUG/orders/01-impl-opus-high.md" reviewer-high
progress_raw "$d/.delegate/$SLUG" '| 1 | 01-impl-opus-high | | | | |\n'
run_close "$d" "$SLUG"
expect close_readonly_row_with_empty_return_fails 1 '^FAIL pair .*01-impl-opus-high'

d="$(task_repo c17f)"
write_order "$d/.delegate/$SLUG/orders/01-review-opus-high.md" reviewer-high
progress_raw "$d/.delegate/$SLUG" '## Do Not Repeat\n- 01-review-opus-high 는 미실행\n'
run_close "$d" "$SLUG"
expect close_readonly_stem_outside_round_table_fails 1 '^FAIL pair .*01-review-opus-high'

d="$(task_repo c17g)"
write_order "$d/.delegate/$SLUG/orders/01-review-opus-high.md" reviewer-high
progress_raw "$d/.delegate/$SLUG" '| 1 | 01-review-opus-high_old | 반환 요약 | | | |\n'
run_close "$d" "$SLUG"
expect close_readonly_partial_stem_in_order_cell_fails 1 '^FAIL pair .*01-review-opus-high'

d="$(task_repo c17h)"
write_order "$d/.delegate/$SLUG/orders/01-review-opus-high.md" reviewer-high
progress_raw "$d/.delegate/$SLUG" '| 1 | 02-other-opus-high | 01-review-opus-high 참조 | | | |\n'
run_close "$d" "$SLUG"
expect close_readonly_stem_in_other_cell_fails 1 '^FAIL pair .*01-review-opus-high'

d="$(task_repo c17i)"
write_order "$d/.delegate/$SLUG/orders/01-review-opus-high.md" reviewer-high
progress_raw "$d/.delegate/$SLUG" '## Open Items\n| 1 | 01-review-opus-high | 반환 요약 | | | |\n'
run_close "$d" "$SLUG"
expect close_readonly_row_in_other_section_fails 1 '^FAIL pair .*01-review-opus-high'

d="$(task_repo c17j)"
write_order "$d/.delegate/$SLUG/orders/01-review-opus-high.md" reviewer-high
progress_raw "$d/.delegate/$SLUG" '|  2  |  01-review-opus-high  |  H 0건  |||  |\n'
run_close "$d" "$SLUG"
expect close_readonly_row_with_padded_cells_passes 0 "" '^FAIL'

# M2: files that are not NN-<name>.md must fail instead of being skipped
d="$(task_repo c18)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" executor-high
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
write_order "$d/.delegate/$SLUG/orders/02-extra-sonnet-high.MD" executor-high
run_close "$d" "$SLUG"
expect close_uppercase_md_order_fails 1 '^FAIL order-filename .*02-extra-sonnet-high\.MD'
rm "$d/.delegate/$SLUG/orders/02-extra-sonnet-high.MD"
echo note > "$d/.delegate/$SLUG/orders/notes.txt"
run_close "$d" "$SLUG"
expect close_txt_in_orders_fails 1 '^FAIL order-filename .*notes\.txt'
rm "$d/.delegate/$SLUG/orders/notes.txt"
echo x > "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.txt"
run_close "$d" "$SLUG"
expect close_txt_in_outputs_fails 1 '^FAIL output-filename .*01-impl-sonnet-high\.txt'
rm "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.txt"
write_output "$d/.delegate/$SLUG/outputs/02-extra-sonnet-high.MD"
run_close "$d" "$SLUG"
expect close_uppercase_md_output_fails 1 '^FAIL output-filename .*02-extra-sonnet-high\.MD'
rm "$d/.delegate/$SLUG/outputs/02-extra-sonnet-high.MD"
touch "$d/.delegate/$SLUG/orders/.gitkeep"
run_close "$d" "$SLUG"
expect close_dotfile_in_orders_is_ignored 0 "" '^FAIL'
# a broken symlink is a file that cannot be checked, not an absent one
ln -s "$SANDBOX_ROOT/nonexistent" "$d/.delegate/$SLUG/orders/02-link-sonnet-high.md"
run_close "$d" "$SLUG"
expect close_broken_symlink_order_fails 1 '^FAIL order-filename .*02-link-sonnet-high\.md'
rm "$d/.delegate/$SLUG/orders/02-link-sonnet-high.md"
ln -s "$SANDBOX_ROOT/nonexistent" "$d/.delegate/$SLUG/outputs/02-ghost-sonnet-high.md"
run_close "$d" "$SLUG"
expect close_broken_symlink_output_fails 1 '^FAIL output-filename .*02-ghost-sonnet-high\.md'
rm "$d/.delegate/$SLUG/outputs/02-ghost-sonnet-high.md"

# L1: a `## ` heading counts only as a whole line (trailing blanks allowed)
d="$(task_repo c19)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" executor-high
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
o="$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md"
sed 's/^## 목표$/## 목표물/' "$o" > "$o.new" && mv "$o.new" "$o"
run_close "$d" "$SLUG"
expect close_heading_with_suffix_text_fails 1 "^FAIL order-section .*'## 목표' 없음"
sed 's/^## 목표물$/## 목표   /' "$o" > "$o.new" && mv "$o.new" "$o"
run_close "$d" "$SLUG"
expect close_heading_with_trailing_blanks_passes 0 "" '^FAIL'

# L3: the `- tier:` line counts only inside the 「발주 정보」 section
d="$(task_repo c20)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" ""
echo "- tier: executor-high" >> "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md"
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
run_close "$d" "$SLUG"
expect close_tier_line_after_info_section_fails 1 '^FAIL order-tier .*01-impl-sonnet-high'
d="$(task_repo c20b)"
o="$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md"
{ echo "- tier: executor-high"; echo "# ORDER"; echo "## 발주 정보"; echo "## 목표"; echo "- tier: executor-high"; } > "$o"
for sec in "입력" "유효 결정" "쓰기 범위" "금지" "완료 증거"; do echo "## $sec" >> "$o"; done
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
run_close "$d" "$SLUG"
expect close_tier_line_in_other_section_fails 1 '^FAIL order-tier .*01-impl-sonnet-high'
# only the first 「발주 정보」 section counts
d="$(task_repo c20c)"
o="$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md"
write_order "$o" ""
printf '## 발주 정보\n- tier: executor-high\n' >> "$o"
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
run_close "$d" "$SLUG"
expect close_tier_line_in_second_info_section_fails 1 '^FAIL order-tier .*01-impl-sonnet-high'

# L4: duplicate order numbers
d="$(task_repo c21)"
write_order "$d/.delegate/$SLUG/orders/01-impl-sonnet-high.md" executor-high
write_output "$d/.delegate/$SLUG/outputs/01-impl-sonnet-high.md"
write_order "$d/.delegate/$SLUG/orders/01-fix-sonnet-high.md" executor-high
write_output "$d/.delegate/$SLUG/outputs/01-fix-sonnet-high.md"
run_close "$d" "$SLUG"
expect close_duplicate_order_number_fails 1 '^FAIL order-number .*01'

# L5: valid boundary dates close cleanly
for okslug in "20260101-x" "20261231-x" "20260131-x"; do
  d="$(new_repo "c22-$okslug")"
  write_order "$d/.delegate/$okslug/orders/01-impl-sonnet-high.md" executor-high
  write_output "$d/.delegate/$okslug/outputs/01-impl-sonnet-high.md"
  run_close "$d" "$okslug"
  expect "close_accepts_date_slug[$okslug]" 0 "^PASS"
done

# Pin drift lock: close-task.sh's tier pin table must equal each tier's
# frontmatter model/effort in this repo's .claude/agents/.
for tier in explorer-low executor-med executor-high executor-max reviewer-high judge-max; do
  af="$REPO_ROOT/.claude/agents/$tier.md"
  m="$(sed -n 's/^model:[[:space:]]*//p' "$af" | head -1)"
  e="$(sed -n 's/^effort:[[:space:]]*//p' "$af" | head -1)"
  d="$(task_repo "c15-$tier")"
  write_order "$d/.delegate/$SLUG/orders/01-pin-$m-$e.md" "$tier"
  write_output "$d/.delegate/$SLUG/outputs/01-pin-$m-$e.md"
  run_close "$d" "$SLUG"
  if [ -n "$m" ] && [ -n "$e" ]; then
    expect "close_pin_matches_frontmatter[$tier]" 0 "" '^FAIL'
  else
    record "close_pin_matches_frontmatter[$tier]" FAIL "frontmatter model/effort not found in $af"
  fi
done

# Template round trip: new-task.sh output plus a filled-in ORDER template
# closes cleanly, and the unfilled ORDER template is rejected.
d="$(new_repo c16)"
run_new "$d" "$SLUG"
t="$d/.delegate/$SLUG"
sed 's/^- tier: .*/- tier: executor-med (sonnet·medium)/' "$TEMPLATES/ORDER.md" > "$t/orders/01-doc-sonnet-medium.md"
write_output "$t/outputs/01-doc-sonnet-medium.md"
run_close "$d" "$SLUG"
expect close_filled_order_template_passes 0 "" '^FAIL'
cp "$TEMPLATES/ORDER.md" "$t/orders/02-raw-sonnet-medium.md"
write_output "$t/outputs/02-raw-sonnet-medium.md"
run_close "$d" "$SLUG"
expect close_unfilled_order_template_fails 1 '^FAIL order-tier .*02-raw-sonnet-medium'

# new-task.sh must not leave a half-built task directory behind when a step
# after mkdir fails. A copy of the skill dir with an unreadable PROGRESS.md
# template (the third template copied) makes the copy step fail mid-way.
cp -R "$SKILL_DIR" "$SANDBOX_ROOT/skill-copy"
chmod 000 "$SANDBOX_ROOT/skill-copy/templates/PROGRESS.md"
d="$(new_repo n9)"
OUT="$(cd "$d" && bash "$SANDBOX_ROOT/skill-copy/scripts/new-task.sh" "$SLUG" 2>&1)"; RC=$?
if [ -r "$SANDBOX_ROOT/skill-copy/templates/PROGRESS.md" ]; then
  record new_failure_after_mkdir_leaves_nothing FAIL "chmod 000 did not make the template unreadable (running as root?)"
elif [ "$RC" -eq 2 ] && [ ! -e "$d/.delegate" ]; then
  record new_failure_after_mkdir_leaves_nothing PASS
else
  record new_failure_after_mkdir_leaves_nothing FAIL "exit=$RC .delegate-exists=$([ -e "$d/.delegate" ] && echo y || echo n) out=[$OUT]"
fi
# an already existing .delegate/ with other tasks survives the cleanup
d="$(new_repo n10)"
mkdir -p "$d/.delegate/20260101-other/orders"
OUT="$(cd "$d" && bash "$SANDBOX_ROOT/skill-copy/scripts/new-task.sh" "$SLUG" 2>&1)"; RC=$?
if [ "$RC" -eq 2 ] && [ ! -e "$d/.delegate/$SLUG" ] && [ -d "$d/.delegate/20260101-other/orders" ]; then
  record new_failure_cleanup_keeps_other_tasks PASS
else
  record new_failure_cleanup_keeps_other_tasks FAIL "exit=$RC out=[$OUT]"
fi
chmod 644 "$SANDBOX_ROOT/skill-copy/templates/PROGRESS.md"

echo
echo "PASS $PASS_COUNT/$((PASS_COUNT + FAIL_COUNT))"
if [ "$FAIL_COUNT" -ne 0 ]; then
  echo "One or more cases failed — see FAIL detail lines above."
  exit 1
fi
echo "All cases passed."
exit 0
