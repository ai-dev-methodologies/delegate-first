#!/usr/bin/env bash
# test-reinstall.sh — sandboxed test suite for scripts/reinstall.sh.
#
# Everything happens inside a throwaway mktemp -d tree. This script never
# reads or writes the real $HOME/.claude or any real project — every run
# sets REINSTALL_HOME to a fake home inside the sandbox, and --src/--dst
# always point at fixtures built fresh for each case. A trap removes the
# whole sandbox on exit (success, failure, or interrupt).
#
# Cases 1-10 cover the original reinstall procedure (backup, dry-run,
# guards, succession, rollback, global propagation opt-in). Cases 11-12
# cover the generalized $NEW-construction step: the canonical repo's
# top-level skill-dir entries are copied generically (no hardcoded
# "SKILL.md"/"references" pair), so a new canonical file installs even if
# dst has no file by that name (11) and wins over a stale same-named dst
# file instead of being shadowed by succession (12).
#
# Non-vacuity for 11/12 is checked out-of-band, not as extra numbered
# cases here: point REINSTALL_BIN at a copy of reinstall.sh predating this
# generalization (hardcoded SKILL_PROVIDED_NAMES=("SKILL.md" "references")
# array) and confirm cases 11 and 12 both FAIL against it.

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

# --- Case 1: normal reinstall — canonical content + succession preserved ---
{
  d="$(case_dir case1)"
  build_basic_dst "$d/dst"
  out="$("$REINSTALL" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
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
  out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --src "$REPO_ROOT" --dst "$d/dst" --dry-run 2>&1)"
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
  out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --src "$REPO_ROOT" --yes 2>&1)"
  rc=$?
  if [ "$rc" -eq 1 ]; then record "case3_missing_dst" PASS; else record "case3_missing_dst" FAIL "exit=$rc out=$out"; fi
}

# --- Case 4: bad --src -> exit 1 before anything destructive, dst intact ---
{
  d="$(case_dir case4)"
  build_basic_dst "$d/dst"
  before="$(checksum_tree "$d/dst")"
  out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --src "$d/does-not-exist" --dst "$d/dst" --yes 2>&1)"
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
  out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
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
  out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
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
  out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --src "$REPO_ROOT" --dst "$d/dst" --yes 2>&1)"
  rc=$?
  after_old="$(checksum_tree "$d/dst/.claude/skills/delegate-first.old")"
  ok=1
  [ "$rc" -eq 1 ] || { ok=0; detail="exit=$rc"; }
  [ "$before_old" = "$after_old" ] || { ok=0; detail=".old was mutated/deleted on interrupted-state re-run"; }
  [ ! -e "$d/dst/.claude/skills/delegate-first" ] || { ok=0; detail="live dir unexpectedly created"; }
  if [ "$ok" -eq 1 ]; then record "case7_interrupted_state_guard" PASS; else record "case7_interrupted_state_guard" FAIL "$detail"; fi
}

# --- Case 8: --rollback restores dotfiles/symlinks, leaves no leftovers ---
{
  d="$(case_dir case8)"
  build_basic_dst "$d/dst"
  before="$(checksum_tree "$d/dst/.claude/skills/delegate-first")"
  REINSTALL_HOME="$d/home" "$REINSTALL" --src "$REPO_ROOT" --dst "$d/dst" --yes >/dev/null 2>&1
  bak="$(ls -1dt "$d/home/.claude-backups/delegate-first-"* 2>/dev/null | head -1)"
  ok=1
  [ -n "$bak" ] || { ok=0; detail="no backup dir found after install"; }
  if [ "$ok" -eq 1 ]; then
    out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --rollback "$bak" --dst "$d/dst" --yes 2>&1)"
    rc=$?
    after="$(checksum_tree "$d/dst/.claude/skills/delegate-first")"
    [ "$rc" -eq 0 ] || { ok=0; detail="rollback exit=$rc out=$out"; }
    [ "$before" = "$after" ] || { ok=0; detail="post-rollback tree does not match pre-install tree"; }
    [ ! -e "$d/dst/.claude/skills/delegate-first.new" ] || { ok=0; detail="leftover .new after rollback"; }
    [ ! -e "$d/dst/.claude/skills/delegate-first.old" ] || { ok=0; detail="leftover .old after rollback"; }
  fi
  if [ "$ok" -eq 1 ]; then record "case8_rollback_restores_everything" PASS; else record "case8_rollback_restores_everything" FAIL "$detail"; fi
}

# --- Case 9: --rollback-global with no hook/rule in backup -> skip message + exit 0 ---
{
  d="$(case_dir case9)"
  mkdir -p "$d/home/.claude-backups/fake-bak/skills-delegate-first"
  echo "x" > "$d/home/.claude-backups/fake-bak/skills-delegate-first/SKILL.md"
  mkdir -p "$d/dst/.claude"
  out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --rollback "$d/home/.claude-backups/fake-bak" --dst "$d/dst" --rollback-global --yes 2>&1)"
  rc=$?
  ok=1
  [ "$rc" -eq 0 ] || { ok=0; detail="exit=$rc out=$out"; }
  echo "$out" | grep -q "스킵함: enforce-subagent-model.cjs" || { ok=0; detail="missing hook skip message"; }
  echo "$out" | grep -q "스킵함: subagent-model-routing.md" || { ok=0; detail="missing rule skip message"; }
  [ ! -e "$d/home/.claude/hooks/enforce-subagent-model.cjs" ] || { ok=0; detail="hook file created despite absent source"; }
  if [ "$ok" -eq 1 ]; then record "case9_rollback_global_skip_when_absent" PASS; else record "case9_rollback_global_skip_when_absent" FAIL "$detail"; fi
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
  REINSTALL_HOME="$d/home" "$REINSTALL" --src "$REPO_ROOT" --dst "$d/dst" --yes >/dev/null 2>&1
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
  out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --src "$src" --dst "$d/dst" --yes 2>&1)"
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
  out="$(REINSTALL_HOME="$d/home" "$REINSTALL" --src "$src" --dst "$d/dst" --yes 2>&1)"
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
