#!/usr/bin/env bash
# test-reinstall.sh — sandboxed test suite for scripts/reinstall.sh.
#
# Everything happens inside a throwaway mktemp -d tree. This script never
# reads or writes the real $HOME/.claude or any real project — every run
# sets REINSTALL_HOME to a fake home inside the sandbox, and --src/--dst
# always point at fixtures built fresh for each case. A trap removes the
# whole sandbox on exit (success, failure, or interrupt).
#
# Cases 1-7 and 10 cover the original reinstall procedure (backup, dry-run,
# guards, succession, global propagation opt-in). Cases 11-12 cover the
# generalized $NEW-construction step: the canonical repo's top-level
# skill-dir entries are copied generically (no hardcoded
# "SKILL.md"/"references" pair), so a new canonical file installs even if
# dst has no file by that name (11) and wins over a stale same-named dst
# file instead of being shadowed by succession (12).
#
# Non-vacuity for 11/12 is checked out-of-band, not as extra numbered
# cases here: point REINSTALL_BIN at a copy of reinstall.sh predating this
# generalization (hardcoded SKILL_PROVIDED_NAMES=("SKILL.md" "references")
# array) and confirm cases 11 and 12 both FAIL against it.
#
# Cases 20-21 (NEW_INSTALL) cover the brand-new-project install path: a
# $DST with no .claude at all used to be hard-rejected at §0 ("신규 설치는
# 이 스크립트가 아니라 README.md §설치를 따른다") even though $DST itself
# existed — that path had never been exercised end-to-end before. Case 20
# is the no-.claude-at-all case, case 21 is .claude-exists-but-no-skills-
# or-agents-yet (already worked pre-fix; kept as an explicit lock).
# Non-vacuity for 20 is checked out-of-band the same way as 11/12: point
# REINSTALL_BIN at a copy of reinstall.sh predating the NEW_INSTALL fix and
# confirm case 20 exits non-zero (still hard-rejects).
#
# Case 27 (P3) and caseF3 are install-path regression locks kept from the
# P5 followup round (deploy-readiness adversarial review round 2): caseF3
# covers the §0 advisory branch that used to print nothing at all about
# hook registration on a completely fresh machine (rc=0, silent
# half-install); case27 covers §1's `[ -d ]` backup check misreading a
# regular file at the skill path as "nothing to back up", which used to let
# the swap silently destroy that file with no backup and a false "재설치
# 완료" log.
#
# 2026-08-21 (PR #14, chore/drop-rollback): removed every case that only
# exercised `--rollback`/`--rollback-global` (do_rollback itself is gone —
# see BACKLOG B-15/B-17 and gotchas.md). None of those cases carried an
# install-path assertion worth salvaging: each one's setup (install, then
# assert canonical content) duplicates what case1/case13's install-only
# predecessor already covered, so nothing was migrated, only deleted.
# Removed: case8, case9, case13 (F-3), case14/18/19 (F-4), case22 (NEW_INSTALL
# rollback), case23/24 (F-1), case25 (P1) + its non-vacuity twin, case26 (P2
# rollback) + its non-vacuity twin, caseF2, caseF7, caseRollbackRestore,
# caseB16 + caseB16_vac. The BROKEN_P1/BROKEN_P2/BROKEN_F2/BROKEN_F7/
# BROKEN_B16 fixture builders (and the F2/F7/B16 pre-fix snippets) went with
# them, since their only consumers were the removed cases. BROKEN_P3 and
# BROKEN_F3 stay — those guard install-path behavior, not rollback.

set -uo pipefail  # no -e: we want to run every case and tally results

# REINSTALL_BIN (test-only override): point the suite at a different copy of
# reinstall.sh (e.g. a deliberately weakened one, for the non-vacuity check
# described in the task — "disable one safety guard and confirm the
# corresponding case fails"). Default is this repo's real script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REINSTALL="${REINSTALL_BIN:-$SCRIPT_DIR/reinstall.sh}"

SANDBOX_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-reinstall.XXXXXX")"
trap 'rm -rf "$SANDBOX_ROOT"' EXIT

