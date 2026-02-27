# 跨平台使用指南

## 🖥️ 支持的平台

- ✅ **Linux** (Bash 脚本)
- ✅ **macOS** (Bash 脚本)
- ✅ **Windows** (PowerShell 脚本)

---

## 📋 环境变量配置

| 变量 | 作用 | 默认值 |
|------|------|--------|
| `CLAUDECODE_ROOT` | ClaudeCode 根目录，用于定位 `_cc/` 子项目并同步其记忆 | 无（未设置则跳过 `_cc/`） |
| `CLAUDE_WORKSPACE` | claude-workspace 工作目录路径 | `~/claude-workspace` |
| `CLAUDE_HOME` | Claude Code 配置目录 | `~/.claude` |

### restore 自动写入（推荐）

**运行 `restore` 脚本时，交互输入 `CLAUDECODE_ROOT` 路径后，脚本会自动持久化，无需手动操作：**

- `restore.ps1` → 写入 Windows 用户级环境变量（所有新开的 PowerShell / Git Bash 均继承）
- `restore-windows.sh` → 写入 Windows 用户级环境变量 + `~/.bashrc`
- `restore.sh` → 写入 `~/.bashrc` 或 `~/.zshrc`（自动检测当前 shell）

重新打开终端后即生效。

### 手动设置（跳过了 restore，或需要在 pull 前提前配置）

#### Linux/macOS

追加到 `~/.bashrc` 或 `~/.zshrc`：

```bash
export CLAUDECODE_ROOT="$HOME/Documents/ClaudeCode"
```

应用配置：
```bash
source ~/.bashrc  # 或 source ~/.zshrc
```

#### Windows (PowerShell)

**永久设置（用户级，推荐）：**

```powershell
[System.Environment]::SetEnvironmentVariable('CLAUDECODE_ROOT', "$env:USERPROFILE\Documents\ClaudeCode", 'User')
```

重开 PowerShell 或 Git Bash 后生效。

**当前会话（临时）：**
```powershell
$env:CLAUDECODE_ROOT = "$env:USERPROFILE\Documents\ClaudeCode"
```

**图形界面：**
- 打开"系统属性" → "高级" → "环境变量"
- 在"用户变量"中添加 `CLAUDECODE_ROOT`

---

## 🔄 更新配置

### Linux/macOS

```bash
cd ~/claude-config-sync
./update.sh "更新配置描述"
```

### Windows (PowerShell)

```powershell
cd $env:USERPROFILE\claude-config-sync
.\update.ps1 -Message "更新配置描述"
```

update 脚本自动完成 `git add / commit / push`，只需提供 commit message。

---

## 📥 新设备恢复配置

### Linux/macOS

```bash
# 1. 克隆仓库
git clone https://YOUR_USERNAME:YOUR_TOKEN@YOUR_GIT_HOST/YOUR_USERNAME/YOUR_REPO.git ~/claude-config-sync

# 2. 恢复配置
cd ~/claude-config-sync
chmod +x restore.sh update.sh
./restore.sh

# 3. 重新登录
claude setup-token
```

### Windows (PowerShell)

```powershell
# 1. 克隆仓库
git clone https://YOUR_USERNAME:YOUR_TOKEN@YOUR_GIT_HOST/YOUR_USERNAME/YOUR_REPO.git $env:USERPROFILE\claude-config-sync

# 2. 允许脚本执行（首次需要，管理员权限）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 3. 恢复配置
cd $env:USERPROFILE\claude-config-sync
.\restore.ps1

# 4. 重新登录
claude setup-token
```

---

## 🔧 脚本功能说明

### update.sh / update.ps1

**自动检测功能：**
1. ✅ 自动查找所有项目的 memory 目录
2. ✅ 自动检测工作目录路径（支持多个常见位置）
3. ✅ 支持环境变量自定义路径
4. ✅ 彩色输出显示进度
5. ✅ PowerShell 版本支持参数传递

**文件来源优先级：**
- Claude 配置：`$CLAUDE_HOME` → `~/.claude` (Unix) 或 `%USERPROFILE%\.claude` (Windows)
- 工作目录：`$CLAUDE_WORKSPACE` → `~/claude-workspace` → `~/workspace`

