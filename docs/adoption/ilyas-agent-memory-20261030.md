# Ilyas 에이전트 기억·조율 자료 적용 판정

이 문서는 Ilyas 4부작 자료의 delegate-first 적용 판정(항목별 adopt·connect·skip·defer와 그 근거)을 소유한다. 설계 결과는 [v2 청사진](../blueprint/delegate-first-v2.md)이 소유하고, 이 문서는 청사진의 각 요소가 왜 채택됐는지를 적는다. 원문 문장은 복사하지 않고 경로와 절로 인용한다.

## 1. 읽은 자료

| 약칭 | 저장소 | 읽은 경로 | 기준 SHA | 현재 main HEAD |
|---|---|---|---|---|
| RI | research | `docs/ilyas-agent-memory-series-20261026/{README,integrated-insights,insights-and-application}.md` | 949bf5619e3cf19d00f216ad808bc782909fb2af | 949bf5619e3cf19d00f216ad808bc782909fb2af(같음) |
| HQ | HQ | `docs/guides/hq-team/PORTING.md`, `governance/HQ-TEAM-OPERATING-CONTRACT.md`, `docs/guides/hq-team/README.md`, `scripts/check_delivery.py` | 5c4b54af9a49a0849a6c71711dbdeebddc688734 | 385c873d27e68a682ce6e309d339ffbb1ea59c37 |
| HP | HQ | `coordination/handoffs/2026-10-30-ilyas-agent-memory-apply-to-project-prompt.md`(지시서) | 385c873d27e68a682ce6e309d339ffbb1ea59c37 | 같음 |

- research HEAD는 `gh api repos/ai-dev-methodologies/ai-dev-methodologies-research/git/ref/heads/main`으로 확인했다.
- HQ HEAD는 HQ 클론에서 `git ls-remote origin refs/heads/main`으로 확인했다.
- HQ HEAD는 기준 SHA보다 1커밋 앞선다. 그 1커밋은 지시서 추가이고, 읽은 네 파일은 두 SHA 사이에 변경이 없다(`git diff --stat 5c4b54af origin/main -- <네 파일>`이 빈 출력).
- 로컬 HQ 클론의 `main` 브랜치는 `73f8f208`로 원격과 다르다. 모든 읽기는 SHA를 지정해 했다.
- 읽지 않은 자료는 원문·번역·역주(`part-*.md`), HQ의 구현 보고서, `templates/team/run.template.json`, `registry/hq-team.json`, `scripts/hq_contract.py`, `scripts/hq_ledger.py`다. 해당 행의 판정은 PORTING의 층별 표와 `check_delivery.py`의 읽은 구간에 근거한다.

## 2. 근거의 신뢰 수준

| 구분 | 내용 | 이 문서에서의 취급 |
|---|---|---|
| 저자 주장 | MetaEnsemble 자체 평가 수치, 지속적 정체성은 원장 기록이라는 설명(RI `integrated-insights.md` §2) | 수치를 설계 근거로 쓰지 않는다. 저자 평가이고 재현하지 않았다 |
| 우리 해석 | 인사이트 6개(RI `integrated-insights.md` §3), HQ 채택안 | 방향의 근거로 쓴다. HQ도 다른 PC·OS·CI·비용 효과를 검증하지 않았다(HQ `PORTING.md` 「적용 전에 알아야 할 경계」) |
| 이 문서의 판단 | 판정표의 근거 열 | 이 레포 파일의 줄 번호로 확인할 수 있는 것만 적는다 |
| 미검증 | §6 | 사실로 쓰지 않는다 |

## 3. 판정표

판정별 개수는 adopt 7, connect 3, skip 7, defer 1이다. 합계 18행이다. 「근거」 열의 connect 행은 연결 지점, skip 행은 이 레포의 규칙 파일과 줄을 가리킨다.