# F-2: real $HOME/.claude-backups leak fix. Every case used to set
# REINSTALL_HOME by hand before invoking "$REINSTALL" — case1 forgot to
# (no REINSTALL_HOME prefix at all), so every run of this suite created a
# real backup under the actual $HOME/.claude-backups/ and read the actual
# global hook/rule files, contradicting this file's own "부작용 0" header
# claim (실측: this leaked delegate-first-20260818-2339xx into a real
# ~/.claude-backups). A single hand-set env var per call site is exactly
# the kind of thing that's easy to forget again, so instead every case
# below MUST go through this wrapper, which refuses outright if the
# sandbox home is empty or resolves to the real $HOME — the mistake can no
# longer silently reach "$REINSTALL".
REAL_HOME_RESOLVED="$(cd "$HOME" 2>/dev/null && pwd -P || echo "$HOME")"
run_reinstall() {
  local home="$1"; shift
  if [ -z "$home" ]; then
    echo "run_reinstall: REINSTALL_HOME 인자가 비어 있음 — 실제 \$HOME 오염을 막기 위해 거부" >&2
    return 99
  fi
  local resolved
  resolved="$(cd "$home" 2>/dev/null && pwd -P || echo "$home")"
  if [ "$resolved" = "$REAL_HOME_RESOLVED" ]; then
    echo "run_reinstall: REINSTALL_HOME('$home')이 실제 \$HOME과 동일 — 거부" >&2
    return 99
  fi
  REINSTALL_HOME="$home" "$REINSTALL" "$@"
}

# Broken-copy fixtures for the P3/F3 non-vacuity checks (case27/caseF3,
# S14 / silent-half-install). Each guard is wrapped in
# "# P<N>-GUARD-START" / "# P<N>-GUARD-END" marker comments in
# reinstall.sh. Stripping the lines between one pair of markers reproduces
# exactly the pre-fix vulnerable behavior for that one guard, so the
# matching case can prove its assertion is non-vacuous by running the
# identical scenario against the stripped copy and confirming the old bug
# (not just "some failure") actually reproduces.
#
# P5-0: the fixture builder below self-verifies with `cmp -s` that the
# broken copy actually differs from $REINSTALL. Without this, a typo'd
# marker name (or a guard whose markers got renamed/removed upstream) makes
# sed match nothing, silently producing a "broken" copy that is
# byte-identical to the real script — every non-vacuity case built on it
# would then report a false PASS (it would just be re-running the fixed
# script against itself) instead of catching the real pre-fix bug. A
# mismatch here is a fixture-authoring error, not a case failure, so it
# aborts the whole suite immediately with a clear diagnostic rather than
# quietly letting downstream cases "pass" for the wrong reason.
#
# 2026-08-21 (PR #14): this used to also build BROKEN_P1/BROKEN_P2 (do_rollback
# guards) and, via a separate make_broken_copy_replace helper, BROKEN_F2/
# BROKEN_F7/BROKEN_B16 (also do_rollback-only, needing pre-fix source text
# substituted back in rather than a bare deletion). All five were removed
# along with do_rollback itself — see the file header note above. Only
# BROKEN_P3 and BROKEN_F3 remain, since P3 and F3 guard install-path
# behavior that still exists.
make_broken_copy() {
  local marker="$1" out="$2"
  sed "/# ${marker}-GUARD-START/,/# ${marker}-GUARD-END/d" "$REINSTALL" > "$out"
  chmod +x "$out"
  if cmp -s "$REINSTALL" "$out"; then
    echo "make_broken_copy: $out is byte-identical to $REINSTALL — sed removed nothing for marker '$marker' (typo'd marker, or the ${marker}-GUARD-START/END markers were renamed/removed in reinstall.sh). Aborting suite — this fixture cannot prove non-vacuity." >&2
    exit 1
  fi
}
BROKEN_P3="$SANDBOX_ROOT/reinstall-broken-p3.sh"
BROKEN_F3="$SANDBOX_ROOT/reinstall-broken-f3.sh"
make_broken_copy P3 "$BROKEN_P3"
make_broken_copy F3 "$BROKEN_F3"

# run_broken <script> <home> <args...> — same REINSTALL_HOME safety wrapper
# as run_reinstall, but against one of the broken copies above instead of
# the real $REINSTALL.
run_broken() {
  local script="$1" home="$2"; shift 2
  if [ -z "$home" ]; then
    echo "run_broken: REINSTALL_HOME 인자가 비어 있음 — 실제 \$HOME 오염을 막기 위해 거부" >&2
    return 99
  fi
  local resolved
  resolved="$(cd "$home" 2>/dev/null && pwd -P || echo "$home")"
  if [ "$resolved" = "$REAL_HOME_RESOLVED" ]; then
    echo "run_broken: REINSTALL_HOME('$home')이 실제 \$HOME과 동일 — 거부" >&2
    return 99
  fi
  REINSTALL_HOME="$home" "$script" "$@"
}

PASS_COUNT=0
FAIL_COUNT=0
RESULTS=()

record() {
  local name="$1" status="$2" detail="${3:-}"
  RESULTS+=("$status|$name|$detail")
  if [ "$status" = "PASS" ]; then
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  FAIL detail: $detail" >&2
  fi
}

