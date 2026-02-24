#!/bin/bash
# Claude Code 配置快速验证脚本（Linux/macOS）

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}开始验证 Claude Code 配置...${NC}\n"

PASSED=0
FAILED=0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
WORKSPACE_PATH="${CLAUDE_WORKSPACE:-$HOME/claude-workspace}"
CLAUDECODE_ROOT="${CLAUDECODE_ROOT:-}"

path_to_hash() {
    local real
    real=$(realpath -m "$1" 2>/dev/null || echo "$1")
    printf '%s' "$real" | python3 -c "import sys; s=sys.stdin.read(); print(''.join('-' if c=='/' or ord(c)>127 else c for c in s), end='')"
}
WORKSPACE_HASH=$(path_to_hash "$WORKSPACE_PATH")

check() {
    local name=$1 path=$2 type=$3
    if [ "$type" = "file" ] && [ -f "$path" ]; then
        echo -e "${GREEN}✅ $name${NC}"; ((PASSED++))
    elif [ "$type" = "dir" ] && [ -d "$path" ]; then
        echo -e "${GREEN}✅ $name${NC}"; ((PASSED++))
    else
        echo -e "${RED}❌ $name${NC}"; ((FAILED++))
    fi
}

# 0. 检查 sync.conf
echo -e "${BLUE}0️⃣  检查同步配置${NC}"
if [ -f "${SCRIPT_DIR}/sync.conf" ]; then
    echo -e "${GREEN}✅ sync.conf 存在${NC}"; ((PASSED++))
    entry_count=$(grep -v '^\s*#' "${SCRIPT_DIR}/sync.conf" | grep -v '^\s*$' | wc -l)
    echo "   已配置 $entry_count 个同步条目"
else
    echo -e "${RED}❌ sync.conf 不存在${NC}"; ((FAILED++))
fi
echo ""

# 1. 检查基础目录
echo -e "${BLUE}1️⃣  检查基础目录${NC}"
check "~/.claude 存在"       "${CLAUDE_HOME}"              "dir"
check "settings.json 存在"   "${CLAUDE_HOME}/settings.json" "file"
check "CLAUDE.md 存在"       "${CLAUDE_HOME}/CLAUDE.md"    "file"
check "projects 目录存在"    "${CLAUDE_HOME}/projects"     "dir"
check "skills 目录存在"      "${CLAUDE_HOME}/skills"       "dir"
echo ""

# 2. 检查项目记忆
echo -e "${BLUE}2️⃣  检查项目记忆${NC}"
WORKSPACE_MEMORY="${CLAUDE_HOME}/projects/${WORKSPACE_HASH}/memory"
if [ -d "$WORKSPACE_MEMORY" ] && [ "$(ls -A "$WORKSPACE_MEMORY" 2>/dev/null)" ]; then
    mem_files=$(ls -1 "$WORKSPACE_MEMORY" | wc -l)
    echo -e "${GREEN}✅ _workspace 记忆已落地（${mem_files} 个文件）${NC}"; ((PASSED++))
    ls -1 "$WORKSPACE_MEMORY" | sed 's/^/   📄 /'
else
    echo -e "${RED}❌ _workspace 记忆未找到（${WORKSPACE_MEMORY}）${NC}"; ((FAILED++))
fi

