describe("raccoon", function()
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

  it("defines terminal fallback colors for diff and file tree highlights", function()
    local raccoon = require("raccoon")
    raccoon.setup()

    local add = vim.api.nvim_get_hl(0, { name = "RaccoonAdd", link = false })
    local delete = vim.api.nvim_get_hl(0, { name = "RaccoonDelete", link = false })
    local add_sign = vim.api.nvim_get_hl(0, { name = "RaccoonAddSign", link = false })
    local delete_sign = vim.api.nvim_get_hl(0, { name = "RaccoonDeleteSign", link = false })
    local in_commit = vim.api.nvim_get_hl(0, { name = "RaccoonFileInCommit", link = false })
    local visible = vim.api.nvim_get_hl(0, { name = "RaccoonFileVisible", link = false })

    assert.is_not_nil(add.ctermbg)
    assert.is_not_nil(delete.ctermbg)
    assert.is_not_nil(add_sign.ctermfg)
    assert.is_not_nil(delete_sign.ctermfg)
    assert.is_not_nil(in_commit.ctermfg)
    assert.is_not_nil(visible.ctermfg)
  end)

  it("reuses DiffAdd and DiffDelete colors when the colorscheme defines them", function()
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
    assert.equals(diff_add.fg, add_sign.fg)
    assert.equals(diff_add.ctermfg, add_sign.ctermfg)
    assert.equals(diff_delete.fg, delete_sign.fg)
    assert.equals(diff_delete.ctermfg, delete_sign.ctermfg)
  end)
end)