# case_dir <case-name> — makes and returns a fresh subtree with real-src,
# fake-home, and fake-dst, and prints the case root path.
case_dir() {
  local name="$1"
  local dir="$SANDBOX_ROOT/$name"
  mkdir -p "$dir/home" "$dir/dst"
  echo "$dir"
}

# checksum_tree <dir> — stable recursive checksum (path + content), used to
# assert "nothing changed" for dry-run cases. Falls back gracefully if a
# path has no entries.
checksum_tree() {
  local dir="$1"
  if [ ! -e "$dir" ]; then
    echo "MISSING"
    return 0
  fi
  find "$dir" -type f -exec cksum {} \; 2>/dev/null | sort
  find "$dir" -type l -exec sh -c 'printf "%s -> %s\n" "$1" "$(readlink "$1")"' _ {} \; 2>/dev/null | sort
}

# build_basic_dst <dst-root> — a realistic "existing local copy" fixture:
# stale SKILL.md/references content, plus files the canonical repo does
# not provide (dotfile, symlink, subdirectory, space/한글 names).
build_basic_dst() {
  local dst="$1"
  mkdir -p "$dst/.claude/skills/delegate-first/references" "$dst/.claude/agents"
  echo "stale skill md" > "$dst/.claude/skills/delegate-first/SKILL.md"
  echo "stale ref" > "$dst/.claude/skills/delegate-first/references/stale-ref.md"
  echo "handoff notes" > "$dst/.claude/skills/delegate-first/HANDOFF.md"
  ln -s HANDOFF.md "$dst/.claude/skills/delegate-first/HANDOFF-link.md"
  mkdir -p "$dst/.claude/skills/delegate-first/notes dir"
  echo "sub" > "$dst/.claude/skills/delegate-first/notes dir/파일 이름.md"
  echo "dotfile content" > "$dst/.claude/skills/delegate-first/.local-only"
  touch "$dst/.claude/agents/executor-high.md"
}

# build_fixture_src <src-root> — a minimal but complete canonical repo
# fixture (SKILL.md + references/ + 5 tier agent files, all reinstall.sh's
# §0 pre-checks require) that additionally carries a new top-level file
# (CHANGELOG.md) the real $REPO_ROOT does not currently have. Used to prove
# the generalized $NEW-construction step (scripts/reinstall.sh) picks up
# canonical top-level entries generically instead of only "SKILL.md" +
# "references" — see cases 11/12 below.
FIXTURE_CANONICAL_CHANGELOG="CANONICAL CHANGELOG CONTENT"
build_fixture_src() {
  local src="$1"
  mkdir -p "$src/.claude/skills/delegate-first/references" "$src/.claude/agents"
  echo "canonical skill" > "$src/.claude/skills/delegate-first/SKILL.md"
  echo "canonical ref" > "$src/.claude/skills/delegate-first/references/prompt-templates.md"
  echo "$FIXTURE_CANONICAL_CHANGELOG" > "$src/.claude/skills/delegate-first/CHANGELOG.md"
  local agent
  for agent in explorer-low executor-med executor-high reviewer-high judge-max; do
    echo "model: sonnet" > "$src/.claude/agents/$agent.md"
  done
}

echo "=== reinstall.sh test suite ==="
echo "sandbox: $SANDBOX_ROOT"
echo

# --- Case 0: run_reinstall guard non-vacuity — the guard itself must
# actually refuse an empty/real-$HOME REINSTALL_HOME, not just exist as
# dead code. This directly reproduces the F-2 mistake (a call site that
# forgets to sandbox REINSTALL_HOME) and confirms the wrapper catches it
# BEFORE "$REINSTALL" ever runs — both sub-checks return before invoking
# the real binary, so this is safe to execute against the real $HOME. ---
{
  ok=1
  run_reinstall "" --src "$REPO_ROOT" --dst "$SANDBOX_ROOT/does-not-matter" --dry-run >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 99 ] || { ok=0; detail="empty REINSTALL_HOME not rejected (rc=$rc, expected 99)"; }
  run_reinstall "$HOME" --src "$REPO_ROOT" --dst "$SANDBOX_ROOT/does-not-matter" --dry-run >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 99 ] || { ok=0; detail="real \$HOME REINSTALL_HOME not rejected (rc=$rc, expected 99)"; }
  if [ "$ok" -eq 1 ]; then record "case0_run_reinstall_guard_non_vacuous" PASS; else record "case0_run_reinstall_guard_non_vacuous" FAIL "$detail"; fi
}

