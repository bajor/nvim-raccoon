# Configuration Reference

All configuration for raccoon.nvim lives in a single JSON file at `~/.config/raccoon/config.json`. Run `:Raccoon config` to create it with defaults and open it for editing.

## How it works

On every PR operation (opening, syncing, merging), the plugin reads `config.json`, merges it with built-in defaults, validates required fields, and uses the result. You only need to specify fields you want to set or override — everything else falls back to sensible defaults.

The merge uses a deep merge strategy, so nested objects like `shortcuts` and `commit_viewer` can be partially overridden without losing the rest.

Validation rules:
- **`tokens`** is required and must contain at least one entry
- Unknown fields are silently ignored

## Minimal config

The smallest valid config needs just a token:

```json
{
  "tokens": {
    "your-username": "ghp_xxxxxxxxxxxxxxxxxxxx"
  }
}
```

This uses `github.com` as the host, auto-discovers PRs from your token's permissions, and uses defaults for everything else.

## Required fields

### `tokens`

| Type | Default | Required |
|------|---------|----------|
| object | `{}` | Yes |

A map of owner/org names to GitHub personal access tokens. Each owner/org you want to access needs a matching token entry.

Tokens are used for both API authentication (`Authorization: Bearer <token>`) and HTTPS git operations (cloning, fetching).

```json
{
  "tokens": {
    "my-username": "ghp_personal_xxxxxxxxxxxx",
    "work-org": "ghp_work_xxxxxxxxxxxx"
  }
}
```

To create a token:
- **Classic token** ([github.com/settings/tokens](https://github.com/settings/tokens)): enable the `repo` scope
- **Fine-grained token** ([github.com/settings/personal-access-tokens](https://github.com/settings/personal-access-tokens)): grant read access to metadata, and read/write access to code, issues, and pull requests

For GitHub Enterprise, create the token on your enterprise instance (e.g. `github.mycompany.com/settings/tokens`).

## Optional fields

### `github_username`

| Type | Default |
|------|---------|
| string | `""` |

Your GitHub username. Used as the display name for optimistic comment rendering (shows your name on new comments before the API responds). If not set, displays "you" as a placeholder.

```json
{
  "github_username": "octocat"
}
```

### `github_host`

| Type | Default |
|------|---------|
| string | `"github.com"` |

The GitHub host to connect to. Set this to your company's GitHub Enterprise domain to use the plugin with a self-hosted GitHub instance.

> **Requires GHES 3.9 or newer.** The plugin sends the `X-GitHub-Api-Version: 2022-11-28` header which is not supported by older GHES versions. A one-time info message is shown when GHES mode is active.

The plugin auto-computes the correct API endpoints from the host:

| Host | REST API | GraphQL API |
|------|----------|-------------|
| `github.com` | `https://api.github.com` | `https://api.github.com/graphql` |
| `github.mycompany.com` | `https://github.mycompany.com/api/v3` | `https://github.mycompany.com/api/graphql` |

PR URLs, clone URLs, and git remote parsing all use the configured host. For example, with `"github_host": "github.mycompany.com"`, the plugin expects PR URLs like `https://github.mycompany.com/owner/repo/pull/123`.

```json
{
  "github_host": "github.mycompany.com"
}
```

Leave this unset (or set to `"github.com"`) for regular GitHub.

### `clone_root`

| Type | Default |
|------|---------|
| string | `~/.local/share/nvim/raccoon/repos` |

Root directory where PR branches are shallow-cloned for review. Each PR gets its own subdirectory at `{clone_root}/{owner}/{repo}/pr-{number}`.

Supports tilde expansion (`~/...`).

```json
{
  "clone_root": "~/code/pr-reviews"
}
```

Clones persist on disk, so reopening a PR is fast — it fetches updates instead of cloning from scratch. Delete the directory to free disk space when you no longer need old review clones.

### `pull_changes_interval`

| Type | Default |
|------|---------|
| number | `300` |

How often (in seconds) the plugin checks for new commits pushed to the PR branch while a review session is active. Set lower for faster detection, higher to reduce API calls. Minimum value is 10 seconds.

```json
{
  "pull_changes_interval": 120
}
```

The sync check compares the HEAD SHA — if nothing changed, no further API calls are made. Auto-sync is paused while commit viewer mode is active and resumes when you exit. You can also manually sync with `:Raccoon sync` at any time.

### `commit_viewer`

Nested object controlling the commit viewer grid layout.

#### `commit_viewer.grid.rows`

| Type | Default |
|------|---------|
| number | `2` |

Number of rows in the commit viewer diff grid. Each cell shows one diff hunk.

#### `commit_viewer.grid.cols`

| Type | Default |
|------|---------|
| number | `2` |

Number of columns in the commit viewer diff grid. A 2x2 grid shows 4 diff hunks at once.

```json
{
  "commit_viewer": {
    "grid": { "rows": 3, "cols": 2 }
  }
}
```

#### `commit_viewer.base_commits_count`

| Type | Default |
|------|---------|
| number | `20` |

Number of recent base branch commits shown in the commit viewer sidebar. These appear below the PR branch commits, allowing you to see what was on the base branch before the PR.

```json
{
  "commit_viewer": {
    "base_commits_count": 30
  }
}
```

### `shortcuts`

| Type | Default |
|------|---------|
| object | see [shortcuts_docs.md](shortcuts_docs.md) |

Custom keyboard shortcuts. See [shortcuts_docs.md](shortcuts_docs.md) for the full reference of all 23 configurable shortcuts with descriptions and examples.

Partial overrides are merged with defaults — you only need to specify keys you want to change. Set any shortcut to `false` to disable it.

```json
{
  "shortcuts": {
    "pr_list": "<leader>gp",
    "merge": false
  }
}
```

## Full config example

```json
{
  "github_username": "your-username",
  "github_host": "github.com",
  "tokens": {
    "your-username": "ghp_personal_token",
    "work-org": "ghp_work_token"
  },
  "clone_root": "~/code/pr-reviews",
  "pull_changes_interval": 120,
  "commit_viewer": {
    "grid": { "rows": 3, "cols": 2 },
    "base_commits_count": 30
  },
  "shortcuts": {
    "pr_list": "<leader>pr",
    "next_point": "<C-n>",
    "prev_point": "<C-p>"
  }
}
```

## GitHub Enterprise example

Requires GHES 3.9 or newer.

```json
{
  "github_host": "github.acme-corp.com",
  "tokens": {
    "jdoe": "ghp_xxxxxxxxxxxxxxxxxxxx",
    "platform-team": "ghp_yyyyyyyyyyyyyyyyyyyy"
  }
}
```

## Config file location

The config file is always at `~/.config/raccoon/config.json`. This path is not configurable.

| Command | What it does |
|---------|-------------|
| `:Raccoon config` | Creates the file with defaults (if missing) and opens it in a buffer |

The file is plain JSON — edit it with any editor. Changes take effect on the next PR operation (no restart needed).
