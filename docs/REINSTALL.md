# REINSTALL — 정본 레포 → 프로젝트 로컬 재설치 절차 (초안)

이 문서는 **완성된 정본 레포 버전**을 이미 로컬 사본이 돌아가고 있는 프로젝트(최초 대상: `goone-rest`)에 덮어 설치하는 절차다.

> **실행 승인 게이트**: 이 절차는 **사용자 명시 승인 후에만** 실행한다. 대상 프로젝트의 로컬 스킬은 **의도적으로 git 추적 밖(untracked)** 이라 되돌릴 git 히스토리가 없다 — 백업(1단계)을 건너뛰면 복구 수단이 없다.

---

## 0. 사전 확인

변수 (아래 표의 확인 명령이 `$DST`를 참조하므로 표보다 먼저 정의한다):

```bash
SRC="/PATH/TO/delegate-first"     # ← 반드시 실제 경로로 교체 (예: .../workspace/delegate-first)
DST="/Users/plletdata/dev/goone-rest"
STAMP=$(date +%Y%m%d-%H%M%S)
BAK="$HOME/.claude-backups/delegate-first-$STAMP"
```

| 항목 | 확인 방법 | 기대값 |
|---|---|---|
| 정본 PR 머지 완료 | `git -C <정본레포> log --oneline -1 main` | 이관 PR이 main에 있음 |
| 대상 프로젝트 경로 | — | `/Users/plletdata/dev/goone-rest` |
| 로컬 사본 존재 | `ls <대상>/.claude/skills/delegate-first` | SKILL.md, references/, HANDOFF.md, NEW-REPO-PROMPT.md |
| 훅 위치 | `ls ~/.claude/hooks/enforce-subagent-model.cjs` | 존재(전역 설치) |
| 훅 등록 위치 | `grep -n "enforce-subagent-model" ~/.claude/settings.json "$DST/.claude/settings.json" 2>/dev/null` | 전역(`~/.claude/settings.json`)에 등록돼 있으면 전역 유지 / 대상 프로젝트 `.claude/settings.json`으로 전환하려면 그쪽에 등록 — 둘 다 없으면 §4의 2번(훅 차단 스모크)이 실패한다. 이 표의 판정이 §4-2번의 전제다. |

## 1. 백업 (건너뛰기 금지)

백업은 대상 프로젝트 워킹트리 **밖**(`$HOME/.claude-backups/`)에 둔다. 대상 레포의 `.git/info/exclude`가 `.claude/skills/`·`.claude/agents/`만 덮고 워킹트리 안의 다른 경로는 덮지 않는 경우, 백업을 `$DST/.claude/` 아래 두면 untracked 상태로 노출되어 다음 `git add -A`에 그대로 커밋된다 — "스킬은 의도적으로 git 추적 밖"이라는 전제를 백업 자신이 깨뜨리게 된다(2026-08-18 goone-rest 실측: `git check-ignore --no-index`로 NOT IGNORED 확인).

```bash
mkdir -p "$BAK"
cp -R "$DST/.claude/skills/delegate-first" "$BAK/skills-delegate-first"
cp -R "$DST/.claude/agents"               "$BAK/agents"
cp "$HOME/.claude/hooks/enforce-subagent-model.cjs" "$BAK/" 2>/dev/null  # 없으면 스킵됨(정상) — 단 §5 주의사항 참조
cp "$HOME/.claude/rules/subagent-model-routing.md"  "$BAK/" 2>/dev/null  # 없으면 스킵됨(정상) — 단 §5 주의사항 참조
```

백업 디렉터리가 실제로 채워졌는지 눈으로 확인한다(`find "$BAK" -type f`). 0바이트·빈 디렉터리를 "존재=정상"으로 넘기지 않는다.

## 2. 교체 전 diff 확인 (덮어쓰기 전에 무엇이 바뀌는지 본다)

```bash
diff -ru "$DST/.claude/skills/delegate-first" "$SRC/.claude/skills/delegate-first" | head -100
diff -ru "$DST/.claude/agents" "$SRC/.claude/agents"
diff -u "$HOME/.claude/hooks/enforce-subagent-model.cjs" "$SRC/.claude/hooks/enforce-subagent-model.cjs"
diff -u "$HOME/.claude/rules/subagent-model-routing.md"  "$SRC/.claude/rules/subagent-model-routing.md"
```

