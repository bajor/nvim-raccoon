# Architecture Diff

## Summary
Split diff comments now use one target classification, and inline diff highlights are token-stable and projected onto wrapped rows.

## Diagram(s)

```mermaid
flowchart TD
    A[Cursor target] --> B[resolve_new_thread_target]
    B --> C{Target kind}
    C -->|line| D[New Thread title and line REST comment]
    C -->|file| E[New File Comment title and file REST comment]
    C -->|disabled| F[Warn and disable send]
    D --> G[Picker label]
    E --> G
    F --> G
```

```mermaid
flowchart LR
    A[Paired delete/add row] --> B[UTF-8 char diff]
    B --> C[Expand heavily changed identifier fragments]
    C --> D[Inline byte spans]
    D --> E[Split rendered chunks with byte ranges]
    E --> F[Project spans onto visible row chunks]
    F --> G[Neovim extmarks]
```

## Changes

### Added
- `comments.lua` now resolves new comment targets as `line`, `file`, or `disabled` before labeling, restoring, or sending.
- Split inline rendering now tracks byte ranges for each wrapped visual chunk.

### Modified
- Out-of-hunk changed-file targets remain allowed, but are consistently labeled and sent as file comments.
- Identifier replacements with noisy character matches are highlighted as whole changed tokens.
- Inline split highlights are projected onto continuation rows instead of disappearing when a changed line wraps.

### Removed
- Independent picker/editor/send decisions that could label a file comment as a line thread.
- The single-row-only guard that skipped inline highlights for wrapped split rows.
