# Claude Code 配置同步仓库

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-Linux%20%7C%20macOS%20%7C%20Windows-blue)](#脚本版本说明)
[![Sync](https://img.shields.io/badge/sync-Gitea%20→%20GitHub-green)](#)

多设备同步 Claude Code 的配置、记忆、技能和工作脚本。

## 从模板开始使用

> ⚠️ **必须使用私有仓库**
> 同步内容包含 AI 记忆、个人配置和认证 Token，请务必将你的配置仓库设为 **Private**，切勿公开存储。

### 第一步：创建你自己的私有仓库

在 GitHub 点击 **Use this template → Create a new repository**，设为 **Private**。也可以在 Gitea 等自托管 Git 服务上创建私有仓库。

### 第二步：克隆到本地

```bash
git clone https://YOUR_USERNAME:YOUR_TOKEN@YOUR_GIT_HOST/YOUR_USERNAME/YOUR_REPO.git ~/claude-config-sync
```

> 推荐将 Token 嵌入 URL，脚本后续的推送操作无需额外认证。

### 第三步：配置同步清单

```bash
cd ~/claude-config-sync
cp sync.conf.example sync.conf
```

按需编辑 `sync.conf`，指定要同步的文件和目录（详见下方说明）。

### 第四步：恢复配置

```bash
./restore.sh           # Linux/macOS
.\restore.ps1          # Windows PowerShell
```

脚本会将仓库内容应用到 `~/.claude/` 和工作目录。

### 第五步：登录 Claude Code

```bash
claude setup-token
```

### 第六步：完成 Skill 初始化

在 Claude Code 中调用：

```
/sync-claude-config
```

首次调用时，Claude 会自动读取仓库 URL 并将其写入 Skill，之后直接使用无需再次配置。

---

## 目录结构

```
claude-config-sync/
├── sync.conf                    # 同步清单（配置化，按需修改）
├── claude/
│   ├── CLAUDE.md               # 全局 AI 行为约束
│   ├── settings/
│   │   └── settings.json       # 全局设置（模型、语言等）
│   ├── memory/                 # 项目记忆文件
│   │   ├── MEMORY.md
│   │   └── halo-blog-helper.md
│   └── skills/                 # 自定义技能
│       ├── halo-blog/
│       └── sync-claude-config/
├── workspace-scripts/          # 工作目录 keep/ 脚本
├── pull.sh / pull.ps1 / pull-windows.sh       # 拉取并应用配置
├── update.sh / update.ps1 / update-windows.sh # 推送本地变更
├── restore.sh / restore.ps1 / restore-windows.sh  # 新设备恢复
└── verify.sh / verify.ps1 / verify-windows.sh     # 验证配置完整性
```

## sync.conf 说明

`sync.conf` 定义哪些文件/目录需要同步，无需修改脚本：

```
# 格式：<type> <base> <src> <dest>
file  claude_home  settings.json  claude/settings/settings.json
file  claude_home  CLAUDE.md      claude/CLAUDE.md
dir   claude_home  skills         claude/skills
dir   workspace    keep           workspace-scripts
```

新增同步项只需在 `sync.conf` 加一行，`project memory` 由脚本内置处理。

## 日常使用

### 拉取配置（开始工作前）

```bash
# Linux/macOS
cd ~/claude-config-sync && ./pull.sh

# Windows PowerShell
cd ~\claude-config-sync; .\pull.ps1
```

### 推送变更

```bash
# Linux/macOS
cd ~/claude-config-sync && ./update.sh "更新 MEMORY.md"

# Windows PowerShell
cd ~\claude-config-sync; .\update.ps1 -Message "更新 MEMORY.md"
```

update 脚本自动处理 `git add / commit / push`，只需提供 commit message。

## 新设备恢复

```bash
# 1. 克隆仓库
git clone https://YOUR_USERNAME:YOUR_TOKEN@YOUR_GIT_HOST/YOUR_USERNAME/YOUR_REPO.git ~/claude-config-sync

# 2. 恢复配置
cd ~/claude-config-sync
./restore.sh           # Linux/macOS
.\restore.ps1          # Windows PowerShell

# 3. 登录
claude setup-token

# 4. 验证
./verify.sh            # Linux/macOS
.\verify.ps1           # Windows PowerShell
```

## 环境变量（可选）

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `CLAUDE_HOME` | Claude 配置目录 | `~/.claude` / `%USERPROFILE%\.claude` |
| `CLAUDE_WORKSPACE` | 工作目录 | `~/claude-workspace` / `%USERPROFILE%\claude-workspace` |
| `CLAUDECODE_ROOT` | ClaudeCode 项目根目录（用于同步 `_cc/` 子项目记忆） | 未设置则跳过 `_cc/` |

## 脚本版本说明

| 后缀 | 平台 | 执行者 |
|------|------|--------|
| `.sh` | Linux/macOS | 用户、AI |
| `.ps1` | Windows PowerShell | 用户 |
| `-windows.sh` | Windows Git Bash | AI（Bash 工具） |

**最后更新**: 2026-02-24
