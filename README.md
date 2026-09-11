# claude-subagent

Claude Code용 서브에이전트와 스킬을 모아두는 저장소입니다.

## 구성

- `agents/` — Claude Code 서브에이전트 정의 (`.claude/agents/*.md` 형식)
  - `root-cause-analyzer.md` — 이슈/에러 로그를 분석해 근본 원인과 위치(file:line)를 찾는 원인 분석 전담 에이전트
- `skills/` — Claude Code 스킬 정의
  - `subagent-creation/` — 새로운 서브에이전트를 설계하고 생성하는 스킬

## 사용법

이 저장소의 파일들을 프로젝트의 `.claude/agents/`, `.claude/skills/` 또는 사용자 전역 `~/.claude/agents/`, `~/.claude/skills/` 경로에 복사해서 사용합니다.
