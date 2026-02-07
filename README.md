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

A Neovim plugin for reviewing GitHub pull requests and examining individual commits one by one.

> **Note:** Currently supports GitHub only.

## PR List Picker

Press `<leader>pr` or run `:Raccoon prs` to open a floating picker with all open PRs from your configured repos. Navigate with `j`/`k`, press `Enter` to open a PR for review, and `r` to refresh. This lets you browse and switch between PRs without leaving Neovim.

## Companion App (Optional)

The [prs-and-issues-preview-osx](https://github.com/bajor/prs-and-issues-preview-osx) macOS menu bar app can display your PRs in the menu bar and open them directly in Neovim with raccoon.nvim. Since the plugin now includes a built-in PR picker, the companion app is no longer required but can still be used as a convenience.

## Features

- Open and review PRs directly in Neovim
- Navigate through changed files with diff highlighting
- View and create inline comments
- Jump between diff hunks and comments
- Show PR description and metadata
- Merge PRs (merge, squash, or rebase)
- Auto-sync to detect new commits
- Statusline integration showing file position and sync status

## Requirements

- Neovim 0.9+
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "your-username/nvim-raccoon",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("raccoon").setup()
  end,
}
```

## Configuration

Create a config file at `~/.config/raccoon/config.json`:

```json
{
  "github_token": "ghp_xxxxxxxxxxxxxxxxxxxx",
  "github_username": "your-username",
  "repos": ["owner/repo1", "owner/repo2"],
  "clone_root": "~/.local/share/raccoon/repos"
}
```

Or run `:Raccoon config` to create a default config file.

## Usage

### Commands

- `:Raccoon open <url>` - Open a PR by URL
- `:Raccoon list` - List all comments in the PR
- `:Raccoon description` - Show PR description
- `:Raccoon sync` - Sync PR with remote
- `:Raccoon merge` - Merge the PR
- `:Raccoon squash` - Squash and merge
- `:Raccoon rebase` - Rebase and merge
- `:Raccoon close` - Close the review session
- `:Raccoon prs` - Open the PR list picker
- `:Raccoon config` - Open the config file

### Keymaps (active during PR review)

| Key | Action |
|-----|--------|
| `<leader>j` | Next diff/comment |
| `<leader>k` | Previous diff/comment |
| `<leader>nf` | Next file |
| `<leader>pf` | Previous file |
| `<leader>nt` | Next comment thread |
| `<leader>pt` | Previous comment thread |
| `<leader>c` | Comment at cursor |
| `<leader>dd` | Show PR description |
| `<leader>ll` | List all comments |
| `<leader>pr` | Open PR list picker |
| `<leader>rr` | Merge PR (pick method) |

### Statusline Integration

The statusline shows your current position and sync status:
- `[1/3] ✓ In sync` — reviewing file 1 of 3, branch is up to date
- `[2/3] ⚠ 2 commits behind main` — file 2 of 3, needs sync
- `[1/5] ⛔ CONFLICTS` — merge conflicts detected

When navigating with `<leader>j`/`<leader>k`, notifications show position within the current file:
- `[2/5] src/main.lua:42 (change)` — point 2 of 5 in this file, at line 42

For lualine:

```lua
{
  require('raccoon').statusline,
  cond = require('raccoon').is_active,
}
```

## License
MIT


