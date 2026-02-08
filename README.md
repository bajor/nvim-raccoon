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

## Features

- Browse open PRs with a floating picker
- Review changed files with inline diff highlighting
- Create and view inline comments on specific lines
- Jump between diff hunks and comment threads
- Step through individual commits in a grid layout (commit viewer mode)
- View PR descriptions and metadata
- Merge, squash, or rebase PRs
- Auto-sync to detect new commits pushed to the branch
- Statusline integration showing file position and sync status

## Requirements

- Neovim 0.9+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- A GitHub personal access token — either:
  - **Classic token** ([create here](https://github.com/settings/tokens)): with `repo` scope
  - **Fine-grained token** ([create here](https://github.com/settings/personal-access-tokens)): with these repository permissions:
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

```json
{
  "github_username": "your-username",
  "tokens": {
    "your-username": "ghp_xxxxxxxxxxxxxxxxxxxx"
  },
  "repos": ["owner/repo1", "owner/repo2"]
}
```

### All config fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `github_username` | string | `""` | Your GitHub username |
| `tokens` | object | `{}` | Token per owner/org, e.g. `{"my-org": "ghp_..."}` |
| `repos` | string[] | `[]` | Repos to watch, in `"owner/repo"` format |
| `clone_root` | string | `<nvim data dir>/raccoon/repos` | Where PR branches are cloned for review |
| `poll_interval_seconds` | number | `300` | How often (in seconds) to check for new commits |
| `shortcuts` | object | see below | Custom keyboard shortcuts (partial overrides merged with defaults) |
| `commit_viewer.grid.rows` | number | `2` | Rows in the commit viewer diff grid |
| `commit_viewer.grid.cols` | number | `2` | Columns in the commit viewer diff grid |
| `commit_viewer.base_commits_count` | number | `20` | Number of recent base branch commits shown in the sidebar |

Each owner in your `repos` list needs a matching entry in `tokens`. For example, if you watch `"my-org/backend"`, add `"my-org": "ghp_..."` to `tokens`.

### Shortcut defaults

See [shortcuts_docs.md](shortcuts_docs.md) for a detailed reference of all 22 configurable shortcuts, grouped by context, with descriptions of what each one does and examples of custom configurations.

### Full config example

```json
{
  "github_username": "your-username",
  "tokens": {
    "your-username": "ghp_personal_token",
    "work-org": "ghp_work_token"
  },
  "repos": ["your-username/side-project", "work-org/backend"],
  "clone_root": "~/code/pr-reviews",
  "poll_interval_seconds": 120,
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
    "comment": "<leader>c",
    "description": "<leader>dd",
    "list_comments": "<leader>ll",
    "merge": "<leader>rr",
    "commit_viewer": "<leader>cm",
    "comment_save": "<leader>s",
    "comment_resolve": "<leader>r",
    "comment_unresolve": "<leader>u",
    "close": "<leader>q",
    "commit_mode": {
      "next_page": "<leader>j",
      "prev_page": "<leader>k",
      "next_page_alt": "<leader>l",
      "exit": "<leader>cm",
      "maximize_prefix": "<leader>m"
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
    "commit_mode": {
      "maximize_prefix": false
    }
  }
}
```

Disabled shortcuts show as `(disabled)` in `:Raccoon shortcuts`.

## Getting Started

1. Install the plugin and restart Neovim
2. Run `:Raccoon config` to create and edit your config file
3. Add your username, tokens, and repos you want to review
4. Run `:Raccoon prs` to browse open PRs
5. Press `Enter` on a PR to start reviewing

## How it works

When you open a PR, raccoon shallow-clones the PR branch into a local directory and opens the changed files with inline diff highlighting. Each PR gets its own clone at `{clone_root}/{owner}/{repo}/pr-{number}` (default root: `~/.local/share/nvim/raccoon/repos`). You can change the root with the `clone_root` config field.

The per-PR directory means previous clones stay on disk — reopening a PR is fast because it fetches updates instead of cloning from scratch. Neovim's working directory changes to the clone path during a review session, so LSP, treesitter, and other tools work on the actual source code.

One review session is active at a time. Opening a second PR closes the first.

## Commands

| Command | Description |
|---------|-------------|
| `:Raccoon prs` | Open the PR list picker |
| `:Raccoon open <url>` | Open a PR by its GitHub URL |
| `:Raccoon list` | List all comments in the current PR |
| `:Raccoon description` (or `desc`) | Show PR description and metadata |
| `:Raccoon sync` (or `update`, `refresh`) | Sync the PR with remote |
| `:Raccoon merge` | Merge the PR |
| `:Raccoon squash` | Squash and merge |
| `:Raccoon rebase` | Rebase and merge |
| `:Raccoon commits` | Toggle commit viewer mode |
| `:Raccoon shortcuts` | Show all keyboard shortcuts in a floating window |
| `:Raccoon close` | Close the review session |
| `:Raccoon config` | Open the config file (creates default if missing) |

## Keymaps

All keymaps are configurable via the `shortcuts` field in `config.json`. The values below are the defaults. Override any key by adding it to your config — only the keys you specify are changed, the rest keep their defaults. Set any shortcut to `false` to disable it entirely — the keymap won't be registered, but the underlying `:Raccoon` command still works. Run `:Raccoon shortcuts` to see your active bindings.

| Key | Config key | Action |
|-----|------------|--------|
| `<leader>j` | `next_point` | Next diff/comment |
| `<leader>k` | `prev_point` | Previous diff/comment |
| `<leader>nf` | `next_file` | Next file |
| `<leader>pf` | `prev_file` | Previous file |
| `<leader>nt` | `next_thread` | Next comment thread |
| `<leader>pt` | `prev_thread` | Previous comment thread |
| `<leader>c` | `comment` | Comment at cursor position |
| `<leader>dd` | `description` | Show PR description |
| `<leader>ll` | `list_comments` | List all comments |
| `<leader>pr` | `pr_list` | Open PR list picker |
| `<leader>?` | `show_shortcuts` | Show shortcuts help |
| `<leader>rr` | `merge` | Merge PR (pick method) |
| `<leader>cm` | `commit_viewer` | Toggle commit viewer mode |
| `<leader>q` | `close` | Close window / exit session |

## Commit Viewer Mode

Inspired by chess game review, where you step through moves to understand the sequence that led to the final position. Instead of seeing the PR as a flat diff, commit viewer lets you replay the author's thought process one commit at a time — understanding *how* the code got to where it is, not just *what* changed.

Press `<leader>cm` during a PR review to enter commit viewer mode. A sidebar on the left lists all commits from the PR branch and recent base branch commits. The main area displays a configurable grid of diff hunks. A file tree on the right shows all PR files with three-level highlighting: files in the current commit are brighter, and files currently visible in the grid are highlighted the strongest.

### Commit viewer keymaps

Commit mode shortcuts live under `shortcuts.commit_mode` in config:

| Key | Config key | Action |
|-----|------------|--------|
| `j` / `k` | — | Navigate commits in sidebar (auto-loads diffs) |
| `<leader>j` | `commit_mode.next_page` | Next page of diff hunks |
| `<leader>k` | `commit_mode.prev_page` | Previous page of diff hunks |
| `<leader>l` | `commit_mode.next_page_alt` | Next page of diff hunks (alias) |
| `<leader>m1`..`m9` | `commit_mode.maximize_prefix` | Maximize a grid cell (full file diff) |
| `<leader>q` / `q` | `close` | Exit maximized view |
| `<leader>cm` | `commit_mode.exit` | Exit commit viewer mode |

Each grid cell shows one diff hunk with syntax highlighting and `+`/`-` gutter signs. The filename and cell number are shown in the winbar. A header bar displays the current commit message and page indicator. Navigation crosses seamlessly from PR branch commits into base branch commits. If a file has multiple hunks, each gets its own cell.

Most vim keybindings are disabled in commit mode to prevent breaking the layout. Only the keys listed above work. Exit with `<leader>cm`.

Press `<leader>m<N>` to maximize a cell — this opens a floating window with the full file diff. Normal vim navigation works inside (scrolling, search), but page/cell switching is blocked. Close with `q` or `<leader>q`.

## Statusline

The statusline shows your review position and sync status:

- `[1/3] ✓ In sync` — reviewing file 1 of 3, branch is up to date
- `[2/3] ⚠ 2 commits behind main` — needs sync
- `[1/5] ⛔ CONFLICTS` — merge conflicts detected

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

## License

MIT
