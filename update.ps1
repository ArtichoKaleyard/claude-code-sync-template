# Claude Code 配置更新脚本（Windows PowerShell）
# 更新本地配置到仓库并提交到 Git

param(
    [string]$ClaudeHome = $env:CLAUDE_HOME,
    [string]$ClaudeWorkspace = $env:CLAUDE_WORKSPACE,
    [string]$ClaudeCodeRoot = $env:CLAUDECODE_ROOT,
    [string]$Message = ""
)

$ErrorActionPreference = "Stop"

function Write-ColorOutput {
    param([string]$Message, [string]$Color = "White")
    Write-Host $Message -ForegroundColor $Color
}

Write-ColorOutput "📥 更新 Claude Code 配置到仓库..." "Cyan"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

if (-not $ClaudeHome) {
    $ClaudeHome = Join-Path $env:USERPROFILE ".claude"
}
if (-not (Test-Path $ClaudeHome)) {
    Write-ColorOutput "❌ 错误：Claude 配置目录不存在: $ClaudeHome" "Red"
    exit 1
}

# 检测工作目录
$WorkspacePath = $null
if ($ClaudeWorkspace -and (Test-Path $ClaudeWorkspace)) {
    $WorkspacePath = $ClaudeWorkspace
} elseif (Test-Path (Join-Path $env:USERPROFILE "claude-workspace")) {
    $WorkspacePath = Join-Path $env:USERPROFILE "claude-workspace"
} else {
    $WorkspacePath = Join-Path $env:USERPROFILE "claude-workspace"
}

# 路径转 Claude 项目 hash（Windows：将 : 和 \ 替换为 -）
function Path-To-Hash {
    param([string]$Path)
    return $Path -replace ':', '-' -replace '[/\\]', '-'
}

$WorkspaceHash = Path-To-Hash $WorkspacePath
$CcPrefix = ""
if ($ClaudeCodeRoot) {
    $CcPrefix = Path-To-Hash $ClaudeCodeRoot.TrimEnd('\', '/')
}

# 1. 根据 sync.conf 推送配置
Write-Host "  📦 同步配置到仓库..."
$ConfFile = Join-Path $ScriptDir "sync.conf"

if (-not (Test-Path $ConfFile)) {
    Write-ColorOutput "    ⚠️  未找到 sync.conf，跳过配置同步" "Yellow"
} else {
    Get-Content $ConfFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -match '^\s*#' -or [string]::IsNullOrWhiteSpace($line)) { return }

        $parts = $line -split '\s+', 4
        if ($parts.Count -lt 4) { return }
        $type, $base, $src, $dest = $parts

        $basePath = switch ($base) {
            "claude_home" { $ClaudeHome }
            "workspace"   { $WorkspacePath }
            default {
                Write-ColorOutput "    ⚠️  未知 base: $base，跳过" "Yellow"
                return
            }
        }

        $localPath = Join-Path $basePath  $src
        $repoPath  = Join-Path $ScriptDir $dest

        switch ($type) {
            "file" {
                $null = New-Item -ItemType Directory -Path (Split-Path $repoPath) -Force
                if (Test-Path $localPath) {
                    Copy-Item $localPath -Destination $repoPath -Force
                    Write-ColorOutput "    ✅ $src" "Green"
                } else {
                    Write-Host "    ℹ️  $src 不存在（可选）" -ForegroundColor Gray
                }
            }
            "dir" {
                if ((Test-Path $localPath) -and (Get-ChildItem $localPath -ErrorAction SilentlyContinue)) {
                    $null = New-Item -ItemType Directory -Path $repoPath -Force
                    Copy-Item -Path (Join-Path $localPath "*") -Destination $repoPath -Recurse -Force
                    Write-ColorOutput "    ✅ $src" "Green"
                } else {
                    Write-Host "    ℹ️  $src 为空或不存在（可选）" -ForegroundColor Gray
                }
            }
            default {
                Write-ColorOutput "    ⚠️  未知类型: $type，跳过" "Yellow"
            }
        }
    }
}

