#!/usr/bin/env pwsh
<#
  이 저장소의 agents/*.md, skills/<name>/ 을 프로젝트 로컬(.claude/) 또는
  전역(~/.claude/ 또는 $CLAUDE_CONFIG_DIR) 으로 설치한다.
  같은 로직의 Bash 버전은 scripts/install.sh — 한쪽을 고치면 다른 쪽도 맞춘다.
#>

param(
    [ValidateSet('local', 'global')]
    [string]$Target,

    [string]$DestinationRoot = (Get-Location).Path,

    [string]$Items,

    [switch]$Force,

    [switch]$DryRun,

    [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Help {
    @'
사용법: install.ps1 [-Target local|global] [-DestinationRoot <path>] [-Items <name1,name2,...>|all] [-Force] [-DryRun] [-Help]

  -Target           local: -DestinationRoot 아래 .claude/ 로 설치. global: $CLAUDE_CONFIG_DIR(있으면) 또는 ~/.claude 로 설치.
                    생략하면 실행 중 물어본다.
  -DestinationRoot  local 설치 시 기준 경로. 기본값은 현재 디렉토리.
  -Items            설치할 이름(콤마 구분) 또는 all. 생략하면 실행 중 목록을 보여주고 고르게 한다.
  -Force            대상 파일 내용이 달라도 확인 없이 덮어쓴다. 기본은 항상 확인.
  -DryRun           실제로 쓰지 않고 무엇을 할지만 출력한다.
  -Help             이 도움말을 출력한다.

예시:
  ./scripts/install.ps1 -DryRun
  ./scripts/install.ps1 -Target local -Items root-cause-analyzer,subagent-creation
  ./scripts/install.ps1 -Target global -Items all
'@ | Write-Host
}

if ($Help) {
    Show-Help
    exit 0
}

$RepoRoot = Split-Path -Parent $PSScriptRoot

# --- 1. 설치 가능 항목 스캔 -------------------------------------------------

$AllItems = @()

$agentFiles = Get-ChildItem -Path (Join-Path $RepoRoot 'agents') -Filter '*.md' -File -ErrorAction SilentlyContinue
foreach ($f in $agentFiles) {
    $AllItems += [pscustomobject]@{
        Name = $f.BaseName
        Type = 'agent'
        SourcePath = $f.FullName
    }
}

$skillDirs = Get-ChildItem -Path (Join-Path $RepoRoot 'skills') -Directory -ErrorAction SilentlyContinue
foreach ($d in $skillDirs) {
    if (Test-Path (Join-Path $d.FullName 'SKILL.md')) {
        $AllItems += [pscustomobject]@{
            Name = $d.Name
            Type = 'skill'
            SourcePath = $d.FullName
        }
    }
}

if ($AllItems.Count -eq 0) {
    Write-Host '설치할 agents/skills 항목이 없습니다.'
    exit 0
}

# --- 2. 대상(target) 결정 ----------------------------------------------------

if (-not $Target) {
    Write-Host '설치 대상을 선택하세요:'
    Write-Host '  [1] local  (프로젝트 로컬 .claude/)'
    Write-Host '  [2] global (사용자 전역 ~/.claude/ 또는 $CLAUDE_CONFIG_DIR)'
    $choice = Read-Host '번호 입력'
    switch ($choice) {
        '1' { $Target = 'local' }
        '2' { $Target = 'global' }
        default { Write-Host '잘못된 선택입니다.'; exit 1 }
    }
}

if ($Target -eq 'global') {
    $configDir = $env:CLAUDE_CONFIG_DIR
    if ($configDir) {
        $DestBase = $configDir
    } else {
        $DestBase = Join-Path $HOME '.claude'
    }
} else {
    $DestBase = Join-Path $DestinationRoot '.claude'
}

Write-Host "설치 대상: $Target ($DestBase)"

# --- 3. 항목(items) 선택 ------------------------------------------------------

function Select-Items {
    param([string]$ItemsArg)

    if ($ItemsArg) {
        $names = $ItemsArg -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if ($names -contains 'all') { return $AllItems }
        $selected = @()
        foreach ($n in $names) {
            $match = $AllItems | Where-Object { $_.Name -eq $n }
            if ($match) { $selected += $match } else { Write-Host "경고: '$n' 이름의 항목을 찾을 수 없어 건너뜁니다." }
        }
        return $selected
    }

    Write-Host ''
    Write-Host '설치 가능한 항목:'
    for ($i = 0; $i -lt $AllItems.Count; $i++) {
        Write-Host ("  [{0}] {1,-6} {2}" -f ($i + 1), $AllItems[$i].Type, $AllItems[$i].Name)
    }
    $raw = Read-Host "번호(콤마 구분) 또는 all 입력 (취소는 빈 입력)"
    if (-not $raw) { return @() }
    if ($raw.Trim() -eq 'all') { return $AllItems }

    $selected = @()
    foreach ($tok in ($raw -split ',')) {
        $tok = $tok.Trim()
        if (-not $tok) { continue }
        $idx = 0
        if ([int]::TryParse($tok, [ref]$idx) -and $idx -ge 1 -and $idx -le $AllItems.Count) {
            $selected += $AllItems[$idx - 1]
        } else {
            Write-Host "경고: '$tok' 는 유효한 번호가 아니라 건너뜁니다."
        }
    }
    return $selected
}

$Selected = Select-Items -ItemsArg $Items

if ($Selected.Count -eq 0) {
    Write-Host '선택된 항목이 없습니다. 종료합니다.'
    exit 0
}

# --- 4. 파일 단위 복사 --------------------------------------------------------

$Stats = @{ Created = 0; Updated = 0; Unchanged = 0; SkippedDeclined = 0; WouldCreate = 0; WouldUpdate = 0 }

function Copy-OneFile {
    param([string]$Src, [string]$Dst)

    $exists = Test-Path $Dst -PathType Leaf
    if ($exists) {
        $same = (Get-FileHash -Path $Src -Algorithm SHA256).Hash -eq (Get-FileHash -Path $Dst -Algorithm SHA256).Hash
        if ($same) {
            $Stats.Unchanged++
            return
        }
        if (-not $Force) {
            Write-Host "내용이 다름: $Dst"
            if ($DryRun) { $Stats.WouldUpdate++; return }
            $ans = Read-Host '  덮어쓸까요? (y/N)'
            if ($ans -notin @('y', 'Y')) {
                $Stats.SkippedDeclined++
                return
            }
        } elseif ($DryRun) {
            $Stats.WouldUpdate++
            return
        }
        if ($DryRun) { $Stats.WouldUpdate++; return }
        Copy-Item -Path $Src -Destination $Dst -Force
        Write-Host "갱신: $Dst"
        $Stats.Updated++
    } else {
        if ($DryRun) { $Stats.WouldCreate++; return }
        $parent = Split-Path $Dst -Parent
        if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
        Copy-Item -Path $Src -Destination $Dst
        Write-Host "생성: $Dst"
        $Stats.Created++
    }
}

$AgentsDestDir = Join-Path $DestBase 'agents'
$SkillsDestDir = Join-Path $DestBase 'skills'
$AgentsDirWasNew = -not (Test-Path $AgentsDestDir)
$SkillsDirWasNew = -not (Test-Path $SkillsDestDir)

foreach ($item in $Selected) {
    if ($item.Type -eq 'agent') {
        $dst = Join-Path $AgentsDestDir ("{0}.md" -f $item.Name)
        Copy-OneFile -Src $item.SourcePath -Dst $dst
    } else {
        $files = Get-ChildItem -Path $item.SourcePath -Recurse -File
        foreach ($f in $files) {
            $rel = $f.FullName.Substring($item.SourcePath.Length).TrimStart('\', '/')
            $dst = Join-Path (Join-Path $SkillsDestDir $item.Name) $rel
            Copy-OneFile -Src $f.FullName -Dst $dst
        }
    }
}

# --- 5. 요약 -------------------------------------------------------------------

Write-Host ''
if ($DryRun) {
    Write-Host ("[dry-run] 생성 예정 {0} / 갱신 예정 {1}" -f $Stats.WouldCreate, $Stats.WouldUpdate)
} else {
    Write-Host ("생성 {0} / 갱신 {1} / 변경 없음(스킵) {2} / 사용자 거부로 스킵 {3}" -f $Stats.Created, $Stats.Updated, $Stats.Unchanged, $Stats.SkippedDeclined)
}

if (-not $DryRun) {
    $newlyCreated = ($AgentsDirWasNew -and (Test-Path $AgentsDestDir)) -or ($SkillsDirWasNew -and (Test-Path $SkillsDestDir))
    if ($newlyCreated) {
        Write-Host ''
        Write-Host '참고: agents/ 또는 skills/ 디렉토리가 대상에 처음 생성됐습니다 — Claude Code가 인식하려면 재시작이 필요할 수 있습니다.'
    }
}
