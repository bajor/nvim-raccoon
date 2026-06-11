# Architecture Diff

## Summary
Split diff rendering now uses exact character inline decorations, stable left-column cursor placement, and side-aware comment thread buckets.

## Diagram(s)

```mermaid
flowchart TD
    A[Paired delete/add line] --> B[Split into UTF-8 chars with byte columns]
    B --> C[Trim common prefix and suffix]
    C --> D[LCS over changed middle]
    D --> E[Coalesce changed char runs]
    E --> F[Inline delete spans]
    E --> G[Inline add spans]
    F --> H[apply_split_render priority 200]
    G --> H
    I[Syntax projection priority 110] --> H
    J[Full-line diff priority 90] --> H
```

```mermaid
sequenceDiagram
    participant Nav as Navigation
    participant Diff as diff metadata
    participant UI as Split buffer cursor
    participant Comments as Comment action

    Nav->>Diff: find_split_row(path, side, line)
    Diff-->>Nav: rendered row plus left content column
    Nav->>Diff: set_split_semantic_target(path, side, line, row)
    Nav->>UI: place cursor at left content column
    Comments->>Diff: resolve_cursor_target(row, col)
    Diff-->>Comments: stored semantic side when cursor is still on row
```

```mermaid
flowchart LR
    A[GitHub comments] --> B[thread_index.build]
    B --> C[line_state_by_file aggregate]
    B --> D[side_line_state_by_file]
    B --> E[side_comment_line_state_by_file]
    D --> F[Split badges LEFT old line]
    D --> G[Split badges RIGHT new line]
    E --> H[Same-line picker for selected side]
    I[Line nil placeholder] --> J[File-level new thread editor]
```

## Changes

### Added
- `diff.left_cursor_col(rendered)` for split cursor placement.
- `rendered.position_by_key[path|side|line]` for O(1) split row lookup before scan fallback.
- `diff.set_split_semantic_target()` so right-side navigation can display left while preserving right-side comment semantics.
- Side-aware thread index maps for split badges and same-line thread pickers.

### Modified
- Inline changed-line highlighting now computes exact UTF-8 character add/delete runs with byte columns for Neovim extmarks.
- Split navigation, thread jumps, file jumps, diff-only jumps, and resize restore now use the left content column.
- Split comment badge rendering reads LEFT buckets from `old_line` and RIGHT buckets from `new_line`.
- Same-line thread lookup passes the resolved target side.

### Removed
- One-span prefix/suffix inline diff highlighting for paired changed lines.
- Side-insensitive split badge and same-line picker lookup.
