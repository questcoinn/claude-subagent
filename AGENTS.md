# AGENTS.md

이 파일은 이 저장소에서 작업하는 AI 에이전트(Claude Code 포함, 도구 무관)가 참고할 지침을 제공한다. Claude Code는 `CLAUDE.md`를 통해 이 파일을 그대로 가져와 쓴다.

## 이 저장소는 무엇인가

Claude Code 설정 산출물(서브에이전트 정의, 스킬)을 모아두는 콘텐츠 저장소다. 각 파일은 프로젝트의 `.claude/agents/`, `.claude/skills/`(또는 사용자 전역 `~/.claude/agents/`, `~/.claude/skills/`)로 복사해서 쓴다. `scripts/install.ps1`/`scripts/install.sh`(이 복사를 대신해주는 설치 스크립트) 외에는 빌드·린트·테스트 도구가 없다 — 나머지 파일은 실행되는 코드가 아니라 Claude Code 자신이 읽어들이는 마크다운 스펙이다.

## 저장소 구조

- `agents/*.md` — 서브에이전트 정의, 에이전트당 파일 하나. frontmatter(`name`, `description`, `tools`, `model`, ...) + 시스템 프롬프트 본문으로 구성.
- `skills/<skill-name>/SKILL.md` — 스킬 진입점(frontmatter `name` + `description`, 그다음 지침 본문).
- `skills/<skill-name>/references/*.md` — 스킬이 본문에 다 담지 않고 참조하는 보조 문서(상시 로드되는 스킬 본문이 비대해지지 않도록 분리해둔 것).
- `scripts/install.ps1`, `scripts/install.sh` — `agents/`, `skills/`를 `.claude/`(로컬/전역)로 설치하는 스크립트. 둘이 같은 CLI 계약·로직을 공유하므로 한쪽 동작을 고치면 다른 쪽도 맞춘다.

## 작성 컨벤션 (`skills/subagent-creation/SKILL.md` 기준)

`agents/`에 서브에이전트 `.md` 파일을 새로 만들거나 고칠 때:

- 필수 frontmatter: `name`(소문자-하이픈, `:` 불가)과 `description`(이 서브에이전트가 *무엇을* 하는지와 *언제* 호출해야 하는지를 둘 다 명시해야 함 — Claude가 위임 여부를 판단하는 유일한 신호). 선택 필드: `tools`, `disallowedTools`, `model`, `permissionMode`, `maxTurns`, `skills`, `mcpServers`, `hooks`, `memory`, `background`, `color` — 전체 목록과 저장 위치 우선순위표는 `skills/subagent-creation/references/scope-and-frontmatter.md` 참고.
- `tools`는 최소 권한 원칙으로: 생략하면 모든 도구를 상속하므로, 실제로 그 역할에 필요한 도구만 명시한다(예: 읽기 전용 분석가는 `Read, Grep, Glob`; 파일을 수정해야 할 때만 `Edit`/`Write` 추가). 상속 목록 전체를 다시 나열하지 않으려면 `disallowedTools`로 뺀다. `tools`만으로 표현 안 되는 제약(예: "Bash는 허용하되 쓰기 SQL은 금지")은 `PreToolUse` 훅을 쓴다 — 패턴은 `skills/subagent-creation/references/example-subagents.md`에 있음.
- 서브에이전트의 본문이 곧 그 에이전트의 시스템 프롬프트 전체다(Claude Code의 기본 시스템 프롬프트를 상속하지 않음) — 역할, 호출 직후 진입 순서(서브에이전트는 매번 빈 컨텍스트에서 시작), 요구되는 보고 형식, 명시적인 "하지 말 것" 경계를 본문에 적는다.
- 넓고 모호한 에이전트 하나보다 좁은 역할의 에이전트 여러 개가 낫다 — 여러 책임을 하나의 `description`에 욱여넣지 말고 분리한다.
- 전역(`~/.claude/agents/`) 서브에이전트를 새로 쓰기 전에는 `CLAUDE_CONFIG_DIR`를 먼저 확인한다 — 설정돼 있으면 `~/.claude/agents/` 대신 `$CLAUDE_CONFIG_DIR/agents/`에 쓴다.
- 같은 `name`의 기존 서브에이전트를 말없이 덮어쓰지 않는다 — 먼저 사용자에게 확인한다.

