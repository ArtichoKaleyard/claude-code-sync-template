# Claude Code 配置快速验证脚本（Windows PowerShell）

param(
    [string]$ClaudeHome = $env:CLAUDE_HOME,
    [string]$ClaudeWorkspace = $env:CLAUDE_WORKSPACE,
    [string]$ClaudeCodeRoot = $env:CLAUDECODE_ROOT
)

$ErrorActionPreference = "Continue"

function Write-Status {
    param([string]$Message, [string]$Status = "Info", [string]$Indent = "")
    switch ($Status) {
        "Pass" { Write-Host "$Indent✅ $Message" -ForegroundColor Green }
        "Fail" { Write-Host "$Indent❌ $Message" -ForegroundColor Red }
        "Warn" { Write-Host "$Indent⚠️  $Message" -ForegroundColor Yellow }
        "Info" { Write-Host "$Indent$Message" -ForegroundColor Cyan }
    }
}

Write-Status "开始验证 Claude Code 配置..." "Info"
Write-Host ""

$PASSED = 0
$FAILED = 0
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if (-not $ClaudeHome)     { $ClaudeHome = Join-Path $env:USERPROFILE ".claude" }
if (-not $ClaudeWorkspace){ $ClaudeWorkspace = Join-Path $env:USERPROFILE "claude-workspace" }

function Path-To-Hash { param([string]$Path); return $Path -replace ':', '-' -replace '[/\\]', '-' }
$WorkspaceHash = Path-To-Hash $ClaudeWorkspace
$CcPrefix = if ($ClaudeCodeRoot) { Path-To-Hash $ClaudeCodeRoot.TrimEnd('\', '/') } else { "" }

# 0. 检查 sync.conf
Write-Status "0️⃣  检查同步配置" "Info"
$ConfFile = Join-Path $ScriptDir "sync.conf"
if (Test-Path $ConfFile) {
    Write-Status "sync.conf 存在" "Pass"; $PASSED++
    $entryCount = (Get-Content $ConfFile | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*$' }).Count
    Write-Host "   已配置 $entryCount 个同步条目" -ForegroundColor Gray
} else { Write-Status "sync.conf 不存在" "Fail"; $FAILED++ }
Write-Host ""

# 1. 检查基础目录
Write-Status "1️⃣  检查基础目录" "Info"
@(
    @{Path = $ClaudeHome;                              Type = "Dir";  Name = ".claude 存在"}
    @{Path = Join-Path $ClaudeHome "settings.json";   Type = "File"; Name = "settings.json 存在"}
    @{Path = Join-Path $ClaudeHome "CLAUDE.md";       Type = "File"; Name = "CLAUDE.md 存在"}
    @{Path = Join-Path $ClaudeHome "projects";        Type = "Dir";  Name = "projects 目录存在"}
    @{Path = Join-Path $ClaudeHome "skills";          Type = "Dir";  Name = "skills 目录存在"}
) | ForEach-Object {
    $ok = if ($_.Type -eq "File") { Test-Path $_.Path -PathType Leaf }
          else                    { Test-Path $_.Path -PathType Container }
    if ($ok) { Write-Status $_.Name "Pass"; $PASSED++ }
    else      { Write-Status $_.Name "Fail"; $FAILED++ }
}
Write-Host ""

# 2. 检查项目记忆
Write-Status "2️⃣  检查项目记忆" "Info"
$workspaceMem = Join-Path $ClaudeHome "projects\$WorkspaceHash\memory"
if ((Test-Path $workspaceMem) -and (Get-ChildItem $workspaceMem -ErrorAction SilentlyContinue)) {
    $memFiles = @(Get-ChildItem $workspaceMem -File)
    Write-Status "_workspace 记忆已落地（$($memFiles.Count) 个文件）" "Pass"; $PASSED++
    $memFiles | ForEach-Object { Write-Host "   📄 $($_.Name)" -ForegroundColor Gray }
} else {
    Write-Status "_workspace 记忆未找到（$workspaceMem）" "Fail"; $FAILED++
}

if ($ClaudeCodeRoot -and $CcPrefix) {
    $ccCount = 0
    Get-ChildItem -Path (Join-Path $ClaudeHome "projects") -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name.StartsWith("$CcPrefix-") } | ForEach-Object {
        $rel = $_.Name.Substring($CcPrefix.Length + 1)
        $memDir = Join-Path $_.FullName "memory"
        if (Test-Path $memDir) {
            Write-Status "_cc/$rel 记忆已落地" "Pass"; $PASSED++
            Get-ChildItem $memDir -File | ForEach-Object { Write-Host "   📄 $($_.Name)" -ForegroundColor Gray }
            $ccCount++
        }
    }
    if ($ccCount -eq 0) { Write-Host "   ℹ️  未发现 ClaudeCode 项目记忆（CLAUDECODE_ROOT=$ClaudeCodeRoot）" -ForegroundColor Gray }
}
Write-Host ""

# 3. 检查技能
Write-Status "3️⃣  检查自定义技能" "Info"
$skills = @(Get-ChildItem -Path (Join-Path $ClaudeHome "skills") -Directory -ErrorAction SilentlyContinue)
if ($skills.Count -gt 0) {
    Write-Status "发现 $($skills.Count) 个技能" "Pass"; $PASSED++
    $skills | ForEach-Object { Write-Host "   ⚡ $($_.Name)" }
} else { Write-Status "未找到自定义技能" "Warn" }
Write-Host ""

# 4. 检查工作目录脚本
Write-Status "4️⃣  检查工作目录脚本" "Info"
$keepDir = Join-Path $ClaudeWorkspace "keep"
if (Test-Path $keepDir) {
    Write-Status "keep 目录存在" "Pass"; $PASSED++
    $scripts = @(Get-ChildItem $keepDir -File -ErrorAction SilentlyContinue)
    if ($scripts.Count -gt 0) {
        Write-Status "发现 $($scripts.Count) 个脚本文件" "Pass"; $PASSED++
        $scripts | ForEach-Object { Write-Host "   📜 $($_.Name)" }
    } else { Write-Status "keep 目录为空（可选）" "Warn" }
} else { Write-Status "keep 目录不存在（可选）" "Warn" }
Write-Host ""

# 5. 验证配置内容
Write-Status "5️⃣  验证配置内容" "Info"
$settingsPath = Join-Path $ClaudeHome "settings.json"
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Encoding UTF8 | ConvertFrom-Json
        if ($settings.model)    { Write-Status "模型设置: $($settings.model)"    "Pass"; $PASSED++ }
        if ($settings.language) { Write-Status "语言设置: $($settings.language)" "Pass"; $PASSED++ }
    } catch { Write-Status "settings.json 解析失败" "Fail"; $FAILED++ }
} else { Write-Status "settings.json 不存在" "Fail"; $FAILED++ }
Write-Host ""

