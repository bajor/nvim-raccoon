---@class RaccoonDisplay
---UI compatibility helpers (Windows-safe glyphs, diff marker mode, float winhl).
local M = {}

local config = require("raccoon.config")

---@return boolean
function M.is_windows()
  return vim.fn.has("win32") == 1 or vim.fn.has("win64") == 1
end

---@return table
local function load_ui()
  return config.load_ui()
end

---@return boolean
function M.use_safe_highlights()
  return load_ui().safe_highlights == true
end

---@return boolean
function M.use_ascii_glyphs()
  local mode = load_ui().glyphs
  if mode == "ascii" then
    return true
  end
  if mode == "unicode" then
    return false
  end
  return M.is_windows()
end

---@return "sign"|"prefix"|"both"
function M.diff_marker_mode()
  local mode = load_ui().diff_markers
  if mode == "sign" or mode == "prefix" or mode == "both" then
    return mode
  end
  if M.is_windows() then
    return "both"
  end
  return "sign"
end

---@return boolean
function M.use_sign_markers()
  local mode = M.diff_marker_mode()
  return mode == "sign" or mode == "both"
end

---@return boolean
function M.use_prefix_markers()
  local mode = M.diff_marker_mode()
  return mode == "prefix" or mode == "both"
end

---@return table
function M.glyphs()
  if M.use_ascii_glyphs() then
    return {
      hline = "-",
      vline = "|",
      tree_mid = "+ ",
      tree_last = "\\ ",
      tree_branch = "|  ",
      tree_space = "   ",
      bullet = "*",
      pipe_sep = " | ",
      arrow = "->",
      section_prefix = "-- ",
      section_suffix = " --",
      comment = "C",
      pending = "o",
      resolved = "v",
      warning = "!",
      conflict = "X",
      ok = "v",
    }
  end

  return {
    hline = "─",
    vline = "│",
    tree_mid = "├ ",
    tree_last = "└ ",
    tree_branch = "│  ",
    tree_space = "   ",
    bullet = "•",
    pipe_sep = " │ ",
    arrow = "→",
    section_prefix = "── ",
    section_suffix = " ──",
    comment = "💬",
    pending = "○",
    resolved = "✓",
    warning = "⚠",
    conflict = "⛔",
    ok = "✓",
  }
end

---@param title string
---@return string
function M.section_header(title)
  local g = M.glyphs()
  return g.section_prefix .. title .. g.section_suffix
end

---@param width number
---@return string
function M.separator(width)
  local g = M.glyphs()
  local n = math.max(1, width or 1)
  return string.rep(g.hline, n)
end

---Normalize float background to current terminal theme.
---Useful in terminals where NormalFloat defaults to pure black.
---@param win number
function M.apply_float_winhl(win)
  local ui = load_ui()
  if ui.normalize_float_background ~= true then
    return
  end
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.wo[win].winhl = "Normal:Normal,NormalFloat:Normal,FloatBorder:FloatBorder"
end

return M
