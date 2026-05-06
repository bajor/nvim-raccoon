# Architecture Diff
## Summary
Introduce a display-compatibility layer that normalizes glyphs, diff marker rendering, highlights, and float window backgrounds for better Windows terminal behavior.

## Diagram(s)
```mermaid
flowchart TD
    A[config.load_ui()] --> B[display.lua]
    B --> C[diff.lua]
    B --> D[commit_ui.lua]
    B --> E[ui.lua]
    B --> F[comments.lua]
    B --> G[open.lua]
    B --> H[state.lua]
    B --> I[review.lua/keymaps.lua]
```

## Changes
### Added
- `lua/raccoon/display.lua`: central compatibility policy for glyph selection, diff marker strategy, safe highlights, and float winhl normalization.

### Modified
- `lua/raccoon/config.lua`: new `ui` config defaults and `load_ui()` sanitizer/loader.
- `lua/raccoon/diff.lua`: sign-column enforcement for PR file view and configurable sign/prefix diff markers.
- `lua/raccoon/commit_ui.lua`: optional inline `+/-` prefixes, sign-marker strategy support, ASCII tree fallback, and normalized maximize float window.
- `lua/raccoon/ui.lua`: glyph-aware separators/headers and normalized float windows.
- `lua/raccoon/comments.lua`: glyph-aware signs/dividers/headers, safe highlight linking, normalized float windows.
- `lua/raccoon/open.lua` and `lua/raccoon/state.lua`: glyph-aware statusline symbols and theme-safe highlight groups.
- `lua/raccoon/review.lua` and `lua/raccoon/keymaps.lua`: normalized float windows.
- `lua/raccoon/commits.lua` and `lua/raccoon/localcommits.lua`: section headers now glyph-mode aware.
- `README.md` and `config_docs.md`: documented new `ui.*` configuration.
- `tests/config_spec.lua` and `tests/commits_spec.lua`: coverage updates for new UI config and highlight behavior.

### Removed
- None.
