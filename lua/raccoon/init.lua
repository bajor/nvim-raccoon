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
  -- Dark green background for added lines
  vim.api.nvim_set_hl(0, "RaccoonAdd", {
    bg = "#1a2f1a", -- Dark green background
    fg = nil,
    default = true,
  })

  -- Dark red background for deleted lines
  vim.api.nvim_set_hl(0, "RaccoonDelete", {
    bg = "#3d1a1a", -- Dark red background
    fg = "#cc6666", -- Light red text
    default = true,
  })

  -- Sign column colors
  vim.api.nvim_set_hl(0, "RaccoonAddSign", {
    fg = "#98c379", -- Green
    default = true,
  })

  vim.api.nvim_set_hl(0, "RaccoonDeleteSign", {
    fg = "#e06c75", -- Red
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

  -- Global PR list picker keymap (always available)
  vim.keymap.set("n", "<leader>pr", function()
    require("raccoon.ui").show_pr_list()
  end, { noremap = true, silent = true, desc = "Raccoon: PR list" })
end

--- Get sync status for lualine/statusline integration
--- Add to lualine: { require('raccoon').statusline, cond = require('raccoon').is_active }
---@return string
function M.statusline()
  local open = require("raccoon.open")
  return open.statusline()
end

--- Check if PR review is active (for lualine cond)
---@return boolean
function M.is_active()
  local open = require("raccoon.open")
  return open.is_active()
end

return M