**예상 diff는 2파일·아래 5개 논리 변경이다**(SKILL.md 1 + prompt-templates.md 4) (정본 이관 시 적용한 종속 치환). 여기 열거한 5군데는 **논리 단위**이고, `diff -ru`가 보여주는 **hunk 개수**는 인접 변경이 하나로 병합되는지에 따라 달라질 수 있다 — 실측으로는 4 hunk + `Only in` 표시 2줄로 나타난다. hunk 수를 세지 말고 각 hunk의 **내용**을 아래 5개와 대조한다:

1. `SKILL.md` 3단계 — 위임 로그 경로가 하드코딩에서 **프로젝트 파라미터 문구**로 바뀜. 기본값은 `docs/handoff/delegation-log.md`로 동일하므로 goone-rest는 동작 변화 없음.
2. `references/prompt-templates.md` §Contents 행 — `- Real examples from this project` → `- Worked examples (generic — replace with your own project's cases)`.
3. `references/prompt-templates.md` Template 1 역할 placeholder의 goone 언급 제거.
4. `references/prompt-templates.md` Template 1 "실제 예시" 블록이 **중립 예시**로 교체됨(goone 절대경로·ADR 번호·워크트리명 제거).
5. `references/prompt-templates.md` Template 2 "실제 예시" 블록도 동일하게 중립 예시로 교체됨.

출력에 위 5개 논리 변경 **외의 내용**이 보이면 (hunk 수가 몇 개든) **멈추고** 무엇이 다른지 먼저 파악한다.

에이전트 5종·훅은 **byte-identical**이라 diff가 비어야 한다. 비어 있지 않으면 로컬이 정본보다 앞서 있다는 뜻 — **덮어쓰기 전에 멈추고** 로컬 변경을 정본으로 역포팅한다.

규칙 파일(`subagent-model-routing.md`)은 판정이 다르다 — 정본에서 라우팅 규칙을 고치면 diff가 발생하는 것이 **정상**이다. 이때는 "로컬이 앞서 있다"가 아니라 "**정본이 앞서 있다**"는 뜻이므로 멈추지 말고 §3의 cp로 전파한다. (역포팅 케이스와 헷갈리면 `git -C <정본레포> log -p -- .claude/rules/subagent-model-routing.md`로 정본 쪽 최근 변경 이력을 먼저 확인한다 — 로컬을 직접 고친 기억이 없는데 diff가 있다면 정본 갱신이다.)

