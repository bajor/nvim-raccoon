local ui = require("raccoon.ui")

describe("raccoon.ui", function()
  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(ui)
    end)

    it("has create_floating_window function", function()
      assert.is_function(ui.create_floating_window)
    end)

    it("has show_description function", function()
      assert.is_function(ui.show_description)
    end)

    it("has close_pr_list function", function()
      assert.is_function(ui.close_pr_list)
    end)

    it("has state table", function()
      assert.is_table(ui.state)
    end)
  end)

  describe("create_floating_window", function()
    after_each(function()
      -- Clean up any open windows
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= "" then
          vim.api.nvim_win_close(win, true)
        end
      end
    end)

    it("creates a floating window", function()
      local win, buf = ui.create_floating_window({
        width = 40,
        height = 10,
        title = "Test",
      })

      assert.is_number(win)
      assert.is_number(buf)
      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.is_true(vim.api.nvim_buf_is_valid(buf))

      -- Check window config
      local config = vim.api.nvim_win_get_config(win)
      assert.equals("editor", config.relative)
      assert.equals(40, config.width)
      assert.equals(10, config.height)

      -- Cleanup
      vim.api.nvim_win_close(win, true)
    end)

    it("uses default dimensions if not provided", function()
      local win, buf = ui.create_floating_window({})

      local config = vim.api.nvim_win_get_config(win)
      assert.equals(60, config.width)
      assert.equals(20, config.height)

      vim.api.nvim_win_close(win, true)
    end)

    it("sets buffer options correctly", function()
      local win, buf = ui.create_floating_window({})

      assert.equals("wipe", vim.bo[buf].bufhidden)
      assert.equals("nofile", vim.bo[buf].buftype)
      assert.is_false(vim.bo[buf].swapfile)

      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe("close_pr_list", function()
    it("closes the PR list window if open", function()
      -- Create a window first
      local win, buf = ui.create_floating_window({})
      ui.state.win = win
      ui.state.buf = buf

      -- Close it
      ui.close_pr_list()

      -- Window should be closed
      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.is_nil(ui.state.win)
      assert.is_nil(ui.state.buf)
    end)

    it("handles already closed window gracefully", function()
      ui.state.win = nil
      ui.state.buf = nil

      -- Should not error
      ui.close_pr_list()
    end)
  end)

  describe("state", function()
    it("has expected fields", function()
      -- win and buf start as nil (no window open yet)
      -- but the fields exist on the table
      assert.is_table(ui.state)
      assert.is_table(ui.state.prs)
      assert.is_number(ui.state.selected)
    end)
  end)
end)
