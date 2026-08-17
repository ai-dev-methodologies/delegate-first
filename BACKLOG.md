# Backlog

출처: [docs/HANDOFF-2026-08-17.md](docs/HANDOFF-2026-08-17.md) §5 운영 학습 4건(2026-08-17 실전) + §2 설치 경로 미구현 1건 + 2026-08-18 정본 레포 실측 1건(B-06).
정본 레포의 개선 항목이며, 각 항목이 머지되면 설치 프로젝트는 [docs/REINSTALL.md](docs/REINSTALL.md) 절차로 재설치해야 반영된다.

번호는 발견 순이 아니라 우선순위 순으로 배치돼 있다 — B-06은 2026-08-18에 추가됐지만 우선순위가 B-01과 동급이라 B-01 바로 뒤에 삽입돼 있다(번호가 순차적이지 않은 이유).

---

## B-01 (최상단) — SKILL.md 2단계(Route)에 effort 우선 경로 지침 부재

**상태**: 미착수 · **우선순위**: 1 (다른 항목보다 먼저)

Agent 툴 **즉석 호출**(`subagent_type`을 범용 에이전트로 지정)은 `effort`를 지정할 수 없다. effort를 통제하려면 ① tier 에이전트를 `subagent_type`으로 직접 지정 ② Workflow `agent()` ③ `codex exec` 중 하나를 써야 한다.

이 사실 자체는 이미 `SKILL.md` 본문 **두 곳**에 적혀 있다(확인: `grep -n "not at all\|not specifiable" .claude/skills/delegate-first/SKILL.md`):
- Main-session reasoning-effort policy 마지막 문단: `... or (for the Agent tool) not at all — see routing-matrix.md for details.`
- Flow checklist 3번: `effort not specifiable on ad-hoc Agent calls → record "(default)"`

즉 이전 서술("이 사실은 routing-matrix.md에만 있고 SKILL.md 본문에는 없다")은 **틀렸다** — 검증 결과 거짓으로 확인됐다. 2026-08-17 실전에서 구현 레인 4건이 opus/(기본 effort)로 나간 원인을 "사실을 몰라서"로 재해석하면 안 된다. 실제 공백은 **행동 지침의 부재**다: SKILL.md 2단계(Route)에는 "effort가 필요한 작업이면 즉석 Agent 호출보다 tier 에이전트/Workflow `agent()`/`codex exec` 경로를 **먼저 선택하라**"는 지시가 없다. 사실 서술은 3단계 체크리스트(위임 **후** 기록 시점)와 routing-matrix.md에만 있어서, 경로를 **고르는 시점**(2단계)에는 아무 지침이 없다 — 그래서 즉석 호출이 기본값이 되고, effort 누락은 뒤늦게(로그 기록 시점) 발견된다.

**할 일**: `SKILL.md` 2단계(Route)에 "effort를 지정해야 하는 작업(예: judge-max/reviewer-high 급 적대검증, 고위험 구현)은 tier 에이전트 직접 지정 또는 Workflow `agent()`/`codex exec` 경로를 **우선 선택**한다 — 즉석 Agent 호출은 effort를 지정할 수 없다는 점을 경로 선택 **전에** 인지한다"를 명시.
**완료 기준**: `SKILL.md` 2단계만 읽고도, effort가 필요한 작업에서 즉석 Agent 호출을 기본값으로 쓰지 않게 된다.

---

## B-06 — 훅 MODEL_PINNED_TYPES에 tier 에이전트 5종 부재 (문서-강제장치 불일치)

**상태**: 미착수 · **우선순위**: 1 (B-01과 동급 — 같은 "effort가 실제로 적용되는가" 문제의 양면)

`references/routing-matrix.md` §①은 "tier 에이전트를 `subagent_type`으로 지정하면 예외 — Agent 툴 호출만으로 model+effort 조합이 그대로 적용된다"고 서술한다. 그러나 `enforce-subagent-model.cjs`의 `MODEL_PINNED_TYPES`에는 `oh-my-claudecode:*` 계열과 `statusline-setup`만 있고 tier 에이전트 5종(explorer-low·executor-med·executor-high·reviewer-high·judge-max)이 없다. 훅이 등록된 세션에서 tier 에이전트를 `model` 없이 호출하면 **exit 2로 차단**된다(2026-08-18 실측). 강제로 `model`을 넘기면 통과하지만 그 순간 frontmatter의 `model`이 덮어써져(공식 해석 순서: 호출 파라미터 > 정의 frontmatter) "pinned 조합 그대로 적용"이 깨진다. `effort`·`tools`·`disallowedTools`는 유지된다.

