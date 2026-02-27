#!/bin/bash
# Claude Code 配置恢复脚本（Linux/macOS）
# 在新设备上恢复配置（假设仓库已克隆到本地）

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔄 恢复 Claude Code 配置...${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"

if [ -n "${CLAUDE_WORKSPACE}" ]; then
    WORKSPACE_PATH="${CLAUDE_WORKSPACE}"
elif [ -d "$HOME/claude-workspace" ]; then
    WORKSPACE_PATH="$HOME/claude-workspace"
else
    read -p "📂 请输入工作目录路径 [~/claude-workspace]: " WORKSPACE_INPUT
    WORKSPACE_PATH="${WORKSPACE_INPUT:-$HOME/claude-workspace}"
fi
WORKSPACE_PATH="${WORKSPACE_PATH/#\~/$HOME}"

if [ -n "${CLAUDECODE_ROOT}" ]; then
    : # 已由环境变量提供
else
    _CC_DIR="${SCRIPT_DIR}/claude/memory/_cc"
    if [ -d "$_CC_DIR" ]; then
        _CC_LIST=$(ls "$_CC_DIR" 2>/dev/null | tr '\n' ' ')
        read -p "📂 请输入 ClaudeCode 根目录路径（_cc/ 含项目: ${_CC_LIST}，留空跳过）: " CC_INPUT
    else
        read -p "📂 请输入 ClaudeCode 根目录路径（留空跳过）: " CC_INPUT
    fi
    CLAUDECODE_ROOT="${CC_INPUT:-}"
fi

path_to_hash() {
    local real
    real=$(realpath -m "$1" 2>/dev/null || echo "$1")
    printf '%s' "$real" | python3 -c "import sys; s=sys.stdin.read(); print(''.join('-' if c=='/' or ord(c)>127 else c for c in s), end='')"
}

WORKSPACE_HASH=$(path_to_hash "$WORKSPACE_PATH")
if [ -n "$CLAUDECODE_ROOT" ]; then
    CC_PREFIX=$(path_to_hash "${CLAUDECODE_ROOT%/}")
fi

resolve_cc_target() {
    local rel="$1"
    [ -z "$CLAUDECODE_ROOT" ] && echo "" && return
    # restore 检查实际项目目录是否存在（不同于 pull 检查 claude 项目目录）
    if [ ! -d "${CLAUDECODE_ROOT%/}/${rel}" ]; then
        echo ""
        return
    fi
    local cc_hash
    cc_hash=$(path_to_hash "${CLAUDECODE_ROOT%/}/${rel}")
    echo "${CLAUDE_HOME}/projects/${cc_hash}/memory"
}

mkdir -p "${CLAUDE_HOME}"
mkdir -p "${WORKSPACE_PATH}"

# 1. 根据 sync.conf 恢复配置
echo "  📦 恢复同步配置..."
CONF_FILE="${SCRIPT_DIR}/sync.conf"

if [ ! -f "$CONF_FILE" ]; then
    echo -e "    ${YELLOW}⚠️  未找到 sync.conf，跳过配置恢复${NC}"
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

        repo_path="${SCRIPT_DIR}/${dest}"
        local_path="${base_path}/${src}"

        case "$type" in
            file)
                mkdir -p "$(dirname "$local_path")"
                if [ -f "$repo_path" ]; then
                    cp "$repo_path" "$local_path"
                    echo "    ✅ $src"
                else
                    echo "    ℹ️  $src 不存在（可选）"
                fi
                ;;
            dir)
                if [ -d "$repo_path" ] && [ "$(ls -A "$repo_path" 2>/dev/null)" ]; then
                    mkdir -p "$local_path"
                    cp -r "$repo_path/." "$local_path/"
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

# 2. 恢复项目记忆（按子目录结构）
echo "  📝 恢复项目记忆..."
MEMORY_BASE="${SCRIPT_DIR}/claude/memory"

