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
- Create and view inline comments on specific lines
- Jump between diff hunks and comment threads
- Step through individual commits in a grid layout (commit viewer mode)
- View PR descriptions and metadata
- Merge, squash, or rebase PRs
- Auto-sync to detect new commits pushed to the branch
- Local commit viewer (`:Raccoon local`) for browsing any git repo's history with live "Current changes" view
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
| `tokens` | object | `{}` | Token per owner/org, e.g. `{"my-org": "ghp_..."}` |
| `repos` | array | `[]` | Limit PR list to specific repos, e.g. `["my-org/backend"]`. Only PRs involving you are shown. |
| `clone_root` | string | `<nvim data dir>/raccoon/repos` | Where PR branches are cloned for review |
| `pull_changes_interval` | number | `300` | How often (in seconds) to auto-sync with remote |
| `shortcuts` | object | see below | Custom keyboard shortcuts (partial overrides merged with defaults) |
| `commit_viewer.grid.rows` | number | `2` | Rows in the commit viewer diff grid |
| `commit_viewer.grid.cols` | number | `2` | Columns in the commit viewer diff grid |
| `commit_viewer.base_commits_count` | number | `20` | Number of recent base branch commits shown in the sidebar |

Each key in `tokens` is the **owner or org name from the repo URL** — the first path segment after the host. To find it, open any repo you want to review and copy the name between the host and the repo name:

- **github.com**: `github.com/{owner}/repo` — e.g. `github.com/my-org/backend` → key is `my-org`
- **GitHub Enterprise**: `github.mycompany.com/{owner}/repo` — e.g. `github.mycompany.com/platform-team/core-api` → key is `platform-team`

### GitHub Enterprise

> **Requires GHES 3.9 or newer.** Older versions are not supported and will produce API errors.
>
> **Use a Classic token for GHES.** Fine-grained tokens may not be available on all GHES versions. Create one at `https://<your-host>/settings/tokens` with the `repo` scope.

Set `github_host` to your company's GitHub Enterprise domain:

```json
{
  "github_host": "github.mycompany.com",
  "tokens": {
    "your-username": "ghp_xxxxxxxxxxxxxxxxxxxx"
  }
}
```

The plugin auto-detects the correct API endpoints (`https://<host>/api/v3` for REST, `https://<host>/api/graphql` for GraphQL). PR URLs, clone URLs, and remote parsing all use the configured host.

### Shortcut defaults

See [shortcuts_docs.md](shortcuts_docs.md) for a detailed reference of all 23 configurable shortcuts, grouped by context, with descriptions of what each one does and examples of custom configurations.

### Full config example

```json
{
  "github_host": "github.com",
  "tokens": {
    "your-username": "ghp_personal_token",
    "work-org": "ghp_work_token"
  },
  "repos": ["your-username/project", "work-org/api"],
  "clone_root": "~/code/pr-reviews",
  "pull_changes_interval": 120,
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
3. Add your tokens
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
| `:Raccoon local` | Toggle local commit viewer for the current repo |
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

Press `<leader>cm` during a PR review to enter commit viewer mode. A file tree on the left shows all PR files with three-level highlighting: files in the current commit are brighter, and files currently visible in the grid are highlighted the strongest. The main area displays a configurable grid of diff hunks. A sidebar on the right lists all commits from the PR branch and recent base branch commits.

### Commit viewer keymaps

Commit mode shortcuts live under `shortcuts.commit_mode` in config:

| Key | Config key | Action |
|-----|------------|--------|
| `j` / `k` | — | Navigate commits in sidebar (auto-loads diffs) |
| `<leader>j` | `commit_mode.next_page` | Next page of diff hunks |
| `<leader>k` | `commit_mode.prev_page` | Previous page of diff hunks |
| `<leader>l` | `commit_mode.next_page_alt` | Next page of diff hunks (alias) |
| `<leader>f` | `commit_mode.browse_files` | Toggle focus between commit sidebar and file tree |
| `<leader>m1`..`m9` | `commit_mode.maximize_prefix` | Maximize a grid cell (full file diff) |
| `<leader>q` / `q` | `close` | Exit maximized view |
| `<leader>cm` | `commit_mode.exit` | Exit commit viewer mode |

Each grid cell shows one diff hunk with syntax highlighting and `+`/`-` gutter signs. The filename and cell number are shown in the winbar. A header bar displays the current commit message and page indicator. Navigation crosses seamlessly from PR branch commits into base branch commits. If a file has multiple hunks, each gets its own cell.

Most vim keybindings are disabled in commit mode to prevent breaking the layout. Only the keys listed above work. Exit with `<leader>cm`. Auto-sync is paused while commit viewer mode is active and resumes automatically when you exit.

Press `<leader>m<N>` to maximize a cell — this opens a floating window with the full file diff. Normal vim navigation works inside (scrolling, search), but page/cell switching is blocked. Close with `q` or `<leader>q`.

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

Local mode works alongside an active PR review — entering `:Raccoon local` pauses the PR session, and exiting resumes it.

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

## Inspiration

The design philosophy of this plugin is influenced by Gabriella Gonzalez's [Beyond Agentic Coding](https://haskellforall.com/2026/02/beyond-agentic-coding), which argues that good tools keep the user in a flow state and in direct contact with the code. Raccoon tries to follow that principle as a guiding star — keep everything inside Neovim, stay close to the code, never break focus.

## License

MIT
