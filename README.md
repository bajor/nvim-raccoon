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
- A [GitHub personal access token](https://github.com/settings/tokens) with `repo` scope

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
  "github_token": "ghp_xxxxxxxxxxxxxxxxxxxx",
  "github_username": "your-username",
  "repos": ["owner/repo1", "owner/repo2"]
}
```

### All config fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `github_token` | string | `""` | GitHub personal access token (fallback for all repos) |
| `github_username` | string | `""` | Your GitHub username |
| `repos` | string[] | `[]` | Repos to watch, in `"owner/repo"` format |
| `tokens` | object | `{}` | Per-org tokens, e.g. `{"my-org": "ghp_..."}`. Overrides `github_token` for matching owners |
| `clone_root` | string | `<nvim data dir>/raccoon/repos` | Where PR branches are cloned for review |
| `poll_interval_seconds` | number | `300` | How often (in seconds) to check for new commits |
| `commit_viewer.grid.rows` | number | `2` | Rows in the commit viewer diff grid |
| `commit_viewer.grid.cols` | number | `2` | Columns in the commit viewer diff grid |
| `commit_viewer.base_commits_count` | number | `20` | Number of recent base branch commits shown in the sidebar |

You need either `github_token` (used for all repos) or `tokens` (per-org tokens), or both. When both are present, `tokens` takes priority for matching owners and `github_token` is the fallback.

### Full config example

```json
{
  "github_token": "ghp_xxxxxxxxxxxxxxxxxxxx",
  "github_username": "your-username",
  "repos": ["owner/repo1", "owner/repo2"],
  "tokens": {
    "work-org": "ghp_work_token_here"
  },
  "clone_root": "~/code/pr-reviews",
  "poll_interval_seconds": 120,
  "commit_viewer": {
    "grid": { "rows": 3, "cols": 2 },
    "base_commits_count": 30
  }
}
```

## Getting Started

1. Install the plugin and restart Neovim
2. Run `:Raccoon config` to create and edit your config file
3. Add your GitHub token and username
4. Add repos you want to review (e.g. `["myorg/backend", "myorg/frontend"]`)
5. Run `:Raccoon prs` to browse open PRs
6. Press `Enter` on a PR to start reviewing

When you open a PR, raccoon clones the branch locally and displays each changed file with diff highlighting. You can navigate between files and diff hunks, leave comments, and merge — all from inside Neovim.

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
| `:Raccoon close` | Close the review session |
| `:Raccoon config` | Open the config file (creates default if missing) |

## Keymaps

These keymaps are active during a PR review session:

| Key | Action |
|-----|--------|
| `<leader>j` | Next diff/comment |
| `<leader>k` | Previous diff/comment |
| `<leader>nf` | Next file |
| `<leader>pf` | Previous file |
| `<leader>nt` | Next comment thread |
| `<leader>pt` | Previous comment thread |
| `<leader>c` | Comment at cursor position |
| `<leader>dd` | Show PR description |
| `<leader>ll` | List all comments |
| `<leader>pr` | Open PR list picker |
| `<leader>rr` | Merge PR (pick method) |
| `<leader>cm` | Toggle commit viewer mode |

## Commit Viewer Mode

Inspired by chess game review, where you step through moves to understand the sequence that led to the final position. Instead of seeing the PR as a flat diff, commit viewer lets you replay the author's thought process one commit at a time — understanding *how* the code got to where it is, not just *what* changed.

Press `<leader>cm` during a PR review to enter commit viewer mode. A sidebar lists all commits from the PR branch and recent base branch commits. The main area displays a configurable grid of diff hunks.

### Commit viewer keymaps

| Key | Action |
|-----|--------|
| `j` / `k` | Navigate commits in sidebar (auto-loads diffs) |
| `<leader>j` | Next page of diff hunks |
| `<leader>k` | Previous page of diff hunks |
| `<leader>l` | Next page of diff hunks (alias) |
| `<leader>m1`..`m9` | Maximize a grid cell (full file diff in floating window) |
| `<leader>q` / `q` | Exit maximized view |
| `<leader>cm` | Exit commit viewer mode |

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
