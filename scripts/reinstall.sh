#!/usr/bin/env bash
# reinstall.sh — scripted implementation of docs/REINSTALL.md §0~§4.
#
# This script does not invent new policy. It executes the procedure that
# docs/REINSTALL.md already confirms (backup → diff → copy-to-temp-then-swap
# → tier agents → optional global propagation → verification reminders),
# with the same safety guards that document's §3 spells out (F1~F6 in
# BACKLOG B-13/B-14): guard SRC/DST before anything destructive, verify the
# backup is non-empty, verify succession copies actually landed before the
# swap, and detect an interrupted re-run instead of deleting the only
# recovery copy.
#
# One deliberate deviation from the manual doc, explicitly required by the
# task that produced this script (not invented here):
#   1. Global hook/rule propagation defaults OFF. Use --propagate-global to
#      do what docs/REINSTALL.md §3's last two `cp` lines do unconditionally.
# Everything else (skill swap, tier agent copy, backup layout, succession
# rules, interrupted-reinstall guard) matches the doc exactly.
#
# Recovery model: this script does not implement automated rollback. §1's
# backup is a plain safety copy for a human to consult if something looks
# wrong — it carries no restore contract. To actually recover, reinstall
# from the canonical repo at the commit you want (see docs/REINSTALL.md §5
# and README.md's recovery section): the things this script installs
# (skills, tier agents, hooks, rules) all live in that repo's git history,
# and the things it never touches (project-local custom files) are left
# alone by installing again, so there is nothing a bespoke restore step
# would recover that "reinstall from the desired commit" does not already
# cover.
#
# Usage:
#   reinstall.sh --dst <path> [--src <path>] [--dry-run] [--yes] [--propagate-global]
#
# REINSTALL_HOME env var (test-only override): when set, replaces $HOME as
# the root for backups (<root>/.claude-backups) and for global hook/rule
# paths (<root>/.claude/hooks, <root>/.claude/rules). Production runs never
# set this, so production behavior is exactly "$HOME". scripts/test-reinstall.sh
# uses it to sandbox every run inside a throwaway mktemp -d tree.
#
# REINSTALL_STAMP_OVERRIDE env var (test-only override, P2): when set,
# replaces the date+PID timestamp normally used for the backup directory
# name (delegate-first-<stamp>). Production runs never set this. It exists
# solely so scripts/test-reinstall.sh can force two invocations to compute
# the identical backup path and assert the collision is refused instead of
# silently nested (a real PID collision between two separate processes is
# not something a test can reliably force otherwise).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SRC="$(cd "$SCRIPT_DIR/.." && pwd)"
GLOBAL_ROOT="${REINSTALL_HOME:-$HOME}"

SRC=""
DST=""
DRY_RUN=0
ASSUME_YES=0
PROPAGATE_GLOBAL=0

log() { echo "[reinstall] $*"; }
err() { echo "[reinstall] $*" >&2; }

usage() {
  cat <<'EOF'
Usage:
  reinstall.sh --dst <path> [--src <path>] [--dry-run] [--yes] [--propagate-global]

  --src <path>          Canonical delegate-first repo root. Default: this
                         script's own repo root.
  --dst <path>          Target project to (re)install into. REQUIRED, no
                         default (installing into the wrong path is a
                         destructive mistake). The project directory itself
                         must already exist, but it does NOT need a
                         .claude/ tree yet — a brand-new project with no
                         .claude at all is a supported first-time install,
                         not just a re-install of an existing local copy.
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
  -h, --help            Show this help.

There is no --rollback flag. Recovery = reinstall from the canonical repo
at the commit you want (see docs/REINSTALL.md §5 / README.md): everything
this script installs already lives in that repo's git history, and it
never touches project-local files that aren't part of the install.

Examples:
  # 1. First look at the plan without changing anything:
  reinstall.sh --src /path/to/delegate-first --dst /path/to/your-project --dry-run

  # 2. Actually install (prompts for confirmation unless --yes):
  reinstall.sh --src /path/to/delegate-first --dst /path/to/your-project --yes

  # 3. Something went wrong — recover by reinstalling from the canonical
  #    repo at whatever commit you want (see docs/REINSTALL.md §5):
  git -C /path/to/delegate-first checkout <commit>
  reinstall.sh --src /path/to/delegate-first --dst /path/to/your-project --yes
  git -C /path/to/delegate-first checkout main
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --src) SRC="${2:?--src requires a path}"; shift 2 ;;
    --dst) DST="${2:?--dst requires a path}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    --propagate-global) PROPAGATE_GLOBAL=1; shift ;;
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
# Declared here (before §0's pre-checks below, which are the first thing
# that needs it) so every later step — pre-checks, plan output, swap,
# tier-agent copy, verification — shares one definition.
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
# Reinstall (docs/REINSTALL.md §0~§4)
# ---------------------------------------------------------------------------

[ -n "$DST" ] || { err "--dst는 필수다(기본값 없음) — 지정하지 않으면 설치하지 않는다."; exit 1; }

