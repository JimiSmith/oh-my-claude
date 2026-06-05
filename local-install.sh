#!/bin/bash
# Local installation script for oh-my-claude status line
# This script is for local development - run after cloning the repository
# For web-based installation, use: curl -s https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.sh | bash
# Installs to ~/.claude/oh-my-claude/ and updates Claude Code settings

set -e

# Read version from VERSION file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSION=$(cat "$SCRIPT_DIR/VERSION" 2>/dev/null || echo "unknown")
THEME="claude-native.omp.json"

echo "================================================"
echo "   oh-my-claude Status Line Installation"
echo "   Version: $VERSION"
echo "================================================"
echo ""

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Installation directory
INSTALL_DIR="$HOME/.claude/oh-my-claude"
SETTINGS_FILE="$HOME/.claude/settings.json"

# Check dependencies
echo "Checking dependencies..."
missing_deps=()

if ! command -v oh-my-posh >/dev/null 2>&1; then
    missing_deps+=("oh-my-posh")
fi

# jq is used by this installer to update settings.json
if ! command -v jq >/dev/null 2>&1; then
    missing_deps+=("jq")
fi

# git is optional - only needed for the git segment of the status line
if ! command -v git >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠ git not found - the git segment of the status line will be hidden${NC}"
fi

if [ ${#missing_deps[@]} -ne 0 ]; then
    echo -e "${RED}✗ Missing required dependencies:${NC}"
    for dep in "${missing_deps[@]}"; do
        echo "  - $dep"
    done
    echo ""
    echo "Please install missing dependencies and try again."
    exit 1
fi

# Resolve the oh-my-posh path so the status line command does not depend on PATH
OMP_BIN=$(command -v oh-my-posh)

echo -e "${GREEN}✓ All dependencies found${NC}"
echo ""

# Create installation directory
echo "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
echo -e "${GREEN}✓ Created $INSTALL_DIR${NC}"
echo ""

# Copy theme and VERSION file
echo "Copying theme..."
cp "$SCRIPT_DIR/src/$THEME" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/VERSION" "$INSTALL_DIR/"

echo -e "${GREEN}✓ Copied theme to $INSTALL_DIR${NC}"
echo ""

# Backup and update settings.json
echo "Updating Claude Code settings..."

cmd="$OMP_BIN claude --config $INSTALL_DIR/$THEME"

if [ -f "$SETTINGS_FILE" ]; then
    # Backup existing settings
    backup_file="$SETTINGS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$SETTINGS_FILE" "$backup_file"
    echo -e "${GREEN}✓ Backed up settings to $backup_file${NC}"

    # Update statusLine.command using jq
    tmp_file=$(mktemp)
    jq --arg cmd "$cmd" \
       '.statusLine.command = $cmd | .statusLine.type = "command" | .statusLine.padding = 0' \
       "$SETTINGS_FILE" > "$tmp_file"

    mv "$tmp_file" "$SETTINGS_FILE"
    echo -e "${GREEN}✓ Updated settings.json with new statusLine.command${NC}"
else
    # Create new settings.json
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    cat > "$SETTINGS_FILE" <<EOF
{
  "statusLine": {
    "type": "command",
    "command": "$cmd",
    "padding": 0
  }
}
EOF
    echo -e "${GREEN}✓ Created new settings.json${NC}"
fi
echo ""

# Test installation
echo "Testing installation..."
test_payload='{"model":{"display_name":"Test"},"workspace":{"current_dir":"'"$PWD"'"},"context_window":{"current_usage":{"input_tokens":1000},"context_window_size":200000}}'
if echo "$test_payload" | "$OMP_BIN" claude --config "$INSTALL_DIR/$THEME" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Status line renders${NC}"
else
    echo -e "${YELLOW}⚠ Status line render test failed${NC}"
fi
echo ""

# Print summary
echo "================================================"
echo -e "${GREEN}   Installation Complete!${NC}"
echo "================================================"
echo ""
echo "Installation summary:"
echo "  • Theme installed to: $INSTALL_DIR/$THEME"
echo "  • Settings updated in: $SETTINGS_FILE"
echo ""
echo "The status line is rendered by 'oh-my-posh claude', which reads Claude"
echo "Code's session JSON (model, context, and subscription usage) from stdin."
echo "No tokens, API calls, or background scripts are involved."
echo ""
echo "You can now use Claude Code and see the status line!"
echo ""
echo "Test the status line with:"
echo "  echo '{\"model\":{\"display_name\":\"Test\"},\"context_window\":{\"current_usage\":{\"input_tokens\":1000},\"context_window_size\":200000}}' | $OMP_BIN claude --config $INSTALL_DIR/$THEME"
echo ""
echo "Documentation:"
echo "  • README.md - Getting started guide"
echo ""
echo "================================================"
