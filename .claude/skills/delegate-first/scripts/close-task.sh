#!/usr/bin/env bash
# close-task.sh — end-of-task checks for a delegate-first work directory.
#
#   bash .claude/skills/delegate-first/scripts/close-task.sh <YYYYMMDD-kebab-slug>
#
# Run from inside the project's git repo. Reads .delegate/<slug>/orders/ and
# outputs/ and never writes. Blueprint: docs/blueprint/delegate-first-v2.md
# §7 「close-task.sh」. Skeleton scope (decision D8) — the checks that left
# the hook or were never put in it:
#   - pair:          every order has outputs/<same file name>, except orders
#                    whose tier is read-only (explorer-low·reviewer-high·
#                    judge-max, decision D11); every output has an order
#   - order-section: 「발주 정보」 and the six fields exist as `## ` headings
#   - order-tier:    a `- tier: <tier>` line naming one of the six tiers
#   - name-format / name-pin: the <name> in NN-<name>.md is
#                    <작업>-<model>-<effort> and both tokens equal the tier's
#                    frontmatter pin (B-18, moved out of the hook)
#   - orders-empty:  a task dir exists only for delegated work, so zero
#                    orders fails rather than passing vacuously
# Write-scope, ID-set, promote, review-trigger, attempt-counter checks and
# --dry-run are later blueprint steps (§9 P5), not handled here.
#
# Output: one `FAIL <check> <detail>` line per failure.
# Exit: 0 pass, 1 one or more checks failed, 2 usage or structural error.
# Must run on macOS stock bash 3.2 and BSD tools.

set -u

SLUG_RE='^[0-9]{8}-[a-z0-9]+(-[a-z0-9]+)*$'
NAME_RE='^[a-z0-9]+(-[a-z0-9]+)*-(haiku|sonnet|opus|fable)-(low|medium|high|xhigh|max)$'
SECTIONS="발주 정보|목표|입력|유효 결정|쓰기 범위|금지|완료 증거"

die() { echo "close-task: $*" >&2; exit 2; }

# tier_pin <tier> — prints "<model> <effort>" from the tier frontmatter pins
# (.claude/agents/<tier>.md); scripts/test-delegate-scripts.sh locks this
# table against those files. Empty output means unknown tier.
tier_pin() {
  case "$1" in
    explorer-low)  echo "haiku low" ;;
    executor-med)  echo "sonnet medium" ;;
    executor-high) echo "sonnet high" ;;
    executor-max)  echo "opus high" ;;
    reviewer-high) echo "opus high" ;;
    judge-max)     echo "fable max" ;;
  esac
}

[ "$#" -eq 1 ] || die "사용법: close-task.sh <YYYYMMDD-kebab-slug>"
slug="$1"
printf '%s\n' "$slug" | grep -Eq "$SLUG_RE" || die "slug 형식 위반: '$slug'"

root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "git 저장소 안에서 실행해야 한다"
dir="$root/.delegate/$slug"
[ -d "$dir" ] || die "작업 디렉터리 없음: $dir"
[ -d "$dir/orders" ] || die "orders/ 없음: $dir/orders"

fails=0
fail() { echo "FAIL $*"; fails=$((fails + 1)); }

n_orders=0
for order in "$dir"/orders/*.md; do
  [ -e "$order" ] || continue
  n_orders=$((n_orders + 1))
  file="$(basename "$order")"

  sec_ifs="$IFS"; IFS='|'
  for sec in $SECTIONS; do
    grep -Eq "^## $sec[[:space:]]*\$" "$order" || fail "order-section $file '## $sec' 없음"
  done
  IFS="$sec_ifs"

  tier="$(sed -n 's/^- tier:[[:space:]]*\([^[:space:]]*\).*/\1/p' "$order" | head -1)"
  pin=""
  if [ -z "$tier" ]; then
    fail "order-tier $file '- tier:' 줄 없음"
  else
    pin="$(tier_pin "$tier")"
    [ -n "$pin" ] || fail "order-tier $file 알 수 없는 tier '$tier'"
  fi

  name="$(printf '%s\n' "$file" | sed -n 's/^[0-9][0-9]-\(.*\)\.md$/\1/p')"
  if [ -z "$name" ]; then
    fail "order-filename $file 'NN-<name>.md' 형식이 아님"
    continue
  fi

  if ! printf '%s\n' "$name" | grep -Eq "$NAME_RE"; then
    fail "name-format $file '$name'이 <작업>-<model>-<effort> 형식이 아님"
  elif [ -n "$pin" ]; then
    got="$(printf '%s\n' "$name" | sed -E 's/^.*-([a-z]+)-([a-z]+)$/\1 \2/')"
    [ "$got" = "$pin" ] || fail "name-pin $file 이름 토큰 '$got' != tier '$tier' 핀 '$pin'"
  fi

  case "$tier" in
    explorer-low|reviewer-high|judge-max) ;;
    *) [ -f "$dir/outputs/$file" ] || fail "pair $file 반환물 outputs/$file 없음" ;;
  esac
done

[ "$n_orders" -gt 0 ] || fail "orders-empty $slug 발주문이 0건이다"

for output in "$dir"/outputs/*.md; do
  [ -e "$output" ] || continue
  file="$(basename "$output")"
  [ -f "$dir/orders/$file" ] || fail "pair $file 발주문 orders/$file 없음"
done

[ "$fails" -eq 0 ] || exit 1
echo "PASS close-task $slug (발주문 ${n_orders}건)"
exit 0
