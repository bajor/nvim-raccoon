---@class Raccoon
---@field config table Configuration options
---@field state table Current review session state
local M = {}

--- Default configuration
M.config = {
  -- Config will be loaded from ~/.config/raccoon/config.json
}

--- Setup highlight groups for diff display
--- Uses dark green/red backgrounds for added/deleted lines
local function setup_highlights()
  local add_bg = "#2d5a2d"
  local add_fg = "#98c379"
  local delete_bg = "#5a2020"
  local delete_fg = "#e88888"

  -- Green background for added lines (high contrast)
  vim.api.nvim_set_hl(0, "RaccoonAdd", {
    bg = add_bg,
    fg = add_fg,
    default = true,
  })

  -- Red background for deleted lines (high contrast)
  vim.api.nvim_set_hl(0, "RaccoonDelete", {
    bg = delete_bg,
    fg = delete_fg,
    default = true,
  })

  -- Exact inline spans use the same colors as whole-line fallback rendering.
  vim.api.nvim_set_hl(0, "RaccoonAddInline", {
    bg = add_bg,
    fg = add_fg,
    default = true,
  })

  vim.api.nvim_set_hl(0, "RaccoonDeleteInline", {
    bg = delete_bg,
    fg = delete_fg,
    default = true,
  })

  -- Sign column colors
  vim.api.nvim_set_hl(0, "RaccoonAddSign", {
    fg = add_fg,
    default = true,
  })

  vim.api.nvim_set_hl(0, "RaccoonDeleteSign", {
    fg = delete_fg,
    default = true,
  })

  -- File tree highlights (commit viewer)
  vim.api.nvim_set_hl(0, "RaccoonFileNormal", {
    link = "Comment",
    default = true,
  })

  vim.api.nvim_set_hl(0, "RaccoonFileInCommit", {
    fg = "#aaaaaa",
    default = true,
  })

  vim.api.nvim_set_hl(0, "RaccoonFileVisible", {
    fg = "#ffffff",
    default = true,
  })
end

--- Setup the PR Review plugin
---@param opts? table Optional configuration overrides
function M.setup(opts)
  opts = opts or {}

  -- Merge user options with defaults
  M.config = vim.tbl_deep_extend("force", M.config, opts)

  -- Setup highlight groups
  setup_highlights()

  -- Re-apply highlights when colorscheme changes
  vim.api.nvim_create_autocmd("ColorScheme", {
    group = vim.api.nvim_create_augroup("RaccoonHighlights", { clear = true }),
    callback = setup_highlights,
  })

  -- Load shortcuts from config (falls back to defaults gracefully)
  local cfg = require("raccoon.config")
  local shortcuts = cfg.load_shortcuts()
  local NORMAL_MODE = cfg.NORMAL

  -- Global keymaps (always available, unless disabled by user)
  if cfg.is_enabled(shortcuts.pr_list) then
    vim.keymap.set(NORMAL_MODE, shortcuts.pr_list, function()
      require("raccoon.ui").show_pr_list()
    end, { noremap = true, silent = true, desc = "Raccoon: PR list" })
  end

  if cfg.is_enabled(shortcuts.show_shortcuts) then
    vim.keymap.set(NORMAL_MODE, shortcuts.show_shortcuts, function()
      require("raccoon.ui").show_shortcuts()
    end, { noremap = true, silent = true, desc = "Raccoon: Show shortcuts" })
  end
end

--- Get sync status for lualine/statusline integration
--- Add to lualine: { require('raccoon').statusline, cond = require('raccoon').is_active }
---@return string
function M.statusline()
  return require("raccoon.open").statusline()
end

--- Check if a PR review session is active (for lualine cond)
---@return boolean
function M.is_active()
  return require("raccoon.open").is_active()
end

return M
