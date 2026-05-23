# Architecture Diff

## Summary
Improve cross-platform diff rendering reliability by making highlight resolution theme-aware, enforcing visible diff sign columns in flat diff, and normalizing CRLF patch parsing.

## Diagram(s)
```mermaid
flowchart TD
    A[ColorScheme Groups\nDiffAdd / DiffDelete] --> B[raccoon.init setup_highlights]
    B --> C[RaccoonAdd / RaccoonDelete\nRaccoonAddSign / RaccoonDeleteSign]
    D[GitHub/File Patch Text] --> E[raccoon.diff parse_patch]
    E --> F[Normalized Lines\nstrip trailing CR]
    F --> G[Changed line map]
    G --> H[raccoon.diff apply_highlights]
    H --> I[Extmarks + Signs + Virtual delete lines]
    J[raccoon.diff open_file] --> K[Window signcolumn yes:1]
    K --> I
```

## Changes

### Added
- No new modules.

### Modified
- `lua/raccoon/init.lua`: derive raccoon diff/sign highlight values from `DiffAdd`/`DiffDelete` with fallback RGB + cterm values.
- `lua/raccoon/diff.lua`: normalize CRLF patch lines in parser and enforce `signcolumn=yes:1` when opening review files.
- `tests/init_spec.lua`: add coverage for inherited highlight colors and fallback colors.
- `tests/diff_spec.lua`: add CRLF parsing regression test.
- `CHANGELOG.md`: add unreleased fixes for Windows diff rendering compatibility.

### Removed
- Nothing removed.
