# Agent Template

에이전트 작성 시 이 템플릿을 따릅니다.

## Frontmatter 표준

```yaml
---
name: agent-name
description: "1-2 sentence description. **Use proactively** when: keyword1, keyword2, keyword3."
model: sonnet  # sonnet | opus | haiku
---
```

## Description 형식

```
{역할 요약 (1문장)}. {주요 기능 (1문장)}.
**Use proactively** when: {트리거 키워드 나열}.

Examples:
<example>
Context: {상황 설명}
user: "{사용자 입력}"
assistant: "{에이전트 응답}"
<commentary>
{동작 설명}
</commentary>
</example>
```

## 필수 섹션

1. **Core Expertise** - 핵심 역량 목록
2. **The Iron Law** - 단일 비협상 규칙 (ALL CAPS)
3. **DO NOT** - 4-6개의 금지 항목 (체크박스 형식)
4. **Scope Boundaries** - DOES vs DOES NOT (해당되는 경우)
5. **Red Flags - STOP** - 경고 신호 (3-5개)
6. **Workflow Protocol** - 작업 절차
7. **Output Format** - 출력 형식 (JSON)
8. **Quality Checklist** - 품질 체크리스트

## 경계 정의 (Boundary Definitions)

모든 에이전트는 [Boundary Protocol](./boundary-protocol.md)을 따릅니다.

### The Iron Law 형식
```markdown
## The Iron Law
[단일 규칙을 ALL CAPS로 작성]
```

### DO NOT 형식
```markdown
## DO NOT
- [ ] NEVER [금지 항목 1]
- [ ] NEVER [금지 항목 2]
- [ ] NEVER [금지 항목 3]
- [ ] NEVER [금지 항목 4]
```

### Scope Boundaries 형식
```markdown
## Scope Boundaries

### This Agent DOES:
- [책임 1]
- [책임 2]

### This Agent DOES NOT:
- [비책임 1] (-> [담당 에이전트])
- [비책임 2] (-> [담당 에이전트])
```

### Red Flags 형식
```markdown
## Red Flags - STOP
- [경고 신호 1]
- [경고 신호 2]
- [경고 신호 3]
```

## 선택 섹션

- **Logging Protocol** - 로그 기록 방법 (orchestrator에서 처리)
- **Storage** - 파일 저장 경로 (plan-architect, reporter 등)
- **Integration** - 다른 에이전트와의 연동

## Model 선택 기준

| Model | 용도 |
|-------|------|
| `opus` | 복잡한 계획, 아키텍처 결정 |
| `sonnet` | 일반 개발, 리뷰, 분석 |
| `haiku` | 간단한 작업, 빠른 응답 필요 |
