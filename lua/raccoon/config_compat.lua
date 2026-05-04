---@class RaccoonConfigCompat
---Backward-compat layer for renamed config keys.
---Migrates deprecated keys in a parsed JSON config to their new names so that
---the rest of the loader code only ever sees the current schema. Conflict
---rule: when both the old and new key are present, the new key wins and the
---old key is dropped.
---
---This module is intentionally isolated so a future major release can drop
---it by deleting this file and the single `compat.normalize(...)` call in
---`config.lua`.
local M = {}

--- Extract a string list from a legacy `passthrough_keymaps` value.
--- Each entry may be a string or a `{key = "<lhs>"}` table; anything else is
--- silently dropped. Used only by the passthrough_keymaps migration.
---@param val any
---@return string[]
local function extract_legacy_keys(val)
  if type(val) ~= "table" then return {} end
  local result = {}
  for _, item in ipairs(val) do
    if type(item) == "string" then
      table.insert(result, item)
    elseif type(item) == "table" and type(item.key) == "string" then
      table.insert(result, item.key)
    end
  end
  return result
end

--- Apply backward-compat migrations to a parsed JSON config.
--- Mutates the table in place and returns it. Pass a deepcopy if you need to
--- preserve the original.
---
--- Migrations (each obeys the new-wins conflict rule):
---   * shortcuts.commit_viewer (string|false) -> shortcuts.commit_viewer_toggle
---   * shortcuts.commit_mode   (table)     -> shortcuts.commit_viewer
---   * passthrough_keymaps     (top-level) -> commit_viewer.passthrough_keys
---   * pull_changes_interval               -> sync_interval
---
---@param parsed any Parsed JSON config (typically a table)
---@return any normalized
function M.normalize(parsed)
  if type(parsed) ~= "table" then return parsed end

  local sc = parsed.shortcuts
  if type(sc) == "table" then
    -- Migrate shortcuts.commit_viewer (legacy leaf) -> shortcuts.commit_viewer_toggle.
    -- The current schema uses a table here, so string and false both belong to
    -- the legacy leaf form. Other scalar types stay invalid and fall back later.
    if type(sc.commit_viewer) == "string" or sc.commit_viewer == false then
      if sc.commit_viewer_toggle == nil then
        sc.commit_viewer_toggle = sc.commit_viewer
      end
      sc.commit_viewer = nil
    end

    -- Migrate shortcuts.commit_mode (nested block) -> shortcuts.commit_viewer.
    if type(sc.commit_mode) == "table" then
      if sc.commit_viewer == nil then
        sc.commit_viewer = sc.commit_mode
      end
      sc.commit_mode = nil
    end
  end

  -- Migrate top-level passthrough_keymaps -> commit_viewer.passthrough_keys.
  if parsed.passthrough_keymaps ~= nil then
    if type(parsed.commit_viewer) ~= "table" then
      parsed.commit_viewer = {}
    end
    if parsed.commit_viewer.passthrough_keys == nil then
      parsed.commit_viewer.passthrough_keys = extract_legacy_keys(parsed.passthrough_keymaps)
    end
    parsed.passthrough_keymaps = nil
  end

  -- Migrate pull_changes_interval -> sync_interval.
  if parsed.pull_changes_interval ~= nil then
    if parsed.sync_interval == nil then
      parsed.sync_interval = parsed.pull_changes_interval
    end
    parsed.pull_changes_interval = nil
  end

  return parsed
end

return M