# --- Case 1: normal reinstall — canonical content + succession preserved ---
{
  d="$(case_dir case1)"
  build_basic_dst "$d/dst"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc"; }
  diff -q "$d/dst/.claude/skills/delegate-first/SKILL.md" "$REPO_ROOT/.claude/skills/delegate-first/SKILL.md" >/dev/null 2>&1 || { ok=0; detail="SKILL.md not canonical"; }
  diff -q "$d/dst/.claude/skills/delegate-first/references/prompt-templates.md" "$REPO_ROOT/.claude/skills/delegate-first/references/prompt-templates.md" >/dev/null 2>&1 || { ok=0; detail="references not canonical"; }
  [ -f "$d/dst/.claude/skills/delegate-first/HANDOFF.md" ] || { ok=0; detail="dotfile-adjacent HANDOFF.md not preserved"; }
  [ -f "$d/dst/.claude/skills/delegate-first/.local-only" ] || { ok=0; detail="dotfile not preserved"; }
  [ -L "$d/dst/.claude/skills/delegate-first/HANDOFF-link.md" ] || { ok=0; detail="symlink not preserved"; }
  [ -f "$d/dst/.claude/skills/delegate-first/notes dir/파일 이름.md" ] || { ok=0; detail="space/한글 subdir not preserved"; }
  for agent in explorer-low executor-med executor-high reviewer-high judge-max; do
    diff -q "$d/dst/.claude/agents/$agent.md" "$REPO_ROOT/.claude/agents/$agent.md" >/dev/null 2>&1 || { ok=0; detail="agent $agent not canonical"; }
  done
  if [ "$ok" -eq 1 ]; then record "case1_normal_reinstall" PASS; else record "case1_normal_reinstall" FAIL "$detail"; fi
}

# --- Case 2: --dry-run changes nothing ---
{
  d="$(case_dir case2)"
  build_basic_dst "$d/dst"
  before="$(checksum_tree "$d/dst")"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --dry-run 2>&1)"
  rc=$?
  after="$(checksum_tree "$d/dst")"
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc"; }
  [ "$before" = "$after" ] || { ok=0; detail="tree checksum changed under --dry-run"; }
  [ ! -e "$d/home/.claude-backups" ] || { ok=0; detail="backup dir created under --dry-run"; }
  echo "$out" | grep -q "HANDOFF.md" || { ok=0; detail="plan output missing succession list entry"; }
  if [ "$ok" -eq 1 ]; then record "case2_dry_run_no_changes" PASS; else record "case2_dry_run_no_changes" FAIL "$detail"; fi
}

# --- Case 3: missing --dst -> exit 1, nothing installed ---
{
  d="$(case_dir case3)"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --yes 2>&1)"
  rc=$?
  if [ "$rc" -eq 1 ]; then record "case3_missing_dst" PASS; else record "case3_missing_dst" FAIL "exit=$rc out=$out"; fi
}

# --- Case 4: bad --src -> exit 1 before anything destructive, dst intact ---
{
  d="$(case_dir case4)"
  build_basic_dst "$d/dst"
  before="$(checksum_tree "$d/dst")"
  out="$(run_reinstall "$d/home" --src "$d/does-not-exist" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  after="$(checksum_tree "$d/dst")"
  ok=1
  [ "$rc" -eq 1 ] || { ok=0; detail="exit=$rc"; }
  [ "$before" = "$after" ] || { ok=0; detail="dst tree changed despite bad --src"; }
  [ ! -e "$d/home/.claude-backups" ] || { ok=0; detail="backup created despite bad --src (destructive step ran before guard)"; }
  if [ "$ok" -eq 1 ]; then record "case4_bad_src" PASS; else record "case4_bad_src" FAIL "$detail"; fi
}

# --- Case 5: succession copy failure (permission denied) -> exit 1 before swap, dst intact ---
{
  d="$(case_dir case5)"
  build_basic_dst "$d/dst"
  # Make one existing file unreadable so `cp` fails mid-succession-loop.
  # Checksum captured BEFORE chmod 000, so cksum can read the file both
  # times — otherwise "before" would contain a read-error line that
  # "after" (post chmod-restore) would not, producing a false mismatch
  # unrelated to whether the script actually mutated anything.
  echo "secret" > "$d/dst/.claude/skills/delegate-first/blocked-file.md"
  before="$(checksum_tree "$d/dst/.claude/skills/delegate-first")"
  chmod 000 "$d/dst/.claude/skills/delegate-first/blocked-file.md"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  chmod 644 "$d/dst/.claude/skills/delegate-first/blocked-file.md" 2>/dev/null
  after="$(checksum_tree "$d/dst/.claude/skills/delegate-first")"
  ok=1
  [ "$rc" -ne 0 ] || { ok=0; detail="expected non-zero exit, got 0"; }
  [ -d "$d/dst/.claude/skills/delegate-first" ] || { ok=0; detail="original tree missing after failed swap"; }
  [ "$before" = "$after" ] || { ok=0; detail="dst skill tree mutated despite copy failure"; }
  if [ "$ok" -eq 1 ]; then record "case5_succession_copy_failure" PASS; else record "case5_succession_copy_failure" FAIL "$detail (rc=$rc)"; fi
}