# 6. 项目识别
Write-Status "6️⃣  项目识别" "Info"
$projects = @(Get-ChildItem -Path (Join-Path $ClaudeHome "projects") -Directory -ErrorAction SilentlyContinue)
if ($projects.Count -gt 0) {
    Write-Status "发现 $($projects.Count) 个项目" "Pass"; $PASSED++
    $projects | ForEach-Object {
        $memCount = @(Get-ChildItem (Join-Path $_.FullName "memory") -File -ErrorAction SilentlyContinue).Count
        Write-Host "   📁 $($_.Name)（记忆文件: $memCount）"
    }
} else { Write-Status "未找到项目" "Warn" }
Write-Host ""

# 7. 检查 .ps1 文件编码（UTF-8 BOM）
Write-Status "7️⃣  检查 .ps1 文件编码" "Info"
$ps1Files = @(Get-ChildItem $ScriptDir -Filter "*.ps1")
$noBomFiles = @()
foreach ($f in $ps1Files) {
    $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBOM = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    if (-not $hasBOM) { $noBomFiles += $f.Name }
}
if ($noBomFiles.Count -eq 0) {
    Write-Status "所有 .ps1 文件均为 UTF-8 BOM（共 $($ps1Files.Count) 个）" "Pass"; $PASSED++
} else {
    Write-Status "以下 .ps1 文件缺少 BOM，在中文 Windows 上可能解析失败：" "Fail"; $FAILED++
    $noBomFiles | ForEach-Object { Write-Host "   ⚠️  $_" -ForegroundColor Red }
    Write-Host "   💡 运行 pull.ps1 可自动修复" -ForegroundColor Gray
}
Write-Host ""

# 总结
Write-Host ("=" * 42) -ForegroundColor Cyan
Write-Status "通过: $PASSED" "Pass"
if ($FAILED -gt 0) { Write-Status "失败: $FAILED" "Fail" }
Write-Host ("=" * 42) -ForegroundColor Cyan
Write-Host ""
if ($FAILED -eq 0) { Write-Status "🎉 所有配置已正确生效！" "Pass"; exit 0 }
else               { Write-Status "⚠️  有些配置未能正确恢复，请检查日志" "Warn"; exit 1 }
