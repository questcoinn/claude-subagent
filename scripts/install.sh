#!/usr/bin/env bash
# 이 저장소의 agents/*.md, skills/<name>/ 을 프로젝트 로컬(.claude/) 또는
# 전역(~/.claude/ 또는 $CLAUDE_CONFIG_DIR) 으로 설치한다.
# 같은 로직의 PowerShell 버전은 scripts/install.ps1 — 한쪽을 고치면 다른 쪽도 맞춘다.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

TARGET=""
DEST_ROOT="$(pwd)"
ITEMS=""
FORCE=0
DRY_RUN=0

show_help() {
  cat <<'EOF'
사용법: install.sh [--target local|global] [--dest <path>] [--items <name1,name2,...>|all] [--force] [--dry-run] [--help]

  --target   local: --dest 아래 .claude/ 로 설치. global: $CLAUDE_CONFIG_DIR(있으면) 또는 ~/.claude 로 설치.
             생략하면 실행 중 물어본다.
  --dest     local 설치 시 기준 경로. 기본값은 현재 디렉토리.
  --items    설치할 이름(콤마 구분) 또는 all. 생략하면 실행 중 목록을 보여주고 고르게 한다.
  --force    대상 파일 내용이 달라도 확인 없이 덮어쓴다. 기본은 항상 확인.
  --dry-run  실제로 쓰지 않고 무엇을 할지만 출력한다.
  --help     이 도움말을 출력한다.

예시:
  ./scripts/install.sh --dry-run
  ./scripts/install.sh --target local --items root-cause-analyzer,subagent-creation
  ./scripts/install.sh --target global --items all
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --dest) DEST_ROOT="$2"; shift 2 ;;
    --items) ITEMS="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --help) show_help; exit 0 ;;
    *) echo "알 수 없는 옵션: $1" >&2; show_help; exit 1 ;;
  esac
done

# --- 1. 설치 가능 항목 스캔 -------------------------------------------------

ITEM_NAMES=()
ITEM_TYPES=()
ITEM_SOURCES=()

if [ -d "$REPO_ROOT/agents" ]; then
  for f in "$REPO_ROOT"/agents/*.md; do
    [ -e "$f" ] || continue
    name="$(basename "$f" .md)"
    ITEM_NAMES+=("$name")
    ITEM_TYPES+=("agent")
    ITEM_SOURCES+=("$f")
  done
fi

if [ -d "$REPO_ROOT/skills" ]; then
  for d in "$REPO_ROOT"/skills/*/; do
    [ -e "$d" ] || continue
    d="${d%/}"
    if [ -f "$d/SKILL.md" ]; then
      name="$(basename "$d")"
      ITEM_NAMES+=("$name")
      ITEM_TYPES+=("skill")
      ITEM_SOURCES+=("$d")
    fi
  done
fi

if [ ${#ITEM_NAMES[@]} -eq 0 ]; then
  echo "설치할 agents/skills 항목이 없습니다."
  exit 0
fi

# --- 2. 대상(target) 결정 ----------------------------------------------------

if [ -z "$TARGET" ]; then
  echo "설치 대상을 선택하세요:"
  echo "  [1] local  (프로젝트 로컬 .claude/)"
  echo "  [2] global (사용자 전역 ~/.claude/ 또는 \$CLAUDE_CONFIG_DIR)"
  read -r -p "번호 입력: " choice
  case "$choice" in
    1) TARGET="local" ;;
    2) TARGET="global" ;;
    *) echo "잘못된 선택입니다." >&2; exit 1 ;;
  esac
fi

if [ "$TARGET" = "global" ]; then
  if [ -n "${CLAUDE_CONFIG_DIR:-}" ]; then
    DEST_BASE="$CLAUDE_CONFIG_DIR"
  else
    DEST_BASE="$HOME/.claude"
  fi
else
  DEST_BASE="$DEST_ROOT/.claude"
fi

echo "설치 대상: $TARGET ($DEST_BASE)"

# --- 3. 항목(items) 선택 ------------------------------------------------------

SELECTED_IDX=()

if [ -n "$ITEMS" ]; then
  IFS=',' read -ra names <<< "$ITEMS"
  if [ "${names[0]:-}" = "all" ]; then
    for i in "${!ITEM_NAMES[@]}"; do SELECTED_IDX+=("$i"); done
  else
    for n in "${names[@]}"; do
      n="$(echo "$n" | xargs)"
      [ -n "$n" ] || continue
      found=0
      for i in "${!ITEM_NAMES[@]}"; do
        if [ "${ITEM_NAMES[$i]}" = "$n" ]; then
          SELECTED_IDX+=("$i")
          found=1
          break
        fi
      done
      [ "$found" -eq 1 ] || echo "경고: '$n' 이름의 항목을 찾을 수 없어 건너뜁니다."
    done
  fi