| # | 항목 | 출처 경로 + 절 | 판정 | 근거 | 검증 방법 |
|---|---|---|---|---|---|
| I-01 | 발주 계약 6칸(목표, 입력, 유효 결정, 쓰기 범위, 금지, 완료 증거) | RI `integrated-insights.md` §3 ③ · HQ `PORTING.md` 「실제 작업 방법」 | adopt | `prompt-templates.md:52-70`의 Template 2에는 참고 문서 칸과 유효 결정 칸이 없다. 정지 조건은 「안전 경계」(`:62`)가 일부만 맡는다 | `grep -n -E '^## (목표\|입력\|유효 결정\|쓰기 범위\|금지\|완료 증거)$' .claude/skills/delegate-first/templates/order.md \| wc -l`이 6이다. `bash scripts/test-delegate-scripts.sh`의 「6칸 누락」 케이스가 `close-task.sh` exit 1을 낸다 |
| I-02 | 요구 ID별 증거(파일 존재는 완료가 아니다) | RI `integrated-insights.md` §3 ②·§5 · HQ `scripts/check_delivery.py` L101 | adopt | `SKILL.md:53`의 재현 규칙은 핵심 주장 1건 기준이고 요구별 상태가 없다. 위임 로그 결과 칸(`delegation-log.md:5`)도 건별 한 값이다 | `bash scripts/test-delegate-scripts.sh`의 「`unverified` 잔존」 케이스가 `close-task.sh` exit 1을 낸다 |
| I-03 | 검수자가 같은 요구 ID 집합을 독립 판정(개념만) | HQ `scripts/check_delivery.py` L125-126 · HQ `HQ-TEAM-OPERATING-CONTRACT.md` 항목 5 | adopt | `SKILL.md:39-40`의 4·5단계는 ID 집합 일치를 요구하지 않는다. 검수가 일부 항목만 보고 통과시킬 수 있다 | 같은 테스트의 「검수 ID 집합 불일치」 케이스가 exit 1을 낸다 |
| I-04 | 참고 문서 분류(R/G/S/H)와 활성 결정 검색 경로 | RI `integrated-insights.md` §3 ①·§4 표 · HQ `HQ-TEAM-OPERATING-CONTRACT.md` 항목 3 | adopt | `README.md:5`는 파일별 소유 선언만 있고 활성 결정 색인이 없다. `BACKLOG.md:8`은 해결된 항목을 이력으로 같은 파일에 남긴다. 낡은 항목이 현재 규칙처럼 전달될 수 있다 | `grep -c '\| active \|' docs/decisions.md`가 7 이상이다. 「H 문서 참조」 케이스가 `close-task.sh` exit 1을 낸다 |
| I-05 | 조건부 리뷰(변경 성격별 트리거) | HQ `HQ-TEAM-OPERATING-CONTRACT.md` 「검수 단계」 · HQ `PORTING.md` 「실제 작업 방법」 | adopt | `SKILL.md:83-91`의 fable 트리거 5종은 판정 유형 기준이다. 변경 성격(훅·scripts·.githooks)에 따른 리뷰 기준은 없다. 규칙 `subagent-model-routing.md:24`는 리뷰 1차를 작업 유형으로만 정한다 | 「트리거 y인데 검수 행 없음」 케이스가 `close-task.sh` exit 1을 낸다. 훅 변경 diff에서 `TASK.md` 보안 트리거가 y로 적혀 있는지 `reviewer-high`가 대조한다 |
| I-06 | 위임하지 않는 경우(과잉 위임 경계) | RI `integrated-insights.md` §2·§4 「보류」 행 | adopt | `SKILL.md:14-15`는 예외를 단건 읽기와 단일 검증으로만 둔다. 소규모 수정과 병렬화 기준이 없다 | `grep -n 'When not to delegate' .claude/skills/delegate-first/SKILL.md`가 1건이다. `reviewer-high`가 청사진 §8 표와 행을 대조한다 |
| I-07 | 사용자 진입점 스킬 | HQ `PORTING.md` 「구조와 책임」 진입점 행 | connect | 연결 지점은 `SKILL.md:29-41`의 흐름 체크리스트다. 2단계와 3단계 사이에 「발주 작성」을 더한다. 새 진입점 스킬은 만들지 않는다 | `sed -n 29,45p .claude/skills/delegate-first/SKILL.md`에 「발주 작성」 단계가 있다 |
| I-08 | 역할·실행자 registry | HQ `PORTING.md` 「구조와 책임」 역할 행 | connect | 연결 지점은 `agents/*.md` frontmatter와 훅의 `TIER_EXPECTED_MODEL`(`enforce-subagent-model.cjs:137`)·`TIER_EXPECTED_EFFORT`(`:161`)다. lint Check A가 이미 대조한다. registry JSON은 만들지 않는다 | `python3 scripts/lint-delegate-first.py --strict`가 PASS다 |
| I-09 | 기술 부채 registry | HQ `docs/guides/hq-team/README.md` 「기술 부채」 | connect | 연결 지점은 `BACKLOG.md`다. 우선순위와 상태가 이미 있고 재개 조건은 B-04(`:127-141`)에만 「착수 트리거」로 있다. 미해결 항목 서식에 「재개 조건」을 보강한다 | `grep -c '재개 조건' BACKLOG.md`가 미해결 항목 수 이상이다 |
| I-10 | Principal·역할 버전 | HQ `HQ-TEAM-OPERATING-CONTRACT.md` 항목 1 | skip | 메인 세션의 역할은 `SKILL.md:12`와 규칙 `subagent-model-routing.md:6-7`이 고정한다. 역할 핀은 `agents/*.md`와 훅 map(`enforce-subagent-model.cjs:137-175`)이 강제한다. 버전은 git이 관리한다 | 해당 없음 |
| I-11 | `hq_contract.py` 입력 해시 snapshot | HQ `PORTING.md` 「구조와 책임」 검사 도구 행 | skip | `REFS.md`의 `경로@sha`가 같은 목적을 가진다. 판정은 `SKILL.md:53`의 재현으로 한다. `gotchas.md:64`가 git이 가진 이력을 따로 만들지 말라는 교훈을 적는다 | 해당 없음 |
| I-12 | `hq_ledger.py` 해시 체인 원장 | HQ `docs/guides/hq-team/README.md` 「일반 실행」 7 | skip | 위임 로그 7열이 원장이다(`delegation-log.md:5`, `lint-delegate-first.py:87-88`·`:940-960`). flock은 POSIX 전제이고 변조 탐지는 git 이력이 맡는다 | 해당 없음 |
| I-13 | postmortem 서식 | HQ `docs/guides/hq-team/README.md` 「Postmortem」 | skip | `gotchas.md:1-3`이 증상·원인·복구·재발 방지 한 줄씩의 서식과 착수 시 재읽기를 이미 요구한다 | 해당 없음 |
| I-14 | 번역·Medium 절차 | HQ `PORTING.md` 「구조와 책임」 자료/학습 행 | skip | 이 레포는 스킬·tier·훅으로 구성되고(`README.md:3`) 번역·Medium 작업이 없다 | 해당 없음 |
| I-15 | 품질·예산 5축 gate | HQ `HQ-TEAM-OPERATING-CONTRACT.md` 항목 6 · RI `integrated-insights.md` §3 ⑥ | defer | 위임 로그 7열에 토큰·비용 칸이 없고(`lint-delegate-first.py:87`) 계측 수단이 없다. 필요한 실측은 서브에이전트 전사에서 토큰을 집계할 수 있는지다 | 전사 `.jsonl`의 usage 필드로 한 작업의 토큰을 합산하는 스크립트가 가능한지 시험한다 |
| I-16 | 측정 항목(재설명·누락 요구·재요청, 시간·토큰) | RI `integrated-insights.md` §3 ⑥ · RI `insights-and-application.md` 「한 번만 해볼 실험」 | adopt | 이 레포에는 위임 효과를 재는 기록이 없다. 시간과 토큰은 I-15 때문에 수기 값 또는 「계측 수단 없음」으로 둔다 | `grep -c -E '^(재설명 횟수\|누락 요구 수\|재요청 횟수\|시간\|토큰):' .delegate/20261030-delegate-first-v2/PROGRESS.md`가 5다 |
| I-17 | MetaEnsemble·원문 예제 설치 | RI `integrated-insights.md` §4 「보류」 행 · HP §3 | skip | 지시서가 금지한다. 이 레포의 구성은 로컬 파일과 훅이다(`README.md:3`) | 해당 없음 |
| I-18 | 저자 자체 평가 수치(예산 포함 통과율 등) | RI `integrated-insights.md` §2 | skip | 저자 평가이고 재현하지 않았다. 청사진 §1 원칙 P7과 §10 항목 3이 비수입을 적는다 | 해당 없음 |

