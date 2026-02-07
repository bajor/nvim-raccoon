# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
