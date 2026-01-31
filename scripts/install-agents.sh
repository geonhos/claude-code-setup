#!/bin/bash
#
# Multi-Agent System Installer
#
# 플러그인 설치 후 이 스크립트를 실행하면:
# - agents → .claude/agents/
# - skills → .claude/skills/
# - CLAUDE.md → .claude/CLAUDE.md
#
# Usage:
#   ./install-agents.sh [project-path]
#

set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PLUGIN_NAME="multi-agent-system"
MARKETPLACE_NAME="geonhos-plugins"
PLUGIN_CACHE_BASE="$HOME/.claude/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME"
VERSION_FILE=".claude/.agent-version"

# Get project path
PROJECT_PATH="${1:-.}"
PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Multi-Agent System Installer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Find latest version
find_latest_version() {
    if [ -d "$PLUGIN_CACHE_BASE" ]; then
        ls -1 "$PLUGIN_CACHE_BASE" 2>/dev/null | sort -V | tail -1
    fi
}

LATEST_VERSION=$(find_latest_version)

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${YELLOW}플러그인이 설치되지 않았습니다.${NC}"
    echo ""
    echo "Claude Code에서 다음 명령어를 실행하세요:"
    echo "  /plugin marketplace add geonhos/claude-code-setup"
    echo "  /plugin add multi-agent-system"
    exit 1
fi

PLUGIN_DIR="$PLUGIN_CACHE_BASE/$LATEST_VERSION"
TARGET_DIR="$PROJECT_PATH/.claude"

echo -e "플러그인 버전: ${GREEN}$LATEST_VERSION${NC}"
echo -e "설치 경로: ${GREEN}$TARGET_DIR${NC}"
echo ""

# Create target directory
mkdir -p "$TARGET_DIR/agents"
mkdir -p "$TARGET_DIR/skills"

# 1. Copy agents (flatten structure)
echo -e "${YELLOW}에이전트 복사 중...${NC}"
agent_count=0
for category_dir in "$PLUGIN_DIR/agents"/*/; do
    if [ -d "$category_dir" ]; then
        for agent_file in "$category_dir"*.md; do
            if [ -f "$agent_file" ]; then
                cp "$agent_file" "$TARGET_DIR/agents/"
                agent_count=$((agent_count + 1))
            fi
        done
    fi
done
echo -e "  ${GREEN}✓${NC} $agent_count개 에이전트 복사 완료"

# 2. Copy skills (maintain structure)
echo -e "${YELLOW}스킬 복사 중...${NC}"
skill_count=0
for category_dir in "$PLUGIN_DIR/skills"/*/; do
    if [ -d "$category_dir" ]; then
        category_name=$(basename "$category_dir")
        for skill_dir in "$category_dir"*/; do
            if [ -d "$skill_dir" ]; then
                skill_name=$(basename "$skill_dir")
                mkdir -p "$TARGET_DIR/skills/$skill_name"
                cp -r "$skill_dir"* "$TARGET_DIR/skills/$skill_name/"
                skill_count=$((skill_count + 1))
            fi
        done
    fi
done
echo -e "  ${GREEN}✓${NC} $skill_count개 스킬 복사 완료"

# 3. Copy CLAUDE.md
echo -e "${YELLOW}CLAUDE.md 복사 중...${NC}"
if [ -f "$PLUGIN_DIR/.claude/CLAUDE.md" ]; then
    cp "$PLUGIN_DIR/.claude/CLAUDE.md" "$TARGET_DIR/CLAUDE.md"
    echo -e "  ${GREEN}✓${NC} CLAUDE.md 복사 완료"
else
    echo -e "  ${YELLOW}⚠${NC} CLAUDE.md 없음 (스킵)"
fi

# 4. Save version
echo "$LATEST_VERSION" > "$PROJECT_PATH/$VERSION_FILE"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  설치 완료!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "설치된 항목:"
echo "  - .claude/agents/     ($agent_count개 에이전트)"
echo "  - .claude/skills/     ($skill_count개 스킬)"
echo "  - .claude/CLAUDE.md   (개발 지침)"
echo ""
echo "이제 Claude Code가 자동으로 에이전트와 스킬을 감지합니다."
echo ""
