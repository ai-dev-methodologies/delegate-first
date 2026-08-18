#!/usr/bin/env bash
# reinstall.sh — scripted implementation of docs/REINSTALL.md §0~§5.
#
# This script does not invent new policy. It executes the procedure that
# docs/REINSTALL.md already confirms (backup → diff → copy-to-temp-then-swap
# → tier agents → optional global propagation → verification reminders),
# with the same safety guards that document's §3/§5 spell out (F1~F6 in
# BACKLOG B-13/B-14): guard SRC/DST before anything destructive, verify the
# backup is non-empty, verify succession copies actually landed before the
# swap, detect an interrupted re-run instead of deleting the only recovery
# copy, and use conditional (not unconditional) restores in rollback.
#
# Two deliberate deviations from the manual doc, both explicitly required by
# the task that produced this script (not invented here):
#   1. Global hook/rule propagation defaults OFF. Use --propagate-global to
#      do what docs/REINSTALL.md §3's last two `cp` lines do unconditionally.
#   2. Global hook/rule rollback defaults OFF. Use --rollback-global to do
#      what docs/REINSTALL.md §5's conditional cp block does.
# Everything else (skill swap, tier agent copy, backup layout, succession
# rules, interrupted-reinstall guard) matches the doc exactly.
#
# Usage:
#   reinstall.sh --dst <path> [--src <path>] [--dry-run] [--yes] [--propagate-global]
#   reinstall.sh --rollback <backup-dir> --dst <path> [--rollback-global] [--yes] [--dry-run]
#
# REINSTALL_HOME env var (test-only override): when set, replaces $HOME as
# the root for backups (<root>/.claude-backups) and for global hook/rule
# paths (<root>/.claude/hooks, <root>/.claude/rules). Production runs never
# set this, so production behavior is exactly "$HOME". scripts/test-reinstall.sh
# uses it to sandbox every run inside a throwaway mktemp -d tree.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
GLOBAL_ROOT="${REINSTALL_HOME:-$HOME}"

SRC=""
DST=""
DRY_RUN=0
ASSUME_YES=0
PROPAGATE_GLOBAL=0
ROLLBACK_GLOBAL=0
ROLLBACK_DIR=""

log() { echo "[reinstall] $*"; }
err() { echo "[reinstall] $*" >&2; }

usage() {
  cat <<'EOF'
Usage:
  reinstall.sh --dst <path> [--src <path>] [--dry-run] [--yes] [--propagate-global]
  reinstall.sh --rollback <backup-dir> --dst <path> [--rollback-global] [--yes] [--dry-run]

  --src <path>          Canonical delegate-first repo root. Default: this
                         script's own repo root.
  --dst <path>          Target project to (re)install into. REQUIRED, no
                         default (installing into the wrong path is a
                         destructive mistake).
  --dry-run             Print the plan (backup path, replace targets,
                         succession list, diff summary) and exit. Nothing
                         is written.
  --yes                 Skip the confirmation prompt before destructive
                         steps (required for unattended runs; without it,
                         a non-interactive shell aborts instead of hanging).
  --propagate-global    Also copy the canonical hook/rule file to
                         $REINSTALL_HOME/.claude (default: $HOME/.claude).
                         Off by default — global changes have a different
                         blast radius than one project's local files.
  --rollback <dir>      Restore from a backup directory produced by a
                         previous run's §1 (skills-delegate-first/, agents/,
                         and optionally enforce-subagent-model.cjs /
                         subagent-model-routing.md).
  --rollback-global     Pair with --rollback to also restore the global
                         hook/rule from that backup, if present.
  -h, --help            Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC="${2:?--src requires a path}"; shift 2 ;;
    --dst) DST="${2:?--dst requires a path}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --propagate-global) PROPAGATE_GLOBAL=1; shift ;;
    --rollback) ROLLBACK_DIR="${2:?--rollback requires a backup dir}"; shift 2 ;;
    --rollback-global) ROLLBACK_GLOBAL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "알 수 없는 인자: $1"; usage >&2; exit 1 ;;
  esac
done

[ -n "$SRC" ] || SRC="$DEFAULT_SRC"

BACKUP_ROOT="$GLOBAL_ROOT/.claude-backups"
RULES_TARGET_DIR="$GLOBAL_ROOT/.claude/rules"
HOOKS_TARGET_DIR="$GLOBAL_ROOT/.claude/hooks"
RULE_FILE_NAME="subagent-model-routing.md"
HOOK_FILE_NAME="enforce-subagent-model.cjs"

