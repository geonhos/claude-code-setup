# Agent Logging Protocol

모든 에이전트는 실행 전/후에 로그를 기록합니다.

## 로그 저장 경로

```
./logs/{agent-name}_{YYYYMMDD_HHMMSS}.log
```

## 로그 형식

### 실행 시작 로그
```
================================================================================
[START] {agent-name}
Time: {ISO timestamp}
Task: {task description}
Input: {brief input summary}
================================================================================
```

### 실행 완료 로그
```
================================================================================
[END] {agent-name}
Time: {ISO timestamp}
Duration: {elapsed time}
Status: {success|failed|partial}
Output: {brief output summary}
================================================================================
```

## 로그 레벨

| Level | 용도 |
|-------|------|
| INFO | 일반 실행 정보 |
| WARN | 경고 (진행 가능) |
| ERROR | 오류 (실패) |
| DEBUG | 상세 디버그 정보 |

## 사용법

에이전트 실행 시:
```bash
# 로그 디렉토리 생성
mkdir -p ./logs

# 로그 파일명 생성
LOG_FILE="./logs/${AGENT_NAME}_$(date +%Y%m%d_%H%M%S).log"

# 시작 로그
echo "[START] ${AGENT_NAME} - $(date -Iseconds)" >> "$LOG_FILE"

# ... 작업 수행 ...

# 종료 로그
echo "[END] ${AGENT_NAME} - Status: ${STATUS}" >> "$LOG_FILE"
```

## 필수 기록 항목

1. **시작 시간**: 에이전트 호출 시점
2. **입력 요약**: 전달받은 태스크/프롬프트 요약
3. **주요 액션**: 수행한 주요 작업 목록
4. **종료 시간**: 에이전트 완료 시점
5. **결과 상태**: success / failed / partial
6. **출력 요약**: 생성된 결과물 요약
