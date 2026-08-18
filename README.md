# delegate-first

메인 세션(고비용 프론트티어 모델)이 실행 작업을 직접 하지 않고 **계획·위임·리뷰·판정만** 하도록 강제하는 Claude Code 워크플로 규율 — 스킬 1종 + tier 에이전트 5종 + PreToolUse 강제 훅.

## 이 레포의 위치

**이 레포가 정본(canonical source)이고, 각 프로젝트의 `.claude/` 아래에 있는 것은 설치본(install)이다.**

- 원칙·라우팅·에이전트 정의를 바꿀 때는 **이 레포에서 바꾸고 PR로 머지한 뒤**, 각 프로젝트에 재설치한다.
- 프로젝트 로컬에서 직접 고친 변경은 다음 재설치 때 덮어써진다. 로컬에서 먼저 발견한 개선은 이 레포로 역포팅한다.
- 재설치 절차: [docs/REINSTALL.md](docs/REINSTALL.md)
- 최초 이관 패키지 원본(이력 보존): [docs/HANDOFF-2026-08-17.md](docs/HANDOFF-2026-08-17.md)

## 구성 요소

```
SKILL.md (원칙 + 5단계 체크리스트)
  ├─ references/routing-matrix.md   (작업유형 → model → effort → 실행경로 → tier에이전트)
  ├─ references/prompt-templates.md (조사용 / 구현용 프롬프트 템플릿 2종)
  └─ tier 에이전트 5종 (.claude/agents/*.md)
        explorer-low(haiku/low, 읽기전용) · executor-med(sonnet/medium)
        · executor-high(sonnet/high) · reviewer-high(opus/high, Write/Edit 제외)
        · judge-max(fable/max, Write/Edit 제외)
              ↑ routing-matrix.md가 이 5종의 model+effort 조합을 가리킴
              ↑ 강제(기계적 차단)
        PreToolUse 훅: enforce-subagent-model.cjs
              (matcher: Agent — tool_input.model 없으면 exit 2로 차단)
              ↑ 정책 근거
        글로벌 규칙: subagent-model-routing.md
```

## 레포 구조

```
.
├── .claude/
│   ├── skills/delegate-first/
│   │   ├── SKILL.md
│   │   └── references/{routing-matrix.md, prompt-templates.md}
│   ├── agents/{explorer-low,executor-med,executor-high,reviewer-high,judge-max}.md
│   ├── hooks/enforce-subagent-model.cjs
│   ├── rules/subagent-model-routing.md
│   ├── settings.json                  (이 레포용 활성 훅 등록 — dogfood)
│   └── settings.json.example          (훅 등록 예시 — 복사해서 쓰는 템플릿)
├── docs/
│   ├── REINSTALL.md                   (정본 → 프로젝트 로컬 재설치 절차)
│   ├── HANDOFF-2026-08-17.md          (최초 이관 패키지 원본)
│   └── handoff/delegation-log.md      (위임 로그 — 스킬 3단계가 요구)
├── scripts/
│   ├── smoke-hook.sh                  (훅 회귀 스모크)
│   ├── lint-delegate-first.py         (B-07+B-02+B-09+B-11 린터)
│   └── test-lint.sh                   (린터 자체 회귀망)
├── .githooks/pre-commit               (린터+린터 회귀망+스모크 게이트, 옵트인)
├── .gitignore
├── BACKLOG.md
└── README.md
```

## 설치 (택1)

### A) 프로젝트 로컬 설치 (권장, 빠름)

이 레포의 `.claude/` 트리를 대상 프로젝트의 `.claude/` 아래로 복사한다.

```bash
SRC=<이 레포 경로>
DST=<대상 프로젝트 경로>
mkdir -p "$DST/.claude/skills" "$DST/.claude/agents" "$DST/.claude/hooks" "$DST/.claude/rules"
cp -R "$SRC/.claude/skills/delegate-first" "$DST/.claude/skills/"
cp "$SRC/.claude/agents/"{explorer-low,executor-med,executor-high,reviewer-high,judge-max}.md "$DST/.claude/agents/"
cp "$SRC/.claude/hooks/enforce-subagent-model.cjs" "$DST/.claude/hooks/"
cp "$SRC/.claude/rules/subagent-model-routing.md" "$DST/.claude/rules/"
cp "$SRC/.claude/settings.json.example" "$DST/.claude/"
```