else
  echo ""
  echo "설치 가능한 항목:"
  for i in "${!ITEM_NAMES[@]}"; do
    printf '  [%d] %-6s %s\n' "$((i + 1))" "${ITEM_TYPES[$i]}" "${ITEM_NAMES[$i]}"
  done
  read -r -p "번호(콤마 구분) 또는 all 입력 (취소는 빈 입력): " raw
  if [ -n "$raw" ]; then
    if [ "$(echo "$raw" | xargs)" = "all" ]; then
      for i in "${!ITEM_NAMES[@]}"; do SELECTED_IDX+=("$i"); done
    else
      IFS=',' read -ra toks <<< "$raw"
      for tok in "${toks[@]}"; do
        tok="$(echo "$tok" | xargs)"
        [ -n "$tok" ] || continue
        if echo "$tok" | grep -qE '^[0-9]+$' && [ "$tok" -ge 1 ] && [ "$tok" -le "${#ITEM_NAMES[@]}" ]; then
          SELECTED_IDX+=("$((tok - 1))")
        else
          echo "경고: '$tok' 는 유효한 번호가 아니라 건너뜁니다."
        fi
      done
    fi
  fi
fi

if [ ${#SELECTED_IDX[@]} -eq 0 ]; then
  echo "선택된 항목이 없습니다. 종료합니다."
  exit 0
fi

# --- 4. 파일 단위 복사 --------------------------------------------------------

STAT_CREATED=0
STAT_UPDATED=0
STAT_UNCHANGED=0
STAT_SKIPPED_DECLINED=0
STAT_WOULD_CREATE=0
STAT_WOULD_UPDATE=0

copy_one_file() {
  local src="$1" dst="$2"
  if [ -f "$dst" ]; then
    if cmp -s "$src" "$dst"; then
      STAT_UNCHANGED=$((STAT_UNCHANGED + 1))
      return
    fi
    if [ "$FORCE" -ne 1 ]; then
      echo "내용이 다름: $dst"
      if [ "$DRY_RUN" -eq 1 ]; then
        STAT_WOULD_UPDATE=$((STAT_WOULD_UPDATE + 1))
        return
      fi
      read -r -p "  덮어쓸까요? (y/N) " ans
      case "$ans" in
        y|Y) ;;
        *) STAT_SKIPPED_DECLINED=$((STAT_SKIPPED_DECLINED + 1)); return ;;
      esac
    elif [ "$DRY_RUN" -eq 1 ]; then
      STAT_WOULD_UPDATE=$((STAT_WOULD_UPDATE + 1))
      return
    fi
    if [ "$DRY_RUN" -eq 1 ]; then
      STAT_WOULD_UPDATE=$((STAT_WOULD_UPDATE + 1))
      return
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "갱신: $dst"
    STAT_UPDATED=$((STAT_UPDATED + 1))
  else
    if [ "$DRY_RUN" -eq 1 ]; then
      STAT_WOULD_CREATE=$((STAT_WOULD_CREATE + 1))
      return
    fi
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
    echo "생성: $dst"
    STAT_CREATED=$((STAT_CREATED + 1))
  fi
}

AGENTS_DEST_DIR="$DEST_BASE/agents"
SKILLS_DEST_DIR="$DEST_BASE/skills"
AGENTS_DIR_WAS_NEW=0
SKILLS_DIR_WAS_NEW=0
[ -d "$AGENTS_DEST_DIR" ] || AGENTS_DIR_WAS_NEW=1
[ -d "$SKILLS_DEST_DIR" ] || SKILLS_DIR_WAS_NEW=1

for idx in "${SELECTED_IDX[@]}"; do
  name="${ITEM_NAMES[$idx]}"
  type="${ITEM_TYPES[$idx]}"
  src="${ITEM_SOURCES[$idx]}"

  if [ "$type" = "agent" ]; then
    copy_one_file "$src" "$AGENTS_DEST_DIR/$name.md"
  else
    while IFS= read -r f; do
      rel="${f#"$src"/}"
      copy_one_file "$f" "$SKILLS_DEST_DIR/$name/$rel"
    done < <(find "$src" -type f)
  fi
done

# --- 5. 요약 -------------------------------------------------------------------

echo ""
if [ "$DRY_RUN" -eq 1 ]; then
  echo "[dry-run] 생성 예정 $STAT_WOULD_CREATE / 갱신 예정 $STAT_WOULD_UPDATE"
else
  echo "생성 $STAT_CREATED / 갱신 $STAT_UPDATED / 변경 없음(스킵) $STAT_UNCHANGED / 사용자 거부로 스킵 $STAT_SKIPPED_DECLINED"
fi

if [ "$DRY_RUN" -ne 1 ]; then
  newly_created=0
  if [ "$AGENTS_DIR_WAS_NEW" -eq 1 ] && [ -d "$AGENTS_DEST_DIR" ]; then newly_created=1; fi
  if [ "$SKILLS_DIR_WAS_NEW" -eq 1 ] && [ -d "$SKILLS_DEST_DIR" ]; then newly_created=1; fi
  if [ "$newly_created" -eq 1 ]; then
    echo ""
    echo "참고: agents/ 또는 skills/ 디렉토리가 대상에 처음 생성됐습니다 — Claude Code가 인식하려면 재시작이 필요할 수 있습니다."
  fi
fi
