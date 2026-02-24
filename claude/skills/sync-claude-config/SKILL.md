---
name: sync-claude-config
description: Complete Claude Code configuration sync workflow - pull, push, verify, and restore across multiple devices
---

# Claude Code 配置同步工作流

## ⚙️ 初始化检查

若本文件中存在 `## 🔧 首次初始化` 章节，在处理任何请求前优先执行该章节中的步骤。

## 🔧 首次初始化（仅执行一次）

> **AI 必读**：检测到本节存在，表示此 Skill 尚未绑定仓库。请立即完成以下一次性配置，完成后将本节从文件中永久删除。

**Step 1：获取仓库信息**

```bash
git -C ~/claude-config-sync remote get-url origin
```

输出格式示例：`https://alice:token123@git.example.com/alice/my-config.git`

从中解析：
- **GIT_HOST** = `git.example.com`（`@` 之后、第一个 `/` 之前）
- **USERNAME** = `alice`（`://` 之后、`:` 之前）
- **REPO_NAME** = `my-config`（最后一段，去掉 `.git`）

**Step 2：替换本文件中的占位符**

使用 Edit 工具对 `~/.claude/skills/sync-claude-config/SKILL.md` 进行以下全局替换（replace_all: true）：
- `YOUR_GIT_HOST` → 实际 GIT_HOST
- `YOUR_USERNAME` → 实际 USERNAME
- `YOUR_REPO_NAME` → 实际 REPO_NAME

**Step 3：删除本节**

使用 Edit 工具，将本文件中从 `## 🔧 首次初始化（仅执行一次）` 这一行开始、到 `## Purpose` 之前的全部内容（含上方空行）删除。

**Step 4：完成**

告知用户："Skill 已完成初始化，仓库信息已写入，下次调用将直接使用。"

## Purpose

综合管理 Claude Code 多设备配置同步。通过自动化脚本和 Git 仓库实现：
- 📥 拉取最新配置到本地
- 📤 推送本地修改到远程
- ✅ 验证配置完整性
- 🔄 在新设备上恢复配置

## Repository Information

- **仓库地址**: https://YOUR_GIT_HOST/YOUR_USERNAME/YOUR_REPO_NAME
- **Local Path**: ~/claude-config-sync
- **Authentication**: HTTPS + Personal Access Token

## Complete Workflow

### 1️⃣ 日常拉取 (Pull Configuration)

**快速命令：**
```bash
cd ~/claude-config-sync
./pull.ps1              # Windows PowerShell
./pull-windows.sh       # Windows Bash/WSL（AI 可调用）
./pull.sh               # Linux/macOS Bash
```

**三阶段执行流程：**

| 阶段 | 内容 |
|------|------|
| Phase 1：差异检查 | pull 前对比本地与仓库的差异，有改动的文件在 Phase 3 展示 diff 并暂停，而非静默覆盖 |
| Phase 2：git pull | 从远程仓库拉取；`.ps1` / `-windows.sh` 脚本在 pull 前剥离 BOM、pull 后自动恢复 BOM（防止 git 冲突且保证 PowerShell 正确解析） |
| Phase 3：逐文件应用 | 按 `sync.conf` 应用文件和目录，并恢复项目记忆；无差异直接覆盖，有差异暂停审核 |

**何时使用：**
- 开始工作前同步其他设备的更改
- 切换到不同设备后

### 2️⃣ 修改配置 (Edit Configuration)

**可修改的文件：**
- `~/.claude/settings.json` - 模型和语言设置
- `~/.claude/projects/.../memory/MEMORY.md` - AI 项目记忆
- `~/.claude/skills/` - 自定义技能
- `~/claude-workspace/keep/` - 工作脚本

**修改后：**
直接编辑相应文件，无需手动复制

### 3️⃣ 推送修改 (Push Changes)

**快速命令：**
```bash
cd ~/claude-config-sync
./update.ps1 -Message "更新 MEMORY.md"              # Windows PowerShell
./update-windows.sh "更新 MEMORY.md"                # Windows Bash/WSL（AI 可调用）
./update.sh "更新 MEMORY.md"                        # Linux/macOS Bash
```

**功能：**
- 检测本地修改
- 自动复制更改到仓库
- 自动提交到 Git（需提供 commit message）
- 自动推送到远程仓库

**Commit Message 生成：**
在执行脚本前，根据修改内容生成清晰的 commit message。示例：
- `"更新 MEMORY.md - 添加 Windows 环境记录"`
- `"新增 sync-claude-config skill"`
- `"增强 update.ps1 - 支持 Git 集成"`

### 4️⃣ 验证配置 (Verify Sync)

