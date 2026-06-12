# Architecture Diff

## Summary

Flat diff rendering now plans exact inline add/delete spans from the GitHub patch and applies only character/content highlights in exact mode.

## Diagram(s)

```mermaid
flowchart TD
    A[GitHub unified patch] --> B[raccoon.diff.parse_patch]
    B --> C[raccoon.diff.build_render_plan]
    C --> D{inline_diff enabled and bounded?}
    D -->|yes| E[raccoon.inline_diff.plan_replacement]
    E --> F[token LCS and UTF-8 char refinement]
    D -->|no| G[line-only fallback plan]
    F --> H[raccoon.diff.apply_highlights]
    G --> H
    H --> I[sign-only row markers]
    H --> J[inline add extmark ranges or added-content spans]
    H --> K[deleted virt_lines chunks without padded exact-mode tails]
    H --> L[line-only fallback extmarks]
```

## Changes

### Added

- `lua/raccoon/inline_diff.lua`: bounded token and UTF-8 codepoint diffing for replaced line pairs.
- `raccoon.diff.build_render_plan`: converts parsed patch hunks into added-line ranges and deleted virtual-line chunks.
- `inline_diff` config block: enables exact rendering and defines fallback limits.

### Modified

- `raccoon.diff.apply_highlights`: consumes the render plan, using sign-only markers plus character/content extmarks in exact mode while preserving full-line add and padded deleted-line fallback rendering.
- Highlight setup: adds `RaccoonAddInline` and `RaccoonDeleteInline`.
