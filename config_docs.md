# Configuration Reference

All configuration for raccoon.nvim lives in a single JSON file at `~/.config/raccoon/config.json`. Run `:Raccoon config` to create it with defaults and open it for editing.

## How it works

On every PR operation (opening, syncing, merging), the plugin reads `config.json`, merges it with built-in defaults, validates required fields, and uses the result. You only need to specify fields you want to set or override — everything else falls back to sensible defaults.

The merge uses a deep merge strategy, so nested objects like `shortcuts` and `commit_viewer` can be partially overridden without losing the rest.

Validation rules:
- **`tokens`** is required and must contain at least one entry
- Unknown fields are silently ignored (e.g. legacy `github_username`)
- Renamed keys are migrated transparently by `lua/raccoon/config_compat.lua` — see the [Migrating from older config keys](#migrating-from-older-config-keys) section at the bottom

## Minimal config

The smallest valid config needs just a token:

```json
{
  "tokens": {
    "your-username": "ghp_xxxxxxxxxxxxxxxxxxxx"
  }
}
```

This uses `github.com` as the host, shows open PRs involving you (authored, assigned, review-requested, or commented) from all repos accessible by the token, and uses defaults for everything else.

## Required fields

### `tokens`

| Type | Default | Required |
|------|---------|----------|
| object | `{}` | Yes |

A map of owner/org names to GitHub personal access tokens. Each key is the **owner or org name from the repo URL** — the first path segment after the host. To find it, open any repo you want to review and copy the name between the host and the repo name:

- **github.com**: `github.com/{owner}/repo` — e.g. `github.com/acme-corp/backend` → key is `acme-corp`
- **GitHub Enterprise**: `github.mycompany.com/{owner}/repo` — e.g. `github.mycompany.com/platform-team/core-api` → key is `platform-team`

Each owner/org you want to access needs a matching token entry.

Tokens are used for both API authentication (`Authorization: Bearer <token>`) and HTTPS git operations (cloning, fetching).

Each token value can be either a **string** (uses the default `github_host`) or an **object** with `token`, optional `host`, and optional `login` fields:

```json
{
  "tokens": {
    "my-username": "ghp_personal_xxxxxxxxxxxx",
    "work-org": "ghp_work_xxxxxxxxxxxx"
  }
}
```

**Multi-host example** — access both github.com and a GitHub Enterprise instance:

```json
{
  "tokens": {
    "my-username": "ghp_personal_xxxxxxxxxxxx",
    "work-org": {
      "token": "ghp_work_xxxxxxxxxxxx",
      "host": "github.mycompany.com",
      "login": "my-work-login"
    }
  }
}
```

String tokens use the `github_host` setting (default `"github.com"`). Table tokens with a `host` field override the default host for that owner/org. The host is normalized the same way as `github_host` (lowercased, protocol stripped).

`login` is optional. When present, raccoon uses it as the viewer login for that token instead of calling the GitHub API to discover it. Its only purpose is exact-thread review features such as `[NR]` detection.

To create a token:
- **Classic token** ([github.com/settings/tokens](https://github.com/settings/tokens)): enable the `repo` scope

For GitHub Enterprise, create a **Classic token** on your enterprise instance at `https://<your-host>/settings/tokens` with the `repo` scope.

## Optional fields

### `repos`

| Type | Default |
|------|---------|
| array | `[]` |

Limit the `:Raccoon prs` list to specific repositories. Each entry is an `"owner/repo"` string matching the repo URL (`github.com/{owner}/{repo}`). When set, only open PRs from these repos that involve you (authored, assigned, review-requested, or commented) are shown. When empty or omitted, PRs involving you from all repos accessible by each token are shown.

```json
{
  "repos": ["acme-corp/backend", "acme-corp/frontend"]
}
```

The owner in each repo entry must have a matching token in `tokens`.

### `github_host`

| Type | Default |
|------|---------|
| string | `"github.com"` |

The default GitHub host for tokens that don't specify their own host. Set this to your company's GitHub Enterprise domain if most of your tokens are for a self-hosted instance. For multi-host setups, you can also specify the host per-token in the `tokens` map (see above).

> **Requires GHES 3.9 or newer.** The plugin sends the `X-GitHub-Api-Version: 2022-11-28` header which is not supported by older GHES versions. A one-time info message is shown when GHES mode is active.

The plugin auto-computes the correct API endpoints from the host:

| Host | REST API | GraphQL API |
|------|----------|-------------|
| `github.com` | `https://api.github.com` | `https://api.github.com/graphql` |
| `github.mycompany.com` | `https://github.mycompany.com/api/v3` | `https://github.mycompany.com/api/graphql` |

PR URLs, clone URLs, and git remote parsing all use the host. When opening a PR by URL (`:Raccoon open <url>`), the host is extracted from the URL automatically.

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

### `sync_interval` *(formerly `pull_changes_interval`)*

| Type | Default |
|------|---------|
| number | `300` |

How often (in seconds) the plugin checks for new commits pushed to the PR branch while a review session is active. Set lower for faster detection, higher to reduce API calls. Minimum value is 10 seconds (anything lower is clamped to 10).

```json
{
  "sync_interval": 120
}
```

The sync check compares the HEAD SHA — if nothing changed, no further API calls are made. Auto-sync is paused while commit/local viewer mode is active and resumes when you exit. In flat diff, auto-sync also skips cycles while a reply/new-thread composer contains unsent text. You can manually sync at any time with `:Raccoon sync` or the configured `shortcuts.sync` binding. Toggling between flat diff and PR commit mode preserves the last flat-diff file/thread/composer state and the last commit-viewer selection for the current PR.

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

#### `commit_viewer.sidebar_width`

| Type | Default |
|------|---------|
| number | `50` |

Width in columns of the commit list sidebar (right) and file tree panel (left). Clamped to 1–500.

```json
{
  "commit_viewer": {
    "sidebar_width": 40
  }
}
```

#### `commit_viewer.commit_message_max_lines`

| Type | Default |
|------|---------|
| number | `3` |

Maximum number of lines displayed in the commit message header bar. The header shows the full commit message (subject + body) wrapped to the available width, truncated to this many lines. Clamped to 1–50.

```json
{
  "commit_viewer": {
    "commit_message_max_lines": 5
  }
}
```

#### `commit_viewer.passthrough_keys` *(formerly top-level `passthrough_keymaps`)*

| Type | Default |
|------|---------|
| array | `[]` |

Key sequences (LHS strings) that should *not* be blocked by the commit viewer's keymap lockdown. By default, commit viewer mode replaces most normal-mode keymaps with no-ops to keep the grid layout stable. Add keys here to keep them working — for example, system-wide shortcuts you rely on (`<D-S-e>` for a file picker) or your own leader maps that don't conflict with the built-in commit-viewer keys.

Empty strings, duplicates, and non-string entries are silently dropped.

```json
{
  "commit_viewer": {
    "passthrough_keys": ["<D-S-e>", "<leader>p"]
  }
}
```

### `shortcuts`

| Type | Default |
|------|---------|
| object | see [shortcuts_docs.md](shortcuts_docs.md) |

Custom keyboard shortcuts. See [shortcuts_docs.md](shortcuts_docs.md) for the full reference with mode boundaries, defaults, and examples.

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
  "github_host": "github.com",
  "tokens": {
    "your-username": "ghp_personal_token",
    "work-org": "ghp_work_token"
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
    "next_point": "<C-n>",
    "prev_point": "<C-p>"
  }
}
```

## GitHub Enterprise example

Requires GHES 3.9 or newer. Use a **Classic token** with `repo` scope. Create one at `https://<your-host>/settings/tokens`.

```json
{
  "github_host": "github.acme-corp.com",
  "tokens": {
    "jdoe": "ghp_xxxxxxxxxxxxxxxxxxxx",
    "platform-team": "ghp_yyyyyyyyyyyyyyyyyyyy"
  },
  "repos": ["platform-team/core-api", "platform-team/infra"]
}
```

## Config file location

The config file is always at `~/.config/raccoon/config.json`. This path is not configurable.

| Command | What it does |
|---------|-------------|
| `:Raccoon config` | Creates the file with defaults (if missing) and opens it in a buffer |

The file is plain JSON — edit it with any editor. Changes take effect on the next PR operation (no restart needed).

## Migrating from older config keys

Several keys were renamed in `0.12.0`. Old keys still work — they are migrated transparently at load time by `lua/raccoon/config_compat.lua` — but you should rename them on your own schedule because the compat layer is intended to be removed in a future major release.

| Old key | New key | Notes |
|---------|---------|-------|
| `pull_changes_interval` | `sync_interval` | Same semantics; same minimum (10 s). |
| `passthrough_keymaps` (top-level array of strings or `{key: ...}` objects) | `commit_viewer.passthrough_keys` (array of strings) | Object-shape entries are flattened to their `key` field during migration. |
| `shortcuts.commit_viewer` (string toggle keymap) | `shortcuts.commit_viewer_toggle` | The string leaf moved to a sibling so the `commit_viewer` name can hold the in-mode shortcut block. |
| `shortcuts.commit_mode.*` (in-mode shortcuts block) | `shortcuts.commit_viewer.*` | Identical inner schema; only the parent key name changes. |

**Conflict rule.** If both the old and new key are present in your config, the new key wins and the old key is silently dropped. So you can flip atomically by writing the new key — anything still in the old key is ignored.

**Removed in 0.12.0 (no migration).** The `parallel_agents` config block is no longer recognized at all. Configs that still contain it are silently ignored as unknown fields.
