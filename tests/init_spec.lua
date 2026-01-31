describe("raccoon", function()
  it("can be required", function()
    local raccoon = require("raccoon")
    assert.is_not_nil(raccoon)
  end)

  it("has setup function", function()
    local raccoon = require("raccoon")
    assert.is_function(raccoon.setup)
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
end)
