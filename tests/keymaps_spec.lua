local keymaps = require("raccoon.keymaps")

describe("raccoon.keymaps", function()
  after_each(function()
    -- Clean up keymaps after each test
    keymaps.clear()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(keymaps)
    end)

    it("has keymaps table", function()
      assert.is_table(keymaps.keymaps)
    end)

    it("has setup function", function()
      assert.is_function(keymaps.setup)
    end)

    it("has clear function", function()
      assert.is_function(keymaps.clear)
    end)

    it("has setup_buffer function", function()
      assert.is_function(keymaps.setup_buffer)
    end)

    it("has next_point function", function()
      assert.is_function(keymaps.next_point)
    end)

    it("has prev_point function", function()
      assert.is_function(keymaps.prev_point)
    end)

    it("has comment_at_cursor function", function()
      assert.is_function(keymaps.comment_at_cursor)
    end)

    it("has show_description function", function()
      assert.is_function(keymaps.show_description)
    end)
  end)

  describe("keymaps table", function()
    it("has nn keymap for next point", function()
      local found = false
      for _, km in ipairs(keymaps.keymaps) do
        if km.lhs == "nn" then found = true end
      end
      assert.is_true(found)
    end)

    it("has pp keymap for prev point", function()
      local found = false
      for _, km in ipairs(keymaps.keymaps) do
        if km.lhs == "pp" then found = true end
      end
      assert.is_true(found)
    end)

    it("has cc keymap for comment", function()
      local found = false
      for _, km in ipairs(keymaps.keymaps) do
        if km.lhs == "cc" then found = true end
      end
      assert.is_true(found)
    end)

    it("has leader-dd keymap for description", function()
      local found = false
      for _, km in ipairs(keymaps.keymaps) do
        if km.lhs == "<leader>dd" then found = true end
      end
      assert.is_true(found)
    end)

    it("all keymaps have mode, lhs, rhs, and desc", function()
      for _, km in ipairs(keymaps.keymaps) do
        assert.is_string(km.mode)
        assert.is_string(km.lhs)
        assert.is_not_nil(km.rhs)
        assert.is_string(km.desc)
      end
    end)

    it("has at least 4 keymaps", function()
      -- Keymaps count may grow as features are added
      assert.is_true(#keymaps.keymaps >= 4)
    end)
  end)

  describe("setup", function()
    it("sets up keymaps without error", function()
      -- Should not error
      keymaps.setup()
    end)
  end)

  describe("clear", function()
    it("clears keymaps without error", function()
      keymaps.setup()
      -- Should not error
      keymaps.clear()
    end)

    it("handles clearing when not setup", function()
      -- Should not error even if keymaps weren't setup
      keymaps.clear()
    end)
  end)

  describe("setup_buffer", function()
    it("handles nil buffer", function()
      -- Should not error
      keymaps.setup_buffer(nil)
    end)

    it("handles invalid buffer", function()
      -- Should not error
      keymaps.setup_buffer(-1)
    end)

    it("sets up keymaps for valid buffer", function()
      local buf = vim.api.nvim_create_buf(false, true)
      -- Should not error
      keymaps.setup_buffer(buf)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