`subagent-model-routing.md` 복사는 **선택 사항**이다 — `.claude/rules/`는 자동 로드 경로가 아니므로, 이 규칙에 효력을 주려면 설치 프로젝트의 `CLAUDE.md`에서 명시적으로 참조해야 한다(참조하지 않으면 파일만 있고 로드되지 않는다).

훅은 파일을 두는 것만으로는 작동하지 않는다 — `settings.json`(또는 커밋하지 않을 `settings.local.json`)의 `PreToolUse`에 `matcher: "Agent"`로 **등록해야** 강제된다. `.claude/settings.json.example`을 복사해서 쓴다:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Agent",
        "hooks": [
          { "type": "command", "command": "node <훅 절대경로>/enforce-subagent-model.cjs" }
        ]
      }
    ]
  }
}
```

훅을 프로젝트 로컬(`<프로젝트>/.claude/hooks/`)에 둘지, 사용자 홈(`~/.claude/hooks/`, **전 프로젝트 전역**)에 둘지는 선택이다. 전역으로 두면 모든 프로젝트에서 model 미지정 Agent 호출이 차단된다. 위 `command`의 경로만 그에 맞게 바꾸면 된다.

break-glass는 **사람 전용**이다: `ALLOW_INHERITED_SUBAGENT_MODEL=1`. 에이전트가 이 변수를 스스로 설정하지 않는다.

**B-11(2026-08-18)**: 훅은 이제 tier 5종 호출에 `model`이 지정된 경우 그 **값**까지 검증한다 — `TIER_EXPECTED_MODEL`(tier → 고정 model 맵)과 다른 값을 넘기면 exit 2로 차단한다(예: `judge-max`에 `opus`를 넘겨 최고 검증 게이트를 조용히 저비용 모델로 낮추는 시도). 의도적으로 다른 model을 쓰려면 별도의 **사람 전용** break-glass `ALLOW_TIER_MODEL_OVERRIDE=1`을 설정한다(`ALLOW_INHERITED_SUBAGENT_MODEL`과 별개 — 이쪽은 model 불일치만 허용하고, model 미지정 차단 자체는 여전히 막는다).

이 레포 자체는 이미 활성 `.claude/settings.json`(위 블록과 **같은 구조** — command가 `node <훅 절대경로>/...`가 아니라 `node "${CLAUDE_PROJECT_DIR}/.claude/hooks/enforce-subagent-model.cjs"`라는 점이 다르다)을 포함하고 있다 — 정본 레포가 자기 규율을 dogfood하는 배선이다. `${CLAUDE_PROJECT_DIR}`는 Claude Code가 훅 command 안에서 프로젝트 루트 절대경로로 확장해주는 변수라 경로를 하드코딩하지 않고도 이식 가능하다 — 어느 프로젝트로 복사하든 그대로 동작한다. 큰따옴표로 감싸는 것이 권장된다.

**trust 동작 주의**: 대화형 세션은 workspace trust 다이얼로그를 수락하기 전까지 settings 파일의 훅을 보류한다. 그래서 "Agent 호출이 차단되지 않는다"가 항상 "훅 미등록"을 뜻하지는 않는다 — trust를 아직 수락하지 않은 상태일 수도 있다. 반대로 `-p`/SDK(헤드리스) 세션은 폴더를 신뢰된 것으로 취급해 커밋된 `.claude/settings.json`의 훅이 그대로 실행된다. 레포에 훅을 커밋해 배포할 때는 이 비대칭(대화형=trust 게이트, 헤드리스=즉시 활성)을 인지하고 있어야 한다.

**훅 공급망 고지**: 이 레포는 커밋된 `settings.json` + 커밋된 훅 스크립트(`.claude/hooks/*.cjs`) 조합을 쓴다. 위 비대칭 때문에 헤드리스 소비자에게는 이 조합이 곧 "clone하면 자동 실행되는 코드"다. 그러므로 **`.claude/hooks/*.cjs`를 건드리는 모든 PR은 매번 사람이 diff를 읽는다** — 리뷰 없이 머지하지 않는다. (참고: 현재 `enforce-subagent-model.cjs`는 stdin을 읽고 stderr에 쓰고 exit code를 반환하는 것 외에는 아무 동작도 하지 않는다.) 이 서약의 범위는 `.claude/hooks/*.cjs`로 한정된다 — `scripts/*`와 `.githooks/*`는 별도의 실행 표면이다(B-07/B-02 린터 도입으로 새로 생겼다). `.githooks/pre-commit`은 옵트인(`git config core.hooksPath .githooks`를 사용자가 직접 실행해야 활성화)이라 커밋된 것만으로 자동 실행되지 않지만, 옵트인한 사용자에게는 **커밋마다** `scripts/*.py`/`scripts/*.sh`가 실행된다는 점에서 같은 수준의 신뢰가 필요하다. **그러므로 `scripts/*`와 `.githooks/*`를 건드리는 모든 PR도 사람이 diff를 읽는다** — `.claude/hooks/*.cjs`와 동일하게 리뷰 없이 머지하지 않는다.

### B) 플러그인화

skill + agents + hook을 하나의 Claude Code 플러그인 매니페스트로 묶어 여러 레포에서 재사용하는 경로. **현재 미구현** — [BACKLOG.md](BACKLOG.md) 항목으로 등재돼 있다. 여러 레포에 설치할 계획이면 A) 대신 이쪽을 먼저 만드는 것이 낫다.

## 위임 로그 경로 관례 (프로젝트 파라미터)

`SKILL.md`의 3단계 체크리스트는 매 위임을 `agent/role/model/effort/path` 스키마로 **프로젝트 위임 로그에 append**하도록 요구한다. 이 경로는 프로젝트마다 다를 수 있는 **파라미터**다.

- 기본 관례: `docs/handoff/delegation-log.md`
- 다른 경로를 쓰려면: 설치 프로젝트의 `CLAUDE.md`에 한 줄로 명시한다 — 예 `delegate-first 위임 로그 경로: docs/ops/delegation-log.md`. 스킬 본문을 프로젝트마다 고쳐 갈라지게 만들지 않는다.
- 로그 스키마는 `scripts/lint-delegate-first.py` Check B가 강제한다(7컬럼·빈 셀 없음·날짜 형식·실행경로 허용 집합, [scripts/](#scripts) 참고) — 옵트인 pre-commit이나 수동 실행으로 검사한다. 스키마 예시는 [docs/handoff/delegation-log.md](docs/handoff/delegation-log.md) 헤더 참고.
- Agent 툴 즉석 호출은 effort를 지정할 수 없다 → 로그의 effort 칸에 `(default)`로 기록한다.

## 검증 3단계 (설치 후 반드시 실행)

훅 스크립트 단위 회귀는 `bash scripts/smoke-hook.sh`로 확인한다(부작용 없음, stdin 주입만). 단 이는 스크립트 로직 검증이며, 세션에서 실제로 발효 중인지는 아래 2·3번 라이브 스모크로 확인한다.

1. **스킬 로드 확인** — 설치한 프로젝트 세션에서 `/delegate-first`를 호출해 `SKILL.md` 본문이 그대로 로드되는지 확인한다.
2. **훅 차단 스모크** — `model` 파라미터 **없이** Agent 툴을 즉석 호출한다. `enforce-subagent-model.cjs`가 exit 2로 차단하고 라우팅 안내를 stderr로 되돌려주는지 확인한다. (차단되지 않으면 훅이 `settings.json`에 등록되지 않은 것이다 — 단, 역은 성립하지 않는다: 차단됐다고 해서 **이 프로젝트**에 등록됐다는 뜻은 아니다. `~/.claude/settings.json`에 같은 훅이 **전역**으로 이미 등록돼 있으면, 이 프로젝트의 `.claude/settings.json`을 지워도 스모크는 그대로 통과한다(2026-08-18 실측 — 전역 등록만으로 차단됨). 전역 등록과 프로젝트 등록을 구분하려면 (a) 스모크 전에 전역 등록을 일시 비활성화하거나 (b) 프로젝트 훅 command를 래퍼로 감싸 stderr에 출처를 직접 찍는다 — 예: `{ "type": "command", "command": "sh -c 'echo \"[hook-src=project]\" >&2; exec node \"${CLAUDE_PROJECT_DIR}/.claude/hooks/enforce-subagent-model.cjs\"'" }`. (이전에 검토했던 `--src=project` 같은 인자 부착 방식은 훅 스크립트가 인자를 무시해 stderr가 두 경로에서 동일하게 나오므로 출처 판별이 **성립하지 않는다** — 실제로 검증 가능한 것은 래퍼 방식뿐이다. 래퍼가 `exec` 직전에 자기 출처를 stderr에 찍으므로 훅 스크립트 자체를 고치지 않고도 확실히 동작한다.))
3. **tier 에이전트 스폰 1회** — `subagent_type: explorer-low`로 Agent를 1회 호출해 frontmatter의 `model`+`effort` 조합(haiku/low)이 실제로 적용되는지 확인한다 — B-06 해소로 이제 수행 가능하다. 단 아래 「전제: 발효 중인 훅 버전」을 먼저 읽을 것.

**전제: 발효 중인 훅 버전**: B-06(정본 레포 PR #2)이 훅의 `MODEL_PINNED_TYPES`에 tier 에이전트 5종(explorer-low·executor-med·executor-high·reviewer-high·judge-max)을 추가해, tier 에이전트를 `model` 파라미터 없이 호출해도(=frontmatter의 model+effort 조합을 그대로 쓰려는 의도) 통과하도록 해소했다. **단 이것은 그 세션에서 실제로 발효 중인 훅이 이 레포의 최신 버전(tier 5종이 pinned에 포함된 버전)일 때만 성립한다.** 전역(`~/.claude/settings.json`)과 프로젝트(`.claude/settings.json`)의 동일 matcher(`Agent`) PreToolUse 훅은 **우선순위가 아니라 가산적으로 모두 실행되며, 등록된 훅 중 하나라도 exit 2면 차단**된다(훅 실행 **순서** 자체는 미확인이므로 순서를 단정하지 않는다). 즉 전역 `~/.claude/hooks/`에 tier 5종이 없는 구 버전이 남아 있으면, 그 구 버전이 exit 2를 반환해 프로젝트 쪽이 최신이어도 여전히 차단된다 — 오퍼레이터는 "발효 중인 하나만 갱신"이 아니라 **등록된 모든 사본**을 갱신해야 한다. 이 경우 필요한 것은 되돌리기가 아니라 전역 훅 갱신이다([docs/REINSTALL.md](docs/REINSTALL.md) §3의 훅 전파 단계 참고). 3번 스모크가 차단되면 먼저 발효 중인 훅 버전부터 확인한다.

## scripts/

- `python3 scripts/lint-delegate-first.py [--strict]` — B-07(tier↔훅 pinned 드리프트) + B-02(위임 로그 스키마) + B-09(Set 리터럴 비-정적 항목 검출) + B-11(TIER_EXPECTED_MODEL map ↔ pinned Set ↔ frontmatter 3자 정합성) 검사. 경로는 `--agents-dir`/`--hook-path`/`--log-path`로 override 가능(설치 프로젝트마다 다를 수 있는 파라미터). 종료 코드: FAIL 있으면 1, WARN만 있으면 0(`--strict`면 1). INFO는 알려진 예외(예: 빌트인 `statusline-setup`)를 무시했다는 사실만 보여주며 종료 코드에 영향을 주지 않는다.
- `bash scripts/test-lint.sh` — 위 린터 자신의 회귀망(부작용 없음, `mktemp -d` 사본에만 변형을 가한다). 양성(FAIL 기대) 22건 + 음성(PASS 기대) 4건, 실측 ~1초.
- `bash scripts/smoke-hook.sh` — `enforce-subagent-model.cjs` 회귀 스모크(부작용 없음).
- pre-commit 옵트인: `git config core.hooksPath .githooks`를 **사용자가 직접** 실행하면 커밋 전에 위 세 스크립트가 자동 실행된다(자동 설치되지 않음).

## 원칙 요약

- 메인 세션은 결정·방향·판정 종합 전용. 구현·테스트·탐색·문서 초안은 위임한다.
- 모든 Agent 호출은 `model`을 **명시**한다 — 세션 모델 상속 금지(훅이 기계적으로 차단).
- 서브에이전트의 자기 보고는 증거가 아니다 — 핵심 주장은 메인이 직접 재현(grep/실행)한다.
- 라우팅은 원칙 기반으로 유지한다. 위임 로그에서 자동 재조정(auto-recalibration)하지 않는다 — 틀린 라우팅은 `routing-matrix.md`를 **수기로 즉시** 고친다.
