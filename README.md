# claude-subagent

Claude Code용 서브에이전트와 스킬을 모아두는 저장소입니다.

## 사용법

이 저장소의 파일들을 프로젝트의 `.claude/agents/`, `.claude/skills/` 또는 사용자 전역 `~/.claude/agents/`, `~/.claude/skills/` 경로에 복사해서 사용합니다.

## 설치

`scripts/install.ps1`(PowerShell) 또는 `scripts/install.sh`(Bash)로 개별 에이전트/스킬을 골라 설치할 수 있습니다. 대상에 이미 같은 이름의 파일이 있으면 내용이 다를 때만 확인 후 덮어씁니다.

```bash
./scripts/install.sh --dry-run                                       # 무엇이 설치될지만 확인
./scripts/install.sh --target local --items root-cause-analyzer      # 이 프로젝트의 .claude/ 로
./scripts/install.sh --target global --items all                     # 전역(~/.claude/ 또는 $CLAUDE_CONFIG_DIR)으로 전체 설치

# 항목을 여러 개 지정할 때는 콤마로 이어서 넘겨야 한다.
./scripts/install.sh --target global --items codebase-context-engineer,root-cause-analyzer
```

```powershell
./scripts/install.ps1 -DryRun
./scripts/install.ps1 -Target local -Items root-cause-analyzer
./scripts/install.ps1 -Target global -Items all

# 항목을 여러 개 지정할 때는 콤마로 이어서 넘겨야 한다.
./scripts/install.ps1 -Target global -Items codebase-context-engineer,root-cause-analyzer
```

옵션을 생략하면 실행 중에 대상과 항목을 물어봅니다. 자세한 옵션은 `-Help`/`--help` 참고.
