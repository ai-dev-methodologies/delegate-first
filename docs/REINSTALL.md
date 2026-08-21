# REINSTALL — 정본 레포 → 프로젝트 로컬 재설치 절차 (초안)

이 문서는 **완성된 정본 레포 버전**을 이미 로컬 사본이 돌아가고 있는 프로젝트(최초 대상: `goone-rest`)에 덮어 설치하는 절차다. `scripts/reinstall.sh`는 `.claude/`가 아예 없는 신규 설치 대상도 지원하지만, 이 문서 자체의 서술 범위는 여전히 갱신·재설치 중심이다 — 신규 설치 시 사람이 별도로 챙겨야 할 것(훅 등록 등)은 [README.md](../README.md) §설치의 순서를 따른다.

> **권장 경로는 `scripts/reinstall.sh`다.** 아래 §0~§4는 사람이 복붙하는 bash 절차라 결함이 5건(B-13/B-14 포함) 나온 뒤에야 봉합됐고, 문서를 아무리 정확히 고쳐도 다음 실행자가 그대로 복붙하지 않으면 같은 사고가 재발할 수 있다. 스크립트가 이 절차(백업 → diff → copy-to-temp-then-swap → tier 에이전트 → 검증)를 코드로 강제하고, `scripts/test-reinstall.sh`로 회귀 테스트가 붙어 있다. 사용 예:

```bash
./scripts/reinstall.sh --src "/PATH/TO/정본레포" --dst "/PATH/TO/대상프로젝트" --dry-run   # 1. 계획만 확인
./scripts/reinstall.sh --src "/PATH/TO/정본레포" --dst "/PATH/TO/대상프로젝트" --yes       # 2. 실제 실행
```

> `--rollback`은 없다. 문제가 생기면 §5를 따른다 — 복구는 별도 복원 기계가 아니라 정본을 원하는 커밋으로 되돌려 다시 설치하는 것이다. 전역 훅·규칙 전파는 기본 비활성이다(blast radius가 프로젝트 로컬과 다르므로) — 필요하면 `--propagate-global`을 명시한다. 스크립트가 없는 환경이거나 스크립트 자체를 디버깅해야 할 때만 아래 수동 절차를 직접 따른다 — **이 경우 아래 각 단계에 적힌 함정(§2~§3의 "실측"·"경고" 문단)을 스스로 지켜야 한다**, 스크립트는 이를 코드로 대신 지켜준다. 문서 절차를 바꾸면 `scripts/reinstall.sh`와 `scripts/test-reinstall.sh`도 함께 갱신해 둘이 갈라지지 않게 한다.

> **실행 승인 게이트**: 이 절차는 **사용자 명시 승인 후에만** 실행한다(스크립트 경로든 수동 경로든 동일). 대상 프로젝트의 로컬 스킬은 **의도적으로 git 추적 밖(untracked)** 이라 되돌릴 git 히스토리가 없다 — 백업(1단계)을 건너뛰면 복구 수단이 없다.

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
| 동명 에이전트 model 핀 확인 | `grep -L '^model:' "$DST"/.claude/agents/{explorer-low,executor-med,executor-high,reviewer-high,judge-max}.md` | 출력 0건(모두 model 핀 보유). 핀이 없는 동명 에이전트가 있으면 훅 화이트리스트가 그 이름을 통과시켜 세션 모델 상속 구멍이 된다. |

## 1. 백업 (건너뛰기 금지)

백업은 대상 프로젝트 워킹트리 **밖**(`$HOME/.claude-backups/`)에 둔다. 대상 레포의 `.git/info/exclude`가 `.claude/skills/`·`.claude/agents/`만 덮고 워킹트리 안의 다른 경로는 덮지 않는 경우, 백업을 `$DST/.claude/` 아래 두면 untracked 상태로 노출되어 다음 `git add -A`에 그대로 커밋된다 — "스킬은 의도적으로 git 추적 밖"이라는 전제를 백업 자신이 깨뜨리게 된다(2026-08-18 goone-rest 실측: `git check-ignore --no-index`로 NOT IGNORED 확인).

