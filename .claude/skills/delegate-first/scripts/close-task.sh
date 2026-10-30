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
#                    judge-max, decision D11) and that have a row in
#                    PROGRESS.md's 「회차」 table whose order cell equals the
#                    file-name stem and whose 반환 cell is not empty (main
#                    moves their returned message there; the tier line alone
#                    buys nothing; see progress_returned for what counts as
#                    the table and as empty); every output has an order.
#                    Limit: an executor-max order written as
#                    `- tier: reviewer-high` with such a row passes, since
#                    both pin opus·high.
#   - order-filename / output-filename: orders/ and outputs/ hold only
#                    NN-<name>.md files (dotfiles aside); anything else
#                    (.MD, .txt, broken symlinks, ...) fails instead of being
#                    skipped
#   - order-number:  each NN appears once
#   - order-section: 「발주 정보」 and the six fields exist as `## ` headings
#   - order-tier:    a `- tier: <tier>` line inside the first 「발주 정보」
#                    section naming one of the six tiers (code fences are
#                    not special)
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

# Calendar-invalid dates such as 20260230 pass: the slug is an identifier and
# never used for date arithmetic. Switch to a date(1) check if that changes.
SLUG_RE='^[0-9]{4}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])-[a-z0-9]+(-[a-z0-9]+)*$'
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

