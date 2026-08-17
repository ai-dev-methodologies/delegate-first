# Delegation Log

`SKILL.md` 3단계가 요구하는 위임 로그. 위임 **직후** 한 줄씩 append 한다(사후 일괄 기록 금지 — 사후 기록은 실제 라우팅이 아니라 기억을 적는다).

스키마: `날짜 | agent | role(한 줄) | model | effort | 실행경로 | 결과`

- `effort`: Agent 툴 즉석 호출은 effort 지정이 불가하므로 `(default)`로 적는다. tier 에이전트/Workflow `agent()`/`codex exec` 경로는 실제 값을 적는다.
- `실행경로`: `Agent(tier)` / `Agent(ad-hoc)` / `Workflow agent()` / `codex exec`
- `결과`: `pass` / `re-delegate` / `escalate` — 리뷰(4단계) 후에 채운다.

이 경로는 프로젝트 파라미터다 — 다른 경로를 쓰는 프로젝트는 `CLAUDE.md`에 명시한다(README 참고).

| 날짜 | agent | role | model | effort | 실행경로 | 결과 |
|---|---|---|---|---|---|---|
| | | | | | | |
