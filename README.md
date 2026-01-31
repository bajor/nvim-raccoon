# raccoon.nvim

A Neovim plugin for reviewing GitHub pull requests and examining individual commits one by one.

## Features

- Open and review PRs directly in Neovim
- Navigate through changed files with diff highlighting
- View and create inline comments
- Jump between diff hunks and comments
- Show PR description and metadata
- Merge PRs (merge, squash, or rebase)
- Auto-sync to detect new commits
- Statusline integration for sync status

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
- `:Raccoon config` - Open the config file

### Keymaps (active during PR review)

| Key | Action |
|-----|--------|
| `nn` | Next diff/comment |
| `pp` | Previous diff/comment |
| `nt` | Next comment thread |
| `pt` | Previous comment thread |
| `cc` | Comment at cursor |
| `<leader>dd` | Show PR description |
| `<leader>ll` | List all comments |
| `<leader>rr` | Merge PR (pick method) |

### Statusline Integration

For lualine:

```lua
{
  require('raccoon').statusline,
  cond = require('raccoon').is_active,
}
```

## License

MIT
