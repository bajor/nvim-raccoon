# Vendored inline diff sources

This directory is self-contained. It never checks for updates, downloads code,
or invokes JavaScript at installation time or runtime.

## jsdiff

- Upstream project: jsdiff (`diff` package)
- Upstream repository: <https://github.com/kpdecker/jsdiff>
- Exact release: `v9.0.0`
- Exact commit: `ed13aca03aa25735fafc0645d1185e7a1c68fd8c`
- Package version: `diff@9.0.0`
- Original source paths:
  - `src/diff/base.ts`
  - `src/diff/word.ts`
  - `src/diff/character.ts`
- Copied functions or behavior:
  - The synchronous Myers traversal, path construction, common-token
    extraction, and change-object construction from `Diff`.
  - `WordsWithSpaceDiff.tokenize` and its exact extended-Latin word ranges.
  - Character tokenization by Unicode code point.
- Original license: BSD 3-Clause
- License text: `licenses/jsdiff.txt`
- Local destination: `lua/raccoon/vendor/jsdiff.lua`
- Date vendored: 2026-07-16
- Mechanical changes made during the Lua adaptation:
  - TypeScript classes and zero-based arrays became Lua functions and tables;
    the algorithm's positions remain conceptually zero-based.
  - Regular-expression tokenization became explicit UTF-8 code-point scanning
    with the same word and ECMAScript whitespace categories.
  - Only synchronous, case-sensitive string diffing used by
    `@pierre/diffs` was retained. Async callbacks, comparators,
    case-insensitive mode, array/object diff variants, and unrelated options
    were omitted.
  - Caller-supplied token-product and upstream `maxEditLength` caps can stop
    pathological work; these are Raccoon safety fallbacks and do not alter
    completed results.
  - Malformed UTF-8 is scanned as one-byte code units so the adapter never
    creates a range inside a valid UTF-8 code-point sequence.
- Reason for vendoring: Neovim's built-in `vim.diff` does not reproduce
  jsdiff's tokenization and tie-breaking, while a JavaScript runtime or npm
  dependency is prohibited. This is the smallest relevant source subset used
  by the pinned Pierre release.

Behavioral fixtures in `tests/vendor_jsdiff_spec.lua` were mechanically ported
from `test/diff/word.js` and `test/diff/character.js` at the same tag. They are
covered by the same BSD 3-Clause license.

## @pierre/diffs

- Upstream project: `@pierre/diffs`
- Upstream repository: <https://github.com/pierrecomputer/pierre>
- Exact release: `diffs-v1.2.12`
- Exact commit: `9466c467ae6fc03501b6bca74c12f717d70293a7`
- Package version: `1.2.12`
- Original source paths:
  - `packages/diffs/src/utils/parseDiffDecorations.ts`
  - `packages/diffs/src/utils/renderDiffWithHighlighter.ts`
- Copied function or behavior:
  - `pushOrJoinSpan`, including the default `word-alt` rule that joins a
    single neutral whitespace character between changed spans.
  - The use of `diffWordsWithSpace` for word spans and `diffChars` for
    character spans.
- Original license: Apache License 2.0
- License text: `licenses/pierre-diffs.txt`
- Local destination: `lua/raccoon/intraline.lua`
- Date vendored: 2026-07-16
- Mechanical changes made during the Lua adaptation:
  - TypeScript tuples became named Lua tables.
  - DOM/Shiki decoration offsets became zero-based, end-exclusive Neovim byte
    ranges after spans are assembled.
  - Adjacent or overlapping final ranges are merged before extmark creation.
  - Raccoon's existing safety limits and smarter `vim.diff` line alignment
    remain outside the vendored inline matcher.
  - The pinned word behavior is the baseline. Raccoon additionally applies
    the pinned character matcher inside structured identifiers when unchanged
    content makes refinement useful; this preserves code-focused changes such
    as `old_timeout` to `new_timeout` and `v1` to `v2`.
- Reason for vendoring: the span policy is required for parity, but Pierre's
  DOM, React, HAST, worker, Shiki, cache, and browser-rendering architecture is
  irrelevant to Neovim and is intentionally not copied.