# 2. 同步项目记忆（按项目分类存储）
# 存储结构：
#   claude/memory/_workspace/     ← 全局工作目录（跨平台）
#   claude/memory/_cc/{name}/     ← ClaudeCode 约定项目（跨平台，按相对名）
#   claude/memory/{hash}/         ← 普通项目（原始 hash 名，按缘分同步）
Write-Host "  📝 更新项目记忆..."
$FoundMemory = $false

$ProjectsDir = Join-Path $ClaudeHome "projects"
if (Test-Path $ProjectsDir) {
    Get-ChildItem -Path $ProjectsDir -Directory | ForEach-Object {
        $ProjectMemoryDir = Join-Path $_.FullName "memory"
        if (-not (Test-Path $ProjectMemoryDir)) { return }

        $projectName = $_.Name

        if ($projectName -eq $WorkspaceHash) {
            $destDir = Join-Path $ScriptDir "claude\memory\_workspace"
            $label = "_workspace"
        } elseif ($CcPrefix -and $projectName.StartsWith("$CcPrefix-")) {
            $rel = $projectName.Substring($CcPrefix.Length + 1)
            $destDir = Join-Path $ScriptDir "claude\memory\_cc\$rel"
            $label = "_cc/$rel"
        } else {
            $destDir = Join-Path $ScriptDir "claude\memory\$projectName"
            $label = $projectName
        }

        $null = New-Item -ItemType Directory -Path $destDir -Force
        Get-ChildItem -Path $ProjectMemoryDir -Recurse | ForEach-Object {
            $rel = $_.FullName.Substring($ProjectMemoryDir.Length).TrimStart('\', '/')
            $dest = Join-Path $destDir $rel
            if ($_.PSIsContainer) {
                $null = New-Item -ItemType Directory -Path $dest -Force
            } else {
                $null = New-Item -ItemType Directory -Path (Split-Path $dest) -Force
                Copy-Item $_.FullName -Destination $dest -Force
            }
        }
        Write-ColorOutput "    ✅ $label" "Green"
        $FoundMemory = $true
    }
}
if (-not $FoundMemory) {
    Write-ColorOutput "    ⚠️  警告：未找到项目记忆目录" "Yellow"
}

Write-Host ""
Write-ColorOutput "✅ 配置已同步到本地仓库目录" "Green"
Write-Host ""

# 3. Git 提交和推送
Write-Host "  🔄 检查 Git 状态..."
try {
    $status = git status --porcelain
    if ($status) {
        if ($Message) {
            git add .
            Write-ColorOutput "    ✅ 已暂存所有更改" "Green"
            git commit -m $Message
            Write-ColorOutput "    ✅ 已提交: $Message" "Green"
            git push
            Write-ColorOutput "    ✅ 已推送到远程仓库" "Green"
        } else {
            Write-ColorOutput "    ⚠️  有文件改动但未提供 commit message，跳过提交" "Yellow"
            Write-Host "    示例: .\update.ps1 -Message '更新 MEMORY.md'" -ForegroundColor Cyan
        }
    } else {
        Write-ColorOutput "    ℹ️  没有文件改动，无需提交" "Cyan"
        $unpushed = git log "@{u}..HEAD" --oneline 2>$null
        if ($unpushed) {
            Write-ColorOutput "    ⚠️  发现未推送的提交：" "Yellow"
            $unpushed | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
            git push
            Write-ColorOutput "    ✅ 已推送到远程仓库" "Green"
        }
    }
} catch {
    Write-ColorOutput "    ❌ Git 操作失败: $_" "Red"
    exit 1
}

Write-Host ""
Write-Host "提示：环境变量配置（PowerShell 管理员）：" -ForegroundColor Gray
Write-Host '  [Environment]::SetEnvironmentVariable("CLAUDE_HOME", "$env:USERPROFILE\.claude", "User")' -ForegroundColor Gray
Write-Host '  [Environment]::SetEnvironmentVariable("CLAUDE_WORKSPACE", "$env:USERPROFILE\claude-workspace", "User")' -ForegroundColor Gray
Write-Host '  [Environment]::SetEnvironmentVariable("CLAUDECODE_ROOT", "$env:USERPROFILE\Documents\ClaudeCode", "User")' -ForegroundColor Gray
