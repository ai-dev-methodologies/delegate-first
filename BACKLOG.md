# Backlog

출처: [docs/HANDOFF-2026-08-17.md](docs/HANDOFF-2026-08-17.md) §5 운영 학습 4건(2026-08-17 실전) + §2 설치 경로 미구현 1건 + 2026-08-18 정본 레포 실측 1건(B-06).
정본 레포의 개선 항목이며, 각 항목이 머지되면 설치 프로젝트는 [docs/REINSTALL.md](docs/REINSTALL.md) 절차로 재설치해야 반영된다.

번호는 발견 순이 아니라 우선순위 순으로 배치돼 있다 — B-06은 2026-08-18에 추가됐지만 우선순위가 B-01과 동급이라 B-01 바로 뒤에 삽입돼 있다(번호가 순차적이지 않은 이유). B-08은 이후(같은 날) 사용자 승인 대기 항목으로 최상단(우선순위 0)에 삽입됐다 — 그 결과 B-01 표기에 남아 있던 "(최상단)"·"(다른 항목보다 먼저)"는 사어가 됐다(아래 B-01 참고).

---

## B-08 — 전역 훅 갱신 + 규칙 §원칙2 예외 문구 (사용자 승인 필요)

**상태**: 레포 쪽 반영 완료 (2026-08-18, PR #7) · 전역 전파·end-to-end 실측은 메인 세션이 승인받아 수행 중

**이 항목은 사용자 승인 없이는 진행 불가**임을 명시한다.

**내용**:
① `~/.claude/hooks/enforce-subagent-model.cjs`를 정본 버전으로 갱신한다 — 현재 전역본은 2026-07-16자 구버전이라 tier 5종(explorer-low·executor-med·executor-high·reviewer-high·judge-max)이 `MODEL_PINNED_TYPES`에 없고, 이로 인해 `model` 생략 tier 호출이 전 세션에서 차단된다(실측 확인, B-06 "남은 미검증 항목" 참조).
② `.claude/rules/subagent-model-routing.md` §원칙 2("모든 Agent 호출은 `model`을 명시한다 — 세션 모델 상속 금지")에 예외 구절을 추가한다: 정의 frontmatter에 `model`이 고정돼 있고 **등록된 모든 훅**의 pinned 목록에 등재된 tier 에이전트는 `model` 생략이 원칙이다(호출 파라미터가 정의를 덮어쓰므로, 생략이 오히려 pinned 조합을 보존한다).
③ 실측(2026-08-18, `cmp`): 훅(`enforce-subagent-model.cjs`)은 레포본과 전역본이 **이미 다르다**(전역이 구버전) — 이것이 ①이 필요한 이유다. 반면 규칙 파일(`subagent-model-routing.md`)은 레포본과 전역본이 **byte-identical**이다 — 즉 ②를 한쪽만 고치면 지금까지 없던 desync가 새로 생긴다. 따라서 ①과 ②는 **같은 PR/승인 대화에서 동기 갱신**해야 한다.
④ 갱신 직후 B-06의 완료 기준(end-to-end 실측: `model` 없는 tier 스폰 통과 + 범용 호출 차단 유지)을 그 자리에서 수행해 B-06을 완결한다.

**진행 상황 (2026-08-18, PR #7)**: 레포 쪽 절반(②)만 반영했다 — `.claude/rules/subagent-model-routing.md` §원칙 2에 예외 문구 추가 + §강제 장치에 tier 5종·린터 포인터 보강. `~/.claude/`는 이 PR 범위 밖(경계 위반 금지)이라 건드리지 않았다. 남은 것: ① 전역 훅 `~/.claude/hooks/enforce-subagent-model.cjs` 갱신 ② 전역 규칙 `~/.claude/rules/subagent-model-routing.md` 갱신(이 PR 머지 후, 레포본과 동기화) ③ B-06 완료 기준 end-to-end 실측 — 세 가지 모두 메인 세션이 사용자 승인과 함께 수행한다.

---

## B-01 (이력) — SKILL.md 2단계(Route)에 effort 우선 경로 지침 부재

**상태**: 해결 (2026-08-18, PR #3) · **우선순위**: 1 (이력 — B-08 신설로 최상단·우선순위 0 자리는 B-08로 이동, "(다른 항목보다 먼저)" 표기는 사어)

**해소 내용**: 사실 서술(effort 지정 불가)은 이미 있었으므로 추가하지 않았다 — Step 2(Route) 본문에 "경로 선택 시점"의 행동 지침 2문장을 추가(effort가 중요하면 tier 에이전트/Workflow `agent()`/`codex exec`를 우선 선택하라, tier 에이전트 호출 시 `model` 생략을 권장). Flow checklist 2번 줄에도 같은 취지를 짧게 보강했다.

**정정 (2026-08-18, PR #3 리뷰 반영)**: 위 "tier 에이전트 호출 시 `model` 생략을 권장" 권고는 **B-06의 전역 훅 갱신 이후에만 실제로 발효**된다 — 현재 전역 훅(`~/.claude/hooks/enforce-subagent-model.cjs`)은 2026-07-16자 구버전이라 `MODEL_PINNED_TYPES`에 tier 5종이 없고, `model` 생략 호출은 exit 2로 차단된다(B-06 "남은 미검증 항목" 참조). 즉 이 권고는 지금 그대로 따르면 차단되는 성과 과대 표기였다 — B-06이 이미 지적한 것과 같은 패턴.

Agent 툴 **즉석 호출**(`subagent_type`을 범용 에이전트로 지정)은 `effort`를 지정할 수 없다. effort를 통제하려면 ① tier 에이전트를 `subagent_type`으로 직접 지정 ② Workflow `agent()` ③ `codex exec` 중 하나를 써야 한다.

이 사실 자체는 이미 `SKILL.md` 본문 **두 곳**에 적혀 있다(확인: `grep -n "not at all\|not specifiable" .claude/skills/delegate-first/SKILL.md`):
- Main-session reasoning-effort policy 마지막 문단: `... or (for the Agent tool) not at all — see routing-matrix.md for details.`
- Flow checklist 3번: `effort not specifiable on ad-hoc Agent calls → record "(default)"`

즉 이전 서술("이 사실은 routing-matrix.md에만 있고 SKILL.md 본문에는 없다")은 **틀렸다** — 검증 결과 거짓으로 확인됐다. 2026-08-17 실전에서 구현 레인 4건이 opus/(기본 effort)로 나간 원인을 "사실을 몰라서"로 재해석하면 안 된다. 실제 공백은 **행동 지침의 부재**다: SKILL.md 2단계(Route)에는 "effort가 필요한 작업이면 즉석 Agent 호출보다 tier 에이전트/Workflow `agent()`/`codex exec` 경로를 **먼저 선택하라**"는 지시가 없다. 사실 서술은 3단계 체크리스트(위임 **후** 기록 시점)와 routing-matrix.md에만 있어서, 경로를 **고르는 시점**(2단계)에는 아무 지침이 없다 — 그래서 즉석 호출이 기본값이 되고, effort 누락은 뒤늦게(로그 기록 시점) 발견된다.

**할 일**: `SKILL.md` 2단계(Route)에 "effort를 지정해야 하는 작업(예: judge-max/reviewer-high 급 적대검증, 고위험 구현)은 tier 에이전트 직접 지정 또는 Workflow `agent()`/`codex exec` 경로를 **우선 선택**한다 — 즉석 Agent 호출은 effort를 지정할 수 없다는 점을 경로 선택 **전에** 인지한다"를 명시.
**완료 기준**: `SKILL.md` 2단계만 읽고도, effort가 필요한 작업에서 즉석 Agent 호출을 기본값으로 쓰지 않게 된다.

---

## B-06 — 훅 MODEL_PINNED_TYPES에 tier 에이전트 5종 부재 (문서-강제장치 불일치)

**상태**: 코드 반영 완료 (2026-08-18, PR #2) · end-to-end 실측 대기 (전역 훅 갱신 후) · **우선순위**: 1 (완료)

**해소 내용**: `enforce-subagent-model.cjs`의 `MODEL_PINNED_TYPES`에 tier 5종(explorer-low·executor-med·executor-high·reviewer-high·judge-max)을 각 frontmatter의 model/effort 주석과 함께 추가. `references/routing-matrix.md` §①에 "이 예외는 훅의 pinned 목록에 tier 5종이 포함돼 있을 때만 성립한다"는 전제를 명시.

**남은 미검증 항목**: 실제 Agent 호출로 `model` 없는 tier 스폰이 통과하는 end-to-end 실측은 **전역 훅(`~/.claude/hooks/`)이 이 버전으로 갱신된 뒤**에만 가능하다 — 전역 갱신은 사용자 승인이 필요한 설치 단계라 이 PR 범위 밖이다. 이 PR에서 확보한 증거는 훅 스크립트 단위 스모크(stdin 주입, `scripts/smoke-hook.sh` 24케이스)까지다. B-08의 전역 전파(①②) 완료 후 실측이 수행되면 이 완료 기준이 충족된다(B-08 참조).

**해소 전 상태(이력)**: `references/routing-matrix.md` §①은 "tier 에이전트를 `subagent_type`으로 지정하면 예외 — Agent 툴 호출만으로 model+effort 조합이 그대로 적용된다"고 서술한다. 그러나 `enforce-subagent-model.cjs`의 `MODEL_PINNED_TYPES`에는 `oh-my-claudecode:*` 계열과 `statusline-setup`만 있고 tier 에이전트 5종(explorer-low·executor-med·executor-high·reviewer-high·judge-max)이 없다. 훅이 등록된 세션에서 tier 에이전트를 `model` 없이 호출하면 **exit 2로 차단**된다(2026-08-18 실측). 강제로 `model`을 넘기면 통과하지만 그 순간 frontmatter의 `model`이 덮어써져(공식 해석 순서: 호출 파라미터 > 정의 frontmatter) "pinned 조합 그대로 적용"이 깨진다. `effort`·`tools`·`disallowedTools`는 유지된다.

**할 일 (완료)**: `MODEL_PINNED_TYPES`에 tier 5종 추가(+ 목록이 스킬 트리와 갈라지지 않게 유지하는 방법 검토), 그리고 routing-matrix.md §①에 "이 예외는 훅의 pinned 목록에 tier 5종이 포함돼 있을 때만 성립한다"는 전제 명시. (목록 드리프트를 기계적으로 잡는 방법 검토는 B-07로 이관.)
- (선택) 이 항목처럼 `enforce-subagent-model.cjs`를 실제로 수정하는 PR에서는, README의 훅 공급망 서약("`.claude/hooks/*.cjs`를 건드리는 모든 PR은 매번 사람이 diff를 읽는다")을 훅 파일 헤더 주석에도 복제할지 그 PR에서 함께 판단한다. (참고: 이번 NF-1~NF-8 봉합 PR은 `enforce-subagent-model.cjs`가 원문 바이트 보존 대상이라 건드리지 않았다.)

**완료 기준**: 훅 등록 세션에서 `subagent_type: explorer-low`를 `model` 없이 호출해 **통과**하고, `model` 미지정 범용 호출은 여전히 차단되는 것을 실측으로 확인. — 미충족(위 "남은 미검증 항목" 참조: 전역 훅 갱신 후 end-to-end 실측 대기 중).

---

## B-07 — tier 에이전트 ↔ 훅 pinned 목록 드리프트 린트

**상태**: 해결 (2026-08-18, PR #4) · **우선순위**: 2

**해소 내용**: `scripts/lint-delegate-first.py` Check A로 해소 — `.claude/agents/*.md` frontmatter(라인 파서, YAML 라이브러리 미사용)와 `enforce-subagent-model.cjs`의 `MODEL_PINNED_TYPES`를 대조한다. fs 스캔은 훅 스크립트 자체가 아니라 이 **별도 린터**가 수행하므로 훅의 require/fs 0건 서약(B-06에서 판단 완료)은 그대로 유지된다. 가장 위험한 fail-open 모드(pinned 목록에 남아 있는데 정의의 `model`이 제거되거나 `inherit`로 바뀐 경우)를 FAIL로 검출하며, 스크래치 사본으로 실측 검증했다(model 제거 1건, `model: inherit` 1건 — 둘 다 검출, 종료 코드 1). 그 외 4방향 드리프트 중 나머지(추가 후 미갱신, 삭제 후 잔존, 개명 후 미갱신)는 fail-closed라 WARN 처리한다. pre-commit(`.githooks/pre-commit`, 옵트인)에서 린터 자체 회귀망(`scripts/test-lint.sh`)·스모크(`scripts/smoke-hook.sh`)와 함께 실행된다.

**2026-08-18 후속 강화 (리뷰·릴리스 게이트 지목 미탐 봉합)**: 최초 구현 이후 독립 리뷰(reviewer-high)와 릴리스 게이트(judge-max)가 각각 실측 미탐을 지목해 봉합했다 — (1) fail-open 판정을 `model` 필드 부재/`inherit` 2가지 형태에서 "model 없음"과 의미상 동일한 값 전체(빈 값·빈 문자열·`null`·`~`·`none`, 대소문자·따옴표 무시)로 확장, (2) 훅 `MODEL_PINNED_TYPES` Set 리터럴이 한 줄로 포매팅되면 종결자를 놓치고 파일 전체를 항목으로 오인하던 파서 버그 수정 + 항목 이름 위생 검사(비정상 문자 집합이면 FAIL) 추가, (3) 대조 키를 파일명 stem에서 frontmatter `name` 필드로 바꾸고 `name`↔stem 불일치를 FAIL로 검출, (4) 빌트인 예외(`statusline-setup`)를 명시 처리해 영구 WARN 제거(`--strict`가 이제 이 레포에서 exit 0). `scripts/test-lint.sh`(양성 16건 + 음성 3건)로 회귀망을 만들었고, 각 미탐이 실제로 검출되는지 이전 버전과의 차분 실행으로 확인했다(구버전 exit 0 / 신버전 exit 1).

**완료 기준 (이력)**: 가장 위험한 fail-open 모드(tier 에이전트 frontmatter의 `model`을 제거하거나 `inherit`로 바꾸는데 pinned 목록에는 그 이름이 잔존하는 경우)를 이 린터가 잡아야 한다. — 최초 구현 시점 기준(2건: `model` 제거·`inherit`)이며, 위 2026-08-18 후속 강화로 "model 없음과 의미상 동일한 값" 전체로 넓어졌다.

pinned 목록(`enforce-subagent-model.cjs`의 `MODEL_PINNED_TYPES`)이 `.claude/agents/` 실제 내용과 갈라지는 것을 기계적으로 잡는 대역 검사가 없었다. 훅 안에서 fs 스캔하는 방식은 훅의 감사 특성(require/fs/네트워크/child_process/eval 0건이 공급망 신뢰의 근거)을 훼손하므로 배제했다(B-06에서 판단 완료). B-06의 "목록이 스킬 트리와 갈라지지 않게 유지하는 방법 검토" 잔여 과제를 여기로 이관했었다(고아 방지).

---

## B-02 — 위임 로그 스키마 강제 수단 없음

**상태**: 해결 (2026-08-18, PR #4) · **우선순위**: 2

**해소 내용**: `scripts/lint-delegate-first.py` Check B로 해소 — 후보 (b) 로그 파일 린터를 채택(후보 (a) PostToolUse 자동 append는 아래 2026-08-18 판정대로 기각 유지). `날짜 | agent | role | model | effort | 실행경로 | 결과` 7컬럼 헤더·행별 7컬럼·빈 셀 없음·날짜 `YYYY-MM-DD`(실존 날짜 검증 포함)·`실행경로` 허용 집합 소속·`(리뷰 대기)` 2건 초과 시 경고를 검사한다. 로그 경로는 `--log-path`로 override 가능(README "위임 로그 경로 관례"의 프로젝트 파라미터 원칙과 일치). 컬럼 누락 스크래치 사본으로 실측 검증(FAIL, 종료 코드 1), `scripts/test-lint.sh`에 회귀 케이스로 고정. B-07과 같은 PR(#4)로 묶어 진행했다.

**한계(범위 정정, 과대 라벨 금지)**: 이 린터는 **표에 실제로 적힌 행의 형식 이탈만** 잡는다 — 행 자체를 아예 안 쓴 경우("기록 누락", 위임했는데 로그에 줄을 추가하지 않은 경우)는 표 밖의 일이라 **원리상 검출 불가**다(파일에 없는 행은 스캔 대상이 아니다). BACKLOG가 애초에 문제로 적었던 것("기록 누락·형식 이탈을 잡을 방법이 없었다")의 두 축 중 형식 이탈만 해소됐고, 기록 누락은 B-02의 1차 실패 모드로 여전히 미해결이다(별도 과제 없음 — 위임 시점 즉시 append 규율에 의존). "해결" 라벨은 이 좁은 범위(형식 이탈)로 읽는다(B-06에서 이미 지적된 "완료 기준 미충족을 숨기지 않는다" 패턴과 동일 원칙).

**완료 기준(형식 이탈 범위로 좁힘)**: 위임 로그 표에 실제로 적힌 행이 7컬럼·빈 셀 없음·날짜 형식·실행경로 허용 집합을 벗어나면 이 린터가 FAIL로 잡는다. 행을 아예 쓰지 않은 기록 누락은 이 기준의 범위 밖이다.

위임 로그 단계는 2026-08-17에 `SKILL.md` 체크리스트 3번으로 추가됐었다(`agent/role/model/effort/path` 스키마). 그때는 **스키마를 강제하는 코드가 없어** 문서 지침으로만 존재했고 기록 누락·형식 이탈을 잡을 방법이 없었다.

**후보 방향(이력)**: (a) PostToolUse 훅으로 Agent 호출 시 로그 라인을 자동 append (b) 로그 파일 린터 스크립트 + pre-commit (c) 문서 지침 유지 결정.
**주의**: 자동 append를 만들 때도 라우팅 **자동 재조정**은 금지(`SKILL.md` §Prohibited) — 로그는 기록용이지 학습 입력이 아니다.

**판정 (2026-08-18, PR #3 리뷰 반영)**: 후보 (a) PostToolUse 자동 append 훅은 **기각** — 훅 공급망 신뢰의 근거(부작용 0의 단순 감사 표면)를 깨고, 로그를 학습 입력화하려는 유혹에 가까워진다(`SKILL.md` §Prohibited와 상충). 후보 (b) 린터를 채택하고, B-07(pinned 목록 드리프트 린트)과 같은 PR로 묶어 진행한다.

---

## B-03 — 판정 에이전트 idle 회수 관행 (SendMessage 재요구)

**상태**: 해결 (2026-08-18, PR #3) — 타임박스 기준값은 의도적 미채택(작업 종류별 편차가 커서 고정값이 오히려 오적용을 부름), 대신 Step 3의 위임 프롬프트 필수 항목으로 정박(판정/리뷰 위임에는 항상 타임박스를 명시하게 강제) · **우선순위**: 3

**해소 내용**: `SKILL.md`에 `## Escalation ladder` 뒤 `## Idle recovery` 절을 신설 — 타임박스를 위임 시점에 정하고, 무응답 시 `SendMessage` 재요구 → 그래도 무응답이면 재위임(프롬프트 강화) → 재위임도 무응답이면 중단·사용자 보고 순서를 명시. 원래 할 일이었던 "SKILL.md 4~5단계에 추가"가 아니라 별도 `## Idle recovery` 절로 배치했다 — 이탈이지만 4~5단계(Review/Judge)와 성격이 달라(회수는 판정 이전 단계) 분리 배치가 더 정확하다고 판단.

**할 일 2개 처리 결과**: ①"규칙 추가" — 완료(위). ②"타임박스 기준값도 함께 정한다" — **값을 정하지 않고 정박만 했다**: 작업 종류별 소요시간 편차가 커서 고정 분(分) 단위 기준값은 과소·과대 추정 리스크가 있다고 판단, 대신 "위임 시점에 정한다 + 판정급은 짧은 조회보다 길게"라는 원칙과 Step 3 필수 항목화로 대체했다.

2026-08-17 실전에서 판정 에이전트(`reviewer-high`, `judge-max` 등)가 **보고 없이 idle 상태로 남는 패턴이 잦았다**. 메인이 통지를 기다리기만 하면 라운드가 멈춘다 — `SendMessage`로 판정문을 재요구하는 관행이 필요하다는 것이 확인됐다.

**할 일**: `SKILL.md` 4~5단계에 "판정 에이전트가 무응답이면 타임박스 후 `SendMessage`로 판정문을 재요구한다(무한 대기 금지)"를 규칙으로 추가. 타임박스 기준값도 함께 정한다.

---

## B-04 — 플러그인화 (설치 경로 B)

**상태**: 미착수 · **우선순위**: 4

skill + agents + hook을 하나의 Claude Code 플러그인 매니페스트로 묶어 여러 레포에 재사용하는 경로. 2026-08-17 이관 시점에는 미구현 — 로컬 `.claude/` 복사(경로 A)만 존재한다.

**트리거**: 설치 대상 프로젝트가 3곳을 넘어가면 복사 방식의 드리프트 비용이 플러그인 작성 비용을 넘는다.

**리스크**: 플러그인화하면 `subagent_type`이 `delegate-first:executor-high` 형태로 바뀌어 현행 훅 pinned 목록(`enforce-subagent-model.cjs`의 `MODEL_PINNED_TYPES`, 비수식 일반명만 등록)에서 **차단된다**(실측 확인). 따라서 B-04는 훅 pinned 목록 네임스페이스 갱신 PR을 반드시 동반해야 하며, 안 하면 B-06이 새 이름(`delegate-first:*`)으로 재발한다.

플러그인화로 tier 이름이 `delegate-first:*`가 되면 **린터 Check A(B-07)의 정방향 fail-open 검출(pinned↔frontmatter model 정합성)은 조용히 사라진다** — 린터는 `:`가 든 네임스페이스 항목을 "이 레포 밖 정의"로 보고 정방향 검사에서 면제하기 때문이다(`scripts/lint-delegate-first.py`의 `if ":" in name: continue`, 실측: 비수식명이면 FAIL 1/exit 1인 fail-open이 `delegate-first:*`로 바꾸면 FAIL 0/exit 0으로 사라짐). 다만 완전한 무출력은 아니다 — 역방향 검사("agents/에 있지만 pinned 목록엔 없음")가 대신 **WARN**을 내고 `--strict`에서는 exit 1이 된다(실측 확인, WARN이라 기본 모드에선 커밋을 막지 못함). 즉 실질은 "FAIL이 WARN으로 강등"이다. B-04는 훅 pinned 목록 갱신 + 린터의 네임스페이스 처리 갱신을 **함께** 해야 한다.

---

## B-05 — fable 강제 트리거 5종: 실전 검증 기록 (정보, 변경 없음)

**상태**: 관찰 기록 · **우선순위**: — (조치 불필요, 근거 보존용)

`SKILL.md` §"Mandatory top-tier-model (fable) triggers" 5종이 2026-08-17 하루에 **8회 실전 검증**됐다. 그중 **2회는 REFUTED(반박) 발견**이 나왔고, 같은 라운드 안에서 봉합·수렴됐다. → 트리거 목록을 축소·완화하지 않을 근거. 향후 트리거 조정 논의 시 이 기록을 먼저 반박해야 한다.

---

## B-09 — 훅 Set 리터럴 파서: 문자열 연결·비-정적 리터럴은 여전히 못 잡음

**상태**: 미착수 · **우선순위**: 5

`scripts/lint-delegate-first.py` Check A(B-07)는 정규식 기반 라인 파서다 — 실제 JS 파서가 아니다. B-07 후속 강화(2026-08-18)로 한 줄 포매팅·`/* */` 블록 주석·백틱 리터럴·항목 이름 위생 검사는 해소했지만, **문자열 연결**(예: `"executor-" + "high"`)로 쓴 항목은 여전히 못 잡는다 — 실측: `executor-high`를 이런 형태로 바꾸고 같은 커밋에서 `model`을 제거해도(진짜 fail-open) 두 조각("executor-", "high")이 서로 다른 미상 항목으로 오추출돼 원래 이름이 pinned 목록에서 "빠진 것"처럼 보이고, 정작 있어야 할 FAIL이 WARN 2건 + 무관한 리버스 WARN 1건으로 격하되며 종료 코드가 0이 된다(정상이면 FAIL 1, 종료 코드 1이어야 함).

**보상 통제**: README "훅 공급망 고지"의 사람-diff 서약 — `.claude/hooks/*.cjs`를 건드리는 모든 PR은 사람이 직접 diff를 읽으므로, 이런 형태로의 변형 자체가 리뷰 단계에서 걸릴 가능성이 높다. 즉 이 구멍은 기계 게이트 단독으로는 안 잡히고 사람 리뷰에 의존한다.

**할 일(미착수)**: 파서를 문자열 연결까지 인식하도록 넓힐지, 아니면 "Set 항목은 리터럴 문자열만 허용"을 훅 파일 자체의 컨벤션(주석 명시)으로 못박고 파서 확장은 보류할지 결정 필요.

---

## B-10 — pre-commit을 `--strict`로 승격할지 결정

**상태**: 미착수 (결정 대기) · **우선순위**: 5

PR#4로 베이스라인이 WARN-free가 됐다(`--strict`가 이제 exit 0). 따라서 pre-commit을 `--strict`로 올리면 (a) B-09의 실질 표면(Set 문자열 연결 미탐 시 부수 WARN 3건이 뜨므로 strict면 걸린다) (b) stale-pinned 드리프트 WARN이 기계 게이트에 걸린다.

대가: 작업 중 `(리뷰 대기)` 행이 3건 이상 쌓이면 커밋이 막힌다(현재 WARN 조건 — 실제 판정은 `> MAX_PENDING(2)`이므로 3건째부터 걸린다).

소유자 결정 사항이며, 결정 전까지 기본 모드 유지.