confirm() {
  if [ "$ASSUME_YES" -eq 1 ]; then
    return 0
  fi
  if [ ! -t 0 ]; then
    err "비대화형 환경이고 --yes가 없다 — 확인을 받을 수 없어 중단한다."
    exit 1
  fi
  local reply
  read -r -p "[reinstall] 위 계획대로 진행할까? [y/N] " reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) err "사용자가 확인하지 않아 중단했다."; exit 1 ;;
  esac
}

# List the top-level entries (files, dirs, dotfiles alike) of a directory,
# one basename per line. Used both to show "what the canonical repo
# provides" and, generically, to drive the copy/succession steps below —
# no hardcoded name list, so a new top-level file in $SRC's skill dir
# (e.g. CHANGELOG.md) is picked up automatically.
list_top_level_names() {
  local dir="$1"
  [ -d "$dir" ] || return 0
  find "$dir" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort
}

# Compute which top-level entries of an existing $DST skill dir would be
# carried over (i.e. names $SRC's skill dir does not provide). Printed one
# per line. Provided-ness is derived from $SRC's actual listing, not a
# hardcoded array — so a name the canonical repo newly provides is never
# mistaken for something to succeed from the (possibly stale) $DST copy.
compute_succession_list() {
  local dst_skill_dir="$1" src_skill_dir="$2"
  [ -d "$dst_skill_dir" ] || return 0
  local base
  while IFS= read -r -d '' item; do
    base="$(basename "$item")"
    if [ -e "$src_skill_dir/$base" ] || [ -L "$src_skill_dir/$base" ]; then
      continue
    fi
    printf '%s\n' "$base"
  done < <(find "$dst_skill_dir" -mindepth 1 -maxdepth 1 -print0)
}

# ---------------------------------------------------------------------------
# Rollback (docs/REINSTALL.md §5)
# ---------------------------------------------------------------------------
do_rollback() {
  [ -n "$DST" ] || { err "--rollback에는 --dst도 필요하다 — 복원 대상이 없다."; exit 1; }
  [ -d "$ROLLBACK_DIR/skills-delegate-first" ] || {
    err "백업 없음: $ROLLBACK_DIR — 경로가 §1이 실제로 백업을 만든 그 디렉터리인지 확인하라."
    exit 1
  }

  log "=== 롤백 계획 ==="
  log "복원 소스: $ROLLBACK_DIR"
  log "대상 스킬 디렉터리: $DST/.claude/skills/delegate-first (통째로 교체됨)"
  if [ -d "$ROLLBACK_DIR/agents" ]; then
    log "대상 에이전트: $DST/.claude/agents (백업 내용으로 덮어씀)"
  else
    log "백업에 agents/ 없음 — 에이전트 복원 생략"
  fi
  if [ "$ROLLBACK_GLOBAL" -eq 1 ]; then
    log "전역 훅/규칙 롤백 요청됨(--rollback-global) — 백업이 '전파 전' 사본이 아닐 수 있다는 점을 감안할 것"
  else
    log "전역 훅/규칙은 건드리지 않음(--rollback-global 없음)"
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    log "--dry-run: 아무것도 바꾸지 않았다."
    exit 0
  fi

  confirm

  log "잔여 .new/.old 정리"
  rm -rf "$DST/.claude/skills/delegate-first.new" "$DST/.claude/skills/delegate-first.old"

  log "스킬 디렉터리 복원"
  mkdir -p "$DST/.claude/skills"
  rm -rf "$DST/.claude/skills/delegate-first"
  cp -R "$ROLLBACK_DIR/skills-delegate-first" "$DST/.claude/skills/delegate-first"

  if [ -d "$ROLLBACK_DIR/agents" ]; then
    log "에이전트 복원"
    mkdir -p "$DST/.claude/agents"
    cp -R "$ROLLBACK_DIR/agents/." "$DST/.claude/agents/"
  else
    log "스킵함: agents (백업에 소스 없음)"
  fi

  if [ "$ROLLBACK_GLOBAL" -eq 1 ]; then
    err "경고: 이 백업이 별도 전파 절차(예: B-08) 이후에 만들어졌다면, 여기 담긴 훅/규칙은 이미 정본판일 수 있다 — 그 경우 이 복원은 롤백이 아니라 재설치가 된다."
    if [ -f "$ROLLBACK_DIR/$HOOK_FILE_NAME" ]; then
      mkdir -p "$HOOKS_TARGET_DIR"
      cp "$ROLLBACK_DIR/$HOOK_FILE_NAME" "$HOOKS_TARGET_DIR/$HOOK_FILE_NAME"
      log "복원함: $HOOK_FILE_NAME"
    else
      log "스킵함: $HOOK_FILE_NAME (백업에 소스 없음)"
    fi
    if [ -f "$ROLLBACK_DIR/$RULE_FILE_NAME" ]; then
      mkdir -p "$RULES_TARGET_DIR"
      cp "$ROLLBACK_DIR/$RULE_FILE_NAME" "$RULES_TARGET_DIR/$RULE_FILE_NAME"
      log "복원함: $RULE_FILE_NAME"
    else
      log "스킵함: $RULE_FILE_NAME (백업에 소스 없음)"
    fi
  fi

  log "롤백 완료. §4 검증 3단계를 다시 수동으로 확인할 것(스킬 로드/훅 스모크/tier 스폰은 실행 중인 세션에서만 확인 가능)."
  exit 0
}

