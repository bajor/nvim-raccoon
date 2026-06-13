# Inline Diff Behavior Notes

## Required User Behavior

- Flat review buffers show signs for added/deleted rows.
- Flat review buffers highlight only changed added spans when a replacement pair is known.
- Deleted virtual lines show unchanged deleted-side context as neutral text and removed spans as delete inline text.
- Commit/local hunk buffers use the same inline span decisions as flat review.
- Pure additions highlight the whole added content in exact mode.
- Pure deletions highlight the whole deleted content in exact mode.
- Legacy line-only rendering remains available internally for fallback tests.
- Public config does not expose inline diff options.

## Known Current-PR Design Problems

- Current pairing and rendering are spread across `inline_diff.lua`, `diff.lua`, and `commit_ui.lua`.
- Current parser does not expose old and new line numbers as first-class fields.
- Current algorithm is LCS-heavy and heuristic-heavy instead of a clear histogram/Myers pipeline.

## Replacement Acceptance Criteria

- One planner produces render rows for both flat review and commit/local buffers.
- Renderers contain extmark code only.
- Algorithm code does not know Neovim highlight group names.
- Large or ambiguous regions degrade conservatively rather than inventing low-confidence inline spans.
