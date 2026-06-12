# Architecture Diff

## Summary

Flat and commit/local diff rendering now plan exact inline add/delete spans from patch hunks, align similar lines inside multi-line blocks, and apply only character/content highlights in exact mode.

## Diagram(s)

```mermaid
flowchart TD
    A[Unified patch] --> B[raccoon.diff.parse_patch]
    B --> C[flat review file buffer]
    B --> D[commit/local hunk buffer]
    C --> E[raccoon.diff.build_render_plan]
    D --> F[raccoon.commit_ui.apply_diff_highlights]
    E --> G{bounded text diff?}
    F --> G
    G -->|yes| H[raccoon.inline_diff.plan_replacement]
    H --> I[bounded line alignment]
    I --> J[token LCS and UTF-8 char refinement]
    G -->|no| K[line-only fallback plan]
    J --> L[inline add/delete extmark ranges]
    K --> M[line-only fallback extmarks]
    E --> N[flat review signs and virtual deletes]
    F --> O[commit/local hunk signs]
```

## Changes

### Added

- `lua/raccoon/inline_diff.lua`: bounded token and UTF-8 codepoint diffing for replaced line pairs.
- `raccoon.diff.build_render_plan`: converts parsed patch hunks into added-line ranges and deleted virtual-line chunks.
- Inline diff rendering uses internal text-based bounds for precision and fallback behavior.

### Modified

- `raccoon.diff.apply_highlights`: consumes the render plan, using sign-only markers plus character/content extmarks in exact mode while preserving full-line add and padded deleted-line fallback rendering.
- `raccoon.inline_diff.plan_replacement`: aligns similar old/new lines before computing character spans, so insertions inside multi-line blocks do not force index-based whole-row changes.
- `raccoon.commit_ui.apply_diff_highlights`: reuses inline replacement planning for commit/local hunk rows and renders unchanged deleted-row context with `Comment`.
- `raccoon.inline_diff.diff_pair`: renders old-side unchanged context as grey `Comment` chunks, while highlighting only deleted spans in red and added spans in green.
- Highlight setup: keeps whole-line, inline, and sign groups on one green/red intensity per diff side.