## 4. 다른 자료와 결합한 지점

Youssef 루프 자료와 사용자 결정 D1~D7을 이 자료에 섞은 곳이다.

| # | 결합 요소 | Ilyas 쪽 | 결합한 자료 | 결합 방식 | 충돌·이탈 |
|---|---|---|---|---|---|
| X1 | 발주문 「완료 증거」와 검사자 기준 | I-01·I-02 | Youssef 가드레일 1(RY `JAVA21-HARNESS-LOOP-GUARDRAILS-2026-09.md`) | 발주문의 요구 ID별 증거와 `TASK.md`의 검사자 pass/fail 기준을 같은 ID로 잇는다 | 충돌 없음 |
| X2 | ID별 판정과 실패 정책 | I-03 | Youssef 실패 정책(RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5) + 이 레포 사다리(`SKILL.md:57-70`) | 같은 ID가 두 번 실패하면 자동 재시도를 멈추고 상향을 판정한다 | Youssef는 두 번째 실패에서 정지를 요구하고 사다리는 상향한다. 청사진 결정 D12가 둘을 합쳤다 |
| X3 | 활성 결정과 실패 접근 | I-04 | Youssef 가드레일 2 | 유효한 결정은 `docs/decisions.md`에, 시도했다 실패한 접근은 `PROGRESS.md`의 `Do Not Repeat`에 둔다. `[promote]` 표시로 이어 준다 | 충돌 없음 |
| X4 | 조건부 리뷰와 강제 수단 | I-05 | 청사진 결정 D8(D4 대체) | 트리거 충족 여부를 `close-task.sh`가 사후 검사한다. 훅은 발주문을 보지 않는다 | HQ 계약은 새 훅을 추가하지 않는다고 적는다(HQ `HQ-TEAM-OPERATING-CONTRACT.md` 「사용 진입점」 2문단). 결정 D8로 이 레포도 발주 계약 훅을 만들지 않는다 |
| X5 | 작업 단위 문서 위치 | I-01·I-04 | 사용자 D2·D3 | HQ의 packet 방식 대신 프로젝트 안 `.delegate/<slug>/`를 쓰고 기본은 gitignore다 | HQ는 packet을 추적 대상으로 둔다. 이 레포는 승격한 문서만 추적한다 |
| X6 | 측정 기록 위치 | I-16 | 사용자 D2 | 위임 로그 7열을 늘리지 않고 `PROGRESS.md`의 측정 절에 둔다 | 위임 로그의 7열 스키마는 lint가 강제하므로 열을 더하지 않는다 |
| X7 | 모델·effort 라우팅 | HQ `PORTING.md` 「적용 전에 알아야 할 경계」(라우팅은 이식 기본값이 아니다) | 이 레포 B-11·B-12·B-18 | 경계 문구를 그대로 지킨다. 이 레포의 라우팅은 이 레포에 설치된 tier 핀으로 따로 정한다 | 충돌 없음 |

