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

  it("defines subdued rows and stronger exact-span highlight groups", function()
    local raccoon = require("raccoon")
    raccoon.setup({})

    local add = vim.api.nvim_get_hl(0, { name = "RaccoonAdd", link = false })
    local add_inline = vim.api.nvim_get_hl(0, { name = "RaccoonAddInline", link = false })
    local delete = vim.api.nvim_get_hl(0, { name = "RaccoonDelete", link = false })
    local delete_inline = vim.api.nvim_get_hl(0, { name = "RaccoonDeleteInline", link = false })

    assert.is_not_nil(add.bg)
    assert.is_not_nil(delete.bg)
    assert.is_not_equal(add.bg, add_inline.bg)
    assert.is_not_equal(delete.bg, delete_inline.bg)
  end)
end)
