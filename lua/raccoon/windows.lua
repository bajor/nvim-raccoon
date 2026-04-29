---@class RaccoonWindows
---Window tracking helpers for raccoon-owned floating windows.
local M = {}

local RACCOON_WIN_VAR = "raccoon_window"

---Mark a window as owned by raccoon.
---@param win number|nil
function M.mark(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  pcall(vim.api.nvim_win_set_var, win, RACCOON_WIN_VAR, true)
end

---Check whether a window is marked as raccoon-owned.
---@param win number
---@return boolean
function M.is_marked(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return false end
  local ok, val = pcall(vim.api.nvim_win_get_var, win, RACCOON_WIN_VAR)
  return ok and val == true
end

---Return whether any raccoon-owned floating windows are open.
---@return boolean
function M.has_open()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if M.is_marked(win) then
      return true
    end
  end
  return false
end

---Close all raccoon-owned floating windows.
---@return number closed_count
function M.close_all()
  local closed = 0
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if M.is_marked(win) then
      local ok = pcall(vim.api.nvim_win_close, win, true)
      if ok then
        closed = closed + 1
      end
    end
  end
  return closed
end

return M
