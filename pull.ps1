# Claude Code 配置拉取和应用脚本（Windows PowerShell）
# 三阶段：差异检查 → git pull → 审核应用

param(
    [string]$ClaudeHome = $env:CLAUDE_HOME,
    [string]$ClaudeWorkspace = $env:CLAUDE_WORKSPACE,
    [string]$ClaudeCodeRoot = $env:CLAUDECODE_ROOT,
    [switch]$NonInteractive,
    [switch]$ApplyMissingCc
)

$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

# PowerShell 在中文 Windows 上需要 UTF-8 BOM 才能正确解析含中文的脚本
# git 通常存储无 BOM 版本（尤其来自 Linux 端），故每次 pull 前剥离、pull 后恢复
function Set-Ps1BOM {
    param([string]$Dir, [bool]$AddBOM)
    $enc = [System.Text.UTF8Encoding]::new($AddBOM)
    Get-ChildItem $Dir -Filter "*.ps1" | ForEach-Object {
        $text = [System.IO.File]::ReadAllText($_.FullName, [System.Text.Encoding]::UTF8)
        [System.IO.File]::WriteAllText($_.FullName, $text, $enc)
    }
}

Write-ColorOutput "🔄 拉取并应用 Claude Code 配置..." "Cyan"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

if (-not $ClaudeHome) { $ClaudeHome = Join-Path $env:USERPROFILE ".claude" }

$WorkspacePath = $null
if ($ClaudeWorkspace) {
    $WorkspacePath = $ClaudeWorkspace
} elseif (Test-Path (Join-Path $env:USERPROFILE "claude-workspace")) {
    $WorkspacePath = Join-Path $env:USERPROFILE "claude-workspace"
} elseif (-not $NonInteractive) {
    $Default = Join-Path $env:USERPROFILE "claude-workspace"
    $Input = Read-Host "📂 请输入工作目录路径 [$Default]"
    $WorkspacePath = if ([string]::IsNullOrWhiteSpace($Input)) { $Default } else { $Input }
} else {
    $WorkspacePath = Join-Path $env:USERPROFILE "claude-workspace"
}
$WorkspacePath = [System.Environment]::ExpandEnvironmentVariables($WorkspacePath)

# 路径转 Claude 项目 hash
function Path-To-Hash { param([string]$Path); return $Path -replace ':', '-' -replace '[/\\]', '-' }

