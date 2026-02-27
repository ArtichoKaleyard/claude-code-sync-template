# Claude Code 配置恢复脚本（Windows PowerShell）
# 在新设备上恢复配置（假设仓库已克隆到本地）

param(
    [string]$ClaudeHome = $env:CLAUDE_HOME,
    [string]$ClaudeWorkspace = $env:CLAUDE_WORKSPACE,
    [string]$ClaudeCodeRoot = $env:CLAUDECODE_ROOT,
    [switch]$NonInteractive
)

$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "🔄 恢复 Claude Code 配置..." "Cyan"

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

if (-not $ClaudeCodeRoot -and (-not $NonInteractive)) {
    $CcMemPath = Join-Path $ScriptDir "claude\memory\_cc"
    if (Test-Path $CcMemPath) {
        $CcProjects = (Get-ChildItem -Path $CcMemPath -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name) -join ', '
        $CcInput = Read-Host "📂 请输入 ClaudeCode 根目录路径（_cc/ 含项目: $CcProjects，留空跳过）"
    } else {
        $CcInput = Read-Host "📂 请输入 ClaudeCode 根目录路径（留空跳过）"
    }
    $ClaudeCodeRoot = if ([string]::IsNullOrWhiteSpace($CcInput)) { "" } else { $CcInput }
}

function Path-To-Hash { param([string]$Path); return $Path -replace ':', '-' -replace '[/\\]', '-' }

$WorkspaceHash = Path-To-Hash $WorkspacePath
$CcPrefix = ""
if ($ClaudeCodeRoot) { $CcPrefix = Path-To-Hash $ClaudeCodeRoot.TrimEnd('\', '/') }

function Resolve-CcTarget {
    param([string]$Rel)
    if (-not $ClaudeCodeRoot) { return "" }
    # restore 检查实际项目目录是否存在（不同于 pull 检查 claude 项目目录）
    $projectDir = Join-Path $ClaudeCodeRoot.TrimEnd('\', '/') $Rel
    if (-not (Test-Path $projectDir -PathType Container)) { return "" }
    $ccHash = Path-To-Hash "$($ClaudeCodeRoot.TrimEnd('\', '/'))/$Rel"
    return Join-Path $ClaudeHome "projects\$ccHash\memory"
}

$null = New-Item -ItemType Directory -Path $ClaudeHome -Force
$null = New-Item -ItemType Directory -Path $WorkspacePath -Force

# 1. 根据 sync.conf 恢复配置
Write-Host "  📦 恢复同步配置..."
$ConfFile = Join-Path $ScriptDir "sync.conf"

if (-not (Test-Path $ConfFile)) {
    Write-ColorOutput "    ⚠️  未找到 sync.conf，跳过配置恢复" "Yellow"
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
                    Copy-Item $repoPath -Destination $localPath -Force
                    Write-ColorOutput "    ✅ $src" "Green"
                } else { Write-Host "    ℹ️  $src 不存在（可选）" -ForegroundColor Gray }
            }
            "dir" {
                if ((Test-Path $repoPath) -and (Get-ChildItem $repoPath -ErrorAction SilentlyContinue)) {
                    $null = New-Item -ItemType Directory -Path $localPath -Force
                    Copy-Item -Path (Join-Path $repoPath "*") -Destination $localPath -Recurse -Force
                    Write-ColorOutput "    ✅ $src" "Green"
                } else { Write-Host "    ℹ️  $src 为空或不存在（可选）" -ForegroundColor Gray }
            }
            default { Write-ColorOutput "    ⚠️  未知类型: $type，跳过" "Yellow" }
        }
    }
}

# 2. 恢复项目记忆（按子目录结构）
Write-Host "  📝 恢复项目记忆..."
$MemoryBase = Join-Path $ScriptDir "claude\memory"

