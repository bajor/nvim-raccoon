# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.4] - 2026-02-07

### Added
- Commit viewer mode (`<leader>cm` or `:Raccoon commits`) — browse individual commits from the PR branch in a configurable grid of diff hunks
- Sidebar on the right listing PR branch commits and recent base branch commits
- Configurable grid layout via `commit_viewer.grid` in config.json (default 2x2)
- j/k navigation in sidebar auto-loads the selected commit's diffs into the grid
- `<leader>j`/`<leader>k` to page through diff hunks when there are more than the grid can show
- `<leader>l` as alias for next page
- Git sync pauses while in commit viewer mode and resumes on exit
- New git operations: `unshallow_if_needed`, `log_commits`, `log_base_commits`, `show_commit`
- `commit_viewer.base_commits_count` config option (default 20)

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
