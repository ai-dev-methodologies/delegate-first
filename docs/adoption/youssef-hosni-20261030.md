# Youssef Hosni 루프 자료 적용 판정

이 문서는 Youssef Hosni 루프 엔지니어링 자료의 delegate-first 적용 판정(항목별 adopt·skip·defer와 그 근거)을 소유한다. 설계 결과는 [v2 청사진](../blueprint/delegate-first-v2.md)이 소유하고, 이 문서는 청사진의 각 요소가 왜 채택됐는지를 적는다. 원문 문장은 복사하지 않고 경로와 절로 인용한다.

## 1. 읽은 자료

| 약칭 | 저장소 | 읽은 경로 | 기준 SHA | 현재 main HEAD |
|---|---|---|---|---|
| RY | research | `docs/references/claude-loop-engineering/README.md`, `docs/CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md`, `docs/JAVA21-HARNESS-LOOP-GUARDRAILS-2026-09.md`, `docs/loop-harness-rules-2026-09/REPORT.md` | 30962a60380ba43a27e933337858752d906a4716 | 949bf5619e3cf19d00f216ad808bc782909fb2af |
| HY | HQ | `coordination/handoffs/2026-10-30-youssef-hosni-apply-to-project-prompt.md`(지시서) | 5c4b54af9a49a0849a6c71711dbdeebddc688734 | 385c873d27e68a682ce6e309d339ffbb1ea59c37 |

- research HEAD는 `gh api repos/ai-dev-methodologies/ai-dev-methodologies-research/git/ref/heads/main`으로, HQ HEAD는 HQ 클론에서 `git ls-remote origin refs/heads/main`으로 확인했다.
- research HEAD는 기준 SHA보다 1커밋 앞선다(`gh api .../compare/<기준>...<HEAD>`의 `ahead_by`가 1). 읽은 네 파일의 blob SHA는 두 시점에서 같다.
- HQ HEAD는 기준 SHA보다 1커밋 앞선다. 그 1커밋은 Ilyas 지시서 추가이고 Youssef 지시서 파일은 두 SHA 사이에 변경이 없다.
- 로컬 HQ 클론의 `main` 브랜치는 `73f8f208`로 원격과 다르다. 모든 읽기는 SHA를 지정해 했다.
- 읽지 않은 자료는 자료 A의 원문·번역(`original-en.md`, `ko.md`)과 자료 B 전체다. 자료 B는 이번 범위가 아니라 §3 Y-17에 보류 한 행으로만 둔다.

## 2. 근거의 신뢰 수준

| 구분 | 내용 | 이 문서에서의 취급 |
|---|---|---|
| 저자 주장 | 루프 6부품, 준비 5질문, 권한 사다리, maker-checker, 실패 정책(RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §1~§5) | 구조만 참고한다. 저자 1인의 처방형 글이고 검증된 효과가 없다(RY `README.md` 「이 자료를 쓸 때」) |
| 미검증 문법 | `/loop`·`/goal` 명령과 제품 UI 서술 | 사실로 쓰지 않는다 |
| 후속 조사 | 반복 한도 수치에 측정 근거가 없다는 결론(RY `REPORT.md` §2 Q4) | 한도 숫자를 기본값으로 복사하지 않는다 |
| 이 문서의 판단 | 판정표의 근거 열 | 이 레포 파일의 줄 번호로 확인할 수 있는 것만 적는다 |

## 3. 판정표

판정별 개수는 adopt 7, skip 8, defer 3이다. 합계 18행이다. 지시서의 판정 범주에 connect가 없어 쓰지 않았다. 「근거」 열의 skip 행은 이 레포의 규칙 파일과 줄을 가리킨다.

