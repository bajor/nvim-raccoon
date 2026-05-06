# Architecture Diff

## Summary
Release workflow now classifies `X.Y.0` versions as full releases (create GitHub Release) while keeping `X.Y.Z` with `Z > 0` as patch-only tags.

## Diagram(s)
```mermaid
flowchart TD
    A[Read top CHANGELOG version] --> B{Version format}
    B -->|X.Y or X.Y.0| C[is_release=true]
    B -->|X.Y.Z where Z>0| D[is_release=false]
    B -->|Other| E[warn + is_release=false]
    C --> F[Create tag]
    C --> G[Extract release notes]
    C --> H[Create GitHub Release]
    D --> F
    E --> F
```

## Changes
### Modified
- `.github/workflows/release.yml`: broadened release-detection regex and added explicit fallback warning for unknown version formats.

### Added
- `ARCHITECTURE_DIFF.md`: documents release classification behavior for this change set.
