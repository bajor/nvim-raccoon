# raccoon.nvim

⣿⣿⣿⣿⣿⣿⣿⣿⡿⠿⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⢿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⡿⢡⠖⠒⠲⢦⣭⣙⠻⢿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠿⢛⣩⣴⠖⠒⠒⢮⠹⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⡇⡏⠄⠄⠄⠄⠉⠛⢷⣦⡉⠛⢿⣿⡿⠿⠛⣛⣉⣭⣥⣤⣤⣤⣤⣤⣤⣭⣭⣉⡛⠛⠿⣿⡿⠟⢋⣤⣾⠟⠉⠄⠄⠄⠄⠘⡆⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⡇⡇⠄⠄⠄⠄⠄⠄⠄⠙⠛⢧⡀⢠⣶⢾⡻⡟⠫⠛⠋⢫⠋⠁⠙⠈⠋⠑⠙⠙⠻⢻⣶⡦⠄⣰⠟⠁⠄⠄⠄⠄⠄⠄⠄⢰⠃⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣷⠸⡄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣠⡾⠋⠂⠁⢈⠋⠄⡀⡀⣰⠄⠆⢀⠠⠄⠄⢀⠄⠄⠙⠿⣦⡀⠄⠄⠄⠄⠄⠄⠄⠄⠄⡞⣸⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣧⠱⡄⠄⠄⠄⠄⠄⣀⡤⠝⠓⠒⠉⢉⣑⣒⡒⠮⢕⡳⠿⠄⢰⣾⣇⣦⣦⣦⣞⢆⣄⢄⠄⠹⢳⣀⡀⠄⠄⠄⠄⢀⡞⣰⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣷⡘⢆⡀⣀⠔⠋⣀⣤⣶⣾⣶⠄⢀⣽⣿⣿⣿⣶⣮⣑⠦⡀⣿⣿⣿⣿⣿⣯⡿⣿⣧⢔⣀⡀⠙⣷⡄⠄⠄⣠⠎⣴⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⢌⠟⠁⢠⣾⣿⣿⣿⣿⣷⣾⣿⣿⣿⣿⣿⣿⣿⣿⠄⢈⠪⡻⣿⣿⣿⣿⣾⣾⣿⣿⣿⣂⠄⠈⢿⣦⡘⠁⣾⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⣿⡣⠃⢀⣠⣌⣛⣿⣿⣿⣿⣿⣿⣿⣿⣿⠟⣿⣿⣿⡇⠄⠄⣷⡝⣝⡟⢯⣿⣿⣿⣿⣿⣿⣿⣯⣤⠄⠘⢿⣆⠻⣿⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣿⠳⠁⢰⣿⣿⣿⣿⣿⣿⣿⣿⣿⡿⠟⠻⠯⠄⣿⣿⡿⠄⠄⠄⠸⣿⡌⡄⠰⠿⠛⠿⣿⣿⣿⣿⣿⣿⣯⡄⠨⣿⣦⠹⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⡿⢃⠇⠄⣬⣿⣿⣿⣿⡟⠛⠛⠋⠄⠄⣀⡀⠄⠄⠄⢻⣇⠄⠄⠄⠄⣿⡏⠸⡀⠄⣀⠄⠄⠉⠛⠛⢻⣿⣿⣷⣶⣽⣿⣗⠹⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⠇⢼⠄⣿⣿⣿⣿⣿⠋⠄⠄⠄⠄⢀⠄⠈⠄⠄⠄⠄⠈⣿⡀⠄⠄⢠⣿⠄⠄⡇⠄⠁⠄⠠⠄⠄⠄⠄⠉⣿⣿⣿⣿⣿⣿⣆⢻⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⠁⢾⢸⠄⣿⣿⣿⠛⠁⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⢰⣿⣧⣠⣆⣾⣿⡄⠄⡇⠄⠄⠄⠄⠄⠄⠄⠄⠄⠈⠙⢻⣿⣿⣿⣿⡦⢙⣿⣿⣿⣿
⣿⣿⣿⣿⣧⠄⣩⣿⠄⠯⠓⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⣠⣿⣿⣿⣿⣿⣿⣿⣿⡄⡇⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠺⢯⣿⣿⣍⠠⣽⣿⣿⣿
⣿⣿⣿⣿⣷⠈⣹⣧⠆⠘⠢⠤⠤⠄⠄⢀⡀⠄⠄⠄⠄⠄⠄⢀⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⠰⣄⠄⠄⠄⠄⠄⠄⠄⢀⡀⠄⠠⠤⠤⡿⣿⣿⣍⠰⣾⣿⣿⣿
⣿⣿⣿⣿⣿⣶⡀⠿⠞⡄⢐⠂⠄⠤⠄⠄⠄⢐⡃⠐⠄⢄⣴⣿⣿⣿⣿⡿⠛⠿⠿⠛⢿⢣⣳⣿⣷⣄⠠⠰⠄⠛⠄⠉⣀⣀⡀⠄⣠⣾⠿⠧⢐⣾⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⣅⠘⠚⢄⠱⣤⣒⠒⠒⠒⠒⠂⠈⠁⣾⣿⣿⣿⣿⡟⠁⢠⣤⣤⡄⡠⢳⣿⣿⣿⣿⡆⠈⠉⣈⠉⠉⠁⣀⣴⣶⠟⠛⣀⣼⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⣿⠏⢐⣦⡈⠳⣌⠛⠿⣷⣶⣶⣂⡉⢈⢿⣿⣿⣿⣿⡅⠄⠄⠄⣠⠞⠁⢸⣿⣿⣿⣿⡇⢙⣂⣴⣶⡿⠟⠏⠉⢀⣮⠂⠹⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⡿⠂⢾⣿⠄⠄⠈⠓⢤⣀⠄⠄⠄⠉⠉⠘⠛⢿⣿⣿⠷⢄⡤⠚⠁⢀⣠⣾⣿⡿⠟⠓⠉⠁⠂⠄⠄⠄⠄⠄⠄⠙⣿⡣⠐⣿⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⣿⡇⢠⣿⡵⣂⣀⣤⠤⠄⠈⠙⠒⠦⠤⠤⠤⠤⠤⠴⠒⠋⠥⢤⣤⡤⠤⠖⠋⠁⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠠⣽⣷⡀⢼⣿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⠟⠄⣻⣿⣿⣿⣿⣷⢋⣀⠄⠄⠄⠄⠄⢹⣿⣿⠉⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⢀⣀⣑⣶⣷⣶⣼⣿⣝⠄⢿⣿⣿⣿⣿⣿
⣿⣿⣿⣿⣿⠂⢼⣿⣿⣿⣿⣿⣿⣋⡁⠄⠄⠄⠄⠄⣨⣟⣛⡤⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠄⠐⠤⣙⡿⣿⣿⣿⣿⣿⣿⢆⠸⣿⣿⣿⣿⣿

