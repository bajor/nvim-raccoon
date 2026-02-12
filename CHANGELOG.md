# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
