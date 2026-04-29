#!/bin/bash
# Claude Code 配置拉取和应用脚本（Windows Bash - Git Bash/WSL）
# 三阶段：差异检查 → git pull → 审核应用

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}🔄 拉取并应用 Claude Code 配置...${NC}"

# PowerShell 在中文 Windows 上需要 UTF-8 BOM 才能正确解析含中文的脚本
# git 通常存储无 BOM 版本（尤其来自 Linux 端），故每次 pull 前剥离、pull 后恢复
_ps1_bom() {
    local action="$1" dir="$2"
    local win_dir add_bom
    win_dir=$(cygpath -w "$dir" 2>/dev/null || echo "$dir")
    [ "$action" = "add" ] && add_bom="\$true" || add_bom="\$false"
    powershell.exe -NoProfile -Command "
        \$enc = [System.Text.UTF8Encoding]::new($add_bom)
        Get-ChildItem '$win_dir' -Filter '*.ps1' | ForEach-Object {
            \$text = [System.IO.File]::ReadAllText(\$_.FullName, [System.Text.Encoding]::UTF8)
            [System.IO.File]::WriteAllText(\$_.FullName, \$text, \$enc)
        }
    " > /dev/null 2>&1 || true
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

APPLY_MISSING_CC=false
for arg in "$@"; do
    [ "$arg" = "--apply-missing-cc" ] && APPLY_MISSING_CC=true
done

CLAUDE_HOME="${CLAUDE_HOME:-$USERPROFILE/.claude}"

if [ -n "${CLAUDE_WORKSPACE}" ]; then
    WORKSPACE_PATH="${CLAUDE_WORKSPACE}"
elif [ -d "$USERPROFILE/claude-workspace" ]; then
    WORKSPACE_PATH="$USERPROFILE/claude-workspace"
else
    read -p "📂 请输入工作目录路径 [$USERPROFILE/claude-workspace]: " WORKSPACE_INPUT
    WORKSPACE_PATH="${WORKSPACE_INPUT:-$USERPROFILE/claude-workspace}"
fi
WORKSPACE_PATH="${WORKSPACE_PATH/#\~/$USERPROFILE}"

CLAUDECODE_ROOT="${CLAUDECODE_ROOT:-}"

# 路径转 Claude 项目 hash（Windows：将 : 和 \ 替换为 -）
path_to_hash() {
    echo "$1" | sed 's/:/\-/g' | sed 's|[/\\]|-|g'
}

WORKSPACE_HASH=$(path_to_hash "$WORKSPACE_PATH")
CC_PREFIX=""
if [ -n "$CLAUDECODE_ROOT" ]; then
    CC_PREFIX=$(path_to_hash "${CLAUDECODE_ROOT%\\}")
fi

_PULL_RESTARTS=${_PULL_RESTARTS:-0}

resolve_memory_target() {
    local dir_name="$1"
    case "$dir_name" in
        _workspace)
            echo "${CLAUDE_HOME}/projects/${WORKSPACE_HASH}/memory"
            ;;
        _cc)
            echo ""
            ;;
        *)
            if [ -d "${CLAUDE_HOME}/projects/${dir_name}" ]; then
                echo "${CLAUDE_HOME}/projects/${dir_name}/memory"
            else
                echo ""
            fi
            ;;
    esac
}

resolve_cc_target() {
    local rel="$1"
    [ -z "$CLAUDECODE_ROOT" ] && echo "" && return
    local cc_hash
    cc_hash=$(path_to_hash "${CLAUDECODE_ROOT%\\}/${rel}")
    echo "${CLAUDE_HOME}/projects/${cc_hash}/memory"
}