| # | 항목 | 출처 경로 + 절 | 판정 | 근거 | 검증 방법 |
|---|---|---|---|---|---|
| Y-01 | 회차 간 상태 파일 `PROGRESS.md` | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §4 「PROGRESS.md 템플릿」 | adopt | 작업 단위 상태 파일이 없다. 위임 로그는 위임 1건당 완료 후 한 행이다(`delegation-log.md:5`). 회차 사이 상태는 메인 대화에만 남는다(`SKILL.md:43`의 0단계도 진행 중 위임을 전사에서 복원한다) | `bash scripts/test-delegate-scripts.sh`가 `new-task.sh`의 생성 결과에서 `PROGRESS.md`의 필수 절 10개를 확인한다. `grep -c '^## ' .claude/skills/delegate-first/templates/PROGRESS.md`가 10이다 |
| Y-02 | `Do Not Repeat`(해소된 항목은 지운다) | RY `JAVA21-HARNESS-LOOP-GUARDRAILS-2026-09.md` 「가드레일 2」 | adopt | `gotchas.md:1-3`은 레포 전체의 교훈을 착수 시 읽게 한다. 작업 회차 단위로 실패한 접근을 다음 발주에 전달하는 곳이 없다. `SKILL.md:67`은 프롬프트 보강만 요구한다 | `grep -n '^## Do Not Repeat' .claude/skills/delegate-first/templates/PROGRESS.md .claude/skills/delegate-first/templates/order.md`가 2건이다 |
| Y-03 | 검사자에게 항목별 pass/fail 기준을 준다 | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5 · RY `JAVA21-HARNESS-LOOP-GUARDRAILS-2026-09.md` 「가드레일 1」 | adopt | `SKILL.md:40`의 판정은 pass·re-delegate·escalate 한 값이다. `prompt-templates.md:9-26`의 조사용 템플릿도 완료 기준이 체크박스 목록이라 부분 점수 금지와 누락 가정 금지가 없다 | `grep -n '^## 검사자 pass/fail 기준' .claude/skills/delegate-first/templates/TASK.md`가 1건이다. 샌드박스 테스트의 「검사자 기준 ID가 요구 ID에 없음」 케이스가 `close-task.sh` exit 1을 낸다 |
| Y-04 | 실패 정책 Retry/Escalate/Stop | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5 「검증 실패 시 정책」 | adopt | `SKILL.md:69-70`은 같은 원인의 두 번째 실패에서 상향하고 세 번째에서 멈춘다. 검사 항목 단위 카운터와, 쓰기 범위·금지 경로 위반 시 즉시 정지 규칙이 없다 | 샌드박스 테스트의 「`attempts_total`이 `max_attempts_total` 초과」 케이스가 `close-task.sh` exit 1을 낸다 |
| Y-05 | 시도 횟수 4필드 표기 | RY `REPORT.md` §2 Q4 「반드시 해소할 모호성」 | adopt | `SKILL.md:69-70`의 「twice」와 「3rd」는 총 시도 수와 재시도 수를 구분하지 않는다. 후속 조사가 지적한 모호성과 같은 형태다 | `grep -c -E '^(attempts_total\|max_attempts_total\|retries_max\|stop_on):' .claude/skills/delegate-first/templates/PROGRESS.md`가 4다 |
| Y-06 | 최소 구조 `TASK.md`·`outputs/` | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §4 「최소 루프 구조」 | adopt | 작업 목표와 범위가 발주 프롬프트 안에만 있다(`prompt-templates.md:52-70`). 작업이 끝나면 발주 내용을 다시 볼 파일이 없다 | `new-task.sh x-test` 뒤 `find .delegate/*x-test -type f`에 `TASK.md`·`REFS.md`·`PROGRESS.md`가 있다 |
| Y-07 | 쓰기 범위 사후 대조(검사 단계의 금지 파일 미수정 확인) | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5 「Checker phase」 | adopt | 쓰기 범위는 프롬프트의 「경계」 문장뿐이다(`prompt-templates.md:58`). 위반을 기계가 보지 못한다 | 샌드박스 테스트의 「범위 밖 파일 변경」 케이스가 `close-task.sh` exit 1을 낸다 |
| Y-08 | `LOOP_INSTRUCTIONS.md`(회차 절차 문서) | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §4 | skip | 회차 절차는 `SKILL.md:29-55`의 흐름 체크리스트와 단계 설명이 맡는다. 스킬이 전역에 있어(결정 D1) 프로젝트마다 사본이 필요 없다. 안정된 지시와 바뀌는 상태를 분리한다는 원칙은 이 구조가 이미 지킨다 | 해당 없음 |
| Y-09 | 루프 6부품 | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §1 | skip | 이 레포의 5단계가 대응한다. 시작은 사용자 호출(`SKILL.md:8`), 행동은 위임(`:49`), 검증은 리뷰(`:53`), 판단은 판정(`:55`)이다. JDK 하네스 채택 문서도 같은 이유로 비채택했다(RY `JAVA21-HARNESS-LOOP-GUARDRAILS-2026-09.md` 「채택하지 않은 것과 그 이유」) | 해당 없음 |
| Y-10 | 준비 5질문 | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §2 | skip | 이 스킬은 명시 호출 전용이고 반복 루프가 아니다(`SKILL.md:8`). 위임 필요성 판정은 청사진 §8과 Ilyas 판정 I-06이 대신한다 | 해당 없음 |
| Y-11 | 권한 사다리 6단계 | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §3 | skip | 권한은 tier 정의의 도구 제한으로 이미 고정된다. `reviewer-high`와 `judge-max`는 Write·Edit이 없다(`routing-matrix.md:26`). 쓰기 범위는 Y-07이 맡는다 | 해당 없음 |
| Y-12 | 작성과 검사의 단계 분리 | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5 | skip | 독립 검증을 별도 에이전트에게 맡기는 규칙이 이미 있다(규칙 `subagent-model-routing.md:29-30`, `SKILL.md:39-40`). 새로 필요한 것은 기준 제공(Y-03)뿐이다 | 해당 없음 |
| Y-13 | 반복 한도 수치(회차당 횟수·시간·수정 파일 수) | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §5 「반복 한도」 · RY `REPORT.md` §2 Q4 | skip | 후속 조사가 측정 근거가 있는 수치를 찾지 못했다. 한도 값은 작업마다 `TASK.md`가 정한다. 이 레포의 기존 숫자는 `SKILL.md:69-70`이 소유한다 | 해당 없음 |
| Y-14 | `/loop`·`/goal` 문법과 스케줄링 | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §6 · RY `README.md` 「이 자료를 쓸 때」 | skip | 미검증 문법이다. 이 스킬은 자동 스케줄 없이 명시 호출만 받는다(`SKILL.md:8`) | 해당 없음 |
| Y-15 | 첫 루프 실패 10패턴과 신뢰 요소 8개 | RY `CLAUDE-LOOP-ENGINEERING-REFERENCE-2026-09.md` §7 | skip | 개별 행으로 흡수했다. 상태 파일은 Y-01, 검증 기준은 Y-03, 정지 조건은 Y-04, 좁은 쓰기 권한은 Y-07이다. 감사 기록은 위임 로그가, 사람 검토 경로는 세 번째 실패 시 사용자 보고(`SKILL.md:70`)가 맡는다 | 해당 없음 |
| Y-16 | 계층화된 정지 규칙(벽시계·토큰·무진전 탐지) | RY `REPORT.md` §2 Q4 | defer | 벽시계와 토큰 한도를 에이전트 밖에서 강제할 수단이 없다. 훅은 Agent 호출 시점만 본다. 필요한 실측은 서브에이전트의 실행 시간과 토큰을 전사에서 집계할 수 있는지다 | 전사 `.jsonl`에서 한 작업의 시간과 토큰을 합산하는 시험 |
| Y-17 | 자료 B: 후보 모델 평가 방법 | HY §0 자료 B | defer | 이번 범위가 아니다. 후보 모델 실험에는 유료 호출이 필요해 지시서가 금지한다(HY §3). 필요한 실측은 같은 작업과 수용 기준으로 tier 모델을 비교하는 설계다 | 실험 설계 문서를 먼저 쓴다. 호출은 사용자 승인 뒤 한다 |
| Y-18 | 훅 차단의 end-to-end 실효 | RY `REPORT.md` §5 경고 1·9 | defer | 공식 사양상 차단되는 동작이 현장에서 무시된다는 보고가 있고 패치 여부를 확인하지 못했다. 이 레포의 강제 장치는 PreToolUse 훅에 의존한다. Stop 훅의 연속 차단 상한은 Stop 훅 한정이라 직접 걸리지 않는다 | BACKLOG B-08의 4단계 실측(음성 대조 → 양성 → 전사 값 대조 → 사후 음성)을 훅 전파에도 적용한다 |

