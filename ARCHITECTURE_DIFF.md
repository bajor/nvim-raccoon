# Architecture Diff

## Summary

Raccoon popup windows now opt into the editor's base highlight groups instead of inheriting theme-specific `NormalFloat` colors, and the plugin's custom diff/file-tree highlights now define terminal fallback colors for environments that do not render RGB-only highlight attrs reliably.

## Diagrams

```mermaid
flowchart TD
    A[raccoon.setup] --> B[setup_highlights]
    B --> C[RaccoonAdd/Delete/File* groups]
    C --> D[Diff buffers]
    C --> E[Commit file tree]
    F[ui.apply_popup_window_style] --> G[ui.create_floating_window]
    F --> H[comments popups]
    F --> I[commit maximize and picker floats]
```

```mermaid
sequenceDiagram
    participant U as User
    participant P as Popup creator
    participant UI as ui.apply_popup_window_style
    participant NV as Neovim window

    U->>P: Open PR list / thread / maximize view
    P->>NV: nvim_open_win(...)
    P->>UI: apply_popup_window_style(win)
    UI->>NV: winhl = Normal / FloatBorder / SignColumn -> Normal
    NV-->>U: Popup matches editor background
```

## Changes

### Added

- `lua/raccoon/ui.lua`: shared popup styling helper for plugin-owned floating windows.
- Terminal fallback attrs in setup tests to guard against regressions in Windows and non-`termguicolors` terminals.

### Modified

- `lua/raccoon/init.lua`: custom diff, sign, and commit file-tree highlights now include `ctermfg`/`ctermbg` fallbacks.
- `lua/raccoon/comments.lua`: readonly thread and editor popups now reuse the shared popup window style.
- `lua/raccoon/commit_ui.lua`: maximize diff, maximize picker, and file-content popup windows now reuse the shared popup window style.
- `tests/init_spec.lua`, `tests/ui_spec.lua`, `tests/comments_spec.lua`, `tests/commit_ui_spec.lua`: cover terminal highlight fallbacks and popup `winhl` behavior.

### Removed

- Reliance on theme-provided `NormalFloat` backgrounds for Raccoon popup windows.
- RGB-only custom highlights as the sole color path for diff and file-tree rendering.