# ──────────────────────────────────────────────────────────────
# Phase 1: 差异检查（git pull 之前）
# ──────────────────────────────────────────────────────────────
if [ -z "${_PULL_DIFF_STATE_FILE}" ] || [ ! -f "${_PULL_DIFF_STATE_FILE}" ]; then
    echo "  🔍 检查本地配置差异..."
    DIFF_STATE_FILE=$(mktemp /tmp/claude-pull-diff-XXXXXX)
    export _PULL_DIFF_STATE_FILE="${DIFF_STATE_FILE}"
    HAS_ANY_DIFF=false

    CONF_FILE="${SCRIPT_DIR}/sync.conf"
    if [ -f "$CONF_FILE" ]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            line="${line%$'\r'}"
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "${line// }" ]] && continue
            read -r type base src dest <<< "$line"
            case "$base" in
                claude_home) base_path="$CLAUDE_HOME" ;;
                workspace)   base_path="$WORKSPACE_PATH" ;;
                *) continue ;;
            esac
            repo_path="${SCRIPT_DIR}/${dest}"
            local_path="${base_path}/${src}"
            case "$type" in
                file)
                    if [ -f "$local_path" ] && [ -f "$repo_path" ]; then
                        if ! diff -q --strip-trailing-cr "$local_path" "$repo_path" > /dev/null 2>&1; then
                            echo "DIFF:${src}" >> "${DIFF_STATE_FILE}"
                            HAS_ANY_DIFF=true
                        fi
                    fi
                    ;;
                dir)
                    if [ -d "$local_path" ] && [ -d "$repo_path" ]; then
                        while IFS= read -r -d '' repo_file; do
                            rel="${repo_file#${repo_path}/}"
                            local_file="${local_path}/${rel}"
                            if [ -f "$local_file" ]; then
                                if ! diff -q --strip-trailing-cr "$local_file" "$repo_file" > /dev/null 2>&1; then
                                    echo "DIFF:${src}/${rel}" >> "${DIFF_STATE_FILE}"
                                    HAS_ANY_DIFF=true
                                fi
                            fi
                        done < <(find "$repo_path" -type f -print0)
                    fi
                    ;;
            esac
        done < "$CONF_FILE"
    fi

    MEMORY_BASE="${SCRIPT_DIR}/claude/memory"
    if [ -d "$MEMORY_BASE" ]; then
        for repo_mem_dir in "${MEMORY_BASE}"/*/; do
            [ -d "$repo_mem_dir" ] || continue
            dir_name=$(basename "$repo_mem_dir")
            if [ "$dir_name" = "_cc" ]; then
                for cc_subdir in "${repo_mem_dir}"*/; do
                    [ -d "$cc_subdir" ] || continue
                    rel=$(basename "$cc_subdir")
                    target=$(resolve_cc_target "$rel")
                    [ -z "$target" ] && continue
                    while IFS= read -r -d '' repo_file; do
                        frel="${repo_file#${cc_subdir}}"
                        local_file="${target}/${frel}"
                        if [ -f "$local_file" ] && ! diff -q --strip-trailing-cr "$local_file" "$repo_file" > /dev/null 2>&1; then
                            echo "DIFF:_cc/${rel}/${frel}" >> "${DIFF_STATE_FILE}"
                            HAS_ANY_DIFF=true
                        fi
                    done < <(find "$cc_subdir" -type f -print0)
                done
            else
                target=$(resolve_memory_target "$dir_name")
                [ -z "$target" ] && continue
                while IFS= read -r -d '' repo_file; do
                    frel="${repo_file#${repo_mem_dir}}"
                    local_file="${target}/${frel}"
                    if [ -f "$local_file" ] && ! diff -q --strip-trailing-cr "$local_file" "$repo_file" > /dev/null 2>&1; then
                        echo "DIFF:${dir_name}/${frel}" >> "${DIFF_STATE_FILE}"
                        HAS_ANY_DIFF=true
                    fi
                done < <(find "$repo_mem_dir" -type f -print0)
            fi
        done
    fi

    if $HAS_ANY_DIFF; then
        echo -e "    ${YELLOW}⚠️  发现本地修改，拉取后将暂停审核${NC}"
    else
        echo "    ✅ 无本地修改"
    fi
else
    echo "  🔍 使用已保存的差异状态（脚本自重启后）"
fi

# ──────────────────────────────────────────────────────────────
# Phase 2: git pull（完整覆盖本地仓库）
# ──────────────────────────────────────────────────────────────
echo "  📥 从仓库拉取最新配置..."

# Pull 前：剥离 .ps1 BOM，避免 git 将其识别为本地修改而拒绝合并
_ps1_bom "strip" "${SCRIPT_DIR}"

SCRIPT_HASH_BEFORE=$(md5sum "$0" 2>/dev/null | cut -d' ' -f1)
if ! git pull; then
    echo -e "${RED}❌ 拉取失败${NC}"
    _ps1_bom "add" "${SCRIPT_DIR}"   # 失败时也恢复 BOM
    rm -f "${_PULL_DIFF_STATE_FILE}"
    exit 1
fi
echo "    ✅ 拉取完成"

SCRIPT_HASH_AFTER=$(md5sum "$0" 2>/dev/null | cut -d' ' -f1)
if [ "$SCRIPT_HASH_BEFORE" != "$SCRIPT_HASH_AFTER" ]; then
    if [ "$_PULL_RESTARTS" -lt 1 ]; then
        echo -e "${YELLOW}⚠️  脚本已更新，自动重启以应用新版本...${NC}"
        export _PULL_RESTARTS=$((_PULL_RESTARTS + 1))
        exec "${SCRIPT_DIR}/pull-windows.sh" "$@"
    else
        echo -e "${YELLOW}⚠️  脚本已更新但已重启过一次，继续使用当前版本${NC}"
    fi
fi

