# TASK <slug>

## 목표(끝상태)
<활동이 아니라 끝상태를 한 문단으로>

## 기준 커밋
<new-task.sh가 git rev-parse HEAD로 채운다>

## 요구 ID와 수용 기준
| ID | 수용 기준 | 증거 종류 |
|---|---|---|
| R1 | <관찰 가능한 조건> | 명령 출력 / 경로@sha / diff |

## 쓰기 범위
- <레포 상대 경로 글롭, 한 줄에 하나>

## 금지
- <경로·명령·행동>

## 정지 조건
- max_attempts_total: <n>
- retries_max: <n>
- stop_on: same_check_failed_twice

## 검사자 pass/fail 기준
- C1 (R1): <PASS 조건. 부분 점수 없음>

## 리뷰 트리거
| 조건 | 해당 | 근거 |
|---|---|---|
| 훅·scripts·.githooks 변경(보안) | y/n | |
| 변경 200줄 초과 또는 새 인터페이스(구조) | y/n | |
| SKILL.md 5종 fable 트리거 | y/n | |