# §0 hard pre-checks — must run before ANY mutation (including backup),
# so an --src typo fails clean with the target tree untouched.
SKILL_SRC_DIR="$SRC/.claude/skills/delegate-first"
[ -f "$SKILL_SRC_DIR/SKILL.md" ] || { err "SRC 미설정/오경로: $SRC (SKILL.md 없음)"; exit 1; }
[ -d "$SKILL_SRC_DIR/references" ] || { err "SRC 미설정/오경로: $SRC (references/ 없음)"; exit 1; }
for agent in "${TIER_AGENTS[@]}"; do
  [ -f "$SRC/.claude/agents/$agent.md" ] || { err "SRC 미설정/오경로: $SRC (agents/$agent.md 없음)"; exit 1; }
done
# NEW_INSTALL: $DST/.claude가 아예 없으면 "완전히 새 프로젝트에 처음 설치"로
# 취급한다 — 예전에는 여기서 무조건 거부하고 README.md §설치(수동 cp)로
# 떠넘겼지만, 그 경로는 실행 검증 이력이 없었고 배포(다른 레포로 확산)
# 직전 첫 채택자가 반드시 거치는 경로다. $DST 자신은 여전히 실존을 요구한다
# (오타로 존재하지 않는 경로에 mkdir -p로 새 트리를 만들어버리면 "잘못된
# 경로에 설치"를 감지할 방법이 없어진다 — 그건 신규 설치 지원이 아니라
# 안전장치 제거다). 아래 §1~§3은 이미 $DST/.claude/skills, .../agents가
# 없는 경우를 mkdir -p로 다루므로(백업 스킵 로그 + $NEW 생성이 상위
# 디렉터리까지 만듦) 이 지점 이후 추가 분기가 필요 없다.
[ -d "$DST" ] || {
  err "DST 미설정/오경로: $DST (디렉터리 자체가 없다). 대상 프로젝트 디렉터리를 먼저 만든 뒤 다시 실행하라."
  exit 1
}
if [ ! -d "$DST/.claude" ]; then
  log "정보: $DST/.claude 없음 — 신규 설치로 진행한다(빈 프로젝트에 새로 설치)"
  # 여기서 mkdir하지 않는다 — --dry-run은 "아무것도 쓰지 않는다"는 계약이라,
  # 계획 출력 단계(§0 나머지)에서 디렉터리를 실제로 만들면 그 계약이 깨진다.
  # 아래 §1~§3은 존재하지 않는 디렉터리를 이미 안전하게 다룬다: 백업은
  # `[ -d ]` 가드로 스킵되고, $NEW 생성의 `mkdir -p "$NEW"`와 tier 에이전트
  # 단계의 `mkdir -p "$DST/.claude/agents"`가 필요한 상위 디렉터리를 실제
  # 실행(비-dry-run) 시점에 만든다.
fi

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
# F3-GUARD-START
else
  # F-3: settings.json이 전역/프로젝트 어디에도 없는 완전 신규 머신에서는
  # 위 두 분기 모두 스킵되어 훅 등록에 대한 언급이 한 줄도 나오지 않는다
  # — "재설치 완료" 로그와 함께 강제(PreToolUse 차단)가 발효되지 않은
  # 반쪽 설치가 조용히 끝난다. README.md §설치와 동일한 사실을 여기서도
  # 명시적으로 경고한다.
  log "경고: settings.json을 전역($GLOBAL_ROOT/.claude/settings.json)/프로젝트($DST/.claude/settings.json) 어디서도 찾지 못했다 — 이 스크립트는 skills + tier 에이전트만 설치하며 훅 파일도 settings.json 등록도 하지 않는다. README.md §설치의 '훅을 별도로 등록한다' 단계를 수행하지 않으면 강제(PreToolUse 차단)가 발효되지 않은 반쪽 설치로 남는다."
# F3-GUARD-END
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

# P3-GUARD-START
# P3: 대상 경로가 존재하는데 디렉터리도 심볼릭 링크(위 C6)도 아닌 일반
# 파일(또는 다른 타입)이면, §1 백업 단계의 `[ -d ]` 검사가 이를 "기존
# 스킬 디렉터리 없음"으로 오판해 백업 없이 스왑을 진행한다 — 그런데
# §2/§3의 스왑은 `[ -e ]` 기준으로 mv하므로 이 파일을 여전히 .old로
# 옮겼다가 스왑 성공 후 무경고로 영구 삭제한다(실측: 백업 없음, rc=0,
# 허위 "재설치 완료" 로그까지 남는다). 파괴적 단계 전에 거부한다.
if [ -e "$DST_SKILL_DIR" ] && [ ! -d "$DST_SKILL_DIR" ]; then
  err "거부(P3): $DST_SKILL_DIR 가 디렉터리가 아닌 일반 파일(또는 다른 타입)이다."
  err "이 상태로 진행하면 백업 없이 스왑이 진행돼 이 파일이 영구 소실된다."
  err "해당 경로를 확인하고 처리(이동/삭제)한 뒤 다시 실행하라."
  exit 1
fi
# P3-GUARD-END

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
log "백업 완료: $BAK ($BACKUP_FILE_COUNT 파일) — 자동 복원 대상이 아니라, 필요하면 사람이 직접 참고할 사본이다."

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
log "백업 위치(참고용 사본, 자동 복원 없음): $BAK"
log "문제가 생기면: 정본 레포를 원하는 커밋으로 checkout한 뒤 이 스크립트를 다시 실행하라(docs/REINSTALL.md §5 참고)."
log "재설치 완료."
