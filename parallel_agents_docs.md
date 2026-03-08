# Parallel Agents

Dispatch fire-and-forget CLI agent processes (e.g. `claude -p`, `amp -x`) directly from the commit viewer's maximized diff view. Review a commit diff, optionally select code, and fire off an agent with context automatically injected. Multiple agents can run in parallel.

## Configuration

Add a `parallel_agents` section to `~/.config/raccoon/config.json`:

```json
{
  "parallel_agents": {
    "enabled": true,
    "command": "claude -p <PROMPT>",
    "suffix_prompt": "Commit and push when done.",
    "shortcut": "<leader>aa"
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Enable the feature. When false, no keymaps are registered. |
| `command` | string | `""` | Shell command template. Must contain `<PROMPT>` as a placeholder — it will be replaced with the assembled prompt (shell-escaped). |
| `suffix_prompt` | string | `""` | Text appended to every agent prompt. Use this for instructions like "always commit and push when done". |
| `shortcut` | string or false | `"<leader>aa"` | Keymap to trigger agent dispatch in maximized diff view. Set to `false` to disable. |

The `command` field is a shell string executed via `sh -c`. The `<PROMPT>` placeholder is replaced with a shell-escaped prompt containing the user's task description, commit context, and optionally the visual selection.

### Command template examples

```json
"command": "claude -p <PROMPT>"
"command": "amp -x <PROMPT>"
"command": "aider --message <PROMPT>"
```

## Usage

1. Open the commit viewer (`:Raccoon commits` or `:Raccoon local`)
2. Navigate to a commit and maximize a diff cell (`<leader>m1`, `<leader>m2`, etc.) or browse files and press Enter
3. In the maximized diff view:
   - **Normal mode**: Press the shortcut (default `<leader>a`), type your task, press Enter
   - **Visual mode**: Select lines of interest, press the shortcut, type your task, press Enter

The agent receives:
- Your task description
- Visual selection context (if any): filename, line range, selected code with syntax highlighting hint
- Commit context: short SHA and commit message
- Suffix prompt (if configured)

### Prompt structure

```
<your task text>

Selected code from <filename>, lines <start>-<end>:
```<filetype>
<selected lines>
```

Commit: <sha_short> — <commit_message>

<suffix_prompt>
```

The visual selection block is only included when you select lines before dispatching.

## Statusline

When agents are running, the statusline shows a count:

```
PR #42: Open  [2 agents]
```

The `is_active()` function returns `true` while agents are running, even without an active PR session. This means your lualine `cond` function will keep the statusline section visible while agents finish.

## Where agents run

**PR mode**: Agents run in the shallow clone at `{clone_root}/{owner}/{repo}/pr-{number}`, checked out to the PR branch. Pushing from here updates the PR directly — making `suffix_prompt: "Commit and push when done."` a natural fit for review-driven fixes.

**Local mode**: Agents run in your working directory (the git root). Changes happen in place.

## Concurrent access

Multiple agents can run simultaneously on the same repo. Since they share the working directory, be aware of potential git conflicts if multiple agents modify the same files. Using the suffix prompt to instruct agents to work on branches can help avoid this.

## Notes

- The feature is completely inert when `enabled` is `false` (the default) — no keymaps are registered, no modules are loaded unnecessarily
- Agents run as detached processes — closing Neovim does not kill them
- The shortcut works in both normal and visual mode, making it the first visual-mode keymap in the commit viewer
- The feature works in both PR commit viewer and local commit viewer modes