**PowerShell 高级用法：**
```powershell
# 使用自定义路径
.\update.ps1 -ClaudeHome "D:\MyApps\.claude" -ClaudeWorkspace "D:\Projects\claude"

# 查看帮助
Get-Help .\update.ps1 -Detailed
```

### restore.sh / restore.ps1

**智能恢复功能：**
1. ✅ 自动检测或询问工作目录路径
2. ✅ 根据路径自动生成项目目录名
3. ✅ 交互式确认路径（无环境变量时）
4. ✅ 显示恢复后的路径信息
5. ✅ PowerShell 版本支持非交互模式
6. ✅ 自动将 `CLAUDECODE_ROOT` 等变量持久化到系统（Windows 用户级环境变量 / shell rc 文件）

**路径转换规则：**
- Linux: `/home/user/claude-workspace` → `~/.claude/projects/-home-user-claude-workspace/memory`
- macOS: `/Users/user/workspace` → `~/.claude/projects/-Users-user-workspace/memory`
- Windows: `C:\Users\User\claude-workspace` → `%USERPROFILE%\.claude\projects\C--Users-User-claude-workspace\memory`

**PowerShell 高级用法：**
```powershell
# 非交互模式（自动化脚本）
.\restore.ps1 -NonInteractive

# 指定自定义路径
.\restore.ps1 -ClaudeHome "D:\MyApps\.claude" -ClaudeWorkspace "D:\Projects\claude"
```

---

## 📂 目录结构

```
claude-config-sync/
├── sync.conf                        # 同步清单（配置化）
├── claude/
│   ├── CLAUDE.md                   # 全局 AI 行为约束
│   ├── settings/
│   │   └── settings.json           # 全局设置
│   ├── memory/                     # 项目记忆
│   │   ├── MEMORY.md
│   │   └── halo-blog-helper.md
│   └── skills/                     # 自定义技能
│       └── halo-blog/
├── workspace-scripts/              # 工作目录脚本
├── pull.sh / pull.ps1 / pull-windows.sh        # 拉取并应用配置
├── update.sh / update.ps1 / update-windows.sh  # 推送本地变更
├── restore.sh / restore.ps1 / restore-windows.sh  # 新设备恢复
├── verify.sh / verify.ps1 / verify-windows.sh     # 验证完整性
├── README.md                       # 基本说明
└── PLATFORM-GUIDE.md              # 本文件
```

> `-windows.sh` 系列脚本为 Windows Git Bash 版本，主要供 AI 通过 Bash 工具自动执行。

---

## 🔍 故障排查

### Windows PowerShell 执行策略问题

**错误信息：**
```
无法加载文件 xxx.ps1，因为在此系统上禁止运行脚本。
```

**解决方案：**
```powershell
# 方案一：仅当前用户（推荐）
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# 方案二：临时绕过（仅当前会话）
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# 方案三：查看当前策略
Get-ExecutionPolicy -List
```

### 问题：找不到项目记忆

**Linux/macOS:**
```bash
# 检查实际项目路径
ls ~/.claude/projects/

# 手动设置环境变量
export CLAUDE_WORKSPACE="/path/to/your/workspace"
./restore.sh
```

**Windows (PowerShell):**
```powershell
# 检查实际项目路径
Get-ChildItem $env:USERPROFILE\.claude\projects\

# 手动设置环境变量
$env:CLAUDE_WORKSPACE = "C:\path\to\your\workspace"
.\restore.ps1
```

### 问题：脚本无法执行

**Linux/macOS:**
```bash
# 添加执行权限
chmod +x update.sh restore.sh
```

**Windows (PowerShell):**
```powershell
# 检查执行策略
Get-ExecutionPolicy

# 临时允许执行
Set-ExecutionPolicy Bypass -Scope Process -Force
.\restore.ps1
```

### 问题：路径包含空格

脚本已支持路径中的空格，无需特殊处理。

**示例：**
```powershell
# Windows - 路径有空格也能正常工作
$env:CLAUDE_WORKSPACE = "C:\Users\My Name\My Documents\claude workspace"
.\update.ps1
```