`agents/root-cause-analyzer.md`는 이 컨벤션을 그대로 따른 예시다: 읽기 전용(`Read, Grep, Glob, Bash`, `Edit`/`Write` 없음) 결함 위치 특정 서브에이전트로, 번호가 매겨진 조사 순서와 고정된 보고 구조(이슈 요약 → `file:line` 근거를 곁들인 랭킹된 근본 원인 → 재현 결과 → 관련 이력 → 실제 수정은 하지 않고 방향만 제안)를 갖고 있다.

<!-- codebase-context-engineer:begin (last_analyzed_commit: c2db2f22effe184454d15ec0e89b920a28b101aa, last_analyzed_date: 2026-09-11) -->
## AI를 위한 프로젝트 규칙

### 정본과 설치본

- **정본은 저장소의 `agents/`, `skills/`다.** 사용자가 `scripts/install.*`로 프로젝트 `.claude/`나 전역에 복사해둔 것은 설치본(사본)이며, 정본과 갈라져 있을 수 있다.
- 정본을 수정한 뒤 **설치본으로 자동 복사하지 않고, 설치 스크립트를 대신 실행하지도 않는다.** 설치 시점은 사용자가 정한다 — 임의로 설치하면 사용자가 의도적으로 다르게 유지 중인 사본을 덮어쓸 수 있다.
- 반대로, 두 위치의 내용이 갈라져 보이면 조용히 맞추지 말고 사용자에게 알린다.

### 변경 검증 절차

자동 검증 수단이 없으므로, 다음을 직접 확인하는 것이 유일한 "테스트"다.

1. frontmatter가 `---`로 정확히 닫혔는지, `name`이 소문자-하이픈인지.
2. **문서 안의 파일 참조 경로가 실제로 존재하는지.** 경로 표기 규칙이 위치마다 다르다 — `SKILL.md` 안에서는 스킬 디렉토리 기준 상대 경로(`references/x.md`), `AGENTS.md`/`README.md`에서는 저장소 루트 기준 경로(`skills/subagent-creation/references/x.md`). 파일을 옮기거나 이름을 바꿀 때 양쪽 표기를 모두 갱신한다.
3. `scripts/install.ps1`/`install.sh`를 고쳤으면 **두 스크립트를 모두** dry-run으로 돌려 항목 목록과 예정 동작이 일치하는지 비교한다(실행법은 README의 "설치" 절). 한쪽만 고쳐 두 구현이 갈라지는 것이 이 저장소에서 가장 나기 쉬운 회귀다.
4. 구조가 바뀌었으면 `docs/INDEX.md`의 파일 맵·섹션 위치 인덱스도 함께 갱신한다(줄 번호 포인터라 본문이 늘어나면 쉽게 어긋난다).

### 설치 항목 명명 불변식

- 설치 항목 이름은 `agents/<name>.md`의 파일명 또는 `skills/<name>/`의 디렉토리명 그대로다(`--items`/`-Items`에 넘기는 값). 파일명을 바꾸면 사용자가 쓰던 설치 명령이 조용히 "항목 없음" 경고로 바뀐다.
- `SKILL.md`가 없는 스킬 디렉토리는 **경고 없이** 설치 목록에서 빠진다 — 새 스킬은 `SKILL.md`부터 만든다.

### 파일·경로 경계

- `.gitignore`가 `docs/*`와 `.claude/knowledge-location.md`를 제외한다. 따라서 **`docs/` 안의 인덱스 산출물은 커밋되지 않는다** — 팀과 공유해야 하는 내용을 `docs/`에만 적어두면 안 된다.
- 이 저장소에는 시크릿·자격증명·`.env`가 없다(분석 시점 기준 전수 확인). `LICENSE`(MIT)는 손대지 않는다.

### 작성 언어

- 문서·스펙 본문은 한국어로 쓴다. 기술 식별자(frontmatter 키, 도구 이름, CLI 플래그, 경로)는 원문 그대로 둔다. 스크립트의 사용자 출력 메시지·help 텍스트도 한국어다.
- 커밋 메시지는 영어 소문자로 짧게 쓴다(예: `add license and readme file`, `add install scripts`). 커밋 4건 모두 이 형태지만, 표본이 적어 확립된 규칙이라기보다 관측된 패턴이다.

### 인덱스 사용법

- 어떤 파일의 어떤 섹션을 봐야 할지 찾을 때는 전체를 읽지 말고 `docs/INDEX.md`를 먼저 본다. 파일별 책임, `file:line` 섹션 포인터, 문서 간 상호 참조 그래프가 있다.
<!-- codebase-context-engineer:end -->