# Pull 后：为所有 .ps1 加回 BOM（PowerShell 在中文 Windows 上需要）
_ps1_bom "add" "${SCRIPT_DIR}"
echo "    ✅ .ps1 UTF-8 BOM 已恢复"

# ──────────────────────────────────────────────────────────────
# Phase 3: 逐文件应用（有差异的暂停，展示 diff 供审核）
# ──────────────────────────────────────────────────────────────
echo "  📦 应用同步配置..."
NEEDS_REVIEW=false
SKIPPED_FILES=()

has_diff() {
    [ -f "${_PULL_DIFF_STATE_FILE}" ] || return 1
    grep -qxF "DIFF:$1" "${_PULL_DIFF_STATE_FILE}" 2>/dev/null || return 1
}

show_diff() {
    local label="$1" local_path="$2" repo_path="$3"
    echo -e "${YELLOW}  ┌─ 需审核: ${label}${NC}"
    if [ -f "$local_path" ] && [ -f "$repo_path" ]; then
        diff --unified=3 --strip-trailing-cr "$local_path" "$repo_path" 2>/dev/null || true
    elif [ ! -f "$local_path" ]; then
        echo "  （本地文件不存在，仓库为新增）"
    fi
    echo -e "${YELLOW}  └────────────────────────────────────${NC}"
}

CONF_FILE="${SCRIPT_DIR}/sync.conf"
if [ ! -f "$CONF_FILE" ]; then
    echo -e "    ${YELLOW}⚠️  未找到 sync.conf，跳过配置应用${NC}"
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
                if [ -f "$repo_path" ]; then
                    mkdir -p "$(dirname "$local_path")"
                    # settings.json 合并模式：仓库白名单 key 覆盖本地，保留本地非白名单 key
                    if [ "$src" = "settings.json" ] && [ -f "${SCRIPT_DIR}/settings-filter.conf" ]; then
                        FILTER_SCRIPT="${SCRIPT_DIR}/filter-settings.py"
                        PYTHON=$(command -v python3 2>/dev/null || command -v python 2>/dev/null)
                        if [ -f "$FILTER_SCRIPT" ] && [ -f "$local_path" ] && [ -n "$PYTHON" ]; then
                            "$PYTHON" "$FILTER_SCRIPT" "$repo_path" "${SCRIPT_DIR}/settings-filter.conf" --merge "$local_path" > "${local_path}.tmp"
                            mv "${local_path}.tmp" "$local_path"
                            echo "    ✅ $src（已合并）"
                        elif [ -f "$FILTER_SCRIPT" ] && [ -n "$PYTHON" ]; then
                            "$PYTHON" "$FILTER_SCRIPT" "$repo_path" "${SCRIPT_DIR}/settings-filter.conf" > "$local_path"
                            echo "    ✅ $src（已过滤）"
                        elif [ -f "$FILTER_SCRIPT" ]; then
                            echo -e "    ${YELLOW}⚠️  settings-filter.conf 已配置但 python 不可用，跳过过滤${NC}"
                        elif has_diff "$src"; then
                            show_diff "$src" "$local_path" "$repo_path"
                            SKIPPED_FILES+=("$src")
                            NEEDS_REVIEW=true
                            echo -e "    ${YELLOW}⏸  $src（跳过，需审核）${NC}"
                        else
                            cp "$repo_path" "$local_path"
                            echo "    ✅ $src"
                        fi
                    elif has_diff "$src"; then
                        show_diff "$src" "$local_path" "$repo_path"
                        SKIPPED_FILES+=("$src")
                        NEEDS_REVIEW=true
                        echo -e "    ${YELLOW}⏸  $src（跳过，需审核）${NC}"
                    else
                        cp "$repo_path" "$local_path"
                        echo "    ✅ $src"
                    fi
                else
                    echo "    ℹ️  $src 不存在（可选）"
                fi
                ;;
            dir)
                if [ -d "$repo_path" ] && [ "$(ls -A "$repo_path" 2>/dev/null)" ]; then
                    mkdir -p "$local_path"
                    dir_has_skip=false
                    while IFS= read -r -d '' repo_file; do
                        rel="${repo_file#${repo_path}/}"
                        local_file="${local_path}/${rel}"
                        diff_key="${src}/${rel}"
                        if has_diff "$diff_key"; then
                            show_diff "$diff_key" "$local_file" "$repo_file"
                            SKIPPED_FILES+=("$diff_key")
                            NEEDS_REVIEW=true
                            dir_has_skip=true
                        else
                            mkdir -p "$(dirname "$local_file")"
                            cp "$repo_file" "$local_file"
                        fi
                    done < <(find "$repo_path" -type f -print0)
                    if $dir_has_skip; then
                        echo -e "    ${YELLOW}⚠️  $src（部分文件跳过，需审核）${NC}"
                    else
                        echo "    ✅ $src"
                    fi
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