## 5. adopt 구현 계획

| 판정 | 청사진 절 | 재구축 단계 | 담당 tier |
|---|---|---|---|
| I-01 | [§4 발주문 규격](../blueprint/delegate-first-v2.md#4-발주문-규격) | P2, P10 | `executor-max`, `executor-high` |
| I-02 | [§2 위임 흐름](../blueprint/delegate-first-v2.md#2-위임-흐름) · [§7 강제 장치](../blueprint/delegate-first-v2.md#7-강제-장치) | P5 | `executor-max` |
| I-03 | [§2 위임 흐름](../blueprint/delegate-first-v2.md#2-위임-흐름) · [§7 강제 장치](../blueprint/delegate-first-v2.md#7-강제-장치) | P5 | `executor-max` |
| I-04 | [§5 참고 문서 분류](../blueprint/delegate-first-v2.md#5-참고-문서-분류) | P13 | `executor-med` |
| I-05 | [§3 템플릿 골격](../blueprint/delegate-first-v2.md#3-작업-디렉터리-규격) · [§7 강제 장치](../blueprint/delegate-first-v2.md#7-강제-장치) | P5, P15 | `executor-max`, `reviewer-high` |
| I-06 | [§8 위임하지 않는 경우](../blueprint/delegate-first-v2.md#8-위임하지-않는-경우) | P10 | `executor-high` |
| I-16 | [§3 템플릿 골격](../blueprint/delegate-first-v2.md#3-작업-디렉터리-규격) | P20 | 메인 |

### 작업 한 건 적용 계획

청사진 결정 D8로 B-19를 만들지 않는다. 그래서 이 계획의 적용 대상은 메인이 다시 정한다. 아래 계약과 측정 항목은 B-19를 대상으로 쓴 원래 안이다. 계약 → 실행 → 별도 검수 → 요구별 증거 순서는 새 대상에도 같다.

계약(발주문 6칸)

| 칸 | 내용 |
|---|---|
| 목표 | tier 호출(`explorer-low` 제외)에 `CONTRACT:` 줄이 없거나 형식·이름이 어긋나면 훅이 exit 2를 낸다 |
| 입력 | `enforce-subagent-model.cjs`의 `passWithNameCheck` 구간, `scripts/smoke-hook.sh`, 청사진 §4·§7 |
| 유효 결정 | B-18 이름 규약은 유지한다. 이름 필수·금지는 어떤 break-glass로도 우회되지 않는다 |
| 쓰기 범위 | `.claude/skills/delegate-first/hooks/enforce-subagent-model.cjs`, `scripts/smoke-hook.sh` |
| 금지 | 전역 훅 사본(`~/.claude`) 수정, commit, push, B-11·B-12 분기의 의미 변경 |
| 완료 증거 | 아래 요구 ID별 표 |

요구 ID별 증거

| ID | 수용 기준 | 증거 |
|---|---|---|
| R1 | `CONTRACT:` 줄 없는 tier 호출은 exit 2 | smoke 케이스가 구현 전 실패, 구현 후 통과 |
| R2 | 줄의 `<name>`이 Agent `name`과 다르면 exit 2 | 같음 |
| R3 | `explorer-low`는 줄이 없어도 exit 0 | 같음 |
| R4 | 형식을 지킨 호출은 기존 정상 호출과 같은 exit 0 | 기존 104건이 그대로 통과 |
| R5 | 변이 게이트가 B-19 분기를 끈 변이본에서 실패 | `bash scripts/test-smoke-nonvacuous.sh` 출력 |

검수는 `reviewer-high`가 한다. 검수 발주문에는 `TASK.md`의 R1~R5를 직접 주고 구현 반환문의 ID 목록을 근거로 쓰지 않게 한다. 검수 반환의 ID 집합이 R1~R5와 다르면 무효다.

측정 항목

| 항목 | 기록 위치 | 비교 기준 | 한계 |
|---|---|---|---|
| 메인이 같은 내용을 다시 설명한 횟수 | `PROGRESS.md` 측정 절 | B-18 작업의 반환 대화(전사) | 두 작업의 난이도가 달라 우열로 일반화하지 않는다 |
| 누락된 요구 수 | 검수 반환 | 같음 | 같음 |
| 재요청 횟수 | `PROGRESS.md` 회차 표 | 같음 | 같음 |
| 시간·토큰 | `PROGRESS.md` 측정 절 | 없음 | 계측 수단이 없으면 「계측 수단 없음」으로 적는다 |

## 6. 미검증으로 남긴 것

| # | 항목 | 내용 |
|---|---|---|
| U1 | 원문 대조 | 원문·번역·역주를 읽지 않았다. 인사이트 6개의 원문 근거는 RI의 정리에 의존한다 |
| U2 | HQ 도구 구현 | `hq_contract.py`와 `hq_ledger.py`를 읽지 않았다. skip 판정은 PORTING 표와 `check_delivery.py` 구간에 근거한다 |
| U3 | 다른 PC·OS | `close-task.sh`와 `new-task.sh`는 macOS의 bash로만 설계했다. 다른 환경은 시험하지 않았다 |
| U4 | 효과 | 6칸 계약과 요구 ID 검사가 재설명·재요청을 줄이는지 측정 전이다. 효과가 없으면 청사진 §1 원칙 P6에 따라 규칙을 줄인다 |
| U5 | 위임 이득 | 저자 평가는 단일 컨텍스트 작업에서 위임의 이득을 입증하지 않는다. 이 레포의 과잉 위임 위험은 I-06 판정으로만 완화했다 |
| U6 | 훅 end-to-end | smoke는 입력 JSON 시험이다. 실제 하네스 경로의 차단은 전파 뒤 별도 실측이 필요하다(청사진 §10 항목 8) |