# --- Case 6: canonical gains a file that also exists stale in dst's references -> final content is canonical ---
{
  d="$(case_dir case6)"
  build_basic_dst "$d/dst"
  # A file that exists in the real references/ dir, but with different
  # (stale) content, planted at the same relative path in dst's copy.
  echo "STALE VERSION" > "$d/dst/.claude/skills/delegate-first/references/prompt-templates.md"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc out=$out"; }
  diff -q "$d/dst/.claude/skills/delegate-first/references/prompt-templates.md" "$REPO_ROOT/.claude/skills/delegate-first/references/prompt-templates.md" >/dev/null 2>&1 || { ok=0; detail="stale dst version survived instead of canonical"; }
  if [ "$ok" -eq 1 ]; then record "case6_canonical_wins_over_stale" PASS; else record "case6_canonical_wins_over_stale" FAIL "$detail"; fi
}

# --- Case 7: interrupted state (.old only, no live dir) -> exit 1, .old preserved ---
{
  d="$(case_dir case7)"
  mkdir -p "$d/dst/.claude/skills"
  mkdir -p "$d/dst/.claude/skills/delegate-first.old"
  echo "recovery copy" > "$d/dst/.claude/skills/delegate-first.old/SKILL.md"
  before_old="$(checksum_tree "$d/dst/.claude/skills/delegate-first.old")"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  after_old="$(checksum_tree "$d/dst/.claude/skills/delegate-first.old")"
  ok=1
  [ "$rc" -eq 1 ] || { ok=0; detail="exit=$rc"; }
  [ "$before_old" = "$after_old" ] || { ok=0; detail=".old was mutated/deleted on interrupted-state re-run"; }
  [ ! -e "$d/dst/.claude/skills/delegate-first" ] || { ok=0; detail="live dir unexpectedly created"; }
  if [ "$ok" -eq 1 ]; then record "case7_interrupted_state_guard" PASS; else record "case7_interrupted_state_guard" FAIL "$detail"; fi
}

# --- Case 10: without --propagate-global, global paths are untouched ---
{
  d="$(case_dir case10)"
  build_basic_dst "$d/dst"
  mkdir -p "$d/home/.claude/hooks" "$d/home/.claude/rules"
  echo "pre-existing hook" > "$d/home/.claude/hooks/enforce-subagent-model.cjs"
  echo "pre-existing rule" > "$d/home/.claude/rules/subagent-model-routing.md"
  before_hook="$(cksum "$d/home/.claude/hooks/enforce-subagent-model.cjs")"
  before_rule="$(cksum "$d/home/.claude/rules/subagent-model-routing.md")"
  run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes >/dev/null 2>&1
  rc=$?
  after_hook="$(cksum "$d/home/.claude/hooks/enforce-subagent-model.cjs")"
  after_rule="$(cksum "$d/home/.claude/rules/subagent-model-routing.md")"
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc"; }
  [ "$before_hook" = "$after_hook" ] || { ok=0; detail="global hook checksum changed without --propagate-global"; }
  [ "$before_rule" = "$after_rule" ] || { ok=0; detail="global rule checksum changed without --propagate-global"; }
  if [ "$ok" -eq 1 ]; then record "case10_no_propagate_by_default" PASS; else record "case10_no_propagate_by_default" FAIL "$detail"; fi
}

# --- Case 11: canonical gains a brand-new top-level file, dst has none by
# that name -> reinstall installs it with canonical content (proves $NEW
# construction is not hardcoded to "SKILL.md"/"references" only) ---
{
  d="$(case_dir case11)"
  src="$d/src"
  build_fixture_src "$src"
  build_basic_dst "$d/dst"
  out="$(run_reinstall "$d/home" --src "$src" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc out=$out"; }
  [ -f "$d/dst/.claude/skills/delegate-first/CHANGELOG.md" ] || { ok=0; detail="new canonical top-level file (CHANGELOG.md) not installed at all"; }
  if [ "$ok" -eq 1 ]; then
    content="$(cat "$d/dst/.claude/skills/delegate-first/CHANGELOG.md")"
    [ "$content" = "$FIXTURE_CANONICAL_CHANGELOG" ] || { ok=0; detail="CHANGELOG.md installed but content is not canonical: got [$content]"; }
  fi
  if [ "$ok" -eq 1 ]; then record "case11_new_canonical_file_installed" PASS; else record "case11_new_canonical_file_installed" FAIL "$detail"; fi
}

