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

  it("defines subdued row and stronger inline highlight groups", function()
    local raccoon = require("raccoon")
    raccoon.setup({})

    local add = vim.api.nvim_get_hl(0, { name = "RaccoonAdd", link = false })
    local add_text = vim.api.nvim_get_hl(0, { name = "RaccoonAddText", link = false })
    local delete = vim.api.nvim_get_hl(0, { name = "RaccoonDelete", link = false })
    local delete_text = vim.api.nvim_get_hl(0, { name = "RaccoonDeleteText", link = false })

    assert.is_number(add.bg)
    assert.is_number(add_text.bg)
    assert.is_number(delete.bg)
    assert.is_number(delete_text.bg)
    assert.is_true(add.bg ~= add_text.bg)
    assert.is_true(delete.bg ~= delete_text.bg)
    assert.is_nil(add.fg)
    assert.is_nil(add_text.fg)
    assert.is_nil(delete.fg)
    assert.is_nil(delete_text.fg)
  end)

  it("preserves user highlight overrides across setup and colorscheme events", function()
    local raccoon = require("raccoon")
    local custom_background = 0x123456
    vim.api.nvim_set_hl(0, "RaccoonAddText", { bg = custom_background })

    raccoon.setup({})
    vim.api.nvim_exec_autocmds("ColorScheme", {})

    local highlight = vim.api.nvim_get_hl(0, { name = "RaccoonAddText", link = false })
    assert.equals(custom_background, highlight.bg)
  end)
end)