if (-not (Test-Path $MemoryBase) -or -not (Get-ChildItem $MemoryBase -ErrorAction SilentlyContinue)) {
    Write-ColorOutput "    ⚠️  仓库中无项目记忆" "Yellow"
} else {
    Get-ChildItem -Path $MemoryBase -Directory | ForEach-Object {
        $dirName = $_.Name

        if ($dirName -eq "_workspace") {
            $target = Join-Path $ClaudeHome "projects\$WorkspaceHash\memory"
            $null = New-Item -ItemType Directory -Path $target -Force
            Get-ChildItem -Path $_.FullName -Recurse | ForEach-Object {
                $rel = $_.FullName.Substring($_.Parent.FullName.Length + 1)
                if ($_.PSIsContainer) {
                    $null = New-Item -ItemType Directory -Path (Join-Path $target $rel) -Force
                } else {
                    $dest = Join-Path $target $_.FullName.Substring($_.FullName.IndexOf($dirName) + $dirName.Length + 1 + (Join-Path $MemoryBase $dirName).Length - (Join-Path $MemoryBase $dirName).Length)
                    $frel = $_.FullName.Substring((Join-Path $MemoryBase $dirName).Length).TrimStart('\', '/')
                    $dest = Join-Path $target $frel
                    $null = New-Item -ItemType Directory -Path (Split-Path $dest) -Force
                    Copy-Item $_.FullName -Destination $dest -Force
                }
            }
            Write-ColorOutput "    ✅ _workspace" "Green"

        } elseif ($dirName -eq "_cc") {
            Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
                $rel = $_.Name
                $ccSubPath = $_.FullName
                $target = Resolve-CcTarget $rel
                if (-not $target) {
                    Write-Host "    ⏭  _cc/$rel（本机无此项目，跳过）" -ForegroundColor Gray
                    return
                }
                $null = New-Item -ItemType Directory -Path $target -Force
                Get-ChildItem -Path $ccSubPath -Recurse -File | ForEach-Object {
                    $frel = $_.FullName.Substring($ccSubPath.Length).TrimStart('\', '/')
                    $dest = Join-Path $target $frel
                    $null = New-Item -ItemType Directory -Path (Split-Path $dest) -Force
                    Copy-Item $_.FullName -Destination $dest -Force
                }
                Write-ColorOutput "    ✅ _cc/$rel" "Green"
            }

        } else {
            $projPath = Join-Path $ClaudeHome "projects\$dirName"
            if (Test-Path $projPath) {
                $target = Join-Path $projPath "memory"
                $null = New-Item -ItemType Directory -Path $target -Force
                $memSubPath = $_.FullName
                Get-ChildItem -Path $memSubPath -Recurse -File | ForEach-Object {
                    $frel = $_.FullName.Substring($memSubPath.Length).TrimStart('\', '/')
                    $dest = Join-Path $target $frel
                    $null = New-Item -ItemType Directory -Path (Split-Path $dest) -Force
                    Copy-Item $_.FullName -Destination $dest -Force
                }
                Write-ColorOutput "    ✅ $dirName" "Green"
            } else {
                Write-Host "    ⏭  $dirName（本机无此项目，跳过）" -ForegroundColor Gray
            }
        }
    }
}

# 3. 持久化环境变量到 Windows 用户级环境变量
Write-Host "  💾 持久化环境变量..."
$envWrote = $false
if ($ClaudeCodeRoot) {
    $existing = [System.Environment]::GetEnvironmentVariable("CLAUDECODE_ROOT", "User")
    if ($existing -eq $ClaudeCodeRoot) {
        Write-Host "    ℹ️  CLAUDECODE_ROOT 已存在（相同值，跳过）" -ForegroundColor Gray
    } else {
        [System.Environment]::SetEnvironmentVariable("CLAUDECODE_ROOT", $ClaudeCodeRoot, "User")
        Write-ColorOutput "    ✅ CLAUDECODE_ROOT -> 用户环境变量" "Green"
        $envWrote = $true
    }
}
$defaultWorkspace = Join-Path $env:USERPROFILE "claude-workspace"
if ($WorkspacePath -and $WorkspacePath -ne $defaultWorkspace) {
    $existingWs = [System.Environment]::GetEnvironmentVariable("CLAUDE_WORKSPACE", "User")
    if ($existingWs -eq $WorkspacePath) {
        Write-Host "    ℹ️  CLAUDE_WORKSPACE 已存在（相同值，跳过）" -ForegroundColor Gray
    } else {
        [System.Environment]::SetEnvironmentVariable("CLAUDE_WORKSPACE", $WorkspacePath, "User")
        Write-ColorOutput "    ✅ CLAUDE_WORKSPACE -> 用户环境变量" "Green"
        $envWrote = $true
    }
}
if (-not $ClaudeCodeRoot -and -not $envWrote) {
    Write-Host "    ℹ️  CLAUDECODE_ROOT 未提供，跳过" -ForegroundColor Gray
}

Write-Host ""
Write-ColorOutput "✅ 配置恢复完成！" "Green"
Write-Host ""
Write-ColorOutput "⚠️  接下来请执行：" "Yellow"
Write-Host "  1. 运行 'claude setup-token' 重新登录"
Write-Host "  2. 运行 '.\verify.ps1' 验证配置"
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