# --- Case 12: canonical gains a brand-new top-level file, dst already has a
# stale file by that same name -> canonical wins, succession must NOT let
# the stale dst copy occupy the canonical file's slot ---
{
  d="$(case_dir case12)"
  src="$d/src"
  build_fixture_src "$src"
  build_basic_dst "$d/dst"
  echo "STALE CHANGELOG FROM DST" > "$d/dst/.claude/skills/delegate-first/CHANGELOG.md"
  out="$(run_reinstall "$d/home" --src "$src" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc out=$out"; }
  [ -f "$d/dst/.claude/skills/delegate-first/CHANGELOG.md" ] || { ok=0; detail="CHANGELOG.md missing after reinstall"; }
  if [ "$ok" -eq 1 ]; then
    content="$(cat "$d/dst/.claude/skills/delegate-first/CHANGELOG.md")"
    [ "$content" = "$FIXTURE_CANONICAL_CHANGELOG" ] || { ok=0; detail="stale dst CHANGELOG.md survived instead of canonical: got [$content]"; }
  fi
  if [ "$ok" -eq 1 ]; then record "case12_canonical_wins_over_stale_new_file" PASS; else record "case12_canonical_wins_over_stale_new_file" FAIL "$detail"; fi
}

# --- Case 15 (C-1): --src == --dst is refused before any destructive step.
# Uses build_fixture_src (not build_basic_dst) for the shared directory —
# it plants all 5 tier agent files, so §0's pre-checks (which require SRC
# to have all 5) would otherwise PASS and let the script proceed to a
# self-referential swap. build_basic_dst only has 1/5 tier files, which
# would make §0 reject this case for an unrelated reason (missing tier
# agents in SRC) and the C-1 guard would never actually be exercised. ---
{
  d="$(case_dir case15)"
  same="$d/dst"
  build_fixture_src "$same"
  before="$(checksum_tree "$same")"
  out="$(run_reinstall "$d/home" --src "$same" --dst "$same" --yes 2>&1)"
  rc=$?
  after="$(checksum_tree "$same")"
  ok=1
  [ "$rc" -ne 0 ] || { ok=0; detail="expected non-zero exit for --src == --dst, got 0"; }
  [ "$before" = "$after" ] || { ok=0; detail="tree changed despite --src == --dst guard"; }
  [ ! -e "$d/home/.claude-backups" ] || { ok=0; detail="backup created despite --src == --dst guard (destructive step ran before guard)"; }
  if [ "$ok" -eq 1 ]; then record "case15_src_eq_dst_refused" PASS; else record "case15_src_eq_dst_refused" FAIL "$detail"; fi
}

# --- Case 16 (C6): a symlinked $DST skill directory is refused instead of
# silently producing zero-file succession and replacing the link with a
# real directory (orphaning whatever the link used to point at). ---
{
  d="$(case_dir case16)"
  mkdir -p "$d/dst/.claude/agents" "$d/link-target/notes"
  echo "real target content" > "$d/link-target/HANDOFF.md"
  echo "sub" > "$d/link-target/notes/keep.md"
  mkdir -p "$d/dst/.claude/skills"
  ln -s "$d/link-target" "$d/dst/.claude/skills/delegate-first"
  before="$(checksum_tree "$d/link-target")"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  after="$(checksum_tree "$d/link-target")"
  ok=1
  [ "$rc" -ne 0 ] || { ok=0; detail="expected non-zero exit for symlinked skill dir, got 0"; }
  [ -L "$d/dst/.claude/skills/delegate-first" ] || { ok=0; detail="symlink was replaced despite guard"; }
  [ "$before" = "$after" ] || { ok=0; detail="link target contents mutated despite guard"; }
  [ ! -e "$d/home/.claude-backups" ] || { ok=0; detail="backup created despite symlink guard (destructive step ran before guard)"; }
  if [ "$ok" -eq 1 ]; then record "case16_symlinked_skill_dir_refused" PASS; else record "case16_symlinked_skill_dir_refused" FAIL "$detail"; fi
}