# progress_returned <stem> — PROGRESS.md's 「회차」 table (columns as in
# templates/PROGRESS.md: 회차 | order | 반환 | ...) has a row whose order
# cell is exactly <stem> and whose 반환 cell holds a letter. The section
# runs from `## 회차` (closing `#`s allowed) to the next `#`/`##` or setext
# (`---`/`===` under a text line that is not a list item) heading. These do
# not count: rows under a `###` or deeper subsection, lines inside ``` or
# ~~~ fences, lines indented 4+ columns, and lines inside an HTML comment (a
# `<!--` left open on a line runs to the next `-->`; one inside a backtick
# code span is literal). A 반환 cell holds a letter when, with comments
# removed, letters() finds one both with the stripped characters deleted
# and with them turned into spaces, so neither joining nor splitting words
# turns a placeholder into a value.
PH='대기
대기중
중
없음
미반환
미정
tbd
todo
n
a
na
pending
wip'
progress_returned() {
  [ -f "$dir/PROGRESS.md" ] &&
    STEM="$1" PH="$PH" LC_ALL=C awk '
      BEGIN { n = split(ENVIRON["PH"], p, "\n"); for (k = 1; k <= n; k++) PH[p[k]] = 1 }
      # uncomment <s> — <s> without closed comments; an open one cuts the
      # rest and sets incom. A backtick code span is copied as is; a run
      # with no closing run of the same length is literal.
      function uncomment(s,   i, j, n, out) {
        while (match(s, /<!--|`+/)) {
          if (substr(s, RSTART, 1) == "`") {
            n = RLENGTH; i = RSTART + n
            if ((j = span_end(substr(s, i), n))) i += j - 1
            out = out substr(s, 1, i - 1); s = substr(s, i)
            continue
          }
          out = out substr(s, 1, RSTART - 1); s = substr(s, RSTART + 4)
          if (!(j = index(s, "-->"))) { incom = 1; return out }
          s = substr(s, j + 3)
        }
        return out s
      }
      # span_end <r> <n> — position in <r> just past the first run of
      # exactly <n> backticks, or 0.
      function span_end(r, n,   k) {
        while (match(r, /`+/)) {
          if (RLENGTH == n) return k + RSTART + n
          k += RSTART + RLENGTH - 1; r = substr(r, RSTART + RLENGTH)
        }
        return 0
      }
      # letters <v> <sep> — 1 when a word other than a placeholder in PH
      # (case-insensitive) is left after tags, character references, the
      # marks *_`~, non-ASCII bytes outside Hangul syllables and ASCII
      # punctuation become <sep>. Letters are Hangul syllables
      # (U+AC00-U+D7A3, UTF-8 EA B0 80-ED 9E A3) and ASCII alphanumerics
      # only; any other script counts as no letter (known limit).
      function letters(v, sep,   out, n, w, i) {
        gsub(/<[^>]*>/, sep, v)
        gsub(/&[A-Za-z][A-Za-z0-9]*;|&#[0-9]+;|&#[xX][0-9A-Fa-f]+;/, sep, v)
        gsub(/[*_`~]/, sep, v)
        while (match(v, /[\200-\377]/)) {
          out = out substr(v, 1, RSTART - 1); v = substr(v, RSTART)
          if (match(v, /^(\352[\260-\277][\200-\277]|[\353\354][\200-\277][\200-\277]|\355[\200-\235][\200-\277]|\355\236[\200-\243])/)) {
            out = out substr(v, 1, 3); v = substr(v, 4)
          } else { out = out sep; v = substr(v, 2) }
        }
        v = tolower(out v)
        gsub(/[^a-z0-9 \t\200-\377]/, sep, v)
        n = split(v, w, " ")
        for (i = 1; i <= n; i++) if (!(w[i] in PH)) return 1
        return 0
      }
      function empty_cell(r) { return !letters(r, " ") || !letters(r, "") }
      { sub(/\r$/, ""); t = $0; sub(/^(   |  | )/, "", t) }  # up to 3 spaces of indent
      fn {
        if (substr(t, 1, 1) == fc && match(t, /^(`+|~+)[[:space:]]*$/) &&
            match(t, /^(`+|~+)/) && RLENGTH >= fn) fn = 0
        next
      }
      incom {
        if ((i = index($0, "-->")) > 0) { incom = 0; uncomment(substr($0, i + 3)) }
        para = 0; next
      }
      match(t, /^(```+|~~~+)/) { fc = substr(t, 1, 1); fn = RLENGTH; para = 0; next }
      t ~ /^<!--/ { uncomment(t); para = 0; next }  # HTML block: whole line
      { t = uncomment($0); sub(/^(   |  | )/, "", t) }
      t ~ /^[[:space:]]*$/ { para = 0; next }
      t ~ /^[ \t]/ { next }  # 4+ columns: code, or a paragraph continuation
      match(t, /^#+([[:space:]]|$)/) {
        if (match(t, /^#+/) && RLENGTH <= 2) {
          insec = (t ~ /^## 회차([[:space:]]+#+)?[[:space:]]*$/); insub = 0
        } else insub = 1
        para = 0; next
      }
      # para: 1 in a paragraph, 2 in a list item, where an underline is no
      # setext heading
      para == 1 && t ~ /^(=+|-+)[[:space:]]*$/ { insec = 0; para = 0; next }  # setext
      t ~ /^[-*_ \t]+$/ { para = 0; next }  # thematic break
      t !~ /^\|/ { para = (para == 2 || t ~ /^([-*+]|[0-9]+[.)])([ \t]|$)/) ? 2 : 1; next }
      {
        para = 0
        if (!insec || insub) next
        split(t, f, "|"); o = f[3]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", o)
        if (o == ENVIRON["STEM"] && !empty_cell(f[4])) { found = 1; exit }
      }
      END { exit !found }' "$dir/PROGRESS.md"
}

n_orders=0
seen_nums=""
for order in "$dir"/orders/*; do
  [ -e "$order" ] || [ -L "$order" ] || continue  # unmatched glob
  file="$(basename "$order")"
  if [ ! -e "$order" ]; then
    fail "order-filename $file 깨진 심볼릭 링크다"; continue
  fi
  case "$file" in
    *.md) ;;
    *) fail "order-filename $file 'NN-<name>.md' 형식이 아니다(.md 소문자 확장자만 인정)"; continue ;;
  esac
  n_orders=$((n_orders + 1))
  stem="${file%.md}"

  sec_ifs="$IFS"; IFS='|'
  for sec in $SECTIONS; do
    grep -Eq "^## $sec[[:space:]]*\$" "$order" || fail "order-section $file '## $sec' 없음"
  done
  IFS="$sec_ifs"

  tier="$(awk '/^## /{ if (insec) done = 1; insec = !done && ($0 ~ /^## 발주 정보[[:space:]]*$/) } insec' "$order" |
    sed -n 's/^- tier:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)"
  pin=""
  if [ -z "$tier" ]; then
    fail "order-tier $file '발주 정보' 절 안에 '- tier:' 줄 없음"
  else
    pin="$(tier_pin "$tier")"
    [ -n "$pin" ] || fail "order-tier $file 알 수 없는 tier '$tier'"
  fi

  name="$(printf '%s\n' "$file" | sed -n 's/^[0-9][0-9]-\(.*\)\.md$/\1/p')"
  if [ -z "$name" ]; then
    fail "order-filename $file 'NN-<name>.md' 형식이 아님"
    continue
  fi

  num="${file%%-*}"
  prev="$(printf '%s' "$seen_nums" | sed -n "s/^$num //p" | head -1)"
  if [ -n "$prev" ]; then
    fail "order-number $file 번호 '${num}'이 ${prev}와 중복"
  else
    seen_nums="$seen_nums$num $file
"
  fi

  if ! printf '%s\n' "$name" | grep -Eq "$NAME_RE"; then
    fail "name-format $file '$name'이 <작업>-<model>-<effort> 형식이 아님"
  elif [ -n "$pin" ]; then
    got="$(printf '%s\n' "$name" | sed -E 's/^.*-([a-z]+)-([a-z]+)$/\1 \2/')"
    [ "$got" = "$pin" ] || fail "name-pin $file 이름 토큰 '$got' != tier '$tier' 핀 '$pin'"
  fi

  if [ ! -f "$dir/outputs/$file" ]; then
    case "$tier" in
      explorer-low|reviewer-high|judge-max)
        progress_returned "$stem" || fail "pair $file 읽기 전용 tier는 반환물이 없으면 PROGRESS.md 회차 표에 order 칸 '$stem'·반환 칸이 채워진 행이 있어야 한다(결정 D11)" ;;
      *) fail "pair $file 반환물 outputs/$file 없음" ;;
    esac
  fi
done

[ "$n_orders" -gt 0 ] || fail "orders-empty $slug 발주문이 0건이다"

for output in "$dir"/outputs/*; do
  [ -e "$output" ] || [ -L "$output" ] || continue  # unmatched glob
  file="$(basename "$output")"
  if [ ! -e "$output" ]; then
    fail "output-filename $file 깨진 심볼릭 링크다"; continue
  fi
  case "$file" in
    *.md) ;;
    *) fail "output-filename $file '<발주문 이름>.md' 형식이 아니다(.md 소문자 확장자만 인정)"; continue ;;
  esac
  [ -f "$dir/orders/$file" ] || fail "pair $file 발주문 orders/$file 없음"
done

[ "$fails" -eq 0 ] || exit 1
echo "PASS close-task $slug (발주문 ${n_orders}건)"
exit 0