if [ -n "$ROLLBACK_DIR" ]; then
  do_rollback
fi

# ---------------------------------------------------------------------------
# Reinstall (docs/REINSTALL.md §0~§4)
# ---------------------------------------------------------------------------

[ -n "$DST" ] || { err "--dst는 필수다(기본값 없음) — 지정하지 않으면 설치하지 않는다."; exit 1; }

# §0 hard pre-checks — must run before ANY mutation (including backup),
# so an --src typo fails clean with the target tree untouched.
SKILL_SRC_DIR="$SRC/.claude/skills/delegate-first"
[ -f "$SKILL_SRC_DIR/SKILL.md" ] || { err "SRC 미설정/오경로: $SRC (SKILL.md 없음)"; exit 1; }
[ -d "$SKILL_SRC_DIR/references" ] || { err "SRC 미설정/오경로: $SRC (references/ 없음)"; exit 1; }
TIER_AGENTS=(explorer-low executor-med executor-high reviewer-high judge-max)
for agent in "${TIER_AGENTS[@]}"; do
  [ -f "$SRC/.claude/agents/$agent.md" ] || { err "SRC 미설정/오경로: $SRC (agents/$agent.md 없음)"; exit 1; }
done
[ -d "$DST/.claude" ] || {
  err "DST 미설정/오경로: $DST (.claude 없음). 신규 설치는 이 스크립트가 아니라 README.md §설치를 따른다."
  exit 1
}

# §0 advisory checks (informational only — never block; matches the doc's
# own framing that these interpret results rather than gate execution).
if [ -f "$GLOBAL_ROOT/.claude/settings.json" ] || [ -f "$DST/.claude/settings.json" ]; then
  if grep -qs "enforce-subagent-model" "$GLOBAL_ROOT/.claude/settings.json" "$DST/.claude/settings.json" 2>/dev/null; then
    log "정보: 훅 등록 흔적 확인됨(전역 또는 프로젝트 settings.json)"
  else
    log "정보: enforce-subagent-model 훅 등록을 settings.json에서 찾지 못했다 — §4-2 스모크 해석 시 참고할 것"
  fi
fi
if [ -d "$DST/.claude/agents" ]; then
  for agent in "${TIER_AGENTS[@]}"; do
    f="$DST/.claude/agents/$agent.md"
    if [ -f "$f" ] && ! grep -q '^model:' "$f"; then
      log "정보: $DST/.claude/agents/$agent.md 에 model: 핀이 없다(교체 후에는 정본판이 채워진다)"
    fi
  done
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
BAK="$BACKUP_ROOT/delegate-first-$STAMP"
DST_SKILL_DIR="$DST/.claude/skills/delegate-first"

log "=== 재설치 계획 ==="
log "SRC: $SRC"
log "DST: $DST"
log "백업 위치(예정): $BAK"
log "교체 대상: $DST_SKILL_DIR (통째로 스왑)"
log "교체 대상: $DST/.claude/agents/{${TIER_AGENTS[*]// /,}}.md"
if [ "$PROPAGATE_GLOBAL" -eq 1 ]; then
  log "전역 전파 대상: $HOOKS_TARGET_DIR/$HOOK_FILE_NAME, $RULES_TARGET_DIR/$RULE_FILE_NAME"
else
  log "전역 전파: 생략(--propagate-global 없음)"
fi

log "--- 정본이 제공하는 항목($SKILL_SRC_DIR 최상위 전체) ---"
PROVIDED_PREVIEW="$(list_top_level_names "$SKILL_SRC_DIR")"
if [ -n "$PROVIDED_PREVIEW" ]; then
  echo "$PROVIDED_PREVIEW" | sed 's/^/  - /'