```bash
mkdir -p "$BAK"
cp -R "$DST/.claude/skills/delegate-first" "$BAK/skills-delegate-first"
cp -R "$DST/.claude/agents"               "$BAK/agents"
cp "$HOME/.claude/hooks/enforce-subagent-model.cjs" "$BAK/" 2>/dev/null  # 없으면 스킵됨(정상)
cp "$HOME/.claude/rules/subagent-model-routing.md"  "$BAK/" 2>/dev/null  # 없으면 스킵됨(정상)
```

백업 디렉터리가 실제로 채워졌는지 눈으로 확인한다(`find "$BAK" -type f`). 0바이트·빈 디렉터리를 "존재=정상"으로 넘기지 않는다.

**이 백업은 참고용이다, 자동 복원 대상이 아니다**: 위 블록의 `$BAK`는 이 재설치를 시작하는 시점의 스냅샷일 뿐이다 — 복구는 이 백업에서 파일을 되돌리는 방식이 아니라 §5의 "정본을 원하는 커밋으로 되돌려 다시 설치"로 한다. `$BAK`는 문제가 생겼을 때 "재설치 전에 실제로 뭐가 있었는지" 사람이 직접 열어 보는 용도로만 쓴다.

## 2. 교체 전 diff 확인 (덮어쓰기 전에 무엇이 바뀌는지 본다)

```bash
diff -ru "$DST/.claude/skills/delegate-first" "$SRC/.claude/skills/delegate-first" | head -100
diff -ru "$DST/.claude/agents" "$SRC/.claude/agents"
diff -u "$HOME/.claude/hooks/enforce-subagent-model.cjs" "$SRC/.claude/hooks/enforce-subagent-model.cjs"
diff -u "$HOME/.claude/rules/subagent-model-routing.md"  "$SRC/.claude/rules/subagent-model-routing.md"
```

