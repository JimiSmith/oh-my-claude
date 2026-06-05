#!/bin/bash
# Status line command for Claude Code with oh-my-posh integration

# Load common functions
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Get script directory and version
script_dir=$(get_script_dir)
VERSION=$(get_version "$script_dir")
handle_version_flag "$1" "$VERSION"

# Read JSON input from stdin
input=$(cat)

# Extract values using jq
model=$(echo "$input" | jq -r '.model.display_name')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')

# Calculate context percentage
usage=$(echo "$input" | jq '.context_window.current_usage')
if [ "$usage" != "null" ]; then
    input_tokens=$(echo "$usage" | jq '.input_tokens // 0')
    cache_creation=$(echo "$usage" | jq '.cache_creation_input_tokens // 0')
    cache_read=$(echo "$usage" | jq '.cache_read_input_tokens // 0')
    size=$(echo "$input" | jq '.context_window.context_window_size // 1')

    # Calculate current usage using awk (no bc dependency)
    current=$(awk "BEGIN {print $input_tokens + $cache_creation + $cache_read}")
    if [ "$size" != "0" ]; then
        pct=$(awk "BEGIN {printf \"%.0f\", $current * 100 / $size}")
    else
        pct=0
    fi

    context_pct="${pct}%"
else
    context_pct=""
fi

# Fetch usage data with automatic updates from ccusage
cache_file="$script_dir/.usage_cache"
cache_timeout=60
update_script="$script_dir/update-usage.sh"

# Check if cache exists and is fresh
if [ -f "$cache_file" ]; then
    cache_age=$(($(date +%s) - $(get_file_mtime "$cache_file")))
    [ "$cache_age" -ge "$cache_timeout" ] && bash "$update_script" &>/dev/null &

    # Read cached ccusage session token count
    cache_json=$(cat "$cache_file" 2>/dev/null)
    session_tokens=$(echo "$cache_json" | jq -r '.code.session_tokens // 0')
else
    # No cache, trigger update and use empty data for now
    bash "$update_script" &>/dev/null &
    session_tokens=""
fi

# 5h / 7d subscription usage comes straight from the status line stdin JSON
# (.rate_limits), supplied by Claude Code itself - no OAuth token or API call.
# Note: rate_limits is only present for subscribers after the first API response,
# so these may be briefly empty at the very start of a session.
pro_five_hour_usage=$(echo "$input" | jq -r '(.rate_limits.five_hour.used_percentage // .rate_limits.five_hour.utilization) // empty')
pro_seven_day_usage=$(echo "$input" | jq -r '(.rate_limits.seven_day.used_percentage // .rate_limits.seven_day.utilization) // empty')
pro_five_hour_resets=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
pro_seven_day_resets=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Round percentages to whole numbers for display
[ -n "$pro_five_hour_usage" ] && pro_five_hour_usage=$(awk -v v="$pro_five_hour_usage" 'BEGIN {printf "%.0f", v}')
[ -n "$pro_seven_day_usage" ] && pro_seven_day_usage=$(awk -v v="$pro_seven_day_usage" 'BEGIN {printf "%.0f", v}')

# Format Code usage display (tokens only) - using only awk
code_usage_display=""
if [ -n "$session_tokens" ] && [ "$session_tokens" != "0" ]; then
    session_m=$(awk -v t="$session_tokens" 'BEGIN {v=t/1000000; printf(v==int(v)?"%.0f":"%.1f", v)}')
    code_usage_display="${session_m}M"
fi

# Format Pro usage display
pro_usage_display=""
if [ -n "$pro_five_hour_usage" ] && [ -n "$pro_seven_day_usage" ]; then
    pro_usage_display="5h:${pro_five_hour_usage}% 7d:${pro_seven_day_usage}%"
fi

# Format reset times display (resets_at are Unix epoch seconds)
reset_display=""
five_hour_display=""
seven_day_display=""
now_sec=$(date +%s)

# 5h reset: time remaining until the window resets
if [[ "$pro_five_hour_resets" =~ ^[0-9]+$ ]]; then
    diff_sec=$((pro_five_hour_resets - now_sec))
    if [ "$diff_sec" -gt 0 ]; then
        hours=$((diff_sec / 3600))
        mins=$(((diff_sec % 3600) / 60))
        five_hour_display="${hours}h${mins}min"
    else
        five_hour_display="resetting..."
    fi
fi

# 7d reset: day + time (date -d @epoch on GNU, date -r epoch on BSD/macOS)
if [[ "$pro_seven_day_resets" =~ ^[0-9]+$ ]]; then
    seven_day_day=$(date -d "@$pro_seven_day_resets" "+%a" 2>/dev/null || date -r "$pro_seven_day_resets" "+%a" 2>/dev/null)
    seven_day_time=$(date -d "@$pro_seven_day_resets" "+%H:%M" 2>/dev/null || date -r "$pro_seven_day_resets" "+%H:%M" 2>/dev/null)
    [ -n "$seven_day_day" ] && [ -n "$seven_day_time" ] && seven_day_display="${seven_day_day}${seven_day_time}"
fi

if [ -n "$five_hour_display" ] && [ -n "$seven_day_display" ]; then
    reset_display="5h:${five_hour_display} 7d:${seven_day_display}"
fi

# Build separate 5h / 7d usage segments for the custom theme.
# (five_hour_display / seven_day_display are set above when reset data is present.)
claude_5h=""
if [ -n "$pro_five_hour_usage" ]; then
    claude_5h="${pro_five_hour_usage}%"
    [ -n "$five_hour_display" ] && claude_5h="${claude_5h} · ${five_hour_display}"
fi
claude_7d=""
if [ -n "$pro_seven_day_usage" ]; then
    claude_7d="${pro_seven_day_usage}%"
    [ -n "$seven_day_display" ] && claude_7d="${claude_7d} · ${seven_day_display}"
fi

# Path to oh-my-posh config file
config_file="$script_dir/claude-custom.omp.json"

# Use oh-my-posh to render the status line with clean environment
env -i \
  HOME="$HOME" \
  CLAUDE_MODEL="$model" \
  CLAUDE_CONTEXT="$context_pct" \
  CLAUDE_CODE_USAGE="$code_usage_display" \
  CLAUDE_PRO_USAGE="$pro_usage_display" \
  CLAUDE_RESET="$reset_display" \
  CLAUDE_5H="$claude_5h" \
  CLAUDE_7D="$claude_7d" \
  PATH="$PATH" \
  oh-my-posh print primary --config "$config_file" --pwd "$cwd"