if [ -n "$CLAUDECODE_ROOT" ]; then
    CC_PREFIX=$(path_to_hash "${CLAUDECODE_ROOT%/}")
    cc_count=0
    for proj_dir in "${CLAUDE_HOME}/projects"/*/; do
        proj_name=$(basename "$proj_dir")
        if [[ "$proj_name" == "${CC_PREFIX}-"* ]]; then
            rel="${proj_name#${CC_PREFIX}-}"
            mem_dir="${proj_dir}memory"
            if [ -d "$mem_dir" ]; then
                echo -e "${GREEN}✅ _cc/${rel} 记忆已落地${NC}"; ((PASSED++))
                ls -1 "$mem_dir" 2>/dev/null | sed 's/^/   📄 /'
                ((cc_count++))
            fi
        fi
    done
    [ $cc_count -eq 0 ] && echo "   ℹ️  未发现 ClaudeCode 项目记忆（CLAUDECODE_ROOT=${CLAUDECODE_ROOT}）"
fi
echo ""

# 3. 检查技能
echo -e "${BLUE}3️⃣  检查自定义技能${NC}"
skill_count=$(find "${CLAUDE_HOME}/skills" -maxdepth 1 -type d ! -path "${CLAUDE_HOME}/skills" 2>/dev/null | wc -l)
if [ $skill_count -gt 0 ]; then
    echo -e "${GREEN}✅ 发现 $skill_count 个技能${NC}"; ((PASSED++))
    ls -1d "${CLAUDE_HOME}/skills"/*/ 2>/dev/null | xargs -I {} basename {} | sed 's/^/   ⚡ /'
else
    echo -e "${YELLOW}⚠️  未找到自定义技能${NC}"
fi
echo ""

# 4. 检查工作目录脚本
echo -e "${BLUE}4️⃣  检查工作目录脚本${NC}"
check "keep 目录存在" "${WORKSPACE_PATH}/keep" "dir"
script_count=$(find "${WORKSPACE_PATH}/keep" -maxdepth 1 -type f 2>/dev/null | wc -l)
if [ $script_count -gt 0 ]; then
    echo -e "${GREEN}✅ 发现 $script_count 个脚本文件${NC}"; ((PASSED++))
    ls -1 "${WORKSPACE_PATH}/keep" 2>/dev/null | sed 's/^/   📜 /'
else
    echo -e "${YELLOW}⚠️  keep 目录为空（可选）${NC}"
fi
echo ""

# 5. 验证配置内容
echo -e "${BLUE}5️⃣  验证配置内容${NC}"
if [ -f "${CLAUDE_HOME}/settings.json" ]; then
    MODEL=$(grep -o '"model": "[^"]*"' "${CLAUDE_HOME}/settings.json" | cut -d'"' -f4)
    LANGUAGE=$(grep -o '"language": "[^"]*"' "${CLAUDE_HOME}/settings.json" | cut -d'"' -f4)
    [ -n "$MODEL" ]    && { echo -e "${GREEN}✅ 模型设置: $MODEL${NC}";    ((PASSED++)); }
    [ -n "$LANGUAGE" ] && { echo -e "${GREEN}✅ 语言设置: $LANGUAGE${NC}"; ((PASSED++)); }
fi
echo ""

# 6. 项目识别
echo -e "${BLUE}6️⃣  项目识别${NC}"
project_count=$(find "${CLAUDE_HOME}/projects" -maxdepth 1 -type d ! -path "${CLAUDE_HOME}/projects" 2>/dev/null | wc -l)
if [ $project_count -gt 0 ]; then
    echo -e "${GREEN}✅ 发现 $project_count 个项目${NC}"; ((PASSED++))
    for proj_dir in "${CLAUDE_HOME}/projects"/*/; do
        proj_name=$(basename "$proj_dir")
        mem_count=$(find "${proj_dir}memory" -type f 2>/dev/null | wc -l)
        echo "   📁 ${proj_name}（记忆文件: ${mem_count}）"
    done
else
    echo -e "${YELLOW}⚠️  未找到项目${NC}"
fi
echo ""

# 总结
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ 通过: $PASSED${NC}"
[ $FAILED -gt 0 ] && echo -e "${RED}❌ 失败: $FAILED${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"

if [ $FAILED -eq 0 ]; then
    echo -e "\n${GREEN}🎉 所有配置已正确生效！${NC}"
    exit 0
else
    echo -e "\n${YELLOW}⚠️  有些配置未能正确恢复，请检查日志${NC}"
    exit 1
fi
