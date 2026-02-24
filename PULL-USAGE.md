# pull.sh / pull.ps1 - 配置拉取和应用脚本

一个综合脚本，用来从 Gitea 仓库拉取最新的 Claude Code 配置，并自动应用到本地系统。

## 三阶段执行流程

### Phase 1：差异检查（pull 之前）

对比本地配置与仓库中的版本，记录有差异的文件。有差异的文件在 Phase 3 中会暂停并展示 diff，而不是静默覆盖。

### Phase 2：git pull

从 Gitea 拉取最新配置。

- **BOM 自动处理**（`.ps1` 和 `-windows.sh` 版本）：pull 前剥离 `.ps1` 文件的 UTF-8 BOM（避免 git 将其识别为本地修改拒绝合并），pull 后自动恢复 BOM（PowerShell 在中文 Windows 上需要 BOM 才能正确解析含中文的脚本）。
- **脚本自更新**：若脚本本身在本次 pull 中被更新，自动重启一次以应用新逻辑。

### Phase 3：逐文件应用

按 `sync.conf` 清单应用文件和目录，并恢复项目记忆到 `~/.claude/projects/`。有差异的文件展示 diff 并跳过，无差异的直接覆盖。

同步内容由 `sync.conf` 配置，默认包含：
- `settings.json`、`CLAUDE.md` → `~/.claude/`
- `skills/` → `~/.claude/skills/`
- `workspace-scripts/` → `~/claude-workspace/keep/`

## 使用方法

### Linux / macOS

```bash
cd ~/claude-config-sync
./pull.sh
```

或指定工作目录：
```bash
CLAUDE_WORKSPACE=~/my-workspace ./pull.sh
```

### Windows PowerShell

```powershell
cd ~\claude-config-sync
.\pull.ps1
```

或指定工作目录：
```powershell
.\pull.ps1 -ClaudeWorkspace "C:\Users\YourName\my-workspace"
```

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CLAUDE_HOME` | Claude Code 配置目录 | `~/.claude` / `%USERPROFILE%\.claude` |
| `CLAUDE_WORKSPACE` | 工作目录路径 | `~/claude-workspace`（自动检测） |
| `CLAUDECODE_ROOT` | ClaudeCode 项目根目录（用于同步 `_cc/` 子项目记忆） | 未设置则跳过 `_cc/` |

### 设置环境变量

**Bash/Zsh:**
```bash
export CLAUDE_HOME="$HOME/.claude"
export CLAUDE_WORKSPACE="$HOME/claude-workspace"
```

**PowerShell:**
```powershell
$env:CLAUDE_HOME = "$env:USERPROFILE\.claude"
$env:CLAUDE_WORKSPACE = "$env:USERPROFILE\claude-workspace"
```

## 使用流程

典型的日常工作流程：

1. 在配置仓库目录运行脚本：
   ```bash
   cd ~/claude-config-sync
   ./pull.sh
   ```

2. 脚本会自动：
   - 检查工作目录（或提示输入）
   - 拉取最新配置
   - 应用所有配置文件到本地

3. 验证配置：
   ```bash
   # Linux/macOS
   cat ~/.claude/settings.json
   ls ~/.claude/projects/*/memory/
   ls ~/.claude/skills/

   # Windows PowerShell
   Get-Content $env:USERPROFILE\.claude\settings.json
   Get-ChildItem $env:USERPROFILE\.claude\projects\*/memory
   Get-ChildItem $env:USERPROFILE\.claude\skills
   ```

## 工作目录自动检测

脚本按以下优先级检测工作目录：

1. **环境变量** - `CLAUDE_WORKSPACE` 环境变量（如果设置）
2. **常见路径** - `~/claude-workspace` 或 `~/claude-workspace` 是否存在
3. **交互式输入** - 用户手动输入（非交互模式除外）

## 多平台兼容特性

### 路径处理

- **Linux/macOS**: 使用 POSIX 路径 (`/home/user/.claude`)
- **Windows**: 使用 Windows 路径 (`C:\Users\User\.claude`)
- **~ 展开**: 自动将 `~` 扩展为用户主目录

### 项目名称转换

工作目录路径转换为项目名称的规则：

- **Linux/macOS**: `/home/atk/claude-workspace` → `-home-atk-claude-workspace`
- **Windows**: `C:\Users\atk\claude-workspace` → `C--Users-atk-claude-workspace`

这确保了相同的工作目录在任何操作系统上都映射到同一个项目记忆目录。

## 故障排查

### 问题：权限错误

**Linux/macOS:**
```bash
chmod +x ~/claude-config-sync/pull.sh
```

**Windows PowerShell:**
```powershell
# 如果遇到执行策略错误
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### 问题：Git 拉取失败

检查 git 配置和认证：
```bash
cd ~/claude-config-sync
git remote -v
git config user.name
git config user.email
```

### 问题：配置不更新

确保仓库目录结构正确：
```bash
# 应该存在这些目录
ls ~/claude-config-sync/claude/{settings,memory,skills}
ls ~/claude-config-sync/workspace-scripts
```

## 与其他脚本的关系

| 脚本 | 用途 |
|------|------|
| `pull.sh/ps1` | ✨ **新** - 拉取并应用配置（本地->仓库->本地） |
| `update.sh/ps1` | 更新本地配置到仓库（本地→仓库） |
| `restore.sh/ps1` | 在新设备恢复配置（仓库→本地） |
| `verify.sh/ps1` | 验证配置完整性和一致性 |

典型用法：

- **日常更新**: `./pull.sh` - 拉取别的设备上传的配置
- **配置同步**: `./update.sh` - 将本地更改上传到仓库
- **新设备**: `./restore.sh` - 首次恢复所有配置
- **验证配置**: `./verify.sh` - 检查配置是否正确

## 非交互模式（仅 PowerShell）

用于自动化脚本或 CI/CD：

```powershell
.\pull.ps1 -NonInteractive -ClaudeWorkspace "C:\Users\YourName\claude-workspace"
```

---

**最后更新**: 2026-02-24
**支持平台**: Linux, macOS, Windows (PowerShell 5.1+)
