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

  it("defines inline diff highlight groups", function()
    local raccoon = require("raccoon")
    raccoon.setup({})

    local add_inline = vim.api.nvim_get_hl(0, { name = "RaccoonAddInline" })
    local delete_inline = vim.api.nvim_get_hl(0, { name = "RaccoonDeleteInline" })

    assert.is_not_nil(add_inline.bg)
    assert.is_not_nil(delete_inline.bg)
    assert.is_not_nil(delete_inline.fg)
  end)
end)