else
  log "(없음 — SRC 스킬 디렉터리가 비어 있음)"
fi

log "--- 승계될 파일 목록(정본이 제공하지 않는 기존 DST 파일) ---"
SUCCESSION_PREVIEW="$(compute_succession_list "$DST_SKILL_DIR" "$SKILL_SRC_DIR")"
if [ -n "$SUCCESSION_PREVIEW" ]; then
  echo "$SUCCESSION_PREVIEW" | sed 's/^/  - /'
else
  log "(없음 — 기존 스킬 디렉터리가 없거나 정본 제공 이름만 있음)"
fi

log "--- diff 요약 (DST 기존 vs SRC 정본, 존재할 때만) ---"
if [ -d "$DST_SKILL_DIR" ]; then
  diff -rq "$DST_SKILL_DIR" "$SKILL_SRC_DIR" || true
else
  log "(DST에 기존 스킬 디렉터리 없음 — 최초 설치처럼 동작)"
fi
if [ -d "$DST/.claude/agents" ]; then
  diff -rq "$DST/.claude/agents" "$SRC/.claude/agents" 2>&1 | grep -E "^(Only|Files)" || log "(agents 디렉터리 diff 없음 또는 비교 대상 없음)"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  log "--dry-run: 위 계획만 출력했다. 아무 파일도 바뀌지 않았다."
  exit 0
fi

confirm

# --- §1 백업 ---
mkdir -p "$BAK"
if [ -d "$DST_SKILL_DIR" ]; then
  cp -R "$DST_SKILL_DIR" "$BAK/skills-delegate-first"
else
  log "백업 스킵: DST에 기존 스킬 디렉터리 없음"
fi
if [ -d "$DST/.claude/agents" ]; then
  cp -R "$DST/.claude/agents" "$BAK/agents"
else
  log "백업 스킵: DST에 기존 agents 디렉터리 없음"
fi
cp "$HOOKS_TARGET_DIR/$HOOK_FILE_NAME" "$BAK/" 2>/dev/null || log "백업 스킵: 전역 훅 소스 없음($HOOKS_TARGET_DIR/$HOOK_FILE_NAME)"
cp "$RULES_TARGET_DIR/$RULE_FILE_NAME" "$BAK/" 2>/dev/null || log "백업 스킵: 전역 규칙 소스 없음($RULES_TARGET_DIR/$RULE_FILE_NAME)"

BACKUP_FILE_COUNT="$(find "$BAK" -type f | wc -l | tr -d ' ')"
if [ -d "$DST_SKILL_DIR" ] && [ "$BACKUP_FILE_COUNT" -eq 0 ]; then
  err "백업이 비어 있다($BAK) — 기존 스킬 디렉터리가 있었는데 백업 내용이 0건. 중단한다."
  exit 1
fi
log "백업 완료: $BAK ($BACKUP_FILE_COUNT 파일)"

# --- §2/§3 교체: copy-to-temp-then-swap (docs/REINSTALL.md §3 그대로) ---
NEW="$DST_SKILL_DIR.new"
OLD="$DST_SKILL_DIR.old"

rm -rf "$NEW"
mkdir -p "$NEW"

# 정본 제공 — $SKILL_SRC_DIR 최상위 전체를 일반적으로 복사한다(이름 하드코딩
# 없음). 정본이 새 최상위 파일/디렉터리(예: CHANGELOG.md)를 얻으면 다음 실행부터
# 자동으로 $NEW에 포함된다. 복사 직후 각 항목 존재를 검증한다(아래 승계 루프와
# 동일한 강도) — 실패하면 스왑 전에 exit 1로 중단하고 원본 트리를 보존한다.
while IFS= read -r -d '' src_item; do
  base="$(basename "$src_item")"
  cp -R "$src_item" "$NEW/"
  if [ ! -e "$NEW/$base" ] && [ ! -L "$NEW/$base" ]; then
    err "정본 제공 실패: $base 가 cp 이후에도 $NEW 에 없다 — 스왑을 중단한다."
    err "원본 트리는 아직 살아 있다: $DST_SKILL_DIR"
    exit 1
  fi
done < <(find "$SKILL_SRC_DIR" -mindepth 1 -maxdepth 1 -print0)

