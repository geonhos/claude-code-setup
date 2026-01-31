#!/bin/bash
#
# Multi-Agent System - Update Checker
#
# Checks if a newer version of agents is available.
#
# Usage:
#   ./check-update.sh [project-path]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
PLUGIN_NAME="multi-agent-system"
MARKETPLACE_NAME="geonhos-plugins"
PLUGIN_CACHE_BASE="$HOME/.claude/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME"
VERSION_FILE=".claude/.agent-version"

PROJECT_PATH="${1:-.}"
PROJECT_PATH=$(cd "$PROJECT_PATH" && pwd)

# Find latest version
find_latest_version() {
    if [ -d "$PLUGIN_CACHE_BASE" ]; then
        ls -1 "$PLUGIN_CACHE_BASE" 2>/dev/null | sort -V | tail -1
    fi
}

# Get installed version
get_installed_version() {
    if [ -f "$PROJECT_PATH/$VERSION_FILE" ]; then
        cat "$PROJECT_PATH/$VERSION_FILE"
    fi
}

LATEST_VERSION=$(find_latest_version)
INSTALLED_VERSION=$(get_installed_version)

echo -e "${BLUE}Multi-Agent System - Update Check${NC}"
echo ""

if [ -z "$LATEST_VERSION" ]; then
    echo -e "${RED}Plugin not installed.${NC}"
    exit 1
fi

if [ -z "$INSTALLED_VERSION" ]; then
    echo -e "${YELLOW}Agents not installed in this project.${NC}"
    echo "Run: ./scripts/install-agents.sh"
    exit 0
fi

echo -e "Installed version: ${GREEN}$INSTALLED_VERSION${NC}"
echo -e "Latest version:    ${GREEN}$LATEST_VERSION${NC}"
echo ""

if [ "$INSTALLED_VERSION" = "$LATEST_VERSION" ]; then
    echo -e "${GREEN}✓ Up to date!${NC}"
else
    echo -e "${YELLOW}Update available!${NC}"
    echo "Run: ./scripts/install-agents.sh"
fi
