# Claude Code Custom Status Line

A fully customized [oh-my-posh](https://ohmyposh.dev/) status line for Claude Code featuring:
- 🎨 Oh-my-posh powered theming with powerline separators (two-line layout)
- 💾 Context window usage percentage
- 🕐 5-hour / 7-day subscription usage with reset times, and a warning colour above 90%
- 🔄 Advanced git status with staging, working changes, and upstream tracking
- ⚡ Zero plumbing — rendered directly by `oh-my-posh claude`, no background scripts, tokens, or API calls

## How it works

This status line is rendered entirely by oh-my-posh's native [`claude` segment](https://ohmyposh.dev/docs/segments/cli/claude). Claude Code pipes its session JSON to the `oh-my-posh claude` command on stdin, and oh-my-posh reads the model, context window, and subscription rate limits directly from it:

```
Claude Code ──(session JSON on stdin)──▶ oh-my-posh claude --config claude-native.omp.json ──▶ status line
```

There is **no wrapper script, no `ccusage`, no token handling, and no cache** — everything the status line shows comes from the data Claude Code already provides.

## Installation

### Quick Install (Recommended)

Install directly from GitHub without cloning:

```bash
curl -s https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.sh | bash
```

**Custom installation directory:**
```bash
curl -s https://raw.githubusercontent.com/JimiSmith/oh-my-claude/main/install.sh | bash -s -- -d ~/.custom/location
```

This will:
- ✅ Check for required dependencies (oh-my-posh, jq; git optional)
- ✅ Install the theme to `~/.claude/oh-my-claude/`
- ✅ Back up and update your `~/.claude/settings.json` to run `oh-my-posh claude`

**Security Note**: The installer only writes to your home directory and never requests sudo access. You can review the script before running: [View install.sh](https://github.com/JimiSmith/oh-my-claude/blob/main/install.sh)

### Alternative: Local Installation

For development or if you prefer to clone the repository:

```bash
git clone https://github.com/JimiSmith/oh-my-claude.git
cd oh-my-claude
bash local-install.sh
```

### Manual setup

If you'd rather wire it up yourself, copy `src/claude-native.omp.json` somewhere and point your `~/.claude/settings.json` at it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "oh-my-posh claude --config ~/.claude/oh-my-claude/claude-native.omp.json",
    "padding": 0
  }
}
```

Use the absolute path to `oh-my-posh` if it isn't on the PATH Claude Code runs with.

## Status Line Display

A two-line powerline prompt:

**Line 1 — workspace**

| Segment | Colour | Description |
|---------|--------|-------------|
| **Path** | Blue | Current directory |
| **Git** | Lime → orange/cyan/coral | Branch and status; colour changes with repo state (clean, dirty, ahead, behind, diverged) |

**Line 2 — Claude session** (driven by the native `claude` segment)

| Segment | Colour | Description |
|---------|--------|-------------|
| **Model** | Teal | Current model (`.Model.DisplayName`) |
| **Context** | Lime | Context window usage % (`.TokenUsagePercent`) |
| **5h** | Teal → orange >90% | 5-hour usage % and time to reset (`.FiveHourUsage` / `.FiveHourResetsIn`) |
| **7d** | Lime → orange >90% | 7-day usage % and reset day/time (`.SevenDayUsage` / `.SevenDayResetsAt`) |

The 5h/7d segments only appear for Pro/Max subscribers once Claude Code has the data (after the first API response); they hide cleanly otherwise.

## Project Structure

```
oh-my-claude/
├── install.sh                    # Web installer (downloads from GitHub)
├── local-install.sh              # Local installer (for development)
├── bump-version.sh               # Version bump helper
├── .gitattributes                # Force LF line endings (cross-platform)
├── src/
│   └── claude-native.omp.json    # The oh-my-posh theme (the whole status line)
├── README.md                     # This file
├── CHANGELOG.md                  # Version history
└── VERSION                       # Current version number
```

## Customization

Everything lives in `~/.claude/oh-my-claude/claude-native.omp.json`:

- **Colours**: edit the `palette` block, or a segment's `background` / `foreground`
- **Icons / labels**: edit a segment's `template`
- **Warning threshold**: the 5h/7d `background_templates` use `{{ if gt .FiveHourUsage 90.0 }}` — change `90.0`
- **Segment order / additions**: rearrange or add segments; see the [oh-my-posh claude segment docs](https://ohmyposh.dev/docs/segments/cli/claude) for every available field

## Status Indicators

> **Note**: icons below are [Nerd Font](https://www.nerdfonts.com/) glyphs and require a Nerd Font installed in your terminal to display.

| Icon | Meaning |
|------|---------|
| folder glyph | Path/directory indicator |
| upstream arrow glyph | Git upstream status indicator |
| staged-files glyph | Staged files in git |
| modified-files glyph | Modified files in git |
| `↑` / `↓` | Commits ahead / behind remote |
| microchip glyph (U+F035B) | Context usage indicator |
| timer glyph (U+F051B) | 5-hour usage indicator |
| gauge glyph (U+F04C5) | 7-day usage indicator |
| robot glyph (U+F0BC9) | Model indicator |

## Dependencies

- **oh-my-posh** (required) — renders the status line
- **jq** (required by the installer) — used to update `settings.json`
- **git** (optional) — only needed for the git segment
- A **Nerd Font** in your terminal for the icons

## Troubleshooting

**Test the status line manually:**
```bash
echo '{"model":{"display_name":"Test"},"context_window":{"current_usage":{"input_tokens":1000},"context_window_size":200000}}' \
  | oh-my-posh claude --config ~/.claude/oh-my-claude/claude-native.omp.json
```

**Status line not appearing?** Check `~/.claude/settings.json` contains:
```json
"statusLine": {
  "type": "command",
  "command": "oh-my-posh claude --config ~/.claude/oh-my-claude/claude-native.omp.json",
  "padding": 0
}
```
If `oh-my-posh` isn't found, use its absolute path in the command.

**5h/7d segments missing?** They only show for Pro/Max subscribers after Claude Code's first API response in a session.

**Git segment missing?** It only appears inside a git repository (and requires `git` on PATH).

## Version Management

```bash
bash bump-version.sh
```

Semantic versioning (MAJOR.MINOR.PATCH): major = breaking changes, minor = new features, patch = bug fixes.

## Credits

Originally based on [oh-my-claude](https://github.com/ssenart/oh-my-claude) by ssenart (MIT licensed); see [LICENSE](LICENSE). This version has been reworked to render natively via `oh-my-posh claude`.

For version history and detailed changes, see [CHANGELOG.md](CHANGELOG.md).