**할 일**: `MODEL_PINNED_TYPES`에 tier 5종 추가(+ 목록이 스킬 트리와 갈라지지 않게 유지하는 방법 검토), 그리고 routing-matrix.md §①에 "이 예외는 훅의 pinned 목록에 tier 5종이 포함돼 있을 때만 성립한다"는 전제 명시.
- (선택) 이 항목처럼 `enforce-subagent-model.cjs`를 실제로 수정하는 PR에서는, README의 훅 공급망 서약("`.claude/hooks/*.cjs`를 건드리는 모든 PR은 매번 사람이 diff를 읽는다")을 훅 파일 헤더 주석에도 복제할지 그 PR에서 함께 판단한다. (참고: 이번 NF-1~NF-8 봉합 PR은 `enforce-subagent-model.cjs`가 원문 바이트 보존 대상이라 건드리지 않았다.)

**완료 기준**: 훅 등록 세션에서 `subagent_type: explorer-low`를 `model` 없이 호출해 **통과**하고, `model` 미지정 범용 호출은 여전히 차단되는 것을 실측으로 확인.

---

## B-02 — 위임 로그 스키마 강제 수단 없음

**상태**: 미착수 · **우선순위**: 2

위임 로그 단계는 2026-08-17에 `SKILL.md` 체크리스트 3번으로 추가됐다(`agent/role/model/effort/path` 스키마). 그러나 **스키마를 강제하는 코드가 없다** — 문서 지침으로만 존재해서 기록 누락·형식 이탈을 잡을 방법이 없다.

**후보 방향**: (a) PostToolUse 훅으로 Agent 호출 시 로그 라인을 자동 append (b) 로그 파일 린터 스크립트 + pre-commit (c) 문서 지침 유지 결정.
**주의**: 자동 append를 만들 때도 라우팅 **자동 재조정**은 금지(`SKILL.md` §Prohibited) — 로그는 기록용이지 학습 입력이 아니다.

---

## B-03 — 판정 에이전트 idle 회수 관행 (SendMessage 재요구)

**상태**: 미착수 · **우선순위**: 3

2026-08-17 실전에서 판정 에이전트(`reviewer-high`, `judge-max` 등)가 **보고 없이 idle 상태로 남는 패턴이 잦았다**. 메인이 통지를 기다리기만 하면 라운드가 멈춘다 — `SendMessage`로 판정문을 재요구하는 관행이 필요하다는 것이 확인됐다.

**할 일**: `SKILL.md` 4~5단계에 "판정 에이전트가 무응답이면 타임박스 후 `SendMessage`로 판정문을 재요구한다(무한 대기 금지)"를 규칙으로 추가. 타임박스 기준값도 함께 정한다.

---

## B-04 — 플러그인화 (설치 경로 B)

**상태**: 미착수 · **우선순위**: 4

skill + agents + hook을 하나의 Claude Code 플러그인 매니페스트로 묶어 여러 레포에 재사용하는 경로. 2026-08-17 이관 시점에는 미구현 — 로컬 `.claude/` 복사(경로 A)만 존재한다.

**트리거**: 설치 대상 프로젝트가 3곳을 넘어가면 복사 방식의 드리프트 비용이 플러그인 작성 비용을 넘는다.

---

## B-05 — fable 강제 트리거 5종: 실전 검증 기록 (정보, 변경 없음)

**상태**: 관찰 기록 · **우선순위**: — (조치 불필요, 근거 보존용)

`SKILL.md` §"Mandatory top-tier-model (fable) triggers" 5종이 2026-08-17 하루에 **8회 실전 검증**됐다. 그중 **2회는 REFUTED(반박) 발견**이 나왔고, 같은 라운드 안에서 봉합·수렴됐다. → 트리거 목록을 축소·완화하지 않을 근거. 향후 트리거 조정 논의 시 이 기록을 먼저 반박해야 한다.