# --- Case 17 (P2): a colliding backup directory name is refused instead of
# silently nesting a second run's backup inside the first's. Uses the
# test-only REINSTALL_STAMP_OVERRIDE hook (see reinstall.sh header comment)
# to force two separate invocations to compute the identical $BAK path —
# a real same-PID collision cannot be reliably forced from a test. ---
{
  d="$(case_dir case17)"
  build_basic_dst "$d/dst"
  fixed_stamp="fixedstamp-p2"
  out1="$(REINSTALL_STAMP_OVERRIDE="$fixed_stamp" run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc1=$?
  bak_path="$d/home/.claude-backups/delegate-first-$fixed_stamp"
  ok=1
  [ "$rc1" -eq 0 ] || { ok=0; detail="first run (establishing the collision target) failed: exit=$rc1 out=$out1"; }
  [ -d "$bak_path" ] || { ok=0; detail="expected backup dir not created: $bak_path"; }
  before_bak="$(checksum_tree "$bak_path")"
  if [ "$ok" -eq 1 ]; then
    out2="$(REINSTALL_STAMP_OVERRIDE="$fixed_stamp" run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
    rc2=$?
    after_bak="$(checksum_tree "$bak_path")"
    [ "$rc2" -ne 0 ] || { ok=0; detail="second run with colliding stamp expected non-zero exit, got 0"; }
    echo "$out2" | grep -q "백업 디렉터리 충돌" || { ok=0; detail="missing collision error message: $out2"; }
    [ "$before_bak" = "$after_bak" ] || { ok=0; detail="P2 regression: second run's content landed inside the first run's backup dir instead of being refused"; }
  fi
  if [ "$ok" -eq 1 ]; then record "case17_backup_dir_collision_refused" PASS; else record "case17_backup_dir_collision_refused" FAIL "$detail"; fi
}

# --- Case 20 (NEW_INSTALL): a brand-new target project with no $DST/.claude
# at all -> reinstall succeeds and installs canonical content, instead of
# the pre-fix hard rejection ("신규 설치는 이 스크립트가 아니라
# README.md §설치를 따른다") even though $DST itself exists. case_dir()
# already makes "$dir/dst" as a bare empty directory with no .claude
# subdir, so no fixture-builder call is needed here — that bareness IS the
# fixture. ---
{
  d="$(case_dir case20)"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc out=$out"; }
  diff -q "$d/dst/.claude/skills/delegate-first/SKILL.md" "$REPO_ROOT/.claude/skills/delegate-first/SKILL.md" >/dev/null 2>&1 || { ok=0; detail="SKILL.md not canonical"; }
  diff -q "$d/dst/.claude/skills/delegate-first/references/prompt-templates.md" "$REPO_ROOT/.claude/skills/delegate-first/references/prompt-templates.md" >/dev/null 2>&1 || { ok=0; detail="references not canonical"; }
  for agent in explorer-low executor-med executor-high reviewer-high judge-max; do
    diff -q "$d/dst/.claude/agents/$agent.md" "$REPO_ROOT/.claude/agents/$agent.md" >/dev/null 2>&1 || { ok=0; detail="agent $agent not canonical"; }
  done
  if [ "$ok" -eq 1 ]; then record "case20_fresh_install_no_claude_dir" PASS; else record "case20_fresh_install_no_claude_dir" FAIL "$detail"; fi
}

# --- Case 21 (NEW_INSTALL): $DST/.claude exists but has neither skills/ nor
# agents/ yet (a project that adopted .claude for something else first, or
# a partially-scaffolded project) -> reinstall succeeds. This path already
# worked before the NEW_INSTALL fix (the old §0 guard only checked for
# $DST/.claude itself); kept here as an explicit regression lock next to
# case20/22 rather than left implicit. ---
{
  d="$(case_dir case21)"
  mkdir -p "$d/dst/.claude"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc out=$out"; }
  diff -q "$d/dst/.claude/skills/delegate-first/SKILL.md" "$REPO_ROOT/.claude/skills/delegate-first/SKILL.md" >/dev/null 2>&1 || { ok=0; detail="SKILL.md not canonical"; }
  for agent in explorer-low executor-med executor-high reviewer-high judge-max; do
    diff -q "$d/dst/.claude/agents/$agent.md" "$REPO_ROOT/.claude/agents/$agent.md" >/dev/null 2>&1 || { ok=0; detail="agent $agent not canonical"; }
  done
  if [ "$ok" -eq 1 ]; then record "case21_claude_dir_without_skills_or_agents" PASS; else record "case21_claude_dir_without_skills_or_agents" FAIL "$detail"; fi
}

