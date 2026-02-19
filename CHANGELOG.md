# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.9.9] - 2026-02-19

### Fixed
- Fix broken colors and black floating window backgrounds on Windows (PowerShell) — added 256-color (`ctermbg`/`ctermfg`) fallbacks to all 14 highlight groups so diff backgrounds, signs, comments, and statusline highlights render correctly when `termguicolors` is off
- Fix floating windows showing black backgrounds on Windows — popup floating windows now set `winhighlight = "Normal:Normal,FloatBorder:Normal"` to inherit the editor background for both content and border areas instead of relying on `NormalFloat`/`FloatBorder`
- Fix case-sensitive path comparison in comment placement that silently fails on Windows (case-insensitive filesystem) — now normalizes and case-folds paths when `win32` is detected
- Switch floating window borders from `"rounded"` to `"single"` — sharp corners (`┌┐└┘`) have broader font support than curved corners (`╭╮╰╯`) on Windows

## [0.9.8] - 2026-02-18

### Added
- Diff size bars in commit mode file tree — each changed file shows a proportional `+++----` bar below it indicating additions (green) and deletions (red) for the current commit
- `compute_file_stats()` and `format_stat_bar()` helpers in commit UI module
- Stat bars automatically update when navigating between commits
- Stat bar lines are skipped by file tree keyboard navigation (j/k)
- Works in both PR commit mode and local commit mode

## [0.9.7] - 2026-02-18

### Added
- **Multi-host support** — use both github.com and GitHub Enterprise in the same config by specifying a `host` per token: `"work-org": { "token": "ghp_...", "host": "github.acme.com" }`. String tokens continue to use the `github_host` default. The PR list fetches from all configured hosts, and opening a PR by URL auto-detects the host.
- `config.get_all_tokens()` helper that returns normalized `{key, token, host}` entries for all tokens
- `state.get_github_host()` — session state now tracks which GitHub host the current PR belongs to
- `api.parse_pr_url()` without a host hint now extracts the host from the URL (4th return value)

### Changed
- `config.get_token_for_owner()` and `config.get_token_for_repo()` now return `(token, host)` tuples (backward compatible — callers capturing one value are unaffected)
- `open_pr()` extracts the host from the PR URL instead of requiring it to match `github_host`
- `sync_pr()` uses the host stored in session state instead of re-reading `github_host` from config
- Review and comment operations (`review.lua`, `comments.lua`) re-initialize the API host from session state before each call, preventing interference from concurrent PR list fetches
- PR list fetching (`ui.lua`) initializes API URLs per-token host instead of once globally

## [0.9.6] - 2026-02-18