### 问题：PowerShell 脚本出现中文乱码或语法报错

`.ps1` 脚本需要保存为 **UTF-8 with BOM**，否则 PowerShell 在中文 Windows 上无法正确解析含中文字符的脚本。

`pull.ps1` 和 `pull-windows.sh` 会在每次 git pull 后自动恢复 BOM，直接运行即可修复：

```powershell
.\pull.ps1
```

也可通过 `verify.ps1` 的 7️⃣ 检查项确认当前状态。

---

## 💡 最佳实践

### 1. 统一工作目录

在所有设备上使用相同的相对路径：
- Linux/macOS: `~/claude-workspace`
- Windows: `%USERPROFILE%\claude-workspace`

### 2. 配置环境变量

即使路径符合默认规则，也建议显式配置环境变量，提高可维护性。

### 3. 定期同步

设置定时任务自动同步：

**Linux (crontab):**
```bash
# 每天凌晨 2 点同步
0 2 * * * cd ~/claude-config-sync && ./update.sh "自动同步 $(date +\%Y-\%m-\%d)" 2>&1 | logger -t claude-sync
```

**Windows (Task Scheduler + PowerShell):**

创建 `auto-sync.ps1`：
```powershell
Set-Location $env:USERPROFILE\claude-config-sync
$date = Get-Date -Format "yyyy-MM-dd HH:mm"
.\update.ps1 -Message "自动同步 $date"
```

然后在任务计划程序中创建任务：
- 程序：`powershell.exe`
- 参数：`-ExecutionPolicy Bypass -File "C:\Users\YourName\claude-config-sync\auto-sync.ps1"`
- 触发器：每天凌晨 2:00

### 4. PowerShell Profile 快捷方式

在 PowerShell 配置文件中添加别名（`$PROFILE`）：

```powershell
# Claude Code 同步快捷命令
function Sync-ClaudeConfig {
    param([string]$Message = "更新配置 $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
    Push-Location $env:USERPROFILE\claude-config-sync
    .\update.ps1 -Message $Message
    Pop-Location
}

Set-Alias -Name claude-sync -Value Sync-ClaudeConfig
```

使用时直接运行：
```powershell
claude-sync
```

---

## 🔐 安全提示

1. **Token 保护**：
   - 不要在公开场合分享克隆命令（包含 token）
   - 使用 Git Credential Manager 存储凭证
   - Windows 推荐安装 [Git Credential Manager](https://github.com/GitCredentialManager/git-credential-manager)

2. **PowerShell 执行策略**：
   - 使用 `RemoteSigned` 而非 `Unrestricted`
   - 验证脚本来源后再执行
   - 考虑对脚本进行数字签名

3. **仓库私有性**：
   - 确保 Gitea 仓库设置为 Private
   - 定期检查访问权限
   - 定期轮换 Access Token

4. **敏感信息**：
   - `.gitignore` 已配置排除敏感文件
   - 不要手动添加 `.credentials.json`
   - 不要提交包含密码或密钥的文件

---

## 🆚 PowerShell vs Batch

### 为什么使用 PowerShell？

| 特性 | PowerShell | Batch |
|------|-----------|-------|
| **现代性** | ✅ 现代化，持续更新 | ❌ 过时，不再发展 |
| **跨平台** | ✅ PowerShell Core 支持 Linux/macOS | ❌ 仅 Windows |
| **对象处理** | ✅ 面向对象，处理复杂数据 | ❌ 纯文本处理 |
| **错误处理** | ✅ Try-Catch，详细错误信息 | ❌ 简单的 ERRORLEVEL |
| **Unicode** | ✅ 完整 Unicode 支持 | ❌ 编码问题频繁 |
| **可读性** | ✅ 清晰的语法和命令 | ❌ 晦涩的语法 |
| **功能** | ✅ 丰富的 cmdlet 和 .NET 库 | ❌ 功能有限 |

---

**最后更新**: 2026-02-28
**PowerShell 版本**: 5.1+ (Windows PowerShell) 或 7+ (PowerShell Core)