아래 기대 목록은 **실측(2026-08-18, `diff -ru`/`diff -u` 읽기 전용 대조, `goone-rest` 로컬 사본 vs 정본 워킹트리 PR #7 head)**이다. "예상 diff는 2파일·5개 논리 변경"이라던 과거 서술은 stale였다 — 실측은 **3파일**이며, `references/routing-matrix.md`가 목록에서 빠져 있었다.

> 아래 실측은 이 문서 작성 시점 기준 정본 스킬 트리의 **현재** 최상위 항목(`SKILL.md`, `references/` 2개)을 전제로 한다. §3의 "정본 제공" 단계는 항목 이름을 하드코딩하지 않고 정본 최상위 전체를 복사하므로, 정본이 새 최상위 항목(예: `CHANGELOG.md`)을 얻으면 이 §2 실측 목록도 늘어난다 — 목록이 다시 stale해지면 아래 "목록이 다시 stale해지는 것을 막는 판정 절차"를 따른다.

### 스킬 트리 — 실측 3파일, hunk 7개(+ 디렉터리 전용표시 2줄)

1. **`SKILL.md`** (3 hunk)
   - Step 2(Route) 서술 교정: "for the Agent tool) not at all" → "for ad-hoc Agent calls) not at all — tier agents get effort from their frontmatter instead" (PR#3, 커밋 5039ad5)
   - Flow checklist 2·3번 + Step 2·3 본문: effort가 중요하면 tier 에이전트/Workflow `agent()`/`codex exec` 경로를 우선 선택하라는 지침, 위임 로그 경로를 "프로젝트 파라미터" 문구로, 판정/리뷰 위임에 timebox 명시를 요구 (PR#3, 커밋 98c5ab3 → 5039ad5에서 문구 보강)
   - `## Idle recovery` 절 신설 — 타임박스·폴링 만료 감지(`ListAgents`/`Monitor`)·`SendMessage` 재요구·재위임·늦게 도착한 판정 처리 규칙 (PR#3, 커밋 98c5ab3 → 5039ad5에서 폴링·늦은 판정 문장 추가)
2. **`references/prompt-templates.md`** (3 hunk)
   - Contents 행 문구 교체(`Real examples from this project` → `Worked examples (generic ...)`)
   - Template 1·2 "실제 예시"가 goone 고유 정보(절대경로·ADR 번호·워크트리명·API 이름)를 제거한 중립 예시로 교체
   - 전부 정본 canonical화 시점(PR#1, 커밋 568f89d)에 적용된 치환 — goone-rest 로컬 사본은 그 이전 상태로 멈춰 있어 diff가 남는다.
3. **`references/routing-matrix.md`** (1 hunk — 논리 변경 2건이 인접해 하나로 병합됨)
   - "이 예외는 훅 pinned 목록에 그 tier가 등록돼 있을 때만 성립한다"는 전제 문장 추가 (PR#2/B-06, 커밋 aab93c5)
   - 핀 누락으로 차단됐을 때 폴백은 그 tier의 frontmatter model 값을 그대로 명시(다른 값=조용한 강등) + 훅이 여러 벌이면 전부 실행되고 하나라도 차단하면 전체 차단 (PR#3, 커밋 5039ad5)

디렉터리 비교에는 추가로 `Only in $DST: HANDOFF.md` / `Only in $DST: NEW-REPO-PROMPT.md` 2줄이 뜬다 — 정상이다(§3 아래 "HANDOFF.md / NEW-REPO-PROMPT.md 처리" 참고, 삭제는 선택 사항).

hunk 수를 세지 말고 각 hunk의 **내용**을 위 목록과 대조한다. 위 목록 **외의 내용**이 보이면 (hunk 수가 몇 개든) **멈추고** 무엇이 다른지 먼저 파악한다.

> **결정 필요 (prompt-templates.md의 goone 예시 제거)**: goone-rest의 프롬프트 템플릿에서 실제 goone 예시가 사라진다. 실무에서 그 예시가 유용하면 (a) 백업본에서 예시 블록만 goone 로컬로 되살리거나 (b) goone-rest의 자체 문서(`docs/handoff/`)에 프로젝트 예시집으로 옮긴다. 사용자 선택 사항이며 재설치 전에 확정한다.

### 에이전트 5종 — byte-identical이어야 함(변경 없음)

실측: `$DST/.claude/agents`와 `$SRC/.claude/agents`는 diff 없음(byte-identical). 이 기대는 지금도 유효하다 — 비어 있지 않으면 **로컬이 정본보다 앞서 있다**는 뜻이므로, **덮어쓰기 전에 멈추고** 로컬 변경을 정본으로 역포팅한다.

### 훅 — 정본이 앞서 있음(과거 "byte-identical" 서술은 훅에는 더 이상 맞지 않음)

실측(2026-08-18): `$HOME/.claude/hooks/enforce-subagent-model.cjs`(전역, 2026-07-16자 구버전)와 `$SRC/.claude/hooks/enforce-subagent-model.cjs`(정본 — tier 5종 `MODEL_PINNED_TYPES` 추가 + 공급망 서약 주석, PR#2/B-06 커밋 aab93c5) 사이에 diff가 **있다**. 과거 §2 서술("에이전트 5종·훅은 byte-identical이라 diff가 비어야 한다")은 그때는 맞았지만 이제 훅에는 맞지 않는다 — 훅은 정본이 앞서 있는 것이 B-06/B-08 이후 현재 **정상 상태**다. §3의 훅 전파 단계(`cp`)를 수행한 뒤에는 이 diff가 **비어야 한다** — 전파 후에도 diff가 있으면 멈추고 원인을 파악한다.

### 규칙 파일 — 정본이 앞서 있음(diff 정상)

실측(2026-08-18): `$HOME/.claude/rules/subagent-model-routing.md`(B-08 이전 상태)와 `$SRC/.claude/rules/subagent-model-routing.md`(PR #7 — §원칙2 예외 범위 한정 문장, §강제 장치 서술 완화·린터 대조 범위 명시) 사이에 diff가 있다. 규칙 파일은 판정이 다르다 — 정본에서 라우팅 규칙을 고치면 diff가 발생하는 것이 **정상**이다. 이때는 "로컬이 앞서 있다"가 아니라 "**정본이 앞서 있다**"는 뜻이므로 멈추지 말고 §3의 cp로 전파한다. (역포팅 케이스와 헷갈리면 `git -C <정본레포> log -p -- .claude/rules/subagent-model-routing.md`로 정본 쪽 최근 변경 이력을 먼저 확인한다 — 로컬을 직접 고친 기억이 없는데 diff가 있다면 정본 갱신이다.) §3의 규칙 전파 단계(`cp`)를 수행한 뒤에는 이 diff도 **비어야 한다** — 전파 후에도 diff가 있으면 멈추고 원인을 파악한다(지금 이 §2 명령을 그대로 실행하면, 전파가 이미 끝난 상태에서는 훅·규칙 둘 다 빈 출력이 정상이다).

### 목록이 다시 stale해지는 것을 막는 판정 절차

이 §2 목록은 정본이 갱신될 때마다 낡는다. diff 출력이 위 목록과 다르면, 목록에 없다는 이유만으로 곧장 멈추지 말고 다음 순서로 판정한다:
1. `git -C <정본레포> log --oneline --merges main`으로 머지 PR 이력을 확인한다.
2. diff에 나온 hunk가 그 이력의 어느 머지 PR로 설명되는지 대조한다(`git -C <정본레포> show <커밋> -- <파일>`).
3. 설명되면 — 즉 "정본이 앞서 있다"고 판정되면 — 멈추지 말고 §3으로 진행한다. 정본 이력 어디에도 설명되지 않는 hunk가 있으면 멈추고 원인을 파악한다(로컬 역포팅 필요 여부 포함).

## 3. 교체

`$SRC`가 미설정이거나 오경로인 채로 아래 블록만 실행하면, 종전에는 `rm -rf`가 `$SRC` 유효성 검사보다 먼저 실행돼 live `references/`를 지운 뒤 `cp`가 전부 실패해 스킬이 파손되는 사고가 가능했다. 그래서 ①선두에 `set -euo pipefail`로 중간 실패 시 즉시 중단 ②delete 전에 `$SRC`/`$DST` 존재를 가드로 확인 ③delete-then-copy 대신 **copy-to-temp-then-swap**(새 트리를 인접 임시 경로에 먼저 완성 → 기존을 `.old`로 옮기고 새 것을 제자리에 놓은 뒤 `.old` 삭제)으로 바꿨다. 이 순서면 중간에 어디서 실패해도 기존 `delegate-first/` 트리가 그대로 살아 있다. 중단됐으면 `.old`가 구 트리다 — `.old`를 제자리(`delegate-first`)로 되돌리면 복구된다.

**재실행 위험 (2026-08-18 리뷰 실측)**: 스왑이 `mv → .old` 직후(즉 `.old`만 있고 `delegate-first`가 아직 없는 상태)에서 중단된 채 이 블록을 **그대로 재실행**하면, 스왑 직전의 무조건 `rm -rf "$OLD"`가 가드 없이 먼저 실행돼 유일한 복구본인 `.old`를 지운다 — 실측으로 HANDOFF.md가 완전히 소실되는 것을 확인했다. 아래 블록은 이 상태를 감지하면 지우지 않고 중단하도록 가드를 넣었다.

**승계 실패 감지 (2026-08-18 리뷰 실측)**: 예전 승계 단계는 `find ... -exec cp -R {} "$NEW/" \;` 형태였는데, **`-exec`는 개별 호출이 전부 실패해도 `find` 자체는 exit 0을 반환할 수 있다**(실측: 두 파일 다 Permission denied인데도 다음 줄에 도달) — `set -euo pipefail`이 이 실패를 못 잡는다. 그 결과 승계가 0건이어도 스왑이 그대로 진행되고 `rm -rf "$OLD"`가 구 트리를 영구 삭제해, 이 문서가 봉합했다고 선언한 손실 모드가 I/O 실패 시 그대로 재현될 수 있었다. 아래 블록은 `find -exec` 대신 **명시적 while 루프 + 복사 직후 목적지 존재 검증**으로 바꿔, `set -e`에 의존하지 않고 승계 실패를 스왑 전에 exit 1로 잡는다.

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

# 정본 제공 — $SRC/.claude/skills/delegate-first 최상위 항목 전체(파일·디렉터리·
# dotfile 포함)를 이름 하드코딩 없이 일반적으로 복사한다. 이렇게 해야 정본이 새
# 최상위 파일(예: CHANGELOG.md)을 얻었을 때 자동으로 설치 대상에 포함된다 —
# "SKILL.md/references만 하드코딩"이면 그 신규 파일은 애초에 복사되지 않고, 뒤이은
# 승계 단계가 DST의 낡은 동명 파일을 그 자리에 채워 넣어 조용히 다운그레이드된다
# (F3, 2026-08-18 재설치 사후 검토). 복사 직후 각 항목이 실제로 $NEW에 도착했는지
# 검증한다(아래 승계 루프와 동일한 강도) — 실패하면 스왑 전에 exit 1.
while IFS= read -r -d '' src_item; do
  base="$(basename "$src_item")"
  cp -R "$src_item" "$NEW/"
  if [ ! -e "$NEW/$base" ] && [ ! -L "$NEW/$base" ]; then
    echo "정본 제공 실패: $base 가 cp 이후에도 $NEW 에 없다 — 스왑을 중단한다." >&2
    echo "원본 트리는 아직 살아 있다: $DST/.claude/skills/delegate-first" >&2
    exit 1
  fi
done < <(find "$SRC/.claude/skills/delegate-first" -mindepth 1 -maxdepth 1 -print0)

# 이관 문서 승계 — $DST의 기존 트리에서 정본이 이미 제공한 항목(지금 $NEW에 이미
# 존재하는 이름 — 위 단계가 채운 정본 최상위 항목 전체)을 제외한 나머지를 전부
# $NEW로 복사한다.
# 제외 판정은 이름을 하드코딩하지 않고 "$NEW에 이미 존재하는가"로 파생시킨다 — 이렇게
# 하면 정본이 새 파일(예: CHANGELOG.md)을 얻어도 그 이름이 위 단계에서 이미 $NEW에
# 채워졌으므로 자동으로 건너뛰어, DST에 남은 낡은 동명 파일이 방금 복사한 정본판을
# 덮어써 조용히 다운그레이드시키는 사고를 막는다.
# dotfile도 반드시 포함한다 — find는 -mindepth 1 -maxdepth 1로 "."/".."만 제외하고
# dotfile은 나열하므로 별도 처리 없이 포함된다(글로빙 `*`만 썼다면 누락됐을 것).
# 근거: 스왑은 디렉터리를 통째로 교체하므로, 이 단계 없이는 정본이 제공하지 않는 기존
# 파일이 조용히 사라진다 — 2026-08-18 goone-rest 재설치 실행 중 HANDOFF.md·
# NEW-REPO-PROMPT.md가 이 결함으로 삭제될 뻔했고, 그 자리에서 승계 방식으로 교정했다.
if [ -d "$DST/.claude/skills/delegate-first" ]; then
  while IFS= read -r -d '' src_item; do
    base="$(basename "$src_item")"
    # 정본이 이미 제공한 이름이면 승계하지 않는다(F3: 하드코딩 제외 목록 대신
    # "$NEW에 이미 있는가"로 판정).
    if [ -e "$NEW/$base" ]; then
      continue
    fi
    cp -R "$src_item" "$NEW/"
    # F1: cp 자체가 아니라 find -exec 조합이 실패를 삼켰던 것이 원래 결함이므로,
    # 여기서는 cp를 -exec 밖에서 직접 호출해 set -e가 실패를 잡게 하는 것과 별개로
    # 복사 직후 목적지 존재를 한 번 더 명시적으로 검산한다 — "성공했겠지"에
    # 의존하지 않는다. `-e`만 쓰면 상대경로 심볼릭 링크가 같은 루프에서 아직
    # 복사되지 않은 형제 파일을 가리킬 때 대상이 없다는 이유로 오탐(false fail)한다
    # — `-e`(대상 존재)와 `-L`(링크 자체 존재, dangling 허용)을 함께 확인한다.
    if [ ! -e "$NEW/$base" ] && [ ! -L "$NEW/$base" ]; then
      echo "승계 실패: $base 가 cp 이후에도 $NEW 에 없다 — 스왑을 중단한다." >&2
      echo "원본 트리는 아직 살아 있다: $DST/.claude/skills/delegate-first" >&2
      exit 1
    fi
  done < <(find "$DST/.claude/skills/delegate-first" -mindepth 1 -maxdepth 1 -print0)
fi

# (여기서 $NEW 내용을 눈으로 확인하고 싶으면 다음 줄 실행 전에 멈춰도 된다)

# F2 가드: 스왑이 "mv → .old" 직후(= .old만 있고 delegate-first가 없음) 중단된
# 상태에서 이 블록을 재실행하면, 아래 무조건 rm -rf "$OLD"가 가드 없이 먼저 실행돼
# 유일한 복구본을 지운다(2026-08-18 리뷰 실측: HANDOFF.md 완전 소실 재현). 재실행
# 시 이 상태를 먼저 감지해 지우지 않고 중단한다.
if [ -e "$OLD" ] && [ ! -e "$DST/.claude/skills/delegate-first" ]; then
  echo "중단된 재설치 감지: $OLD 는 있는데 $DST/.claude/skills/delegate-first 가 없다." >&2
  echo "이전 실행이 스왑 도중(mv 직후) 중단된 상태로 보인다 — $OLD 를 지우지 않고 중단한다." >&2
  echo "복구하려면: mv \"$OLD\" \"$DST/.claude/skills/delegate-first\" 로 되돌린 뒤 원인을 파악하고 처음부터 다시 실행하라." >&2
  exit 1
fi

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

**HANDOFF.md / NEW-REPO-PROMPT.md 처리**: 이 2개는 로컬 스킬 디렉터리에 남아 있는 이관용 문서다. 위 승계 단계가 이 둘을 포함해 정본이 제공하지 않는 기존 파일 전체를 자동으로 `$NEW`로 이관하므로, **스왑 자체로는 삭제되지 않는다**. 정본 레포가 `docs/HANDOFF-2026-08-17.md`로 이력을 보존하므로 로컬에서는 삭제해도 무방하지만, **삭제는 이 절차에서 자동으로 하지 않는다** — 지우고 싶으면 스왑 후 사용자 확인을 거쳐 별도로 지운다(스킬 로딩에는 영향 없음).

## 4. 검증 3단계 (재설치 후 필수)

1. **스킬 로드** — goone-rest 세션에서 `/delegate-first` 호출 → `SKILL.md` 본문이 로드되고 3단계 문구가 **파라미터 표현**으로 바뀐 것을 확인.
   - **2026-08-18 실행 결과**: 파일 내용으로 확인 완료 — `SKILL.md`에 파라미터 표현("for ad-hoc Agent calls) not at all — tier agents get effort from their frontmatter instead")과 `## Idle recovery` 절(타임박스·폴링 만료 감지·재위임)이 goone-rest 로컬 사본에 반영된 것을 확인했다.
2. **훅 차단 스모크** — `model` 없이 Agent 즉석 호출 → exit 2 차단 + 라우팅 안내 stderr 확인. (§0의 "훅 등록 위치" 확인을 먼저 통과해야 이 스모크의 결과를 해석할 수 있다.)
   - **2026-08-18 실행 결과**: 전역 훅 대상 `scripts/smoke-hook.sh` 스모크 24/24 PASS + 실제 Agent 호출로 범용 타입(`general-purpose`)을 `model` 없이 호출 → exit 2 차단(라우팅 안내 포함) 확인.
3. **tier 에이전트 스폰** — `subagent_type: explorer-low` 1회 호출 → haiku/low 적용 확인. **B-06([../BACKLOG.md](../BACKLOG.md), 정본 레포 PR #2)이 해소되었으므로, §3의 훅 전파 단계(`cp "$SRC/.claude/hooks/enforce-subagent-model.cjs" "$HOME/.claude/hooks/enforce-subagent-model.cjs"`)를 수행한 뒤에는 이 3번이 수행 가능하다.** `enforce-subagent-model.cjs`의 `MODEL_PINNED_TYPES`에 tier 에이전트 5종(explorer-low·executor-med·executor-high·reviewer-high·judge-max)이 이제 등록돼 있어, `model` 없이 tier를 호출해도 통과한다. 단 §3의 훅 전파 단계를 건너뛰었거나 전역(`~/.claude/hooks/`)에 tier 5종이 없는 구 버전이 남아 있으면 여전히 exit 2로 차단된다 — 우회하려고 `model`을 넘기면 통과는 하지만 그 순간 호출 파라미터가 frontmatter의 `model`을 덮어써(`effort`·`tools`·`disallowedTools`는 유지) "pinned 조합이 그대로 적용됐는지"를 검증한다는 3번의 목적 자체가 성립하지 않는다. **이 3번에서 막히는 것은 재설치가 뭔가를 깨뜨린 것이 아니라 발효 중인 훅 버전 불일치다** — 오퍼레이터가 이 3번에서 막혔다고 방금 덮어쓴 트리를 되돌리거나 훅을 직접 손대지 말 것. 먼저 §0의 "훅 등록 위치" 확인으로 전역/프로젝트 어느 훅이 발효 중인지 확인하고, 구 버전이면 §3의 훅 전파 단계를 다시 수행한다.
   - **2026-08-18 실행 결과 — 해소됨(더 이상 B-06 제약으로 차단되지 않는다)**: 이제 실제로 수행 가능하며 실측으로 통과를 확인했다. 4단계 판정: ①음성 대조(사전) — `general-purpose`를 `model` 없이 호출 → 차단 ②양성 — `explorer-low`를 `model` 없이 호출 → 스폰 성공, transcript에 `model` 키 부재 + 실제 적용 모델 `claude-haiku-4-5-20251001`(frontmatter 핀 그대로) ③양성 2 — `executor-med`를 `model` 없이 호출 → 실제 모델 `claude-sonnet-5` + `effort: "medium"` 확인(model·effort 둘 다 frontmatter대로 적용) ④음성 대조(사후) — 다시 차단 확인. 세부는 [../BACKLOG.md](../BACKLOG.md) B-06 참조.

추가 확인: `grep -rn "delegating-execution" "$DST/.claude"` → 결과 0건(구 명칭 잔존 없음).

추가 확인: 정본 레포에서 `bash scripts/smoke-hook.sh` 실행 → `PASS n/n` 확인(훅 스크립트 단위 회귀 없음).

## 5. 복구

이 절차(스크립트 경로든 §0~§4의 수동 경로든)에 `--rollback`/롤백은 없다. 예전에는 §1 백업에서 스킬 트리와 tier 5종 에이전트 파일을 복원하는 전용 절차가 있었지만, 결함이 8건(B-15/B-16/B-17 포함, `../BACKLOG.md` 참고) 나온 뒤 걷어냈다 — 롤백이 복원하려던 내용(`SKILL.md`, tier 에이전트, 훅, 규칙)은 전부 이 정본 레포의 git 이력에 이미 있고, 롤백이 손대면 안 됐던 내용(대상 프로젝트 고유 파일 — `HANDOFF.md`, `NEW-REPO-PROMPT.md`, 사용자 커스텀 에이전트)은 설치 절차 자체가 애초에 건드리지 않는다. 그래서 별도 복원 기계 없이, **정본을 원하는 커밋으로 되돌려 다시 설치**하는 것으로 복구가 충분하다:

```bash
git -C <정본레포> checkout <원하는 커밋>
./scripts/reinstall.sh --src <정본레포> --dst <대상프로젝트> --yes
git -C <정본레포> checkout main   # 되돌리기
```

- `<원하는 커밋>`은 보통 이번 재설치 **직전**의 정본 상태 — `git -C <정본레포> log --oneline`으로 재설치 전 마지막 커밋을 찾는다.
- §1의 백업(`$BAK`, 스크립트 경로라면 `$HOME/.claude-backups/delegate-first-<stamp>/`)은 이제 자동 복원 대상이 아니다 — 문제가 생겼을 때 사람이 직접 열어 "무엇이 바뀌었는지" 참고할 사본일 뿐이다.
- 전역 훅·규칙(`$HOME/.claude/hooks/enforce-subagent-model.cjs`, `$HOME/.claude/rules/subagent-model-routing.md`)도 같은 모델을 따른다 — 정본을 원하는 커밋으로 되돌린 뒤 `--propagate-global`을 붙여 재설치하면 전역도 그 커밋 상태로 복구된다.
- 복구 후에도 §4 검증 3단계를 다시 돌려 원상 복구를 확인한다.

**왜 이걸로 충분한가**: 이 스크립트가 설치하는 모든 항목은 정본 레포 워킹트리의 스냅샷이다 — "재설치"와 "복구"는 같은 연산(정본 → 대상 복사)에 커밋 선택만 다르다. 별도 백업/복원 계약을 유지할 이유가 없다.

## 6. 이후 관례

- 이 재설치가 끝난 시점부터 **정본은 이 레포**다. 로컬에서 발견한 개선은 로컬에서 고치지 말고 정본 레포에 PR을 올린 뒤 재설치한다.
- 다른 프로젝트에 처음 설치할 때도 `scripts/reinstall.sh`(신규/재설치 겸용)를 그대로 쓸 수 있다 — 다만 스크립트는 skills + tier 에이전트만 설치하고 훅은 설치하지 않으므로, 훅 등록·검증 순서는 이 문서가 아니라 [README.md](../README.md) §설치("처음 설치하는 사람" 3단계)를 따른다.
- 설치 프로젝트가 3곳을 넘으면 복사 방식을 접고 플러그인화(BACKLOG B-04)로 전환한다.
