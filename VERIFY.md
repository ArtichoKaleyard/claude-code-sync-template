# Claude Code 配置验证指南

## 推荐方式：运行内置验证脚本

```bash
# Linux/macOS
cd ~/claude-config-sync && ./verify.sh

# Windows PowerShell
cd ~\claude-config-sync; .\verify.ps1
```

脚本会自动执行以下 7 项检查并输出通过/失败汇总：

| 检查项 | 内容 |
|--------|------|
| 0️⃣  同步配置 | `sync.conf` 是否存在及条目数 |
| 1️⃣  基础目录 | `.claude`、`settings.json`、`CLAUDE.md`、`projects`、`skills` |
| 2️⃣  项目记忆 | `_workspace` 和 `_cc/*` 记忆文件是否落地 |
| 3️⃣  自定义技能 | `skills/` 目录下的技能数量 |
| 4️⃣  工作目录脚本 | `keep/` 目录及脚本文件 |
| 5️⃣  配置内容 | `settings.json` 中 model/language 字段 |
| 6️⃣  项目识别 | `~/.claude/projects/` 下所有项目及记忆文件数 |
| 7️⃣  .ps1 文件编码 | 所有 `.ps1` 是否为 UTF-8 BOM（缺失时提示修复） |

---

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CLAUDE_HOME` | Claude 配置目录 | `~/.claude` / `%USERPROFILE%\.claude` |
| `CLAUDE_WORKSPACE` | 工作目录 | `~/claude-workspace` / `%USERPROFILE%\claude-workspace` |
| `CLAUDECODE_ROOT` | ClaudeCode 项目根目录（用于验证 `_cc/` 子项目记忆） | 未设置则跳过 `_cc/` |

---

## 常见问题排查

### 问题：`_workspace` 记忆未找到

检查 `CLAUDE_WORKSPACE` 是否与实际工作目录一致：

```powershell
# Windows：查看实际项目目录名
Get-ChildItem $env:USERPROFILE\.claude\projects\ | Select-Object Name
```

确认目录名与 `path_to_hash(WORKSPACE)` 计算结果一致。

### 问题：`_cc/Herald` 跳过

需设置 `CLAUDECODE_ROOT` 环境变量，且对应项目目录需在 `~/.claude/projects/` 中存在（即曾在该目录下打开过 Claude Code）：

```powershell
$env:CLAUDECODE_ROOT = "C:\Users\YourName\Documents\ClaudeCode"
.\verify.ps1
```

### 问题：`.ps1 文件缺少 BOM`

直接运行 pull 脚本即可自动修复：

```powershell
.\pull.ps1
```

### 问题：PowerShell 执行策略错误

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

---

**最后更新**: 2026-02-24
