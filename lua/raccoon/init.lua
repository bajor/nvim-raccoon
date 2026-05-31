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
  local function get_highlight(name)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
    if not ok or type(hl) ~= "table" then
      return {}
    end
    return hl
  end

  local function merge_highlight(base, keys, fallback)
    local merged = vim.deepcopy(fallback)
    for _, key in ipairs(keys) do
      if base[key] ~= nil then
        merged[key] = base[key]
      end
    end
    return merged
  end

  local function merge_sign_highlight(base, fallback)
    if base.bg ~= nil or base.ctermbg ~= nil then
      return vim.deepcopy(fallback)
    end
    return merge_highlight(base, { "fg", "ctermfg" }, fallback)
  end

  local diff_add = get_highlight("DiffAdd")
  local diff_delete = get_highlight("DiffDelete")

  -- Green background for added lines (high contrast)
  vim.api.nvim_set_hl(0, "RaccoonAdd", merge_highlight(diff_add, { "bg", "ctermbg" }, {
    bg = "#2d5a2d",
    ctermbg = 22,
    default = true,
  }))

  -- Red background for deleted lines (high contrast)
  vim.api.nvim_set_hl(0, "RaccoonDelete", merge_highlight(diff_delete, {
    "fg",
    "bg",
    "ctermfg",
    "ctermbg",
  }, {
    bg = "#5a2020",
    fg = "#e88888",
    ctermbg = 52,
    ctermfg = 174,
    default = true,
  }))

  -- Sign column colors
  vim.api.nvim_set_hl(0, "RaccoonAddSign", merge_sign_highlight(diff_add, {
    fg = "#98c379", -- Green
    ctermfg = 114,
    default = true,
  }))

  vim.api.nvim_set_hl(0, "RaccoonDeleteSign", merge_sign_highlight(diff_delete, {
    fg = "#e06c75", -- Red
    ctermfg = 173,
    default = true,
  }))

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