Review GitHub pull requests directly in Neovim. Browse changed files with diff highlighting, leave inline comments, step through individual commits, and merge — all without leaving your editor.

> GitHub only. GitLab/Bitbucket are not supported.

## [Blog post with demo](https://bajor.dev/raccoon-nvim-pr-reviews-in-neovim/)

## Features

- Browse open PRs with a floating picker
- Review changed files with inline diff highlighting
- Exact-thread review comments in flat diff
- Jump between diff hunks, unresolved threads, and needs-reply threads
- File picker and unresolved-thread picker for flat diff
- Broad comment history via `:Raccoon list`
- Step through individual commits in a grid layout (commit viewer mode)
- Switch between flat diff and commit viewer without losing your place or draft reply/thread text
- View PR descriptions and metadata
- Merge, squash, or rebase PRs
- Auto-sync to detect new commits pushed to the branch
- Local commit viewer (`:Raccoon local`) for browsing any git repo's history with live "Current changes" view
- Statusline integration showing file position and sync status

## Requirements

- Neovim 0.10+ (uses `vim.uv`)
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- A GitHub personal access token — either:
  - **Classic token** ([create here](https://github.com/settings/tokens)): with `repo` scope
    - Read access to metadata
    - Read and Write access to code, issues, and pull requests

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "bajor/nvim-raccoon",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("raccoon").setup()
  end,
}
```

## Configuration

Run `:Raccoon config` to create and open the config file at `~/.config/raccoon/config.json`. A minimal config looks like this:

The generated starter file includes the current shortcut defaults and commit-viewer block explicitly. You can trim it down later if you prefer a smaller config.

```json
{
  "tokens": {
    "your-username": "ghp_xxxxxxxxxxxxxxxxxxxx"
  }
}
```

See [config_docs.md](config_docs.md) for a detailed reference of every config field with descriptions, examples, and GitHub Enterprise setup.

### All config fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `github_host` | string | `"github.com"` | GitHub host (set to your GHE domain for GitHub Enterprise) |
| `tokens` | object | `{}` | Token per owner/org — string or `{"token": "...", "host": "...", "login": "..."}` for multi-host |
| `repos` | array | `[]` | Limit PR list to specific repos, e.g. `["my-org/backend"]`. Only PRs involving you are shown. |
| `clone_root` | string | `<nvim data dir>/raccoon/repos` | Where PR branches are cloned for review |
| `sync_interval` | number | `300` | How often (in seconds) to auto-sync with remote (minimum 10) *(formerly `pull_changes_interval`)* |
| `shortcuts` | object | see below | Custom keyboard shortcuts (partial overrides merged with defaults) |
| `commit_viewer.grid.rows` | number | `2` | Rows in the commit viewer diff grid |
| `commit_viewer.grid.cols` | number | `2` | Columns in the commit viewer diff grid |
| `commit_viewer.base_commits_count` | number | `20` | Number of recent base branch commits shown in the sidebar |
| `commit_viewer.sidebar_width` | number | `50` | Width of commit list and file tree sidebars (1–500) |
| `commit_viewer.commit_message_max_lines` | number | `3` | Max lines shown in the commit message header (1–50) |
| `commit_viewer.passthrough_keys` | array | `[]` | Key sequences to leave unblocked in commit viewer mode (e.g. `["<leader>p"]`) *(formerly top-level `passthrough_keymaps`)* |

Each key in `tokens` is the **owner or org name from the repo URL** — the first path segment after the host. To find it, open any repo you want to review and copy the name between the host and the repo name:

- **github.com**: `github.com/{owner}/repo` — e.g. `github.com/my-org/backend` → key is `my-org`
- **GitHub Enterprise**: `github.mycompany.com/{owner}/repo` — e.g. `github.mycompany.com/platform-team/core-api` → key is `platform-team`

### GitHub Enterprise

> **Requires GHES 3.9 or newer.** Older versions are not supported and will produce API errors.
>
> **Use a Classic token for GHES.** Create one at `https://<your-host>/settings/tokens` with the `repo` scope.

If all your repos are on one GHES instance, set `github_host`:

```json
{
  "github_host": "github.mycompany.com",
  "tokens": {
    "your-username": "ghp_xxxxxxxxxxxxxxxxxxxx"
  }
}
```

To use **both github.com and GHES** simultaneously, set the host per token:

```json
{
  "tokens": {
    "personal-user": "ghp_personal_xxxxxxxxxxxx",
    "work-org": { "token": "ghp_work_xxxxxxxxxxxx", "host": "github.mycompany.com" }
  }
}
```

String tokens use the `github_host` default (`"github.com"`). Table tokens with a `host` field override it. Optional `login` skips the viewer lookup for that token and is only used to identify "you" in thread features such as `[NR]`. The PR list fetches from all configured hosts, and `:Raccoon open <url>` auto-detects the host from the URL.

The plugin auto-detects the correct API endpoints (`https://<host>/api/v3` for REST, `https://<host>/api/graphql` for GraphQL). PR URLs, clone URLs, and remote parsing all use the resolved host.

### Shortcut defaults

See [shortcuts_docs.md](shortcuts_docs.md) for the full shortcut reference, mode boundaries, and abbreviation meanings.

### Full config example

```json
{
  "tokens": {
    "your-username": "ghp_personal_token",
    "work-org": { "token": "ghp_work_token", "host": "github.mycompany.com" }
  },
  "repos": ["your-username/project", "work-org/api"],
  "clone_root": "~/code/pr-reviews",
  "sync_interval": 120,
  "commit_viewer": {
    "grid": { "rows": 3, "cols": 2 },
    "base_commits_count": 30
  },
  "shortcuts": {
    "pr_list": "<leader>pr",
    "show_shortcuts": "<leader>?",
    "next_point": "<leader>j",
    "prev_point": "<leader>k",
    "next_file": "<leader>nf",
    "prev_file": "<leader>pf",
    "next_thread": "<leader>nt",
    "prev_thread": "<leader>pt",
    "next_needs_reply_thread": "<leader>nr",
    "comment": "<leader>c",
    "description": "<leader>dd",
    "list_comments": "<leader>ll",
    "list_threads": "<leader>lt",
    "list_files": "<leader>lf",
    "sync": "<leader>r",
    "merge": "<leader>mr",
    "commit_viewer_toggle": "<leader>cm",
    "comment_send": "<leader>s",
    "comment_resolve": "<leader>cr",
    "comment_unresolve": "<leader>cu",
    "close": "<leader>q",
    "commit_viewer": {
      "next_page": "<leader>j",
      "prev_page": "<leader>k",
      "next_page_alt": "<leader>l",
      "exit": "<leader>cm",
      "maximize_prefix": "<leader>m",
      "browse_files": "<leader>f"
    }
  }
}
```

### Disabling shortcuts

Set any shortcut to `false` to prevent it from being registered as a keymap. The feature remains available via `:Raccoon` commands. Every floating window always responds to `Esc`, so disabling `close` won't lock you out.

```json
{
  "shortcuts": {
    "show_shortcuts": false,
    "merge": false,
    "commit_viewer": {
      "maximize_prefix": false
    }
  }
}
```

Disabled shortcuts show as `(disabled)` in `:Raccoon shortcuts`.

## Getting Started

1. Install the plugin and restart Neovim
2. Run `:Raccoon config` to create and edit your config file
3. Add your tokens
4. Run `:Raccoon prs` to browse open PRs
5. Press `Enter` on a PR to start reviewing

## How it works

When you open a PR, raccoon shallow-clones the PR branch into a local directory and opens the changed files with inline diff highlighting. Each PR gets its own clone at `{clone_root}/{owner}/{repo}/pr-{number}` (default root: `~/.local/share/nvim/raccoon/repos`). You can change the root with the `clone_root` config field.

The per-PR directory means previous clones stay on disk — reopening a PR is fast because it fetches updates instead of cloning from scratch. Neovim's working directory changes to the clone path during a review session, so LSP, treesitter, and other tools work on the actual source code.

One review session is active at a time. Opening a second PR closes the first unless a reply/new-thread composer still has unsent text.

## Commands

| Command | Description |
|---------|-------------|
| `:Raccoon prs` | Open the PR list picker |
| `:Raccoon open <url>` | Open a PR by its GitHub URL |
| `:Raccoon list` | List all comments in the current PR |
| `:Raccoon threads` | List unresolved review threads in flat diff order |
| `:Raccoon files` | List changed files with `[NR/U/I]` counts |
| `:Raccoon description` (or `desc`) | Show PR description and metadata |
| `:Raccoon sync` (or `update`, `refresh`) | Refresh the current raccoon context; in review sessions this is a full PR sync |
| `:Raccoon merge` | Merge the PR |
| `:Raccoon squash` | Squash and merge |
| `:Raccoon rebase` | Rebase and merge |
| `:Raccoon commits` | Toggle commit viewer mode |
| `:Raccoon local` | Toggle local commit viewer for the current repo |
| `:Raccoon shortcuts` | Show all keyboard shortcuts in a floating window |
| `:Raccoon close` | Close the review session |
| `:Raccoon config` | Open the config file (creates default if missing) |

## Keymaps

All keymaps are configurable via the `shortcuts` field in `config.json`. Override any key by adding it to your config. Set any shortcut to `false` to disable it; the underlying `:Raccoon` command still works. Run `:Raccoon shortcuts` to see the active bindings.

The most-used defaults at a glance:

| Key | Config key | Action |
|-----|------------|--------|
| `<leader>pr` | `pr_list` | Open PR list picker |
| `<leader>cm` | `commit_viewer_toggle` | Toggle commit viewer mode |
| `<leader>?` | `show_shortcuts` | Show all configured shortcuts |
| `<leader>q` | `close` | Close window / exit session |

For the full reference, including flat-diff-only vs commit/local-mode behavior, see [shortcuts_docs.md](shortcuts_docs.md).

### Flat Diff Thread UI

- Flat diff shows only unresolved review threads plus parsed issue comments.
- `[NR]` means an unresolved thread where you commented and somebody replied after you.
- `[U]` means another unresolved thread.
- `[I]` means a parsed PR issue comment tied to a file/line.
- New review threads can be started from any line in files that are part of the PR changed-file set. Lines in review context use persisted REST review comments, and lines outside GitHub's review context fall back to file-level REST comments with `subject_type=file`. GitHub renders those at file scope, so raccoon mirrors them at the top of the file instead of pretending they are line comments.
- Resolved review threads stay hidden from flat-diff markers and badges, but `<leader>c` on that line still shows them in the same-line picker. Full history is also available in `:Raccoon list`.
- `:Raccoon list` may show multiple rows for the same file and line because review threads are tracked by exact GitHub `thread_id`, not line grouping.

## Commit Viewer Mode

Inspired by chess game review, where you step through moves to understand the sequence that led to the final position. Instead of seeing the PR as a flat diff, commit viewer lets you replay the author's thought process one commit at a time — understanding *how* the code got to where it is, not just *what* changed.

Press `<leader>cm` during a PR review to enter commit viewer mode. A file tree on the left shows all PR files with three-level highlighting: files in the current commit are brighter, and files currently visible in the grid are highlighted the strongest. The main area displays a configurable grid of diff hunks. A sidebar on the right lists all commits from the PR branch and recent base branch commits.

Toggling between flat diff and commit viewer restores both sides of your context. If you switch while writing a reply or new thread, raccoon preserves the draft text, lets you inspect commits, and reopens the same composer when you return to flat diff. Re-entering commit mode also restores the last commit/page/file-tree position for the current PR.

### Commit viewer keymaps

In-mode shortcuts live under `shortcuts.commit_viewer` in config:

| Key | Config key | Action |
|-----|------------|--------|
| `j` / `k` | — | Navigate commits in sidebar (auto-loads diffs) |
| `<leader>j` | `commit_viewer.next_page` | Next page of diff hunks |
| `<leader>k` | `commit_viewer.prev_page` | Previous page of diff hunks |
| `<leader>l` | `commit_viewer.next_page_alt` | Next page of diff hunks (alias) |
| `<leader>f` | `commit_viewer.browse_files` | Toggle focus between commit sidebar and file tree |
| `<leader>m1`..`m9` | `commit_viewer.maximize_prefix` | Maximize a grid cell (full file diff) |
| `<leader>q` | `close` | Exit maximized view |
| `<leader>cm` | `commit_viewer.exit` | Exit commit viewer mode |

Each grid cell shows one diff hunk with syntax highlighting and `+`/`-` gutter signs. The filename and cell number are shown in the winbar. A header bar displays the current commit message and page indicator. Navigation crosses seamlessly from PR branch commits into base branch commits. If a file has multiple hunks, each gets its own cell.

Commit mode is read-only. It does not show inline comments, issue notes, thread pickers, file pickers, or merge actions. Use flat diff for commenting and thread work. `description`, `sync`, and `prs` stay available there. Flat-diff-only actions show `Available only in flat diff review mode`.

Most vim keybindings are disabled in commit mode to prevent breaking the layout. Only the keys listed above work. Exit with `<leader>cm`. Auto-sync is paused while commit/local viewer mode is active and resumes automatically when you exit.

Press `<leader>m<N>` to maximize a cell — this opens a floating window with the full file diff. Normal vim navigation works inside (scrolling, search), but page/cell switching is blocked. Close with the configured `close` shortcut or `Esc`.

### File tree browsing

Press `<leader>f` to move focus from the commit sidebar to the file tree on the left. While in file tree mode:

- `j` / `k` — navigate between files
- `gg` / `G` — jump to first / last file
- `/` — search (vim's built-in search)
- `Enter` — view the file's content at the current commit state in a maximized floating window
- `<leader>f` — return focus to the commit sidebar

The diff grid in the center stays intact while browsing files. The active shortcut is shown in the winbar of both the file tree and commit sidebar panels.

## Local Commit Viewer

Run `:Raccoon local` from any git repository to browse its commit history — no GitHub token or PR required. Uses the same grid layout, file tree, and diff rendering as the PR commit viewer.

The first entry in the sidebar is **"Current changes"** — a live view of all uncommitted modifications (staged + unstaged vs HEAD). When selected, the grid updates as files change on disk, polling once every 3 seconds. After 3 minutes of no changes the polling backs off to once every 30 seconds, and snaps back to fast polling the moment new changes appear.

When a new commit is made (e.g. by an AI agent in another terminal), it appears in the sidebar automatically (10-second HEAD poll). Your selection stays on whatever commit you were viewing — new commits just shift the list without stealing focus.

Local mode works alongside an active PR review — entering `:Raccoon local` pauses the PR session, and exiting resumes it. It follows the same read-only review boundary as commit mode.

## Statusline

The statusline shows your review position and sync status:

- `[1/3] IN SYNC`
- `[2/3] BEHIND 2 main`
- `[1/5] CONFLICTS`

When navigating with `<leader>j`/`<leader>k`, notifications show position within the current file:

- `[2/5] src/main.lua:42 (change)` — point 2 of 5, at line 42

### Lualine integration

```lua
{
  require('raccoon').statusline,
  cond = require('raccoon').is_active,
}
```

## Companion App (Optional)

The [prs-and-issues-preview-osx](https://github.com/bajor/prs-and-issues-preview-osx) macOS menu bar app can display your PRs in the menu bar and open them directly in Neovim with raccoon.nvim. The built-in `:Raccoon prs` picker makes the companion app optional.

## Inspiration

The design philosophy of this plugin is influenced by Gabriella Gonzalez's [Beyond Agentic Coding](https://haskellforall.com/2026/02/beyond-agentic-coding), which argues that good tools keep the user in a flow state and in direct contact with the code. Raccoon tries to follow that principle as a guiding star — keep everything inside Neovim, stay close to the code, never break focus.

## License

MIT