> **결정 필요 (치환 #2)**: goone-rest의 프롬프트 템플릿에서 실제 goone 예시가 사라진다. 실무에서 그 예시가 유용하면 (a) 백업본에서 예시 블록만 goone 로컬로 되살리거나 (b) goone-rest의 자체 문서(`docs/handoff/`)에 프로젝트 예시집으로 옮긴다. 사용자 선택 사항이며 재설치 전에 확정한다.

## 3. 교체

`$SRC`가 미설정이거나 오경로인 채로 아래 블록만 실행하면, 종전에는 `rm -rf`가 `$SRC` 유효성 검사보다 먼저 실행돼 live `references/`를 지운 뒤 `cp`가 전부 실패해 스킬이 파손되는 사고가 가능했다. 그래서 ①선두에 `set -euo pipefail`로 중간 실패 시 즉시 중단 ②delete 전에 `$SRC`/`$DST` 존재를 가드로 확인 ③delete-then-copy 대신 **copy-to-temp-then-swap**(새 트리를 인접 임시 경로에 먼저 완성 → 기존을 `.old`로 옮기고 새 것을 제자리에 놓은 뒤 `.old` 삭제)으로 바꿨다. 이 순서면 중간에 어디서 실패해도 기존 `delegate-first/` 트리가 그대로 살아 있다. 중단됐으면 `.old`가 구 트리다 — `.old`를 제자리(`delegate-first`)로 되돌리면 복구된다.

```bash
set -euo pipefail

# 가드: SRC/DST 유효성 검사 (delete-then-copy 사고 방지 — 아래 delete/swap보다 먼저 실행되어야 한다)
[ -f "$SRC/.claude/skills/delegate-first/SKILL.md" ] || { echo "SRC 미설정/오경로: $SRC"; exit 1; }
[ -d "$DST/.claude" ] || { echo "DST 미설정/오경로: $DST"; exit 1; }

# 스킬 (references/ 포함) — copy-to-temp-then-swap
NEW="$DST/.claude/skills/delegate-first.new"
OLD="$DST/.claude/skills/delegate-first.old"
rm -rf "$NEW"
mkdir -p "$NEW"
cp "$SRC/.claude/skills/delegate-first/SKILL.md" "$NEW/SKILL.md"
cp -R "$SRC/.claude/skills/delegate-first/references" "$NEW/"
# (여기서 $NEW 내용을 눈으로 확인하고 싶으면 다음 줄 실행 전에 멈춰도 된다)
rm -rf "$OLD"
mv "$DST/.claude/skills/delegate-first" "$OLD"
mv "$NEW" "$DST/.claude/skills/delegate-first"
rm -rf "$OLD"

# tier 에이전트 5종
cp "$SRC/.claude/agents/"{explorer-low,executor-med,executor-high,reviewer-high,judge-max}.md "$DST/.claude/agents/"

# 규칙 파일 (전파 — 정본에서 고친 라우팅 규칙을 설치 프로젝트/전역에도 반영. §2 참고)
cp "$SRC/.claude/rules/subagent-model-routing.md" "$HOME/.claude/rules/"

# 훅 (전역 유지 — 내용 동일하면 이 단계는 no-op)
cp "$SRC/.claude/hooks/enforce-subagent-model.cjs" "$HOME/.claude/hooks/enforce-subagent-model.cjs"
```

**HANDOFF.md / NEW-REPO-PROMPT.md 처리**: 이 2개는 로컬 스킬 디렉터리에 남아 있는 이관용 문서다. 정본 레포가 `docs/HANDOFF-2026-08-17.md`로 이력을 보존하므로 로컬에서는 삭제 가능하지만, **삭제는 이 절차에서 자동으로 하지 않는다** — 사용자 확인 후 별도로 지운다(스킬 로딩에는 영향 없음).

## 4. 검증 3단계 (재설치 후 필수)

1. **스킬 로드** — goone-rest 세션에서 `/delegate-first` 호출 → `SKILL.md` 본문이 로드되고 3단계 문구가 **파라미터 표현**으로 바뀐 것을 확인.
2. **훅 차단 스모크** — `model` 없이 Agent 즉석 호출 → exit 2 차단 + 라우팅 안내 stderr 확인. (§0의 "훅 등록 위치" 확인을 먼저 통과해야 이 스모크의 결과를 해석할 수 있다.)
3. **tier 에이전트 스폰** — `subagent_type: explorer-low` 1회 호출 → haiku/low 적용 확인. **B-06([../BACKLOG.md](../BACKLOG.md), 정본 레포 PR #2)이 해소되었으므로, §3의 훅 전파 단계(`cp "$SRC/.claude/hooks/enforce-subagent-model.cjs" "$HOME/.claude/hooks/enforce-subagent-model.cjs"`)를 수행한 뒤에는 이 3번이 수행 가능하다.** `enforce-subagent-model.cjs`의 `MODEL_PINNED_TYPES`에 tier 에이전트 5종(explorer-low·executor-med·executor-high·reviewer-high·judge-max)이 이제 등록돼 있어, `model` 없이 tier를 호출해도 통과한다. 단 §3의 훅 전파 단계를 건너뛰었거나 전역(`~/.claude/hooks/`)에 tier 5종이 없는 구 버전이 남아 있으면 여전히 exit 2로 차단된다 — 우회하려고 `model`을 넘기면 통과는 하지만 그 순간 호출 파라미터가 frontmatter의 `model`을 덮어써(`effort`·`tools`·`disallowedTools`는 유지) "pinned 조합이 그대로 적용됐는지"를 검증한다는 3번의 목적 자체가 성립하지 않는다. **이 3번에서 막히는 것은 재설치가 뭔가를 깨뜨린 것이 아니라 발효 중인 훅 버전 불일치다** — 오퍼레이터가 이 3번에서 막혔다고 방금 덮어쓴 트리를 되돌리거나 훅을 직접 손대지 말 것. 먼저 §0의 "훅 등록 위치" 확인으로 전역/프로젝트 어느 훅이 발효 중인지 확인하고, 구 버전이면 §3의 훅 전파 단계를 다시 수행한다.

추가 확인: `grep -rn "delegating-execution" "$DST/.claude"` → 결과 0건(구 명칭 잔존 없음).

## 5. 롤백

> **주의 — `$BAK`을 재계산하지 말 것**: 롤백은 보통 §0~§4를 실행한 세션과 **다른 세션**에서 실행된다. 그 세션에서 §0을 다시 실행하면 `STAMP=$(date +%Y%m%d-%H%M%S)`가 **재평가**되어 `$BAK`이 **§1에서 실제로 백업을 만든 경로가 아닌, 방금 계산된 존재하지 않는 새 경로**를 가리키게 된다. 이 상태로 아래 블록을 돌리면 `rm -rf`가 먼저 살아있는 스킬을 지우고, 그다음 `cp`는 없는 소스 경로를 읽으려다 실패한다 — §3에서 봉합한 것과 같은 사고 패턴이다. 롤백 시 `$BAK`은 **§1에서 실제로 백업을 만든 그 경로**를 다시 지정해야 한다. 어느 경로였는지 모르면 최근 백업을 찾는다(아래 명령의 출력값을 `BAK=`에 그대로 대입한 뒤 롤백 블록을 실행한다):

```bash
ls -1dt "$HOME/.claude-backups/delegate-first-"* | head -1
```

```bash
set -euo pipefail

# 가드: 백업이 실제로 존재하는지 delete 전에 확인 (STAMP 재평가로 $BAK이 빈 경로를 가리키는 사고 방지)
[ -d "$BAK/skills-delegate-first" ] || { echo "백업 없음: $BAK — STAMP가 재평가되지 않았는지 확인하라 (위 주의사항 참고)"; exit 1; }

# 중단된 재설치가 남긴 .new/.old 잔여물 정리 (가드 통과 후에만 실행 — §3 참고)
rm -rf "$DST/.claude/skills/delegate-first".new "$DST/.claude/skills/delegate-first".old

rm -rf "$DST/.claude/skills/delegate-first"
cp -R "$BAK/skills-delegate-first" "$DST/.claude/skills/delegate-first"
cp -R "$BAK/agents/." "$DST/.claude/agents/"
cp "$BAK/enforce-subagent-model.cjs" "$HOME/.claude/hooks/" 2>/dev/null
cp "$BAK/subagent-model-routing.md"  "$HOME/.claude/rules/" 2>/dev/null
```

**훅/규칙이 원래 없던 환경이었다면**: §1의 두 `cp ... 2>/dev/null` 줄은 원본이 없으면 조용히 아무것도 하지 않는다. 그러면 `$BAK`에도 해당 파일이 없으므로, 위 롤백 블록의 마지막 두 줄도 조용히 아무것도 복원하지 않는다(cp가 소스 부재로 스킵). 이 경우 완전한 원상복구를 위해 롤백 후 아래를 **수동으로** 실행해야 한다:

```bash
rm -f "$HOME/.claude/hooks/enforce-subagent-model.cjs"
rm -f "$HOME/.claude/rules/subagent-model-routing.md"
```

롤백 후에도 4단계 검증 3종을 다시 돌려 원상 복구를 확인한다.

## 6. 이후 관례

- 이 재설치가 끝난 시점부터 **정본은 이 레포**다. 로컬에서 발견한 개선은 로컬에서 고치지 말고 정본 레포에 PR을 올린 뒤 재설치한다.
- 다른 프로젝트에 새로 설치할 때는 이 문서가 아니라 [README.md](../README.md) §설치를 따른다(재설치가 아니라 신규 설치).
- 설치 프로젝트가 3곳을 넘으면 복사 방식을 접고 플러그인화(BACKLOG B-04)로 전환한다.
