# Keyboard Shortcuts Reference

All shortcuts live under `shortcuts` in `~/.config/raccoon/config.json`. Override only the keys you want to change; everything else keeps the default. Set any shortcut to `false` to disable its keymap without removing the underlying `:Raccoon` command.

Run `:Raccoon shortcuts` or press `<leader>?` to see the active bindings.

## Scope

- `flat diff review mode`: inline diff review, comment/thread navigation, thread/file pickers, commenting
- `commit mode`: read-only commit viewer for understanding code history
- `local mode`: read-only local commit viewer

`comment`, `list`, `threads`, `files`, thread navigation, file navigation, and merge are flat-diff-only. In commit/local mode they show `Available only in flat diff review mode`.

`description`, `prs`, and `sync` remain available in commit mode. `prs` also remains available in local mode, and local mode keeps the same read-only boundary.

## Abbreviations

- `[NR]`: unresolved thread where you commented and somebody replied after you
- `[U]`: other unresolved thread
- `[R]`: resolved thread row in `:Raccoon list`
- `[I]`: parsed PR issue comment tied to a file/line

Resolved review threads are hidden from flat-diff markers and badges, but `comment` on that line still shows them in the same-line picker. Full history also remains available in `:Raccoon list`.

## Config shape

```json
{
  "shortcuts": {
    "pr_list": "<leader>pr",
    "show_shortcuts": "<leader>?",
    "next_point": "<leader>j",
    "commit_viewer_toggle": "<leader>cm",
    "commit_viewer": {
      "next_page": "<leader>j"
    }
  }
}
```

`shortcuts.commit_viewer_toggle` is the flat-diff/commit-viewer toggle.
It restores your last flat-diff location or composer draft when you come back, and restores your last commit-viewer position when you re-enter.

`shortcuts.commit_viewer.*` are the keys active inside commit/local viewer layouts.

## Global

| Config key | Default | Description |
|------------|---------|-------------|
| `pr_list` | `<leader>pr` | Open the PR picker. |
| `show_shortcuts` | `<leader>?` | Show the shortcuts help popup. |

## Review Navigation

| Config key | Default | Description |
|------------|---------|-------------|
| `next_point` | `<leader>j` | Next diff hunk or visible comment point. Flat diff only. |
| `prev_point` | `<leader>k` | Previous diff hunk or visible comment point. Flat diff only. |
| `next_file` | `<leader>nf` | Next changed file, using smart landing inside that file. Flat diff only. |
| `prev_file` | `<leader>pf` | Previous changed file, using smart landing inside that file. Flat diff only. |
| `next_thread` | `<leader>nt` | Next unresolved review thread in flat-diff order. Flat diff only. |
| `prev_thread` | `<leader>pt` | Previous unresolved review thread in flat-diff order. Flat diff only. |
| `next_needs_reply_thread` | `<leader>nr` | Next unresolved thread that needs your reply. Flat diff only. |

## Review Actions

| Config key | Default | Description |
|------------|---------|-------------|
| `comment` | `<leader>c` | Open the current line's exact-thread picker or `New thread on this line`. Resolved same-line threads are included there even though flat diff hides their inline markers. Flat diff only. |
| `description` | `<leader>dd` | Toggle the PR description popup. Also available in commit mode. |
| `list_comments` | `<leader>ll` | Open the broad PR comment history. Exact threads get separate rows even on the same line. Flat diff only. |
| `list_threads` | `<leader>lt` | Open unresolved-thread picker. Flat diff only. |
| `list_files` | `<leader>lf` | Open changed-file picker with `[NR/U/I]` counts. Flat diff only. |
| `sync` | `<leader>r` | Full sync of the current raccoon context. In review sessions this is always a full PR sync. |
| `merge` | `<leader>mr` | Open merge method picker. Flat diff only. |
| `commit_viewer_toggle` | `<leader>cm` | Enter or exit commit viewer mode, preserving the last flat-diff draft/location and the last commit-viewer position for the current PR. |

## Thread / Composer

| Config key | Default | Description |
|------------|---------|-------------|
| `comment_send` | `<leader>s` | Send the current reply or new thread immediately. |
| `comment_resolve` | `<leader>cr` | Resolve the current thread. |
| `comment_unresolve` | `<leader>cu` | Unresolve the current thread. |
| `close` | `<leader>q` | Close the current popup when allowed. `Esc` always works as a fallback. |

If a composer contains text, close is blocked until you clear the message or send it.

## Commit / Local Viewer

These live under `shortcuts.commit_viewer`.

| Config key | Default | Description |
|------------|---------|-------------|
| `next_page` | `<leader>j` | Next page of diff hunks. |
| `prev_page` | `<leader>k` | Previous page of diff hunks. |
| `next_page_alt` | `<leader>l` | Alternate next-page binding. |
| `exit` | `<leader>cm` | Exit commit/local viewer. |
| `maximize_prefix` | `<leader>m` | Prefix for maximize actions such as `<leader>m1`. |
| `browse_files` | `<leader>f` | Toggle focus to the file tree. |

Commit/local viewer remains read-only. Use flat diff for commenting and thread work.

## Command equivalents

| Shortcut | Command |
|----------|---------|
| `pr_list` | `:Raccoon prs` |
| `description` | `:Raccoon description` |
| `list_comments` | `:Raccoon list` |
| `list_threads` | `:Raccoon threads` |
| `list_files` | `:Raccoon files` |
| `sync` | `:Raccoon sync` |
| `merge` | `:Raccoon merge` / `:Raccoon squash` / `:Raccoon rebase` |
| `commit_viewer_toggle` | `:Raccoon commits` |
