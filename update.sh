#!/bin/bash
# Claude Code 配置更新脚本（Linux/macOS）
# 更新本地配置到仓库并提交到 Git

set -e

MESSAGE="$1"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📥 更新 Claude Code 配置到仓库...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

if [ ! -d "${CLAUDE_HOME}" ]; then
    echo "❌ 错误：Claude 配置目录不存在: ${CLAUDE_HOME}"
    exit 1
fi

# 检测工作目录
if [ -n "${CLAUDE_WORKSPACE}" ] && [ -d "${CLAUDE_WORKSPACE}" ]; then
    WORKSPACE_PATH="${CLAUDE_WORKSPACE}"
elif [ -d "$HOME/claude-workspace" ]; then
    WORKSPACE_PATH="$HOME/claude-workspace"
else
    WORKSPACE_PATH="$HOME/claude-workspace"
fi

# 检测 ClaudeCode 项目根目录（可选）
CLAUDECODE_ROOT="${CLAUDECODE_ROOT:-}"

# 路径转 Claude 项目 hash（Linux/macOS：将 / 替换为 -）
path_to_hash() {
    local real
    real=$(realpath -m "$1" 2>/dev/null || echo "$1")
    printf '%s' "$real" | python3 -c "import sys; s=sys.stdin.read(); print(''.join('-' if c=='/' or ord(c)>127 else c for c in s), end='')"
}

WORKSPACE_HASH=$(path_to_hash "$WORKSPACE_PATH")
CC_PREFIX=""
if [ -n "$CLAUDECODE_ROOT" ]; then
    CC_PREFIX=$(path_to_hash "${CLAUDECODE_ROOT%/}")
fi

# 1. 根据 sync.conf 推送配置
echo "  📦 同步配置到仓库..."
CONF_FILE="${SCRIPT_DIR}/sync.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo -e "    ${YELLOW}⚠️  未找到 sync.conf，跳过配置同步${NC}"
else
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        read -r type base src dest <<< "$line"

        case "$base" in
            claude_home) base_path="$CLAUDE_HOME" ;;
            workspace)   base_path="$WORKSPACE_PATH" ;;
            *) echo -e "    ${YELLOW}⚠️  未知 base: $base，跳过${NC}"; continue ;;
        esac

        local_path="${base_path}/${src}"
        repo_path="${SCRIPT_DIR}/${dest}"

        case "$type" in
            file)
                mkdir -p "$(dirname "$repo_path")"
                if [ -f "$local_path" ]; then
                    cp "$local_path" "$repo_path"
                    echo "    ✅ $src"
                else
                    echo "    ℹ️  $src 不存在（可选）"
                fi
                ;;
            dir)
                if [ -d "$local_path" ] && [ "$(ls -A "$local_path" 2>/dev/null)" ]; then
                    mkdir -p "$repo_path"
                    cp -r "$local_path/." "$repo_path/"
                    echo "    ✅ $src"
                else
                    echo "    ℹ️  $src 为空或不存在（可选）"
                fi
                ;;
            *)
                echo -e "    ${YELLOW}⚠️  未知类型: $type，跳过${NC}"
                ;;
        esac
    done < "$CONF_FILE"
fi

# 2. 同步项目记忆（按项目分类存储）
# 存储结构：
#   claude/memory/_workspace/     ← 全局工作目录（跨平台）
#   claude/memory/_cc/{name}/     ← ClaudeCode 约定项目（跨平台，按相对名）
#   claude/memory/{hash}/         ← 普通项目（原始 hash 名，按缘分同步）
echo "  📝 更新项目记忆..."
FOUND_MEMORY=0

for project_dir in "${CLAUDE_HOME}/projects"/*/; do
    [ -d "${project_dir}memory" ] || continue
    project_name=$(basename "$project_dir")
    memory_src="${project_dir}memory"

    if [ "$project_name" = "$WORKSPACE_HASH" ]; then
        dest_dir="${SCRIPT_DIR}/claude/memory/_workspace"
        label="_workspace"
    elif [ -n "$CC_PREFIX" ] && [[ "$project_name" == "${CC_PREFIX}-"* ]]; then
        rel="${project_name#${CC_PREFIX}-}"
        dest_dir="${SCRIPT_DIR}/claude/memory/_cc/${rel}"
        label="_cc/${rel}"
    else
        dest_dir="${SCRIPT_DIR}/claude/memory/${project_name}"
        label="${project_name}"
    fi

    mkdir -p "$dest_dir"
    cp -r "${memory_src}/." "$dest_dir/"
    echo "    ✅ ${label}"
    FOUND_MEMORY=1
done

if [ "$FOUND_MEMORY" -eq 0 ]; then
    echo "    ⚠️  警告：未找到项目记忆目录"
fi

echo -e "${GREEN}✅ 配置已同步到本地仓库目录${NC}"
echo ""

# 3. Git 提交和推送
echo "  🔄 检查 Git 状态..."
if git status --porcelain | grep -q .; then
    if [ -n "$MESSAGE" ]; then
        git add .
        echo -e "    ${GREEN}✅ 已暂存所有更改${NC}"
        git commit -m "$MESSAGE"
        echo -e "    ${GREEN}✅ 已提交: $MESSAGE${NC}"
        git push
        echo -e "    ${GREEN}✅ 已推送到远程仓库${NC}"
    else
        echo -e "    ${YELLOW}⚠️  有文件改动但未提供 commit message，跳过提交${NC}"
        echo -e "    ${BLUE}示例: ./update.sh '更新 MEMORY.md'${NC}"
    fi
else
    echo -e "    ${BLUE}ℹ️  没有文件改动，无需提交${NC}"
    UNPUSHED=$(git log @{u}..HEAD --oneline 2>/dev/null)
    if [ -n "$UNPUSHED" ]; then
        echo -e "    ${YELLOW}⚠️  发现未推送的提交：${NC}"
        echo "$UNPUSHED" | sed 's/^/      /'
        git push
        echo -e "    ${GREEN}✅ 已推送到远程仓库${NC}"
    fi
fi

echo ""
echo "提示：环境变量配置"
echo "  - CLAUDE_HOME:      Claude 配置目录（当前: ${CLAUDE_HOME}）"
echo "  - CLAUDE_WORKSPACE: 工作目录路径（当前: ${CLAUDE_WORKSPACE:-未设置}）"
echo "  - CLAUDECODE_ROOT:  ClaudeCode 项目根目录（当前: ${CLAUDECODE_ROOT:-未设置}）"