if [ ! -d "$MEMORY_BASE" ] || [ -z "$(ls -A "$MEMORY_BASE" 2>/dev/null)" ]; then
    echo "    ⚠️  仓库中无项目记忆"
else
    for repo_mem_dir in "${MEMORY_BASE}"/*/; do
        [ -d "$repo_mem_dir" ] || continue
        dir_name=$(basename "$repo_mem_dir")

        if [ "$dir_name" = "_workspace" ]; then
            target="${CLAUDE_HOME}/projects/${WORKSPACE_HASH}/memory"
            mkdir -p "$target"
            cp -r "${repo_mem_dir}." "$target/"
            echo "    ✅ _workspace"

        elif [ "$dir_name" = "_cc" ]; then
            for cc_subdir in "${repo_mem_dir}"*/; do
                [ -d "$cc_subdir" ] || continue
                rel=$(basename "$cc_subdir")
                target=$(resolve_cc_target "$rel")
                if [ -z "$target" ]; then
                    echo "    ⏭  _cc/${rel}（本机无此项目，跳过）"
                else
                    mkdir -p "$target"
                    cp -r "${cc_subdir}." "$target/"
                    echo "    ✅ _cc/${rel}"
                fi
            done

        else
            if [ -d "${CLAUDE_HOME}/projects/${dir_name}" ]; then
                target="${CLAUDE_HOME}/projects/${dir_name}/memory"
                mkdir -p "$target"
                cp -r "${repo_mem_dir}." "$target/"
                echo "    ✅ ${dir_name}"
            else
                echo "    ⏭  ${dir_name}（本机无此项目，跳过）"
            fi
        fi
    done
fi

# 3. 持久化环境变量到 shell 配置文件
echo "  💾 持久化环境变量..."
if [ -n "$ZSH_VERSION" ] || [ "$(basename "${SHELL:-}")" = "zsh" ]; then
    _RC_FILE="$HOME/.zshrc"
else
    _RC_FILE="$HOME/.bashrc"
fi
_write_env_sh() {
    local var_name="$1"
    local var_value="$2"
    if grep -q "^export ${var_name}=" "$_RC_FILE" 2>/dev/null; then
        local existing
        existing=$(grep "^export ${var_name}=" "$_RC_FILE" | tail -1 | sed "s/^export ${var_name}=//; s/['\"]//g")
        if [ "$existing" = "$var_value" ]; then
            echo "    ℹ️  ${var_name} 已存在（相同值，跳过）"
        else
            echo "    ⚠️  $_RC_FILE 中 ${var_name} 值不同，请手动更新"
        fi
    else
        printf '\nexport %s="%s"\n' "$var_name" "$var_value" >> "$_RC_FILE"
        echo "    ✅ ${var_name} -> $_RC_FILE"
    fi
}
if [ -n "$CLAUDECODE_ROOT" ]; then
    _write_env_sh "CLAUDECODE_ROOT" "$CLAUDECODE_ROOT"
fi
DEFAULT_WORKSPACE="$HOME/claude-workspace"
if [ -n "$WORKSPACE_PATH" ] && [ "$WORKSPACE_PATH" != "$DEFAULT_WORKSPACE" ]; then
    _write_env_sh "CLAUDE_WORKSPACE" "$WORKSPACE_PATH"
fi
if [ -z "$CLAUDECODE_ROOT" ]; then
    echo "    ℹ️  CLAUDECODE_ROOT 未提供，跳过"
fi

echo ""
echo -e "${GREEN}✅ 配置恢复完成！${NC}"
echo ""
echo -e "${YELLOW}⚠️  接下来请执行：${NC}"
echo "  1. 运行 'claude setup-token' 重新登录"
echo "  2. 运行 './verify.sh' 验证配置"
echo ""
echo "环境信息："
echo "  - Claude 配置:      ${CLAUDE_HOME}"
echo "  - 工作目录:         ${WORKSPACE_PATH}"
echo "  - ClaudeCode 根目录: ${CLAUDECODE_ROOT:-未设置}"
echo ""
