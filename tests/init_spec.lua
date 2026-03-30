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
end)