### Fixed
- Enable `core.longpaths` for all git operations, fixing "filename too long" errors on Windows when cloning repos with deeply nested paths (also requires Windows long-path support enabled at the OS level; see [Microsoft docs](https://learn.microsoft.com/en-us/windows/win32/fileio/maximum-file-path-limitation?tabs=registry#enable-long-paths-in-windows-10-version-1607-and-later))

## [0.9.5] - 2026-02-17

### Fixed
- Fix GHES 422 errors caused by broken unauthenticated `/meta` version detection — GHES is now inferred from hostname
- Fix GHES 422 errors when listing PRs — replace `user:{owner}` search qualifier with explicit `involves:{username}` resolved via `GET /user`
- Replace `@me` alias in search queries with resolved username for GHES compatibility
- Only show GHES 3.9+ version hint for 404 errors (not 422 validation errors)
- Always send `X-GitHub-Api-Version: 2022-11-28` header (supported by both github.com and GHES 3.9+)
- Normalize `github_host` (lowercase, strip protocol/whitespace/trailing slashes) to prevent GHES misclassification

### Added
- `repos` config option — limit the PR list to specific repositories (`["owner/repo", ...]`) instead of showing all PRs across the entire org
- Auto-detect authenticated username via `GET /user` — no manual username config needed

### Changed
- Removed runtime GHES version detection in favor of deterministic host-based inference
- Show one-time info notification when GHES mode is active
- PR list now only shows PRs involving you (authored, assigned, review-requested, or commented) via GitHub's `involves:{username}` filter

### Removed
- `github_username` config option — it was only used for cosmetic comment display and is now ignored if present (backward compatible)

## [0.9.4] - 2026-02-13

### Changed
- Compact tree connectors in commit mode file explorer: `├──` → `├`, `└──` → `└`, saving horizontal space for deeply nested paths

## [0.9.3] - 2026-02-13

### Fixed
- Normalize backslash paths to forward slashes in `get_current_file_path()` before sending to GitHub API, fixing 422 errors when creating PR review comments on Windows
- Use `vim.fs.joinpath` for file content reading path construction in `show_file_content()`
- Deduplicate config path using centralized `config.config_path` instead of hardcoded `~/.config/raccoon/config.json`

## [0.9.2] - 2026-02-12

### Added
- Auto-detect GitHub Enterprise Server version via `/meta` endpoint for API compatibility
- Conditionally omit `X-GitHub-Api-Version` header for GHES < 3.9
- Graceful degradation for GraphQL thread resolution on older GHES versions

## [0.9.1] - 2026-02-11

### Changed
- Shortened the tree display in the commit mode file explorer.
- Made the exploration and commit tabs slightly wider.
- Made the exploration and commit tabs slightly wider.

## [0.9] - 2026-02-11

### Added
- File tree browsing in commit viewer — press `<leader>f` (configurable via `commit_mode.browse_files`) to toggle focus between the commit sidebar and file tree
- Navigate all repo files with j/k, gg/G, and `/` search while in file tree mode
- Press Enter on any file to view its content at the current commit state in a maximized floating window
- Extracted shared `setup_sidebar_nav` into `commit_ui.lua`, reducing duplication between PR and local commit viewers

### Changed
- File tree and sidebar winbars now show descriptive labels with the `browse_files` shortcut hint instead of raw file/commit counters
- Diff grid stays intact while browsing files in the file tree (no auto-paging)

## [0.8] - 2026-02-10

### Added
- Local commit viewer mode (`:Raccoon local`) — browse commit history in any git repository without a PR or GitHub token
- **"Current changes"** live view at the top of the sidebar showing uncommitted modifications (staged + unstaged vs HEAD)
- Adaptive working directory polling: once every 3 seconds when changes are active, backs off to once every 30 seconds after 3 minutes idle
- Selection preservation — when new commits appear in the sidebar, your current selection stays on the same commit
- Local mode coexists with PR sessions: entering pauses the active PR review, exiting resumes it
- New git functions: `diff_working_dir`, `diff_working_dir_file`, `status_porcelain`
- Extracted `parse_diff_output` helper for shared diff parsing between committed and working directory diffs
- Working directory file tree via `git ls-files` when viewing current changes
- Maximize view support for working directory files

### Changed
- Shared commit UI module (`commit_ui.lua`) now handles nil SHA for working directory mode
- Commit count in sidebar header excludes the pseudo "Current changes" entry

## [0.7] - 2026-02-09

### Added
- `github_host` configuration option for GitHub Enterprise support — set to your GHE hostname instead of the default `github.com`
- `pull_changes_interval` configuration option to control how often the auto-sync timer checks for new commits (default: 300 seconds, minimum: 10 seconds)
- Comprehensive configuration reference documentation (`config_docs.md`)

### Changed
- File tree panel now shows the full repository file tree instead of only PR-touched files, generated per commit via `git ls-tree`
- File tree highlights use a greyscale palette; currently displayed files shown in white
- File tree panel on the left, commit sidebar on the right (swapped from v0.6)
- Track all commit file types including binary, mode-only, and rename-only changes

### Removed
- `repos` config field — PRs are auto-discovered from token permissions; an explicit repo list was never used
- `poll_interval_seconds` config field — was defined but never consumed (sync uses a fixed interval)
- Deprecated `spinner` module and its tests
- Legacy deprecated code paths

## [0.6] - 2026-02-08

### Added
- File tree panel in commit viewer mode — a right-side panel showing all PR files with three-level highlighting: dim for files not in the current commit, medium for files in the current commit, and bright/bold for files currently visible in the grid
- Three new highlight groups: `RaccoonFileNormal`, `RaccoonFileInCommit`, `RaccoonFileVisible` (overridable via colorscheme)

### Changed
- Commit sidebar stays on the right in commit viewer mode; file tree panel takes the left side

## [0.5] - 2026-02-08

### Added
- Configurable keyboard shortcuts — all keymaps defined in `config.json` under `shortcuts`, with commit viewer shortcuts nested under `shortcuts.commit_mode`
- Optional shortcuts — set any shortcut to `false` in config to disable it; the keymap won't be registered but `:Raccoon` commands still work
- `:Raccoon shortcuts` command and `<leader>?` keymap to display all active shortcuts in a floating help window (closes on any keystroke)
- Disabled shortcuts shown as `(disabled)` in the shortcuts help window
- Default shortcut values written to config file on creation via `:Raccoon config`

### Changed
- All hardcoded keymaps across the plugin now load dynamically from config
- All shortcut hints in floating window titles update to reflect user-configured bindings and omit disabled shortcuts
- `keymaps.lua` refactored from static table to dynamic `build_keymaps()` driven by config

### Removed
- `github_token` config field — use the `tokens` table instead (maps owner/org to token)

## [0.4.1] - 2026-02-08

### Fixed
- Use `vim.fs.joinpath` for all filesystem path construction instead of hardcoded `/` concatenation, improving cross-platform portability
- Replace DST-sensitive `os.time(os.date("!*t"))` in `relative_time` with pure-arithmetic UTC-to-epoch conversion, eliminating off-by-one-hour errors near DST transitions
- Strip both `/` and `\` trailing separators in `build_pr_path` for Windows compatibility
- Remove dead config fields (`ghostty_path`, `nvim_path`, `notifications`) that were no longer referenced
- Remove personal vim-plug migration artifact from Makefile
- Restore `stdpath("data")` for temp URL file path (revert of `/tmp` change)

### Changed
- Expose `relative_time` on module table for testability with injectable `now_utc` parameter
- Use portable `clone_root` in `:Raccoon config` default template

## [0.4] - 2026-02-07

### Added
- Commit viewer mode (`<leader>cm` or `:Raccoon commits`) — browse individual commits from the PR branch in a configurable grid of diff hunks
- Fetch base branch with explicit refspec to support shallow single-branch clones
- Sidebar on the right listing PR branch commits and recent base branch commits
- Seamless navigation between PR branch and base branch commits (j/k crosses the boundary)
- Configurable grid layout via `commit_viewer.grid` in config.json (default 2x2)
- j/k navigation in sidebar auto-loads the selected commit's diffs into the grid
- `<leader>j`/`<leader>k` to page through diff hunks when there are more than the grid can show
- `<leader>l` as alias for next page
- `<leader>m1`..`m9` to maximize a grid cell into a floating full-file diff view
- Grid cell numbers (`#1`, `#2`, ...) and filename shown in winbar at top of each cell
- Full-width header bar at top of screen showing page indicator (left) and commit message (right)
- Syntax highlighting and gutter signs (`+`/`-`) for diffs in grid cells
- Focus lock: sidebar stays focused, window-switching keys blocked in commit mode
- Keybinding lockdown in commit mode — only `j`/`k`, `<leader>j`/`<leader>k`, `<leader>cm`, and `<leader>m<N>` work; `:q`, insert mode, editing keys, and other vim commands are blocked
- Maximize window is fully isolated — page navigation and cell switching are blocked; normal vim navigation (scrolling, search, `:` commands) is allowed
- Line wrapping enabled in grid cells and maximize view
- Git sync pauses while in commit viewer mode and resumes on exit
- `diff-tree` used for commit diffs to correctly handle merge commits
- New git operations: `unshallow_if_needed`, `log_commits`, `log_base_commits`, `show_commit`, `show_commit_file`, `fetch_branch`
- `commit_viewer.base_commits_count` config option (default 20)
- `commit_viewer` defaults in config template
- Diff highlights extend to full window width
- Increased diff highlight contrast for colorblind accessibility

### Fixed
- Prefer a-path over `/dev/null` b-path for deleted files in commit viewer
- Pad deleted-line virtual text so red highlight extends to end of line

## [0.3] - 2026-02-07

### Added
- `<leader>pr` keymap to browse all open PRs in a floating picker window
- `:Raccoon prs` command as alternative to the keymap
- j/k and arrow key navigation in PR list, Enter to open, q to close, r to refresh

### Changed
- Move navigation keymaps to leader-prefixed: `<leader>j`/`<leader>k` (next/prev point), `<leader>nf`/`<leader>pf` (next/prev file), `<leader>nt`/`<leader>pt` (next/prev thread), `<leader>c` (comment). Eliminates conflicts with built-in Vim keys.

### Fixed
- Use per-repo tokens in PR list fetch instead of hardcoded global token

## [0.2] - 2026-02-07

### Added
- Read-only thread view from comment list (press Enter to view)
- PR review body display in review sessions
- File count indicator in status bar
- Point position within file shown in navigation notifications
- `u` keymap to unresolve comment threads
- `nf`/`pf` keymaps for next/previous file navigation with wrap-around
- GraphQL API for fetching PR review thread resolution status
- CI status display in merge picker
- Statusline functions restoration
- Companion macOS app documentation in README
- Makefile with devinstall target
- CI workflow

### Fixed
- Remove unused repo variables in resolve/unresolve handlers
- Wrap async window close in pcall to prevent errors
- Correct argument order for resolve/unresolve_review_thread
- Handle vim.NIL in comment line numbers
- Validate line number before setting cursor in comment list
- Handle non-numeric line values in list_comments
- Always show sync status in statusline component
- Restore original get_statusline_component behavior
- Include actual error message in file open failure notification
- Switch to native Neovim pack directory with file open error handling
- Wrap file opening in pcall to handle treesitter errors gracefully
- Add nowait and validity check to merge_picker close keymaps
- Fix config.get() to config.load() in merge_picker
- Update local base branch on PR open and sync
- Fix test failures in review and keymaps modules

### Changed
- Remove duplicate file count from notifications

## [0.1] - 2026-01-31

Initial release.
