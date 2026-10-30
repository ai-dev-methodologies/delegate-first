#!/usr/bin/env bash
# new-task.sh — create the delegate-first work directory for one task.
#
#   bash .claude/skills/delegate-first/scripts/new-task.sh <YYYYMMDD-kebab-slug>
#
# Run from inside the project's git repo. Creates
# <repo>/.delegate/<slug>/{TASK.md,REFS.md,PROGRESS.md,orders/,outputs/}
# from ../templates, filling the slug and TASK.md's base commit (HEAD).
# Blueprint: docs/blueprint/delegate-first-v2.md §3 (layout) and §6
# (tracking policy: only *suggest* the .gitignore line, never edit it).
#
# Exit: 0 created, 2 usage or structural error (nothing written).
# Must run on macOS stock bash 3.2 and BSD tools.

set -u

SLUG_RE='^[0-9]{8}-[a-z0-9]+(-[a-z0-9]+)*$'
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/../templates"

die() { echo "new-task: $*" >&2; exit 2; }

[ "$#" -eq 1 ] || die "사용법: new-task.sh <YYYYMMDD-kebab-slug>"
slug="$1"
printf '%s\n' "$slug" | grep -Eq "$SLUG_RE" || die "slug 형식 위반: '$slug' (기대 형식 $SLUG_RE)"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "git 저장소 안에서 실행해야 한다"
base="$(git -C "$root" rev-parse HEAD 2>/dev/null)" || die "기준 커밋(HEAD)을 읽지 못했다"
for f in TASK.md REFS.md PROGRESS.md; do
  [ -f "$TEMPLATES/$f" ] || die "템플릿 없음: $TEMPLATES/$f"
done

dir="$root/.delegate/$slug"
[ ! -e "$dir" ] || die "이미 있다: $dir (덮어쓰지 않는다)"

mkdir -p "$dir/orders" "$dir/outputs" || die "디렉터리를 만들지 못했다: $dir"
for f in TASK.md REFS.md PROGRESS.md; do
  LC_ALL=C sed \
    -e "s/<slug>/$slug/g" \
    -e "s/^<new-task.sh가 git rev-parse HEAD로 채운다>\$/$base/" \
    "$TEMPLATES/$f" > "$dir/$f" || die "템플릿 복사 실패: $f"
done

echo "생성: $dir"

# §6: no `delegate-workdir: track` line means ignore mode; suggest only.
if ! grep -Eq '^delegate-workdir:[[:space:]]*track[[:space:]]*$' "$root/CLAUDE.md" 2>/dev/null &&
   ! git -C "$root" check-ignore -q "$dir/TASK.md"; then
  echo "제안: .delegate/가 추적 대상이다. ignore 모드면 .gitignore에 '.delegate/' 한 줄을 더한다(이 스크립트는 .gitignore를 고치지 않는다)."
fi
exit 0
