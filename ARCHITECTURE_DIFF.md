# Architecture Diff

## Summary
Combined diff/comment navigation now uses side-aware diff change points, and split inline range highlights are layered above syntax and full-line diff highlights.

## Diagram(s)

```mermaid
flowchart TD
    subgraph Navigation
        A[Unified patch] --> B[diff.parse_patch]
        B --> C[diff.get_change_points]
        C --> D{Change block}
        D -->|Add or replacement| E[RIGHT new line]
        D -->|Delete only| F[LEFT old line]
        E --> G[keymaps get_file_points]
        F --> G
        H[Thread index comments] --> G
        G --> I[Sorted combined points]
        I --> J[diff.find_split_row]
        J --> K[Rendered row and side column]
    end

    subgraph HighlightLayering
        L[Split rows] --> M[Full-line diff extmarks priority 90]
        L --> N[Syntax projection priority 110]
        L --> O[Inline add/delete ranges priority 200]
        M --> P[apply_split_render]
        N --> P
        O --> P
    end
```

## Changes

### Added
- `diff.get_change_points(patch)`: returns one `{ line, side, type = "diff" }` point per contiguous add/delete block.
- Split range highlight priorities for syntax and inline diff entries.

### Modified
- `keymaps`: uses `diff.get_change_points()` for diff navigation while preserving side-aware comment navigation.
- `diff.apply_split_render()`: applies range highlights with extmarks so priority is explicit.

### Removed
- Mixed old/new changed-line grouping from combined point navigation.
