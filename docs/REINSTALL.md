# REINSTALL — 정본 레포 → 프로젝트 로컬 재설치 절차 (초안)

이 문서는 **완성된 정본 레포 버전**을 이미 로컬 사본이 돌아가고 있는 프로젝트(최초 대상: `goone-rest`)에 덮어 설치하는 절차다.

> **실행 승인 게이트**: 이 절차는 **사용자 명시 승인 후에만** 실행한다. 대상 프로젝트의 로컬 스킬은 **의도적으로 git 추적 밖(untracked)** 이라 되돌릴 git 히스토리가 없다 — 백업(1단계)을 건너뛰면 복구 수단이 없다.

---

## 0. 사전 확인

| 항목 | 확인 방법 | 기대값 |
|---|---|---|
| 정본 PR 머지 완료 | `git -C <정본레포> log --oneline -1 main` | 이관 PR이 main에 있음 |
| 대상 프로젝트 경로 | — | `/Users/plletdata/dev/goone-rest` |
| 로컬 사본 존재 | `ls <대상>/.claude/skills/delegate-first` | SKILL.md, references/, HANDOFF.md, NEW-REPO-PROMPT.md |
| 훅 위치 | `ls ~/.claude/hooks/enforce-subagent-model.cjs` | 존재(전역 설치) |

변수:

```bash
SRC=<정본 레포 경로>              # 예: .../workspace/delegate-first
DST=/Users/plletdata/dev/goone-rest
STAMP=$(date +%Y%m%d-%H%M%S)
```

## 1. 백업 (건너뛰기 금지)

```bash
mkdir -p "$DST/.claude/_backup-$STAMP"
cp -R "$DST/.claude/skills/delegate-first" "$DST/.claude/_backup-$STAMP/skills-delegate-first"
cp -R "$DST/.claude/agents"               "$DST/.claude/_backup-$STAMP/agents"
cp "$HOME/.claude/hooks/enforce-subagent-model.cjs" "$DST/.claude/_backup-$STAMP/" 2>/dev/null
cp "$HOME/.claude/rules/subagent-model-routing.md"  "$DST/.claude/_backup-$STAMP/" 2>/dev/null
```

백업 디렉터리가 실제로 채워졌는지 눈으로 확인한다(`find "$DST/.claude/_backup-$STAMP" -type f`). 0바이트·빈 디렉터리를 "존재=정상"으로 넘기지 않는다.

## 2. 교체 전 diff 확인 (덮어쓰기 전에 무엇이 바뀌는지 본다)

```bash
diff -ru "$DST/.claude/skills/delegate-first" "$SRC/.claude/skills/delegate-first" | head -100
diff -ru "$DST/.claude/agents" "$SRC/.claude/agents"
diff -u "$HOME/.claude/hooks/enforce-subagent-model.cjs" "$SRC/.claude/hooks/enforce-subagent-model.cjs"
diff -u "$HOME/.claude/rules/subagent-model-routing.md"  "$SRC/.claude/rules/subagent-model-routing.md"
```

**예상 diff는 2건뿐이다** (정본 이관 시 적용한 종속 치환):

1. `SKILL.md` 3단계 — 위임 로그 경로가 하드코딩에서 **프로젝트 파라미터 문구**로 바뀜. 기본값은 `docs/handoff/delegation-log.md`로 동일하므로 goone-rest는 동작 변화 없음.
2. `references/prompt-templates.md` — "실제 예시" 2건이 **중립 예시**로 교체됨(goone 절대경로·ADR 번호·워크트리명 제거) + Template 1 역할 placeholder의 goone 언급 제거.

에이전트 5종·훅·규칙 파일은 **byte-identical**이라 diff가 비어야 한다. 비어 있지 않으면 로컬이 정본보다 앞서 있다는 뜻 — **덮어쓰기 전에 멈추고** 로컬 변경을 정본으로 역포팅한다.

> **결정 필요 (치환 #2)**: goone-rest의 프롬프트 템플릿에서 실제 goone 예시가 사라진다. 실무에서 그 예시가 유용하면 (a) 백업본에서 예시 블록만 goone 로컬로 되살리거나 (b) goone-rest의 자체 문서(`docs/handoff/`)에 프로젝트 예시집으로 옮긴다. 사용자 선택 사항이며 재설치 전에 확정한다.

## 3. 교체

```bash
# 스킬 (references/ 포함)
rm -rf "$DST/.claude/skills/delegate-first/references"
cp "$SRC/.claude/skills/delegate-first/SKILL.md" "$DST/.claude/skills/delegate-first/SKILL.md"
cp -R "$SRC/.claude/skills/delegate-first/references" "$DST/.claude/skills/delegate-first/"

# tier 에이전트 5종
cp "$SRC/.claude/agents/"{explorer-low,executor-med,executor-high,reviewer-high,judge-max}.md "$DST/.claude/agents/"

# 훅 (전역 유지 — 내용 동일하면 이 단계는 no-op)
cp "$SRC/.claude/hooks/enforce-subagent-model.cjs" "$HOME/.claude/hooks/enforce-subagent-model.cjs"
```

**HANDOFF.md / NEW-REPO-PROMPT.md 처리**: 이 2개는 로컬 스킬 디렉터리에 남아 있는 이관용 문서다. 정본 레포가 `docs/HANDOFF-2026-08-17.md`로 이력을 보존하므로 로컬에서는 삭제 가능하지만, **삭제는 이 절차에서 자동으로 하지 않는다** — 사용자 확인 후 별도로 지운다(스킬 로딩에는 영향 없음).

## 4. 검증 3단계 (재설치 후 필수)

1. **스킬 로드** — goone-rest 세션에서 `/delegate-first` 호출 → `SKILL.md` 본문이 로드되고 3단계 문구가 **파라미터 표현**으로 바뀐 것을 확인.
2. **훅 차단 스모크** — `model` 없이 Agent 즉석 호출 → exit 2 차단 + 라우팅 안내 stderr 확인.
3. **tier 에이전트 스폰** — `subagent_type: explorer-low` 1회 호출 → haiku/low 적용 확인.

추가 확인: `grep -rn "delegating-execution" "$DST/.claude"` → 결과 0건(구 명칭 잔존 없음).

## 5. 롤백

```bash
rm -rf "$DST/.claude/skills/delegate-first"
cp -R "$DST/.claude/_backup-$STAMP/skills-delegate-first" "$DST/.claude/skills/delegate-first"
cp -R "$DST/.claude/_backup-$STAMP/agents/." "$DST/.claude/agents/"
cp "$DST/.claude/_backup-$STAMP/enforce-subagent-model.cjs" "$HOME/.claude/hooks/" 2>/dev/null
```

롤백 후에도 4단계 검증 3종을 다시 돌려 원상 복구를 확인한다.

## 6. 이후 관례

- 이 재설치가 끝난 시점부터 **정본은 이 레포**다. 로컬에서 발견한 개선은 로컬에서 고치지 말고 정본 레포에 PR을 올린 뒤 재설치한다.
- 다른 프로젝트에 새로 설치할 때는 이 문서가 아니라 [README.md](../README.md) §설치를 따른다(재설치가 아니라 신규 설치).
- 설치 프로젝트가 3곳을 넘으면 복사 방식을 접고 플러그인화(BACKLOG B-04)로 전환한다.