echo "  📝 应用项目记忆..."
MEMORY_BASE="${SCRIPT_DIR}/claude/memory"
if [ ! -d "$MEMORY_BASE" ] || [ -z "$(ls -A "$MEMORY_BASE" 2>/dev/null)" ]; then
    echo "    ⚠️  仓库中无项目记忆"
else
    for repo_mem_dir in "${MEMORY_BASE}"/*/; do
        [ -d "$repo_mem_dir" ] || continue
        dir_name=$(basename "$repo_mem_dir")

        if [ "$dir_name" = "_cc" ]; then
            for cc_subdir in "${repo_mem_dir}"*/; do
                [ -d "$cc_subdir" ] || continue
                rel=$(basename "$cc_subdir")
                target=$(resolve_cc_target "$rel")
                if [ -z "$target" ]; then
                    echo "    ⏭  _cc/${rel}（CLAUDECODE_ROOT 未配置，跳过）"
                    continue
                fi
                cc_project_dir="$(dirname "$target")"
                if [ ! -d "$cc_project_dir" ]; then
                    if $APPLY_MISSING_CC; then
                        echo -e "    ${YELLOW}⚠️  _cc/${rel}（本机无此项目，--apply-missing-cc 强制应用）${NC}"
                    else
                        if [ -d "${CLAUDECODE_ROOT%\\}/${rel}" ]; then
                            echo -e "    ${YELLOW}⚠️  _cc/${rel}（仓库含此项目记忆，但本机未在此目录打开过 Claude；疑似旧设备配置迁移，建议执行 restore-windows.sh）${NC}"
                        else
                            echo "    ⏭  _cc/${rel}（本机无此项目，跳过）"
                        fi
                        continue
                    fi
                fi
                mkdir -p "$target"
                dir_has_skip=false
                while IFS= read -r -d '' repo_file; do
                    frel="${repo_file#${cc_subdir}}"
                    local_file="${target}/${frel}"
                    diff_key="_cc/${rel}/${frel}"
                    if has_diff "$diff_key"; then
                        show_diff "_cc/${rel}/${frel}" "$local_file" "$repo_file"
                        SKIPPED_FILES+=("_cc/${rel}/${frel}")
                        NEEDS_REVIEW=true
                        dir_has_skip=true
                    else
                        mkdir -p "$(dirname "$local_file")"
                        cp "$repo_file" "$local_file"
                    fi
                done < <(find "$cc_subdir" -type f -print0)
                if $dir_has_skip; then
                    echo -e "    ${YELLOW}⚠️  _cc/${rel}（部分文件跳过，需审核）${NC}"
                else
                    echo "    ✅ _cc/${rel}"
                fi
            done
        else
            target=$(resolve_memory_target "$dir_name")
            if [ -z "$target" ]; then
                echo "    ⏭  ${dir_name}（本机无此项目，跳过）"
                continue
            fi
            mkdir -p "$target"
            dir_has_skip=false
            while IFS= read -r -d '' repo_file; do
                frel="${repo_file#${repo_mem_dir}}"
                local_file="${target}/${frel}"
                diff_key="${dir_name}/${frel}"
                if has_diff "$diff_key"; then
                    show_diff "${dir_name}/${frel}" "$local_file" "$repo_file"
                    SKIPPED_FILES+=("${dir_name}/${frel}")
                    NEEDS_REVIEW=true
                    dir_has_skip=true
                else
                    mkdir -p "$(dirname "$local_file")"
                    cp "$repo_file" "$local_file"
                fi
            done < <(find "$repo_mem_dir" -type f -print0)
            if $dir_has_skip; then
                echo -e "    ${YELLOW}⚠️  ${dir_name}（部分文件跳过，需审核）${NC}"
            else
                echo "    ✅ ${dir_name}"
            fi
        fi
    done
fi

rm -f "${_PULL_DIFF_STATE_FILE}"
unset _PULL_DIFF_STATE_FILE

echo ""
if $NEEDS_REVIEW; then
    echo -e "${YELLOW}⚠️  以下文件因存在本地修改而跳过：${NC}"
    for f in "${SKIPPED_FILES[@]}"; do
        echo "    - $f"
    done
    echo ""
    echo -e "${YELLOW}   请让 Claude 审核以上差异，确认后再决定如何处理。${NC}"
    echo -e "${YELLOW}   如需保留本地修改，请先执行 update-windows.sh 推送，再重新拉取。${NC}"
else
    echo -e "${GREEN}✅ 配置拉取和应用完成！${NC}"
fi
echo ""
echo "环境信息："
echo "  - Claude 配置:      ${CLAUDE_HOME}"
echo "  - 工作目录:         ${WORKSPACE_PATH}"
echo "  - ClaudeCode 根目录: ${CLAUDECODE_ROOT:-未设置}"
echo ""