**快速命令：**
```bash
cd ~/claude-config-sync
./verify.ps1            # Windows PowerShell
./verify-windows.sh     # Windows Bash/WSL（AI 可调用）
./verify.sh             # Linux/macOS Bash
```

**功能（7 项自动检查）：**
- 0️⃣ sync.conf 存在及条目数
- 1️⃣ 基础目录（.claude、settings.json、CLAUDE.md、projects、skills）
- 2️⃣ 项目记忆（`_workspace` 和 `_cc/*`）是否正确落地
- 3️⃣ 技能目录和数量
- 4️⃣ 工作目录 keep/ 脚本
- 5️⃣ settings.json 中 model/language 字段
- 6️⃣ ~/.claude/projects/ 下所有项目
- 7️⃣ 所有 `.ps1` 文件是否为 UTF-8 BOM（缺失时报错并提示修复）

## 多平台使用

### Windows PowerShell

```powershell
cd ~\claude-config-sync
.\pull.ps1                                    # 拉取 + 应用
.\update.ps1 -Message "修改内容描述"          # 修改后推送
.\verify.ps1                                  # 验证配置
.\restore.ps1                                 # 新设备恢复
```

### Windows Bash (Git Bash / WSL)

```bash
cd ~/claude-config-sync
./pull-windows.sh                       # 拉取 + 应用
./update-windows.sh "修改内容描述"      # 修改后推送
./verify-windows.sh                     # 验证配置
./restore-windows.sh                    # 新设备恢复
```

**说明：** Windows Bash 脚本使用 Windows 路径格式 (`C:\Users\...`)，支持 Git Bash 和 WSL。AI 可通过 Bash 工具自动执行。

### Linux / macOS

```bash
cd ~/claude-config-sync
./pull.sh                       # 拉取 + 应用
./update.sh "修改内容描述"      # 修改后推送
./verify.sh                     # 验证配置
./restore.sh                    # 新设备恢复
```

## 环境变量配置

**Bash/Zsh:**
```bash
export CLAUDE_HOME="$HOME/.claude"
export CLAUDE_WORKSPACE="$HOME/claude-workspace"
export CLAUDECODE_ROOT="$HOME/Documents/ClaudeCode"  # 可选，用于同步 _cc/ 子项目记忆
```

**PowerShell:**
```powershell
$env:CLAUDE_HOME = "$env:USERPROFILE\.claude"
$env:CLAUDE_WORKSPACE = "$env:USERPROFILE\claude-workspace"
$env:CLAUDECODE_ROOT = "$env:USERPROFILE\Documents\ClaudeCode"  # 可选
```

`CLAUDECODE_ROOT` 未设置时，`_cc/` 子项目记忆会被跳过（显示 `⏭  _cc/xxx（本机无此项目，跳过）`），这是正常行为。

## 典型工作流

### 📋 日常工作流

```
1. 开始工作
   cd ~/claude-config-sync && ./pull.ps1
   ↓
2. 修改配置（如更新 MEMORY.md）
   编辑 ~/.claude/projects/.../memory/MEMORY.md
   ↓
3. 生成 commit message
   message="更新 MEMORY.md - 添加新配置"
   ↓
4. 推送修改
   cd ~/claude-config-sync && ./update.ps1 -Message "$message"
   ↓
5. 验证（可选）
   cd ~/claude-config-sync && ./verify.ps1
```

### 🆕 新设备设置

```
1. 从现有设备获取仓库 URL（含 Token）
   git -C ~/claude-config-sync remote get-url origin
   ↓
2. 在新设备克隆（使用上一步完整输出）
   git clone <完整 URL（含 Token）> ~/claude-config-sync
   ↓
3. 运行恢复脚本
   cd ~/claude-config-sync && ./restore.ps1
   ↓
4. 登录 Claude Code
   claude setup-token
   ↓
5. 验证配置
   cd ~/claude-config-sync && ./verify.ps1
```

## Synced Content

```
~/claude-config-sync/
├── claude/
│   ├── memory/
│   │   ├── MEMORY.md              # AI 项目记忆
│   │   └── ...
│   ├── settings/
│   │   └── settings.json          # 全局设置
│   └── skills/
│       ├── sync-claude-config/    # 同步 skill
│       └── ...
├── workspace-scripts/             # 工作脚本
│   └── ...
├── pull.sh / pull.ps1            # 拉取 + 应用
├── update.sh / update.ps1        # 推送修改
├── restore.sh / restore.ps1      # 恢复配置
├── verify.sh / verify.ps1        # 验证完整性
└── README.md
```

## Multi-Device Workflow

**关键规则：**
1. **Always pull before push** - 推送前先拉取最新
2. **Check status first** - 推送前检查冲突
3. **Descriptive messages** - 提交信息清晰明确
4. **Verify after sync** - 同步后验证配置
5. **始终使用脚本，禁止裸 git 命令** - 所有日常操作（pull/push/verify）必须通过脚本执行，不得直接调用 `git pull`、`git commit`、`git push` 等命令，保持工作流一致性

