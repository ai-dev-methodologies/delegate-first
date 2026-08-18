# Delegation Log

`SKILL.md` 3단계가 요구하는 위임 로그. 위임 **직후** 한 줄씩 append 한다(사후 일괄 기록 금지 — 사후 기록은 실제 라우팅이 아니라 기억을 적는다).

스키마: `날짜 | agent | role(한 줄) | model | effort | 실행경로 | 결과`

- `effort`: Agent 툴 즉석 호출은 effort 지정이 불가하므로 `(default)`로 적는다. tier 에이전트/Workflow `agent()`/`codex exec` 경로는 실제 값을 적는다.
- `실행경로`: `Agent(tier)` / `Agent(ad-hoc)` / `Workflow agent()` / `codex exec`
- `결과`: 일반 위임은 `pass` / `re-delegate` / `escalate` — 리뷰(4단계) 후에 채운다. 리뷰/게이트 위임(reviewer-high, judge-max 등)은 판정 요약을 자유 텍스트로 덧붙일 수 있다 — 예 `FIX-THEN-MERGE (Cancer 0, Polyp 6, Cigarette 10)`. 이 자유 텍스트 관례는 2026-08-18부터 실제로 쓰여 왔고(PR #1~#4), 개수(Cancer/Polyp/Cigarette, NF 등)는 감사 시점에 되짚어볼 근거로 유용해 문서를 실태에 맞춰 갱신했다 — 린터(`scripts/lint-delegate-first.py` Check B)는 `결과` 컬럼을 비어 있지 않은지와 `(리뷰 대기)` 누적 건수만 검사하며, 값 자체를 `pass`/`re-delegate`/`escalate`로 제한하지 않는다(자유 텍스트 관례와 일부러 맞춘 설계).

이 경로는 프로젝트 파라미터다 — 다른 경로를 쓰는 프로젝트는 `CLAUDE.md`에 명시한다(README 참고).

`model` 컬럼 관례: `(미지정)`은 훅 차단을 의도적으로 유발한 프로브(예: 훅 검증용 무model 호출)를, `(파라미터 생략)`은 `model` 파라미터를 넘기지 않고 tier 에이전트의 frontmatter 값을 그대로 적용받은 정상 호출을 뜻한다. `(파라미터 생략)`인 행은 이 컬럼만으로는 실제 적용 모델을 알 수 없다 — 실제 적용 모델은 `결과` 컬럼에 기록한다(예: "실제 haiku-4-5 적용 확인").

| 날짜 | agent | role | model | effort | 실행경로 | 결과 |
|---|---|---|---|---|---|---|
| 2026-08-18 | explorer-low | 훅 차단 프로브(의도적 model 미지정) | (미지정) | (default) | Agent(tier) | blocked-as-designed |
| 2026-08-18 | explorer-low | 정본 레포 잔존참조·링크 무결성 전수 조사 | haiku | low(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | claude-code-guide | CLAUDE_PROJECT_DIR·trust·frontmatter 키·model 우선순위 공식문서 확정 | sonnet | (default) | Agent(ad-hoc) | pass |
| 2026-08-18 | executor-med | settings.json 배선 + README·BACKLOG·로그 편집 | sonnet | medium(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | reviewer-high | PR#1 독립 리뷰(원문 보존·문서 정합성·훅 배선 적대 검증) | opus | high(frontmatter) | Agent(tier) | pass (Cancer 0, Polyp 8, Cigarette 5) |
| 2026-08-18 | executor-high | 리뷰 finding P1~P8·C1~C5 봉합 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | judge-max | PR#1 릴리스 게이트 최종 판정(적대 검증) | fable | max(frontmatter) | Agent(tier) | FIX-THEN-MERGE (Cancer 0, 신규 finding 8) |
| 2026-08-18 | executor-high | 릴리스 게이트 finding NF-1~NF-8 봉합 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | executor-high | B-06 해소(훅 pinned 목록 + routing-matrix 전제 + 문서 갱신) | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | reviewer-high | PR#2 훅 변경 독립 리뷰(강제력·스푸핑·정합성) | opus | high(frontmatter) | Agent(tier) | pass (Cancer 0, Polyp 3, Cigarette 3) |
| 2026-08-18 | judge-max | PR#2 릴리스 게이트(권한·강제장치 표면 적대 판정) | fable | max(frontmatter) | Agent(tier) | FIX-THEN-MERGE (Cancer 0, NF-A 필수) |
| 2026-08-18 | executor-high | PR#2 게이트 finding 합집합 봉합 + 스모크 스크립트 신설 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | executor-high | B-01·B-03 SKILL.md 규율 보강 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | reviewer-high | PR#3 스킬 본문 독립 리뷰 | opus | high(frontmatter) | Agent(tier) | FIX-THEN-MERGE (Polyp 3, Cigarette 3) |
| 2026-08-18 | judge-max | PR#3 릴리스 게이트 | fable | max(frontmatter) | Agent(tier) | FIX-THEN-MERGE (Cancer 0, NF 5) |
| 2026-08-18 | executor-high | 판정 반영 봉합(게이트안 채택) | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | executor-high | B-07+B-02 린터 구현 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | reviewer-high | PR#4 린터 독립 리뷰 | opus | high(frontmatter) | Agent(tier) | FIX-THEN-MERGE (Polyp 6, Cigarette 10) |
| 2026-08-18 | judge-max | PR#4 릴리스 게이트 | fable | max(frontmatter) | Agent(tier) | FIX-THEN-MERGE (Cancer 0, NF 5) |
| 2026-08-18 | executor-high | 린터 미탐 봉합 + 자체 테스트 신설 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | judge-max | PR#4 최종 head 재판정 | fable | max(frontmatter) | Agent(tier) | MERGE (Cancer 0, 후속 4) |
| 2026-08-18 | executor-high | 게이트 후속 finding 4건 마무리 | sonnet | high(frontmatter) | Agent(tier) | pass (리뷰에서 P-1 회귀 발견·봉합) |
| 2026-08-18 | reviewer-high | PR#5 후속 4건 독립 리뷰(헤더 변형 20종 전수) | opus | high(frontmatter) | Agent(tier) | FIX-THEN-MERGE (P-1 회귀 발견: 깨진 헤더 표가 통째로 미검사) |
| 2026-08-18 | executor-high | P-1 회귀 봉합(잔여 검사 + 양성 테스트 2건) | sonnet | high(frontmatter) | Agent(tier) | pass (test-lint 22/22, 비공허성 확인) |
| 2026-08-18 | executor-high | B-08 레포 쪽 규칙 예외 문구 작성 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | judge-max | PR#7 릴리스 게이트(전역 규칙 파급 적대 판정) | fable | max(frontmatter) | Agent(tier) | FIX-THEN-MERGE (F1 필수, F2~F6) |
| 2026-08-18 | executor-high | F1~F6 봉합 + REINSTALL §2 갱신 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | explorer-low | B-06 end-to-end 실측 양성 프로브(model 파라미터 없이 스폰) | (파라미터 생략) | low(frontmatter, 미기록) | Agent(tier) | pass (실제 haiku-4-5 적용 확인) |
| 2026-08-18 | executor-med | B-06 effort 적용 확인 프로브(model 없이 스폰) | (파라미터 생략) | medium(frontmatter) | Agent(tier) | pass (sonnet-5 + effort medium 확인) |
| 2026-08-18 | executor-high | B-06·B-08 증거 기록 + REINSTALL 결함 봉합 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | executor-high | B-11·B-09 구현 | sonnet | high(frontmatter) | Agent(tier) | pass |
| 2026-08-18 | explorer-low | B-12 named 스폰 프로브(name 동반, override 없음) | (파라미터 생략) | low(frontmatter, 미적용 관측) | Agent(tier) | pass (model=haiku 적용, effort 키 없음) |
| 2026-08-18 | executor-med | B-12 변수분리 프로브(named, override 없음) | (파라미터 생략) | medium(frontmatter, 미적용) | Agent(tier) | pass (effort=high로 관측 — named 스폰 effort 미적용 확정) |
| 2026-08-18 | executor-high | B-13/B-14 재설치 스크립트화 + 정본 제공목록 일반화 | sonnet | high(frontmatter) | Agent(tier) | pass (test-reinstall 12/12) |
