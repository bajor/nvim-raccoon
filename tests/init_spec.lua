describe("raccoon", function()
  local raccoon_highlight_groups = {
    "RaccoonAdd",
    "RaccoonDelete",
    "RaccoonAddSign",
    "RaccoonDeleteSign",
  }

  local function clear_raccoon_highlights()
    for _, group in ipairs(raccoon_highlight_groups) do
      vim.cmd("highlight clear " .. group)
    end
  end

  before_each(function()
    clear_raccoon_highlights()
  end)

  it("setup accepts empty options", function()
    local raccoon = require("raccoon")
    -- Should not error
    raccoon.setup({})
    assert.is_table(raccoon.config)
  end)

  it("setup merges user options", function()
    local raccoon = require("raccoon")
    raccoon.setup({ custom_option = "test" })
    assert.equals("test", raccoon.config.custom_option)
  end)

  it("reuses DiffAdd and DiffDelete colors when available", function()
    vim.api.nvim_set_hl(0, "DiffAdd", {
      fg = "#d0ffd0",
      bg = "#134013",
      ctermfg = 193,
      ctermbg = 22,
    })
    vim.api.nvim_set_hl(0, "DiffDelete", {
      fg = "#ffd0d0",
      bg = "#401313",
      ctermfg = 224,
      ctermbg = 52,
    })

    local raccoon = require("raccoon")
    raccoon.setup()

    local diff_add = vim.api.nvim_get_hl(0, { name = "DiffAdd", link = false })
    local diff_delete = vim.api.nvim_get_hl(0, { name = "DiffDelete", link = false })
    local add = vim.api.nvim_get_hl(0, { name = "RaccoonAdd", link = false })
    local delete = vim.api.nvim_get_hl(0, { name = "RaccoonDelete", link = false })
    local add_sign = vim.api.nvim_get_hl(0, { name = "RaccoonAddSign", link = false })
    local delete_sign = vim.api.nvim_get_hl(0, { name = "RaccoonDeleteSign", link = false })

    assert.equals(diff_add.bg, add.bg)
    assert.equals(diff_add.ctermbg, add.ctermbg)
    assert.equals(diff_delete.bg, delete.bg)
    assert.equals(diff_delete.ctermbg, delete.ctermbg)
    assert.equals(diff_delete.fg, delete.fg)
    assert.equals(diff_delete.ctermfg, delete.ctermfg)
    assert.is_not_nil(add_sign.fg)
    assert.is_not_nil(add_sign.ctermfg)
    assert.is_not_nil(delete_sign.fg)
    assert.is_not_nil(delete_sign.ctermfg)
  end)

  it("uses fallback colors when DiffAdd and DiffDelete have no colors", function()
    vim.api.nvim_set_hl(0, "DiffAdd", {})
    vim.api.nvim_set_hl(0, "DiffDelete", {})

    local raccoon = require("raccoon")
    raccoon.setup()

    local add = vim.api.nvim_get_hl(0, { name = "RaccoonAdd", link = false })
    local delete = vim.api.nvim_get_hl(0, { name = "RaccoonDelete", link = false })
    local add_sign = vim.api.nvim_get_hl(0, { name = "RaccoonAddSign", link = false })
    local delete_sign = vim.api.nvim_get_hl(0, { name = "RaccoonDeleteSign", link = false })

    assert.is_not_nil(add.bg)
    assert.equals(22, add.ctermbg)
    assert.is_not_nil(delete.bg)
    assert.equals(52, delete.ctermbg)
    assert.is_not_nil(delete.fg)
    assert.equals(174, delete.ctermfg)
    assert.is_not_nil(add_sign.fg)
    assert.equals(114, add_sign.ctermfg)
    assert.is_not_nil(delete_sign.fg)
    assert.equals(173, delete_sign.ctermfg)
  end)

  it("keeps fallback sign colors when DiffAdd and DiffDelete define line backgrounds", function()
    vim.api.nvim_set_hl(0, "DiffAdd", {
      fg = "#000000",
      bg = "#00ff00",
      ctermfg = 0,
      ctermbg = 10,
    })
    vim.api.nvim_set_hl(0, "DiffDelete", {
      fg = "#000000",
      bg = "#ff0000",
      ctermfg = 0,
      ctermbg = 9,
    })

    local raccoon = require("raccoon")
    raccoon.setup()

    local add_sign = vim.api.nvim_get_hl(0, { name = "RaccoonAddSign", link = false })
    local delete_sign = vim.api.nvim_get_hl(0, { name = "RaccoonDeleteSign", link = false })

    assert.equals(114, add_sign.ctermfg)
    assert.equals(173, delete_sign.ctermfg)
  end)

  it("refreshes existing Raccoon highlight groups from active diff colors", function()
    vim.api.nvim_set_hl(0, "DiffAdd", {
      bg = "#134013",
      ctermbg = 22,
    })
    vim.api.nvim_set_hl(0, "DiffDelete", {
      fg = "#ffd0d0",
      bg = "#401313",
      ctermfg = 224,
      ctermbg = 52,
    })
    vim.api.nvim_set_hl(0, "RaccoonAdd", {
      fg = "#ffffff",
    })
    vim.api.nvim_set_hl(0, "RaccoonDelete", {
      fg = "#ffffff",
    })

    local raccoon = require("raccoon")
    raccoon.setup()

    local diff_add = vim.api.nvim_get_hl(0, { name = "DiffAdd", link = false })
    local diff_delete = vim.api.nvim_get_hl(0, { name = "DiffDelete", link = false })
    local add = vim.api.nvim_get_hl(0, { name = "RaccoonAdd", link = false })
    local delete = vim.api.nvim_get_hl(0, { name = "RaccoonDelete", link = false })

    assert.equals(diff_add.bg, add.bg)
    assert.equals(diff_add.ctermbg, add.ctermbg)
    assert.equals(diff_delete.fg, delete.fg)
    assert.equals(diff_delete.bg, delete.bg)
    assert.equals(diff_delete.ctermfg, delete.ctermfg)
    assert.equals(diff_delete.ctermbg, delete.ctermbg)
  end)
end)
