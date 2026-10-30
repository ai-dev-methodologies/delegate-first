# PROGRESS <slug>
## 현재 상태
## 회차
order 칸에는 발주문 파일 이름(NN-<name>, 확장자 없이)을 적는다. 읽기 전용 tier(explorer-low·reviewer-high·judge-max)의 반환은 메인이 이 표의 반환 칸에 옮긴다. close-task.sh는 order 칸이 발주문 이름과 정확히 같고 반환 칸이 비어 있지 않은 행이 이 표에 있을 때만 그 발주문의 반환물 짝 검사를 면제한다. 반환 칸이 공백(전각 공백 포함)·`-`·`—`·`없음`·`(대기)`·`대기`·HTML 주석만으로 이뤄지면 빈 칸으로 본다. 이 절은 `## 회차`부터 다음 `#`·`##` 헤딩 전까지다. 이 절 안의 `###` 이하 하위 절과 코드 펜스(```·~~~) 안의 행은 인정하지 않는다. 이 표 밖의 언급은 인정하지 않는다.
| 회차 | order | 반환 | R1 | R2 | 판정 |
|---|---|---|---|---|---|
## Open Items
## Blockers
## 사람 검토 필요
## 다음 회차
## Decisions Made
- D-1 <결정> [promote]
## Do Not Repeat
- <시도한 접근> / <실패 이유> / <회차>
## 시도 카운터
attempts_total: 0
max_attempts_total: <n>
retries_max: <n>
stop_on: same_check_failed_twice
## 측정
재설명 횟수: 0
누락 요구 수: 0
재요청 횟수: 0
시간: <값 또는 계측 수단 없음>
토큰: <값 또는 계측 수단 없음>
