# Architecture Diff

## Summary
Split diff comments and navigation now resolve semantic targets by path, line, and side before moving the cursor or validating a new thread.

## Diagram(s)

```mermaid
flowchart TD
    A[Review target<br/>{path, line, side}] --> B[diff.find_split_row]
    C[Rendered split rows<br/>old_line/new_line + continuation flags] --> B
    B --> D[Rendered row]
    B --> E[Side content column]
    D --> F[Cursor jump]
    E --> F
    A --> G[New-thread validation]
    G --> H{side}
    H -->|RIGHT| I[Check checkout line bounds]
    H -->|LEFT| J[Skip checkout bounds]
```

## Changes

### Added
- `diff.find_split_row(rendered, target)`: shared semantic-to-rendered split row lookup for `LEFT` old-side and `RIGHT` new-side targets.

### Modified
- `comments`: validates new threads with side-aware bounds, stores/restores draft side, and jumps to review threads using `thread.side`.
- `thread_index`: persists each review thread's root-comment side, defaulting to `RIGHT`.
- `keymaps`: carries side on diff/comment points and resolves current split-buffer destinations through rendered metadata.

### Removed
- Duplicate private split-row lookup logic from comment navigation.
