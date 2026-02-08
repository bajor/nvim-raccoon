# Keyboard Shortcuts Reference

All keyboard shortcuts in raccoon.nvim are configurable via the `shortcuts` field in `~/.config/raccoon/config.json`. You only need to specify the keys you want to change — unspecified keys keep their defaults. Set any shortcut to `false` to disable it entirely.

Run `:Raccoon shortcuts` (or press `<leader>?` by default) to see your active bindings in a floating window.

## How it works

Shortcuts are loaded from `config.json` at startup and whenever a floating window opens. The plugin merges your overrides with the built-in defaults using a deep merge, so you can override a single key without affecting the rest.

Values are validated on load:
- **Strings** are accepted as keybindings (e.g. `"<leader>j"`, `"<C-n>"`, `"gj"`)
- **`false`** disables the shortcut — the keymap is not registered, but the feature remains available via `:Raccoon` commands
- **Invalid values** (numbers, `null`, empty strings) are silently replaced with the default

Every floating window always responds to `Esc`, so disabling `close` won't lock you out.

## Config structure

```json
{
  "shortcuts": {
    "pr_list": "<leader>pr",
    "show_shortcuts": "<leader>?",
    "next_point": "<leader>j",
    "...": "...",
    "commit_mode": {
      "next_page": "<leader>j",
      "...": "..."
    }
  }
}
```

Top-level keys control global and review-session shortcuts. The nested `commit_mode` object controls shortcuts that are only active inside commit viewer mode.

## Global shortcuts

These are registered at startup and work everywhere in Neovim while the plugin is loaded.

| Config key | Default | Description |
|------------|---------|-------------|
| `pr_list` | `<leader>pr` | Open the PR list floating picker. Shows all open PRs across your configured repos, grouped by repository. Use `j`/`k` to navigate and `Enter` to open a PR for review. |
| `show_shortcuts` | `<leader>?` | Open a floating window listing all active shortcuts grouped by category. Disabled shortcuts appear as `(disabled)`. The window closes on any keystroke. |

## Review navigation

Active during a PR review session. These shortcuts navigate between diff hunks, files, and comment threads.

| Config key | Default | Description |
|------------|---------|-------------|
| `next_point` | `<leader>j` | Jump to the next navigation point in the current file. Points include diff hunk starts and comment locations, sorted by line number. Wraps to the next file when reaching the end. |
| `prev_point` | `<leader>k` | Jump to the previous navigation point. Wraps to the previous file when reaching the beginning. |
| `next_file` | `<leader>nf` | Switch to the next changed file in the PR. Files are ordered as returned by the GitHub API (typically alphabetical by path). |
| `prev_file` | `<leader>pf` | Switch to the previous changed file in the PR. |
| `next_thread` | `<leader>nt` | Jump to the next comment thread in the current file. Threads are groups of comments on the same line. |
| `prev_thread` | `<leader>pt` | Jump to the previous comment thread in the current file. |

## Review actions

Active during a PR review session. These open floating windows for specific actions.

| Config key | Default | Description |
|------------|---------|-------------|
| `comment` | `<leader>c` | Open a comment editor at the current cursor line. The comment is attached to the diff position in the PR. Press the `comment_save` shortcut to submit. |
| `description` | `<leader>dd` | Toggle the PR description floating window. Shows the PR title, author, labels, and full body text rendered as markdown. |
| `list_comments` | `<leader>ll` | Open a floating window listing all comments in the PR, grouped by file and line. Press `Enter` on a comment to view its full thread. |
| `merge` | `<leader>rr` | Open the merge method picker. Shows CI status at the top, then three options: merge, squash, or rebase. Press `1`/`2`/`3` or navigate with `Enter`. |
| `commit_viewer` | `<leader>cm` | Toggle commit viewer mode. Enters a grid layout showing individual commit diffs with a sidebar listing all commits. Press again to exit back to normal review. |

## Comment editor

Active inside comment floating windows (new comment, thread view).

| Config key | Default | Description |
|------------|---------|-------------|
| `comment_save` | `<leader>s` | Save and submit the comment. In a thread view, this adds a reply to the existing thread. In a new comment window, this creates a new inline comment on the PR. |
| `comment_resolve` | `<leader>r` | Mark the current comment thread as resolved. Only works in the thread view window, not when creating a new comment. |
| `comment_unresolve` | `<leader>u` | Mark the current comment thread as unresolved. Reverses a previous resolve action. |

## Common

Used across multiple contexts.

| Config key | Default | Description |
|------------|---------|-------------|
| `close` | `<leader>q` | Close the current floating window or exit the review session. Used in the PR list, comment windows, description window, merge picker, and other floating UI. `Esc` always works as a fallback. |

## Commit viewer mode

These shortcuts are nested under `shortcuts.commit_mode` in config and are only active inside commit viewer mode. Normal vim keybindings are mostly disabled in this mode to prevent breaking the grid layout.

| Config key | Default | Description |
|------------|---------|-------------|
| `next_page` | `<leader>j` | Show the next page of diff hunks in the grid. When a commit has more hunks than grid cells, they are paginated. |
| `prev_page` | `<leader>k` | Show the previous page of diff hunks. |
| `next_page_alt` | `<leader>l` | Alias for `next_page`. Provides an alternative key for forward navigation. |
| `exit` | `<leader>cm` | Exit commit viewer mode and return to the normal PR review view. |
| `maximize_prefix` | `<leader>m` | Prefix for maximizing a grid cell. Followed by a cell number (1-9), e.g. `<leader>m1` maximizes cell 1 into a full floating window with the complete file diff. Inside the maximized view, normal vim navigation works (scrolling, search). Close with `q` or the `close` shortcut. |

Note: `j`/`k` for navigating commits in the sidebar and `Enter` for selecting a commit are hardcoded and not configurable.

## Example: custom config

Override only the keys you want to change:

```json
{
  "shortcuts": {
    "next_point": "<C-n>",
    "prev_point": "<C-p>",
    "close": "<leader>x",
    "commit_mode": {
      "exit": "<leader>ce"
    }
  }
}
```

## Example: disabling shortcuts

```json
{
  "shortcuts": {
    "show_shortcuts": false,
    "merge": false,
    "commit_mode": {
      "maximize_prefix": false
    }
  }
}
```

Disabled shortcuts show as `(disabled)` in the `:Raccoon shortcuts` window.

## Corresponding commands

Every shortcut has a `:Raccoon` command equivalent that works regardless of whether the shortcut is enabled:

| Shortcut | Command |
|----------|---------|
| `pr_list` | `:Raccoon prs` |
| `show_shortcuts` | `:Raccoon shortcuts` |
| `description` | `:Raccoon description` |
| `list_comments` | `:Raccoon list` |
| `merge` | `:Raccoon merge` / `:Raccoon squash` / `:Raccoon rebase` |
| `commit_viewer` | `:Raccoon commits` |
| `close` | `:Raccoon close` |
