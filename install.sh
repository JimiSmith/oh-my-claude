#!/bin/bash
# Web installer for oh-my-claude status line
# Downloads latest version from GitHub and installs to ~/.claude/oh-my-claude
# Usage: curl -s https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.sh | bash
# Custom directory: curl -s ... | bash -s -- -d ~/.custom/location

set -e  # Exit on error

# Constants
GITHUB_REPO="JimiSmith/oh-my-claude"
BRANCH="main"
DEFAULT_INSTALL_DIR="$HOME/.claude/oh-my-claude"
SETTINGS_FILE="$HOME/.claude/settings.json"
THEME="claude-native.omp.json"

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Variables (can be overridden by arguments)
INSTALL_DIR="$DEFAULT_INSTALL_DIR"
OMP_BIN="oh-my-posh"

# Create temporary directory for downloads
temp_dir="/tmp/oh-my-claude-install-$$"
mkdir -p "$temp_dir"

# Cleanup function - always remove temp directory on exit
cleanup() {
    rm -rf "$temp_dir"
}
trap cleanup EXIT

# Show help message
show_help() {
    echo "oh-my-claude Web Installer"
    echo ""
    echo "Usage:"
    echo "  curl -s https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.sh | bash"
    echo ""
    echo "Options:"
    echo "  -d, --dir DIR     Install to custom directory (default: ~/.claude/oh-my-claude)"
    echo "  -h, --help        Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Default installation"
    echo "  curl -s https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.sh | bash"
    echo ""
    echo "  # Custom directory"
    echo "  curl -s https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.sh | bash -s -- -d ~/.custom/location"
    echo ""
    echo "Documentation: https://github.com/JimiSmith/oh-my-claude"
}

# Parse command-line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--dir)
                if [ -z "$2" ]; then
                    echo -e "${RED}Error: -d/--dir requires a directory argument${NC}"
                    exit 1
                fi
                INSTALL_DIR="$2"
                shift 2
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                echo "Use -h or --help for usage information"
                exit 1
                ;;
        esac
    done
}

# Download a single file with retry logic
download_file() {
    local url="$1"
    local dest="$2"
    local filename=$(basename "$dest")
    local attempts=3

    for i in $(seq 1 $attempts); do
        if curl -fsSL "$url" -o "$dest" 2>/dev/null; then
            echo -e "${GREEN}✓${NC} $filename"
            return 0
        fi
        if [ $i -lt $attempts ]; then
            echo -e "${YELLOW}⚠${NC} $filename (retrying... $i/$attempts)"
            sleep $((i * 2))  # Exponential backoff
        fi
    done

    echo -e "${RED}✗${NC} $filename (failed after $attempts attempts)"
    return 1
}

# Download all required files from GitHub
download_all_files() {
    local base_url="https://raw.githubusercontent.com/$GITHUB_REPO/$BRANCH"
    local failed=0

    echo "Downloading from GitHub..."

    # The status line is rendered directly by `oh-my-posh claude`, which reads
    # Claude Code's JSON from stdin - so only the theme and VERSION are needed.
    download_file "$base_url/src/$THEME" "$temp_dir/$THEME" || failed=1
    download_file "$base_url/VERSION" "$temp_dir/VERSION" || failed=1

    if [ $failed -eq 1 ]; then
        echo ""
        echo -e "${RED}Error: Failed to download one or more files${NC}"
        echo "Please check your internet connection and try again."
        echo ""
        echo "Alternative: Clone the repository and use local-install.sh"
        echo "  git clone https://github.com/$GITHUB_REPO.git"
        echo "  cd oh-my-claude"
        echo "  bash local-install.sh"
        exit 1
    fi
}

# Verify all downloads completed successfully
verify_downloads() {
    local required_files=("$THEME" "VERSION")

    for file in "${required_files[@]}"; do
        if [ ! -f "$temp_dir/$file" ] || [ ! -s "$temp_dir/$file" ]; then
            echo -e "${RED}Error: Downloaded file $file is missing or empty${NC}"
            exit 1
        fi
    done
}

# Check for required dependencies
check_dependencies() {
    echo "Checking dependencies..."
    local missing_deps=()

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
}

# Detect if this is an update or fresh installation
detect_installation_type() {
    if [ -f "$INSTALL_DIR/VERSION" ]; then
        local installed_version=$(cat "$INSTALL_DIR/VERSION")
        local downloading_version=$(cat "$temp_dir/VERSION")

        if [ "$installed_version" = "$downloading_version" ]; then
            echo "Reinstalling version $downloading_version"
        else
            echo "Updating from $installed_version to $downloading_version"
        fi
    else
        local version=$(cat "$temp_dir/VERSION")
        echo "Installing oh-my-claude version $version"
    fi
}

# Install files to the target directory
install_files() {
    echo ""
    echo "Installing to $INSTALL_DIR..."

    # Create installation directory
    mkdir -p "$INSTALL_DIR"

    # Copy theme and VERSION to installation directory
    cp "$temp_dir/$THEME" "$INSTALL_DIR/"
    cp "$temp_dir/VERSION" "$INSTALL_DIR/"

    echo -e "${GREEN}✓ Files copied${NC}"
}

# Update Claude Code settings.json
update_settings() {
    echo ""
    echo "Updating settings..."

    local cmd="$OMP_BIN claude --config $INSTALL_DIR/$THEME"

    if [ -f "$SETTINGS_FILE" ]; then
        # Backup existing settings
        backup_file="$SETTINGS_FILE.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$SETTINGS_FILE" "$backup_file"
        echo -e "${GREEN}✓ Backed up settings to $(basename "$backup_file")${NC}"

        # Update statusLine.command using jq
        tmp_file=$(mktemp)
        jq --arg cmd "$cmd" \
           '.statusLine.command = $cmd | .statusLine.type = "command" | .statusLine.padding = 0' \
           "$SETTINGS_FILE" > "$tmp_file"

        mv "$tmp_file" "$SETTINGS_FILE"
        echo -e "${GREEN}✓ Configuration updated${NC}"
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
        echo -e "${GREEN}✓ Created settings.json${NC}"
    fi
}

# Display success message
show_success() {
    local version=$(cat "$INSTALL_DIR/VERSION" 2>/dev/null || echo "unknown")

    echo ""
    echo "================================================"
    echo -e "${GREEN}   Installation Complete!${NC}"
    echo "================================================"
    echo ""
    echo "Location: $INSTALL_DIR"
    echo "Version: $version"
    echo ""
    echo "Next steps:"
    echo "  1. Restart Claude Code (if running)"
    echo "  2. Status line will appear automatically"
    echo ""
    echo "Documentation: https://github.com/$GITHUB_REPO"
    echo "================================================"
}

# Main installation flow
main() {
    # Parse command-line arguments
    parse_arguments "$@"

    # Show banner
    echo "================================================"
    echo "   oh-my-claude Web Installer"
    echo "================================================"
    echo ""

    # Check dependencies
    check_dependencies

    # Download files from GitHub
    download_all_files
    echo ""

    # Verify downloads
    verify_downloads

    # Show installation type
    detect_installation_type

    # Install files
    install_files

    # Update settings.json
    update_settings

    # Show success message
    show_success
}

# Run main function with all arguments
main "$@"
