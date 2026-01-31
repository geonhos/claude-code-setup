#!/bin/bash
#
# Multi-Agent System - Local Agent Installer
#
# This script copies agents from the plugin to your project's .claude/agents/ directory
# for automatic detection by Claude Code.
#
# Usage:
#   ./install-agents.sh [project-path]
#
# If project-path is not provided, uses current directory.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PLUGIN_NAME="multi-agent-system"
MARKETPLACE_NAME="geonhos-plugins"
PLUGIN_CACHE_BASE="$HOME/.claude/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME"
VERSION_FILE=".claude/.agent-version"

# Get project path (default: current directory)
PROJECT_PATH="${1:-.}"
PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Multi-Agent System - Local Agent Installer${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Find the latest installed version
find_latest_version() {
    if [ -d "$PLUGIN_CACHE_BASE" ]; then
        ls -1 "$PLUGIN_CACHE_BASE" 2>/dev/null | sort -V | tail -1
    fi
}

# Get currently installed version in project
get_installed_version() {
    if [ -f "$PROJECT_PATH/$VERSION_FILE" ]; then
        cat "$PROJECT_PATH/$VERSION_FILE"
    fi
}

# Main installation logic
install_agents() {
    local version=$1
    local source_dir="$PLUGIN_CACHE_BASE/$version/agents"
    local target_dir="$PROJECT_PATH/.claude/agents"

    echo -e "${YELLOW}Installing agents version $version...${NC}"

    # Create target directory
    mkdir -p "$target_dir"

    # Copy agents (flatten the structure)
    local count=0
    for category_dir in "$source_dir"/*/; do
        if [ -d "$category_dir" ]; then
            for agent_file in "$category_dir"*.md; do
                if [ -f "$agent_file" ]; then
                    cp "$agent_file" "$target_dir/"
                    count=$((count + 1))
                fi
            done
        fi
    done

    # Save version info
    mkdir -p "$PROJECT_PATH/.claude"
    echo "$version" > "$PROJECT_PATH/$VERSION_FILE"

    echo -e "${GREEN}✓ Installed $count agents to $target_dir${NC}"
}

# Check if plugin is installed
LATEST_VERSION=$(find_latest_version)

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${RED}Error: Plugin '$PLUGIN_NAME' not found.${NC}"
    echo ""
    echo "Please install the plugin first:"
    echo "  /plugin marketplace add geonhos/claude-code-setup"
    echo "  /plugin add multi-agent-system"
    exit 1
fi

echo -e "Project path: ${GREEN}$PROJECT_PATH${NC}"
echo -e "Plugin version available: ${GREEN}$LATEST_VERSION${NC}"

# Check current installation
INSTALLED_VERSION=$(get_installed_version)

if [ -n "$INSTALLED_VERSION" ]; then
    echo -e "Currently installed: ${YELLOW}$INSTALLED_VERSION${NC}"

    if [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
        echo ""
        echo -e "${GREEN}✓ Already up to date!${NC}"

        read -p "Reinstall anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    else
        echo ""
        echo -e "${YELLOW}Update available: $INSTALLED_VERSION → $LATEST_VERSION${NC}"
    fi
else
    echo -e "Currently installed: ${YELLOW}(none)${NC}"
fi

echo ""

# Install agents
install_agents "$LATEST_VERSION"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  Installation Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Agents are now available in your project."
echo "Claude will automatically detect and use them based on keywords."
echo ""
echo "To update agents when a new version is released:"
echo "  1. Update the plugin: /plugin update multi-agent-system"
echo "  2. Run this script again: ./scripts/install-agents.sh"
echo ""
