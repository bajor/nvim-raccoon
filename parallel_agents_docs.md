# Parallel Agents

Dispatch fire-and-forget CLI agent processes (e.g. `claude -p`, `amp -x`) directly from the commit viewer's maximized diff view. Review a commit diff, optionally select code, and fire off an agent with context automatically injected. Multiple agents can run in parallel.

## Configuration

Add a `parallel_agents` section to `~/.config/raccoon/config.json`:

```json
{
  "parallel_agents": {
    "enabled": true,
    "command": "claude --dangerously-skip-permissions -p <PROMPT>",
    "suffix_prompt": "When done, create a commit with a description of the changes and how they address the original request."
  },
  "shortcuts": {
    "commit_mode": {
      "dispatch_agent": "<leader>aa"
    }
  }
}
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `false` | Enable the feature. When false, no keymaps are registered. |
| `command` | string | `""` | Shell command template. Must contain `<PROMPT>` as a placeholder — it will be replaced with the assembled prompt (shell-escaped). |
| `suffix_prompt` | string | `""` | Text appended to every agent prompt. Use this for instructions like "always commit and push when done". |
| `popup_width` | number | `70` | Width of the task input popup in columns. Clamped to terminal width minus 4. |

The `command` field is a shell string executed via `sh -c`. The `<PROMPT>` placeholder is replaced with a shell-escaped prompt containing the user's task description, commit context, and optionally the visual selection.
The keybinding is configured separately under `shortcuts.commit_mode.dispatch_agent`. Set it to `false` to disable the maximize-view shortcut while keeping the feature available in config.

### Command template examples

```json
"command": "claude --dangerously-skip-permissions -p <PROMPT>"
"command": "claude --allowedTools Edit,Write,Bash -p <PROMPT>"
"command": "amp -x <PROMPT>"
"command": "aider --message <PROMPT>"
```

For `claude`, use either `--dangerously-skip-permissions` or `--allowedTools <tools>` so the agent doesn't hang on permission prompts. The plugin warns if neither flag is present.

## Usage

1. Open the commit viewer (`:Raccoon commits` or `:Raccoon local`)
2. Navigate to a commit and maximize a diff cell (`<leader>m1`, `<leader>m2`, etc.) or browse files and press Enter
3. In the maximized diff view:
   - **Normal mode**: Press the dispatch shortcut (default `shortcuts.commit_mode.dispatch_agent = <leader>aa`), type your task, press `<leader>s` to send
   - **Visual mode**: Select lines of interest, press the dispatch shortcut, type your task, press `<leader>s` to send

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
[1/5] ✓ In sync [2 agents]
```

The `is_active()` function returns `true` while agents are running, even without an active PR session. This means your lualine `cond` function will keep the statusline section visible while agents finish.

## Where agents run

**PR mode**: Agents run in the shallow clone at `{clone_root}/{owner}/{repo}/pr-{number}`, checked out to the PR branch. Pushing from here updates the PR directly — making a commit-focused `suffix_prompt` a natural fit for review-driven fixes.

**Local mode**: Agents run in your working directory (the git root). Changes happen in place.

## Concurrent access

Multiple agents can run simultaneously on the same repo. Since they share the working directory, be aware of potential git conflicts if multiple agents modify the same files. Using the suffix prompt to instruct agents to work on branches can help avoid this.

## Notes

- The feature is completely inert when `enabled` is `false` (the default) — no keymaps are registered and no agent processes are spawned
- Agents run as child processes of Neovim — closing Neovim will terminate running agents, so ensure agents complete before exiting
- The shortcut works in both normal and visual mode, making it the first visual-mode keymap in the commit viewer
- The feature works in both PR commit viewer and local commit viewer modes
