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
#
# REINSTALL_STAMP_OVERRIDE env var (test-only override, P2): when set,
# replaces the date+PID timestamp normally used for backup directory names
# (delegate-first-<stamp>, pre-rollback-<stamp>). Production runs never set
# this. It exists solely so scripts/test-reinstall.sh can force two
# invocations to compute the identical backup path and assert the
# collision is refused instead of silently nested (a real PID collision
# between two separate processes is not something a test can reliably
# force otherwise).

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
# Moved above do_rollback (was previously declared further down, after the
# rollback dispatch call at the bottom of this file) — do_rollback's F-3 fix
# needs this list to know which agent files a reinstall could have planted,
# and a bash array referenced before its own assignment would silently be
# empty rather than error, so the ordering matters.
TIER_AGENTS=(explorer-low executor-med executor-high reviewer-high judge-max)

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

# Resolve a path to an absolute, symlink-free form. Only ever called on
# paths that already exist (realpath on this platform errors on missing
# paths), so callers must check existence first.
resolve_path() {
  realpath "$1"
}

do_rollback() {
  [ -n "$DST" ] || { err "--rollback에는 --dst도 필요하다 — 복원 대상이 없다."; exit 1; }
  [ -d "$ROLLBACK_DIR/skills-delegate-first" ] || {
    err "백업 없음: $ROLLBACK_DIR — 경로가 §1이 실제로 백업을 만든 그 디렉터리인지 확인하라."
    exit 1
  }
  # P4: 디렉터리만 있고 내용이 비어 있는(또는 아무 백업이나 가리키는) 경로를
  # 백업으로 오인하지 않도록, §1이 항상 만드는 SKILL.md의 존재까지 확인한다.
  [ -f "$ROLLBACK_DIR/skills-delegate-first/SKILL.md" ] || {
    err "백업 불완전: $ROLLBACK_DIR/skills-delegate-first 에 SKILL.md가 없다 — 이 디렉터리는 §1이 만든 진짜 백업이 아닐 수 있다."
    exit 1
  }

  # F-4: --rollback 디렉터리가 복원 대상(스킬 디렉터리)이나 스왑 스크래치
  # 경로(.new/.old) 내부이거나 그 자신이면, 아래 "잔여 .new/.old 정리"·
  # "스킬 디렉터리 복원"의 rm -rf가 백업까지 먼저 삼켜 live+백업 동시
  # 소실로 이어진다 — 파괴 전에 거부한다. .new/.old도 같은 rm -rf 대상이라
  # 본체(SKILL_TARGET_DIR)만 보면 백업이 그 아래 있을 때 못 잡는다.
  SKILL_TARGET_DIR="$DST/.claude/skills/delegate-first"
  NEW="$SKILL_TARGET_DIR.new"
  OLD="$SKILL_TARGET_DIR.old"
  RESOLVED_ROLLBACK_DIR="$(resolve_path "$ROLLBACK_DIR")"
  for GUARD_PATH in "$SKILL_TARGET_DIR" "$NEW" "$OLD"; do
    [ -d "$GUARD_PATH" ] || continue
    RESOLVED_GUARD_PATH="$(resolve_path "$GUARD_PATH")"
    case "$RESOLVED_ROLLBACK_DIR" in
      "$RESOLVED_GUARD_PATH"|"$RESOLVED_GUARD_PATH"/*)
        err "거부(F-4): --rollback 디렉터리($ROLLBACK_DIR)가 복원/정리 대상($GUARD_PATH) 내부(또는 그 자신)다."
        err "이 상태로 진행하면 복원 단계의 rm -rf가 백업 자체를 먼저 지워 live 트리와 백업이 동시에 사라진다."
        err "백업을 스킬 디렉터리(및 .new/.old) 바깥으로 옮긴 뒤 다시 실행하라."
        exit 1
        ;;
    esac
  done

  # P4: 설치 경로(§2/§3)에는 "중단된 재설치 감지" 가드가 있는데 롤백에는
  # 없었다 — .old만 있고 live 디렉터리가 없는(직전 실행이 mv 직후 중단된)
  # 상태에서 롤백을 돌리면 아래 "잔여 정리" 단계가 유일한 회복 사본인
  # .old를 그대로 지운다. 같은 가드를 여기도 건다.
  if [ -e "$DST/.claude/skills/delegate-first.old" ] && [ ! -e "$SKILL_TARGET_DIR" ]; then
    err "중단된 재설치 감지: $DST/.claude/skills/delegate-first.old 는 있는데 $SKILL_TARGET_DIR 가 없다."
    err "이전 재설치가 스왑 도중(mv 직후) 중단된 상태로 보인다 — 이 상태로 롤백을 실행하면 아래 '잔여 정리' 단계가 유일한 회복 사본(.old)을 지운다."
    err "먼저 mv \"$DST/.claude/skills/delegate-first.old\" \"$SKILL_TARGET_DIR\" 로 되돌리고 원인을 파악한 뒤 다시 실행하라."
    exit 1
  fi

  log "=== 롤백 계획 ==="
  log "복원 소스: $ROLLBACK_DIR"
  log "대상 스킬 디렉터리: $SKILL_TARGET_DIR (통째로 교체됨)"
  if [ -d "$ROLLBACK_DIR/agents" ]; then
    log "대상 에이전트: $DST/.claude/agents (tier 5종만 백업 내용으로 교체 복원 — F-3, 아래 참고)"
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

  # P4: 파괴적 단계 직전에 현재(롤백 전) 트리를 별도로 스냅샷한다 — 롤백
  # 자체가 잘못됐을 때(예: 잘못된 백업 디렉터리를 가리켰을 때) 되돌릴 수
  # 있는 마지막 수단. P2와 동일하게 PID를 붙여 같은 초 내 중복 실행과의
  # 충돌을 피하고, mkdir(디렉터리 없을 때만 성공)로 충돌 시 조용히 넘어가지
  # 않게 한다.
  PRE_ROLLBACK_STAMP="${REINSTALL_STAMP_OVERRIDE:-$(date +%Y%m%d-%H%M%S)-$$}"
  PRE_ROLLBACK_DIR="$BACKUP_ROOT/pre-rollback-$PRE_ROLLBACK_STAMP"
  mkdir -p "$BACKUP_ROOT"
  MKDIR_ERR="$(mkdir "$PRE_ROLLBACK_DIR" 2>&1)"
  if [ $? -ne 0 ]; then
    if [ -e "$PRE_ROLLBACK_DIR" ]; then
      err "스냅샷 디렉터리 충돌: $PRE_ROLLBACK_DIR 가 이미 존재한다 — 중단한다(다시 실행하라)."
    else
      err "스냅샷 디렉터리 생성 실패: $PRE_ROLLBACK_DIR ($MKDIR_ERR)"
    fi
    exit 1
  fi
  if [ -d "$SKILL_TARGET_DIR" ]; then
    cp -R "$SKILL_TARGET_DIR" "$PRE_ROLLBACK_DIR/skills-delegate-first"
  fi
  if [ -d "$DST/.claude/agents" ]; then
    cp -R "$DST/.claude/agents" "$PRE_ROLLBACK_DIR/agents"
  fi
  log "롤백 직전 스냅샷 저장: $PRE_ROLLBACK_DIR (문제 생기면 --rollback \"$PRE_ROLLBACK_DIR\" --dst \"$DST\")"

  log "잔여 .new/.old 정리"
  rm -rf "$DST/.claude/skills/delegate-first.new" "$DST/.claude/skills/delegate-first.old"

  log "스킬 디렉터리 복원"
  mkdir -p "$DST/.claude/skills"
  rm -rf "$SKILL_TARGET_DIR"
  cp -R "$ROLLBACK_DIR/skills-delegate-first" "$SKILL_TARGET_DIR"

  if [ -d "$ROLLBACK_DIR/agents" ]; then
    log "에이전트 복원 (F-3: overlay가 아니라 교체 복원)"
    mkdir -p "$DST/.claude/agents"
    # F-3: 단순 overlay(cp -R backup/. dst/)는 재설치가 새로 심은 tier
    # 정의를 백업에 없다는 이유만으로는 지우지 않는다 — 백업 시점 이후
    # 새로 생긴 tier 파일이 롤백 후에도 잔존한다(실측). 그렇다고 dst의
    # agents/ 전체를 지우면 사용자가 별도로 둔(재설치와 무관한) 에이전트
    # 정의까지 날아간다. 그래서 재설치가 실제로 건드리는 대상인 tier
    # 5종(TIER_AGENTS)만 먼저 지우고, 백업 내용으로 다시 채운다 — 백업에
    # 그 tier 파일이 없었다면(예: 최초 설치 전이라 아직 없던 tier) 지운
    # 채로 남아 백업 시점 상태와 정확히 일치한다.
    for agent in "${TIER_AGENTS[@]}"; do
      rm -f "$DST/.claude/agents/$agent.md"
    done
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
# TIER_AGENTS is declared near the top of the file (before do_rollback) now.
for agent in "${TIER_AGENTS[@]}"; do
  [ -f "$SRC/.claude/agents/$agent.md" ] || { err "SRC 미설정/오경로: $SRC (agents/$agent.md 없음)"; exit 1; }
done
[ -d "$DST/.claude" ] || {
  err "DST 미설정/오경로: $DST (.claude 없음). 신규 설치는 이 스크립트가 아니라 README.md §설치를 따른다."
  exit 1
}

# C-1: --src와 --dst가 같은 경로면, 아래 §2/§3의 copy-to-temp-then-swap이
# 정본 스킬 디렉터리 자신을 대상으로 백업→스왑을 수행하게 된다 — 이 경우
# agents cp 단계에서 실패해도(cp가 자기 자신을 자기 자신에 복사하려다
# rc=1) 이미 스왑은 절반 진행된 뒤라 내용은 무손상이어도 상태가 애매해진다.
# 파괴적 단계 전에 명시적으로 거부한다.
RESOLVED_SRC="$(cd "$SRC" && pwd -P)"
RESOLVED_DST="$(cd "$DST" && pwd -P)"
if [ "$RESOLVED_SRC" = "$RESOLVED_DST" ]; then
  err "거부(C-1): --src와 --dst가 동일 경로($DST)다 — 자기 자신에 재설치할 수 없다."
  exit 1
fi

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

# P2: 초 단위 STAMP만 쓰면 같은 초 안의 두 실행이 같은 $BAK를 공유해
# 두 번째 실행의 백업이 첫 번째 백업 디렉터리 안에 중첩된다(실측). PID($$)를
# 붙여 동시 실행 간 충돌 확률을 낮추고, 그래도 충돌하면(극히 드묾) 아래
# mkdir(디렉터리가 이미 있으면 실패)이 mkdir -p처럼 조용히 넘어가지 않고
# 즉시 에러로 표면화한다.
STAMP="${REINSTALL_STAMP_OVERRIDE:-$(date +%Y%m%d-%H%M%S)-$$}"
BAK="$BACKUP_ROOT/delegate-first-$STAMP"
DST_SKILL_DIR="$DST/.claude/skills/delegate-first"

# C6: $DST_SKILL_DIR가 심볼릭 링크면 `[ -d ]`는 링크를 따라가 통과시키지만,
# 아래 승계 계산(compute_succession_list)과 §2/§3의 $NEW 구성이 쓰는
# `find`는 시작 경로 자체가 링크일 때 그 내용을 따라가지 않는다(플랫폼별로
# 다르지만 이 레포에서는 실측상 승계가 조용히 0건이 된다) — 그 상태로
# 스왑까지 진행하면 링크가 실제 디렉터리로 대체되어 원래 링크 대상이
# 고아가 된다. 파괴적 단계 전에 감지해 거부한다(명시적 처리 대신 거부를
# 택한 이유: 링크가 가리키는 실제 위치를 자동으로 판단해 안전하게 승계할
# 방법이 없고, 사용자가 링크를 해제하고 다시 실행하는 편이 명확하다).
if [ -L "$DST_SKILL_DIR" ]; then
  err "거부(C6): $DST_SKILL_DIR 가 심볼릭 링크다."
  err "이 상태로 진행하면 find가 링크를 따라가지 않아 기존 파일 승계가 조용히 0건이 되고, 스왑 후 링크가 실제 디렉터리로 대체돼 원래 링크 대상이 고아가 될 수 있다."
  err "링크를 해제(rm)하고 실제 디렉터리로 옮긴 뒤 다시 실행하라."
  exit 1
fi

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
# P2: mkdir -p는 디렉터리가 이미 있어도 조용히 성공한다 — 그 경우 이번
# 백업이 기존 내용 위에 겹쳐써질 수 있다. 여기서는 STAMP에 PID를 붙였으니
# $BAK가 이미 존재한다는 것은 (동시 실행이 아니라) 뭔가 이상하다는 신호이므로
# plain mkdir로 그 경우를 에러로 표면화한다.
mkdir -p "$BACKUP_ROOT"
if ! mkdir "$BAK" 2>/dev/null; then
  err "백업 디렉터리 충돌: $BAK 가 이미 존재한다 — 중단한다(다시 실행하라)."
  exit 1
fi
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