if [ -d "$DST_SKILL_DIR" ]; then
  while IFS= read -r -d '' src_item; do
    base="$(basename "$src_item")"
    if [ -e "$NEW/$base" ]; then
      continue
    fi
    cp -R "$src_item" "$NEW/"
    if [ ! -e "$NEW/$base" ] && [ ! -L "$NEW/$base" ]; then
      err "승계 실패: $base 가 cp 이후에도 $NEW 에 없다 — 스왑을 중단한다."
      err "원본 트리는 아직 살아 있다: $DST_SKILL_DIR"
      exit 1
    fi
  done < <(find "$DST_SKILL_DIR" -mindepth 1 -maxdepth 1 -print0)
fi

# 재실행 가드: mv → .old 직후(= .old만 있고 delegate-first가 없음) 중단된 상태
if [ -e "$OLD" ] && [ ! -e "$DST_SKILL_DIR" ]; then
  err "중단된 재설치 감지: $OLD 는 있는데 $DST_SKILL_DIR 가 없다."
  err "이전 실행이 스왑 도중(mv 직후) 중단된 상태로 보인다 — $OLD 를 지우지 않고 중단한다."
  err "복구하려면: mv \"$OLD\" \"$DST_SKILL_DIR\" 로 되돌린 뒤 원인을 파악하고 처음부터 다시 실행하라."
  exit 1
fi

rm -rf "$OLD"
if [ -e "$DST_SKILL_DIR" ]; then
  mv "$DST_SKILL_DIR" "$OLD"
fi
mv "$NEW" "$DST_SKILL_DIR"
rm -rf "$OLD"
log "스킬 스왑 완료: $DST_SKILL_DIR"

# --- tier 에이전트 5종 ---
mkdir -p "$DST/.claude/agents"
for agent in "${TIER_AGENTS[@]}"; do
  cp "$SRC/.claude/agents/$agent.md" "$DST/.claude/agents/$agent.md"
done
log "tier 에이전트 5종 교체 완료"

# --- 전역 전파 (기본 비활성) ---
if [ "$PROPAGATE_GLOBAL" -eq 1 ]; then
  mkdir -p "$RULES_TARGET_DIR" "$HOOKS_TARGET_DIR"
  cp "$SRC/.claude/rules/$RULE_FILE_NAME" "$RULES_TARGET_DIR/$RULE_FILE_NAME"
  cp "$SRC/.claude/hooks/$HOOK_FILE_NAME" "$HOOKS_TARGET_DIR/$HOOK_FILE_NAME"
  log "전역 훅/규칙 전파 완료: $HOOKS_TARGET_DIR/$HOOK_FILE_NAME, $RULES_TARGET_DIR/$RULE_FILE_NAME"
else
  log "전역 훅/규칙 전파 생략(--propagate-global 없음) — $GLOBAL_ROOT/.claude 는 건드리지 않았다"
fi

# --- §4 검증: 스크립트가 헤드리스로 할 수 있는 것만 자동 확인 ---
log "=== 자동 검증 ==="
if diff -q "$DST_SKILL_DIR/SKILL.md" "$SKILL_SRC_DIR/SKILL.md" >/dev/null 2>&1; then
  log "OK: SKILL.md가 정본과 동일"
else
  err "경고: SKILL.md가 정본과 다르다 — 교체가 실패했을 수 있다"
fi
AGENT_MISMATCH=0
for agent in "${TIER_AGENTS[@]}"; do
  if ! diff -q "$DST/.claude/agents/$agent.md" "$SRC/.claude/agents/$agent.md" >/dev/null 2>&1; then
    err "경고: agents/$agent.md 가 정본과 다르다"
    AGENT_MISMATCH=1
  fi
done
[ "$AGENT_MISMATCH" -eq 0 ] && log "OK: tier 에이전트 5종 모두 정본과 동일"

LEFTOVER_REFS="$(grep -rln "delegating-execution" "$DST/.claude" 2>/dev/null || true)"
if [ -n "$LEFTOVER_REFS" ]; then
  err "경고: 구 명칭 'delegating-execution' 잔존 발견:"
  echo "$LEFTOVER_REFS" | sed 's/^/  - /' >&2
else
  log "OK: 구 명칭 'delegating-execution' 잔존 없음"
fi

log "=== 수동 확인 필요 (이 스크립트가 자동화할 수 없음 — 실행 중인 세션 필요) ==="
log "1. 대상 프로젝트 세션에서 /delegate-first 호출 → SKILL.md 로드 확인"
log "2. model 없이 Agent 즉석 호출 → 훅이 exit 2로 차단하는지 확인"
log "3. subagent_type: explorer-low 를 model 없이 호출 → haiku/low 적용 확인"
log "백업 위치(문제 생기면 --rollback \"$BAK\" --dst \"$DST\"): $BAK"
log "재설치 완료."