## 4. 다른 자료와 결합한 지점

Ilyas 자료와 사용자 결정 D1~D7을 이 자료에 섞은 곳이다.

| # | 결합 요소 | Youssef 쪽 | 결합한 자료 | 결합 방식 | 충돌·이탈 |
|---|---|---|---|---|---|
| Z1 | 검사자 기준과 요구 ID | Y-03 | Ilyas I-02·I-03 | 검사자 기준 각 항목을 요구 ID에 연결한다. 검수는 `TASK.md`의 같은 ID 집합 전체를 판정한다 | 충돌 없음 |
| Z2 | 실패 정책과 사다리 | Y-04 | 이 레포 사다리(`SKILL.md:57-70`) | 두 번째 실패에서 자동 재시도를 멈추고 상향을 판정하며 세 번째 실패와 범위 위반에서 정지한다 | Youssef는 두 번째 실패에서 정지를 요구하고 사다리는 상향한다. 청사진 결정 D12가 둘을 합쳤다 |
| Z3 | `Do Not Repeat`와 활성 결정 | Y-02 | Ilyas I-04 | 실패한 접근은 `PROGRESS.md`, 유효한 결정은 `docs/decisions.md`에 둔다. `[promote]`로 잇는다 | 충돌 없음 |
| Z4 | 작업 디렉터리 구조 | Y-01·Y-06 | 사용자 D2·D3 | Youssef의 파일 4개 구조에서 `LOOP_INSTRUCTIONS.md`를 빼고 `REFS.md`와 `orders/`를 더한다. 기본은 gitignore다 | Youssef의 구조는 루프 전용이다. 위임 발주문이라는 단위는 사용자 결정이 더했다 |
| Z5 | 쓰기 범위 검사 시점 | Y-07 | 사용자 D4 | Youssef의 회차 안 검사 단계를 작업 종료 시점의 스크립트로 옮긴다 | 도중 차단이 아니라 사후 탐지다. 청사진 §10 항목 1·2가 한계를 적는다 |
| Z6 | 시도 횟수 값 | Y-05·Y-13 | HQ 운영 계약 | 필드만 가져오고 값은 작업별로 정한다 | HQ 운영 계약도 packet별 횟수를 따른다(HQ `HQ-TEAM-OPERATING-CONTRACT.md` 항목 4) |