$WorkspaceHash = Path-To-Hash $WorkspacePath
$CcPrefix = ""
if ($ClaudeCodeRoot) { $CcPrefix = Path-To-Hash $ClaudeCodeRoot.TrimEnd('\', '/') }

$PullRestarts = [int]($env:_PULL_RESTARTS -as [int])

# 将仓库 memory 子目录名映射到本地 project memory 路径（空字符串表示跳过）
function Resolve-MemoryTarget {
    param([string]$DirName)
    switch ($DirName) {
        "_workspace" { return Join-Path $ClaudeHome "projects\$WorkspaceHash\memory" }
        "_cc"        { return "" }
        default {
            $p = Join-Path $ClaudeHome "projects\$DirName"
            if (Test-Path $p) { return Join-Path $p "memory" } else { return "" }
        }
    }
}

function Resolve-CcTarget {
    param([string]$Rel)
    if (-not $ClaudeCodeRoot) { return "" }
    $ccHash = Path-To-Hash "$($ClaudeCodeRoot.TrimEnd('\', '/'))/$Rel"
    return Join-Path $ClaudeHome "projects\$ccHash\memory"
}

# ──────────────────────────────────────────────────────────────
# Phase 1: 差异检查（git pull 之前）
# ──────────────────────────────────────────────────────────────
$DiffStateFile = $env:_PULL_DIFF_STATE_FILE
if (-not $DiffStateFile -or -not (Test-Path $DiffStateFile)) {
    Write-Host "  🔍 检查本地配置差异..."
    $DiffStateFile = [System.IO.Path]::GetTempFileName()
    $env:_PULL_DIFF_STATE_FILE = $DiffStateFile
    $HasAnyDiff = $false

    function Files-Differ {
        param([string]$A, [string]$B)
        if (-not (Test-Path $A) -or -not (Test-Path $B)) { return $false }
        return (Get-FileHash $A -Algorithm MD5).Hash -ne (Get-FileHash $B -Algorithm MD5).Hash
    }

    # sync.conf 文件
    $ConfFile = Join-Path $ScriptDir "sync.conf"
    if (Test-Path $ConfFile) {
        Get-Content $ConfFile | ForEach-Object {
            $line = $_.Trim()
            if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { return }
            $parts = $line -split '\s+', 4
            if ($parts.Count -lt 4) { return }
            $type, $base, $src, $dest = $parts
            $basePath = switch ($base) {
                "claude_home" { $ClaudeHome } "workspace" { $WorkspacePath } default { return }
            }
            $repoPath  = Join-Path $ScriptDir $dest
            $localPath = Join-Path $basePath  $src
            switch ($type) {
                "file" {
                    if ((Files-Differ $localPath $repoPath)) {
                        Add-Content $DiffStateFile "DIFF:$src"; $HasAnyDiff = $true
                    }
                }
                "dir" {
                    if ((Test-Path $localPath) -and (Test-Path $repoPath)) {
                        Get-ChildItem -Path $repoPath -Recurse -File | ForEach-Object {
                            $rel = $_.FullName.Substring($repoPath.Length).TrimStart('\', '/')
                            $localFile = Join-Path $localPath $rel
                            if (Files-Differ $localFile $_.FullName) {
                                $key = "$src/$($rel -replace '\\', '/')"
                                Add-Content $DiffStateFile "DIFF:$key"; $HasAnyDiff = $true
                            }
                        }
                    }
                }
            }
        }
    }

    # 项目记忆
    $MemoryBase = Join-Path $ScriptDir "claude\memory"
    if (Test-Path $MemoryBase) {
        Get-ChildItem -Path $MemoryBase -Directory | ForEach-Object {
            $dirName = $_.Name
            if ($dirName -eq "_cc") {
                Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
                    $rel = $_.Name
                    $target = Resolve-CcTarget $rel
                    if (-not $target) { return }
                    Get-ChildItem -Path $_.FullName -Recurse -File | ForEach-Object {
                        $frel = $_.FullName.Substring((Join-Path $MemoryBase "_cc\$rel").Length).TrimStart('\', '/')
                        $localFile = Join-Path $target $frel
                        if (Files-Differ $localFile $_.FullName) {
                            Add-Content $DiffStateFile "DIFF:_cc/$rel/$($frel -replace '\\', '/')"
                            $HasAnyDiff = $true
                        }
                    }
                }
            } else {
                $target = Resolve-MemoryTarget $dirName
                if (-not $target) { return }
                Get-ChildItem -Path $_.FullName -Recurse -File | ForEach-Object {
                    $frel = $_.FullName.Substring((Join-Path $MemoryBase $dirName).Length).TrimStart('\', '/')
                    $localFile = Join-Path $target $frel
                    if (Files-Differ $localFile $_.FullName) {
                        Add-Content $DiffStateFile "DIFF:$dirName/$($frel -replace '\\', '/')"
                        $HasAnyDiff = $true
                    }
                }
            }
        }
    }

    if ($HasAnyDiff) { Write-ColorOutput "    ⚠️  发现本地修改，拉取后将暂停审核" "Yellow" }
    else             { Write-ColorOutput "    ✅ 无本地修改" "Green" }
} else {
    Write-Host "  🔍 使用已保存的差异状态（脚本自重启后）"
}

# ──────────────────────────────────────────────────────────────
# Phase 2: git pull
# ──────────────────────────────────────────────────────────────
Write-Host "  📥 从仓库拉取最新配置..."

# Pull 前：剥离 .ps1 BOM，避免 git 将其识别为本地修改而拒绝合并
Set-Ps1BOM $ScriptDir $false

$ScriptHashBefore = (Get-FileHash $MyInvocation.MyCommand.Path -Algorithm MD5).Hash
try {
    git pull
    if ($LASTEXITCODE -ne 0) {
        throw "git pull 返回退出码 $LASTEXITCODE"
    }
    Write-ColorOutput "    ✅ 拉取完成" "Green"
} catch {
    Write-ColorOutput "    ❌ 拉取失败: $_" "Red"
    Set-Ps1BOM $ScriptDir $true  # 失败时也恢复 BOM
    Remove-Item $DiffStateFile -Force -ErrorAction SilentlyContinue
    exit 1
}

$ScriptHashAfter = (Get-FileHash $MyInvocation.MyCommand.Path -Algorithm MD5).Hash
if ($ScriptHashBefore -ne $ScriptHashAfter) {
    if ($PullRestarts -lt 1) {
        Write-ColorOutput "⚠️  脚本已更新，自动重启以应用新版本..." "Yellow"
        $env:_PULL_RESTARTS = $PullRestarts + 1
        & $MyInvocation.MyCommand.Path @PSBoundParameters
        exit
    } else {
        Write-ColorOutput "⚠️  脚本已更新但已重启过一次，继续使用当前版本" "Yellow"
    }
}

# Pull 后：为所有 .ps1 加回 BOM（PowerShell 在中文 Windows 上需要）
Set-Ps1BOM $ScriptDir $true
Write-ColorOutput "    ✅ .ps1 UTF-8 BOM 已恢复" "Green"

# ──────────────────────────────────────────────────────────────
# Phase 3: 逐文件应用
# ──────────────────────────────────────────────────────────────
Write-Host "  📦 应用同步配置..."
$NeedsReview = $false
$SkippedFiles = @()

function Has-Diff {
    param([string]$Key)
    if (-not (Test-Path $env:_PULL_DIFF_STATE_FILE)) { return $false }
    return (Get-Content $env:_PULL_DIFF_STATE_FILE -ErrorAction SilentlyContinue) -contains "DIFF:$Key"
}

function Show-Diff {
    param([string]$Label, [string]$LocalPath, [string]$RepoPath)
    Write-ColorOutput "  ┌─ 需审核: $Label" "Yellow"
    if ((Test-Path $LocalPath) -and (Test-Path $RepoPath)) {
        git diff --no-index --unified=3 $LocalPath $RepoPath 2>$null
        if ($LASTEXITCODE -eq 0) { Write-Host "  （内容相同，可能是行尾差异）" }
    } elseif (-not (Test-Path $LocalPath)) {
        Write-Host "  （本地文件不存在，仓库为新增）"
    }
    Write-ColorOutput "  └────────────────────────────────────" "Yellow"
}

# sync.conf
$ConfFile = Join-Path $ScriptDir "sync.conf"
if (-not (Test-Path $ConfFile)) {
    Write-ColorOutput "    ⚠️  未找到 sync.conf，跳过配置应用" "Yellow"
} else {
    Get-Content $ConfFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { return }
        $parts = $line -split '\s+', 4
        if ($parts.Count -lt 4) { return }
        $type, $base, $src, $dest = $parts
        $basePath = switch ($base) {
            "claude_home" { $ClaudeHome } "workspace" { $WorkspacePath }
            default { Write-ColorOutput "    ⚠️  未知 base: $base，跳过" "Yellow"; return }
        }
        $repoPath  = Join-Path $ScriptDir $dest
        $localPath = Join-Path $basePath  $src
        switch ($type) {
            "file" {
                $null = New-Item -ItemType Directory -Path (Split-Path $localPath) -Force
                if (Test-Path $repoPath) {
                    if (Has-Diff $src) {
                        Show-Diff $src $localPath $repoPath
                        $script:SkippedFiles += $src; $script:NeedsReview = $true
                        Write-ColorOutput "    ⏸  $src（跳过，需审核）" "Yellow"
                    } else {
                        Copy-Item $repoPath -Destination $localPath -Force
                        Write-ColorOutput "    ✅ $src" "Green"
                    }
                } else { Write-Host "    ℹ️  $src 不存在（可选）" -ForegroundColor Gray }
            }
            "dir" {
                if ((Test-Path $repoPath) -and (Get-ChildItem $repoPath -ErrorAction SilentlyContinue)) {
                    $null = New-Item -ItemType Directory -Path $localPath -Force
                    $dirHasSkip = $false
                    Get-ChildItem -Path $repoPath -Recurse -File | ForEach-Object {
                        $rel = $_.FullName.Substring($repoPath.Length).TrimStart('\', '/')
                        $localFile = Join-Path $localPath $rel
                        $key = "$src/$($rel -replace '\\', '/')"
                        if (Has-Diff $key) {
                            Show-Diff $key $localFile $_.FullName
                            $script:SkippedFiles += $key; $script:NeedsReview = $true; $dirHasSkip = $true
                        } else {
                            $null = New-Item -ItemType Directory -Path (Split-Path $localFile) -Force
                            Copy-Item $_.FullName -Destination $localFile -Force
                        }
                    }
                    if ($dirHasSkip) { Write-ColorOutput "    ⚠️  $src（部分文件跳过）" "Yellow" }
                    else             { Write-ColorOutput "    ✅ $src" "Green" }
                } else { Write-Host "    ℹ️  $src 为空或不存在（可选）" -ForegroundColor Gray }
            }
        }
    }
}

# 项目记忆
Write-Host "  📝 应用项目记忆..."
$MemoryBase = Join-Path $ScriptDir "claude\memory"
if (-not (Test-Path $MemoryBase) -or -not (Get-ChildItem $MemoryBase -ErrorAction SilentlyContinue)) {
    Write-ColorOutput "    ⚠️  仓库中无项目记忆" "Yellow"
} else {
    Get-ChildItem -Path $MemoryBase -Directory | ForEach-Object {
        $dirName = $_.Name
        if ($dirName -eq "_cc") {
            Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
                $rel = $_.Name
                $ccSubPath = $_.FullName
                $target = Resolve-CcTarget $rel
                if (-not $target) { Write-Host "    ⏭  _cc/$rel（CLAUDECODE_ROOT 未配置，跳过）" -ForegroundColor Gray; return }
                $ccProjectDir = Split-Path $target -Parent
                if (-not (Test-Path $ccProjectDir)) {
                    if ($ApplyMissingCc) {
                        Write-ColorOutput "    ⚠️  _cc/$rel（本机无此项目，-ApplyMissingCc 强制应用）" "Yellow"
                    } else {
                        if ($ClaudeCodeRoot -and (Test-Path (Join-Path $ClaudeCodeRoot $rel))) {
                            Write-ColorOutput "    ⚠️  _cc/$rel（仓库含此项目记忆，但本机未在此目录打开过 Claude；疑似旧设备配置迁移，建议执行 restore.ps1）" "Yellow"
                        } else {
                            Write-Host "    ⏭  _cc/$rel（本机无此项目，跳过）" -ForegroundColor Gray
                        }
                        return
                    }
                }
                $null = New-Item -ItemType Directory -Path $target -Force
                $dirHasSkip = $false
                Get-ChildItem -Path $ccSubPath -Recurse -File | ForEach-Object {
                    $frel = $_.FullName.Substring($ccSubPath.Length).TrimStart('\', '/')
                    $localFile = Join-Path $target $frel
                    $key = "_cc/$rel/$($frel -replace '\\', '/')"
                    if (Has-Diff $key) {
                        Show-Diff $key $localFile $_.FullName
                        $script:SkippedFiles += $key; $script:NeedsReview = $true; $dirHasSkip = $true
                    } else {
                        $null = New-Item -ItemType Directory -Path (Split-Path $localFile) -Force
                        Copy-Item $_.FullName -Destination $localFile -Force
                    }
                }
                if ($dirHasSkip) { Write-ColorOutput "    ⚠️  _cc/$rel（部分文件跳过）" "Yellow" }
                else             { Write-ColorOutput "    ✅ _cc/$rel" "Green" }
            }
        } else {
            $memSubPath = $_.FullName
            $target = Resolve-MemoryTarget $dirName
            if (-not $target) { Write-Host "    ⏭  $dirName（本机无此项目，跳过）" -ForegroundColor Gray; return }
            $null = New-Item -ItemType Directory -Path $target -Force
            $dirHasSkip = $false
            Get-ChildItem -Path $memSubPath -Recurse -File | ForEach-Object {
                $frel = $_.FullName.Substring($memSubPath.Length).TrimStart('\', '/')
                $localFile = Join-Path $target $frel
                $key = "$dirName/$($frel -replace '\\', '/')"
                if (Has-Diff $key) {
                    Show-Diff $key $localFile $_.FullName
                    $script:SkippedFiles += $key; $script:NeedsReview = $true; $dirHasSkip = $true
                } else {
                    $null = New-Item -ItemType Directory -Path (Split-Path $localFile) -Force
                    Copy-Item $_.FullName -Destination $localFile -Force
                }
            }
            if ($dirHasSkip) { Write-ColorOutput "    ⚠️  $dirName（部分文件跳过）" "Yellow" }
            else             { Write-ColorOutput "    ✅ $dirName" "Green" }
        }
    }
}

Remove-Item $DiffStateFile -Force -ErrorAction SilentlyContinue
$env:_PULL_DIFF_STATE_FILE = $null

Write-Host ""
if ($NeedsReview) {
    Write-ColorOutput "⚠️  以下文件因存在本地修改而跳过：" "Yellow"
    foreach ($f in $SkippedFiles) { Write-Host "    - $f" }
    Write-Host ""
    Write-ColorOutput "   请让 Claude 审核以上差异，确认后再决定如何处理。" "Yellow"
    Write-ColorOutput "   如需保留本地修改，请先执行 update.ps1 推送，再重新拉取。" "Yellow"
} else {
    Write-ColorOutput "✅ 配置拉取和应用完成！" "Green"
}
Write-Host ""
Write-Host "环境信息：" -ForegroundColor Cyan
Write-Host "  - Claude 配置:      $ClaudeHome"
Write-Host "  - 工作目录:         $WorkspacePath"
Write-Host "  - ClaudeCode 根目录: $(if ($ClaudeCodeRoot) { $ClaudeCodeRoot } else { '未设置' })"
Write-Host ""

if (-not $NonInteractive) {
    Write-Host "按任意键继续..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
}