**冲突解决：**
- 同一文件在多个设备修改时，后推送者会看到冲突
- 使用 `git status` 查看冲突文件
- 手动合并后重新 `./update.ps1 -Message "解决冲突: <说明>"`

## Token Management

⚠️ **Security Notice:**
- Token 嵌入在克隆 URL 中，不要公开分享
- 如果 Token 暴露，访问 `https://YOUR_GIT_HOST/user/settings/applications` 撤销
- 定期轮换 Token（建议每月一次）

**查看当前 Token（从 remote URL 解析）：**
```bash
git -C ~/claude-config-sync remote get-url origin
# 输出格式：https://用户名:TOKEN@host/用户名/仓库名.git
```

**更新 Token：**
```bash
cd ~/claude-config-sync
git remote set-url origin https://YOUR_USERNAME:新TOKEN@YOUR_GIT_HOST/YOUR_USERNAME/YOUR_REPO_NAME.git
git remote -v  # 验证
```

## Troubleshooting

### 拉取失败

```bash
cd ~/claude-config-sync
git remote -v
git status

# 如果认证错误，更新 token（见 Token Management 章节）
git remote set-url origin https://YOUR_USERNAME:TOKEN@YOUR_GIT_HOST/YOUR_USERNAME/YOUR_REPO_NAME.git
```

### 脚本权限错误 (Linux/macOS)

```bash
chmod +x ~/claude-config-sync/*.sh
```

### 推送后配置未更新

```bash
cd ~/claude-config-sync && ./pull.ps1
```

### 技能无法加载

```bash
chmod -R 755 ~/.claude/skills/
claude --reload
```

### PowerShell 脚本中文乱码 / 语法报错

`.ps1` 文件需要 UTF-8 BOM。直接运行 pull 脚本即可自动修复：

```powershell
.\pull.ps1
```

或通过 `verify.ps1` 7️⃣ 项检查确认状态。

### `_cc/xxx` 始终显示"本机无此项目，跳过"

1. 确认已设置 `$env:CLAUDECODE_ROOT`
2. 确认该项目目录在 `~/.claude/projects/` 中存在（需曾在该目录下打开过 Claude Code）
3. 路径中不要混用 `/` 和 `\`（脚本已自动处理，但环境变量本身不应有异常字符）

## sync.conf 与仓库原生文件

| 文件类型 | 同步方式 | 示例 |
|----------|----------|------|
| 需要复制到 `~/.claude/` 或 workspace 的文件 | 加入 sync.conf | settings.json、MEMORY.md、skills、keep/ |
| 只属于仓库本身的文件 | git 自动同步，无需 sync.conf | `.gitattributes`、`.gitignore`、`README.md`、脚本文件 |

## 特殊 Git 操作

- **行尾规范化**：添加或修改 `.gitattributes` 后，需执行 `git add --renormalize .`
- **手动冲突解决**：merge conflict 时需要手动编辑文件后 `git add`

执行完特殊操作后，**最终的 push 仍应走 `update-windows.sh` / `update.ps1`**，不要用裸 `git push`。

## Best Practices

1. **定期同步** - 每个工作会话开始都 pull 一次
2. **清晰的提交信息** - 说明修改了什么和为什么
3. **Token 安全** - 定期轮换，不要分享
4. **验证配置** - 推送后验证确保完整
5. **脚本优先** - 日常操作永远走脚本，特殊 git 操作是例外而非惯例

## Script Relationships

| 脚本 | 用途 | 使用场景 |
|------|------|---------|
| `pull.ps1` | 拉取 + 应用配置 (Windows PowerShell) | 日常同步、开始工作 |
| `pull-windows.sh` | 拉取 + 应用配置 (Windows Bash/WSL) | AI 自动执行、日常同步 |
| `pull.sh` | 拉取 + 应用配置 (Linux/macOS) | 日常同步、开始工作 |
| `update.ps1` | 推送本地修改 (Windows PowerShell) | 修改配置后 |
| `update-windows.sh` | 推送本地修改 (Windows Bash/WSL) | AI 自动执行、修改配置后 |
| `update.sh` | 推送本地修改 (Linux/macOS) | 修改配置后 |
| `verify.ps1/verify-windows.sh/verify.sh` | 验证配置完整性 | 同步后验证 |
| `restore.ps1/restore-windows.sh/restore.sh` | 新设备完整恢复 | 初次设置设备 |

---

**版本**: 2.4 (template)
**支持平台**: Windows (PowerShell 5.1+, Git Bash, WSL), Linux, macOS