## 5. adopt 구현 계획

| 판정 | 청사진 절 | 재구축 단계 | 담당 tier |
|---|---|---|---|
| Y-01 | [§3 작업 디렉터리 규격](../blueprint/delegate-first-v2.md#3-작업-디렉터리-규격) | P2 | `executor-max` |
| Y-02 | [§3 작업 디렉터리 규격](../blueprint/delegate-first-v2.md#3-작업-디렉터리-규격) | P2 | `executor-max` |
| Y-03 | [§3 작업 디렉터리 규격](../blueprint/delegate-first-v2.md#3-작업-디렉터리-규격) · [§2 위임 흐름](../blueprint/delegate-first-v2.md#2-위임-흐름) | P2, P10 | `executor-max`, `executor-high` |
| Y-04 | [§2 실패 정책](../blueprint/delegate-first-v2.md#실패-정책) | P5 | `executor-max` |
| Y-05 | [§2 실패 정책](../blueprint/delegate-first-v2.md#실패-정책) | P2 | `executor-max` |
| Y-06 | [§3 작업 디렉터리 규격](../blueprint/delegate-first-v2.md#3-작업-디렉터리-규격) | P2 | `executor-max` |
| Y-07 | [§7 close-task.sh](../blueprint/delegate-first-v2.md#close-tasksh) | P5 | `executor-max` |

구현 순서는 샌드박스 테스트 `scripts/test-delegate-scripts.sh`를 먼저 쓰고 실패를 확인한 뒤 스크립트를 구현한다. 각 케이스가 실제로 실패를 재현하는지(비공허성)도 테스트가 확인한다.

## 6. 미검증으로 남긴 것

| # | 항목 | 내용 |
|---|---|---|
| U1 | 효과 | 상태 파일과 `Do Not Repeat`가 같은 실패의 반복을 줄이는지 측정 전이다. 후속 조사도 단발 작업 대비 루프의 이득을 확인하지 못했다(RY `REPORT.md` §5 경고 6) |
| U2 | 사다리 합성 | 두 번째 실패에서 상향을 판정하는 합성안은 이 문서의 제안이다. 어느 쪽이 실패 비용을 줄이는지 비교하지 않았다 |
| U3 | 원문 대조 | 원문과 번역을 읽지 않았다. 구조는 RY의 정리본에 의존한다 |
| U4 | 자료 B | 읽지 않았다. 모델 평가는 이번 범위가 아니다 |
| U5 | 훅 실효 | Y-18의 end-to-end 실측은 전파 뒤에 한다 |
| U6 | 계측 | 시간·토큰 집계 수단이 없다(Y-16) |