# --- Case 27 (P3, S14): $DST/.claude/skills/delegate-first exists but is a
# REGULAR FILE, not a directory (and not a symlink — C6 already guards
# that). Before this fix, §1's `[ -d ]` backup check misread this as "no
# existing skill directory" (backup skipped), but §2/§3's swap uses
# `[ -e ]` and still moves the file to .old, which is then unconditionally
# rm -rf'd once the swap succeeds — the file is permanently lost with no
# backup and no warning, rc=0, and a false "재설치 완료" log. ---
{
  d="$(case_dir case27)"
  mkdir -p "$d/dst/.claude/skills"
  echo "not a directory, just a file" > "$d/dst/.claude/skills/delegate-first"
  before="$(checksum_tree "$d/dst/.claude/skills/delegate-first")"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  after="$(checksum_tree "$d/dst/.claude/skills/delegate-first")"
  ok=1
  [ "$rc" -ne 0 ] || { ok=0; detail="expected non-zero exit for skill-path-is-a-file, got 0"; }
  [ -f "$d/dst/.claude/skills/delegate-first" ] || { ok=0; detail="the original file no longer exists as a plain file — data loss despite the guard"; }
  [ "$before" = "$after" ] || { ok=0; detail="P3 regression: file content mutated/lost despite the guard"; }
  [ ! -e "$d/home/.claude-backups" ] || { ok=0; detail="backup dir created despite the guard (destructive step ran before refusal)"; }
  if [ "$ok" -eq 1 ]; then record "case27_skill_path_is_regular_file_refused" PASS; else record "case27_skill_path_is_regular_file_refused" FAIL "$detail"; fi
  # Non-vacuity: against the pre-fix (broken-p3) copy, the same fixture must
  # reproduce the actual S14 bug — rc=0 AND the file replaced by a
  # directory (permanently lost, no backup).
  if [ "$ok" -eq 1 ]; then
    d2="$(case_dir case27_vac)"
    mkdir -p "$d2/dst/.claude/skills"
    echo "not a directory, just a file" > "$d2/dst/.claude/skills/delegate-first"
    run_broken "$BROKEN_P3" "$d2/home" --src "$REPO_ROOT" --dst "$d2/dst" --yes >/dev/null 2>&1
    rc2=$?
    vac_ok=0
    [ "$rc2" -eq 0 ] && [ -d "$d2/dst/.claude/skills/delegate-first" ] && vac_ok=1
    if [ "$vac_ok" -eq 1 ]; then record "case27_nonvacuous_broken_p3_reproduces_bug" PASS; else record "case27_nonvacuous_broken_p3_reproduces_bug" FAIL "broken-p3 copy did not reproduce the pre-fix S14 file-clobber bug (rc2=$rc2)"; fi
  fi
}

# --- Case F3 (F-3 regression): a completely fresh machine — settings.json
# missing from BOTH the global path ($home/.claude/settings.json) and the
# project path ($dst/.claude/settings.json) — must print the "반쪽 설치"
# hook-registration warning instead of the §0 advisory section going
# entirely silent. Empty $home (case_dir's bare "home" dir has no
# .claude/settings.json) + a $dst with no .claude at all (case_dir's bare
# "dst" dir — no project settings.json either) reproduces exactly the
# scenario the F-3 fix targets. ---
{
  d="$(case_dir caseF3)"
  out="$(run_reinstall "$d/home" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc out=$out"; }
  echo "$out" | grep -qF "settings.json을 전역" || { ok=0; detail="missing F-3 half-install hook warning when settings.json absent everywhere"; }
  if [ "$ok" -eq 1 ]; then record "caseF3_settings_json_absent_warns" PASS; else record "caseF3_settings_json_absent_warns" FAIL "$detail"; fi
  # Non-vacuity: against the deletion-type broken copy (the F3-GUARD region
  # — the entire else-branch body — stripped out, reproducing the exact
  # pre-fix code, which had no else branch at all for this condition), the
  # warning must be completely absent from output while the script still
  # exits 0 — the actual pre-fix "silent half install" symptom: this one
  # §0 advisory branch emits zero lines about hook registration and the
  # script still reports success.
  if [ "$ok" -eq 1 ]; then
    d2="$(case_dir caseF3_vac)"
    out2="$(run_broken "$BROKEN_F3" "$d2/home" --src "$REPO_ROOT" --dst "$d2/dst" --yes 2>&1)"
    rc2=$?
    vac_ok=0
    if [ "$rc2" -eq 0 ] && ! echo "$out2" | grep -qF "settings.json을 전역"; then
      vac_ok=1
    fi
    if [ "$vac_ok" -eq 1 ]; then record "caseF3_nonvacuous_broken_f3_reproduces_bug" PASS; else record "caseF3_nonvacuous_broken_f3_reproduces_bug" FAIL "broken-f3 copy did not reproduce the pre-fix silent half-install symptom (rc2=$rc2 out2=[$out2])"; fi
  fi
}

echo
echo "=== results ==="
for r in "${RESULTS[@]}"; do
  IFS='|' read -r status name detail <<< "$r"
  printf '%-4s %s\n' "$status" "$name"
done

echo
echo "PASS $PASS_COUNT/$((PASS_COUNT + FAIL_COUNT))"

if [ "$FAIL_COUNT" -gt 0 ]; then
  echo
  echo "One or more cases failed — see FAIL detail lines above."
  exit 1
fi

echo
echo "All cases passed."
exit 0
