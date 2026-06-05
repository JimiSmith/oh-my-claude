#!/bin/bash
# Background script to update Claude usage cache using ccusage

# Load common functions
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Get script directory and version
script_dir=$(get_script_dir)
VERSION=$(get_version "$script_dir")
handle_version_flag "$1" "$VERSION"

cache_file="$script_dir/.usage_cache"

# Get current session usage from ccusage (if available)
session_tokens=""
if [ -f "$script_dir/fetch-code-usage.sh" ]; then
    session_tokens=$(bash "$script_dir/fetch-code-usage.sh" 2>/dev/null)
    if [ $? -ne 0 ] || ! [[ "$session_tokens" =~ ^[0-9]+$ ]]; then
        # ccusage failed or returned invalid data, don't modify cache
        exit 0
    fi
else
    # Script not found, don't modify cache
    exit 0
fi

# Write to cache in JSON format for clarity.
# 5h / 7d subscription usage is no longer fetched here: statusline.sh now reads
# it directly from the status line stdin JSON (.rate_limits) provided by Claude
# Code, so no OAuth token or usage API call is required.
mkdir -p "$(dirname "$cache_file")"

cat > "$cache_file" <<EOF
{
  "code": {
    "session_tokens": ${session_tokens}
  },
  "updated_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
