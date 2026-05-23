local keymaps = require("raccoon.keymaps")
local config = require("raccoon.config")

describe("raccoon.keymaps", function()
  local function has_buf_keymap(buf, mode, lhs)
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
      if map.lhs == lhs then
        return true
      end
    end
    return false
  end

  local function current_float_window()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_config = vim.api.nvim_win_get_config(win)
      if win_config.relative ~= "" then
        return win
      end
    end
    return nil
  end

  after_each(function()
    -- Clean up keymaps after each test
    keymaps.clear()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local win_config = vim.api.nvim_win_get_config(win)
      if win_config.relative ~= "" then
        vim.api.nvim_win_close(win, true)
      end
    end
  end)


  describe("build_keymaps", function()
    it("builds keymaps from default shortcuts", function()
      local shortcuts = config.defaults.shortcuts
      local built = keymaps.build_keymaps(shortcuts)
      assert.is_true(#built >= 4)
    end)

    it("uses shortcut values for lhs", function()
      local shortcuts = config.defaults.shortcuts
      local built = keymaps.build_keymaps(shortcuts)
      local found_next = false
      local found_prev = false
      for _, km in ipairs(built) do
        if km.lhs == shortcuts.next_point then found_next = true end
        if km.lhs == shortcuts.prev_point then found_prev = true end
      end
      assert.is_true(found_next)
      assert.is_true(found_prev)
    end)

    it("excludes disabled shortcuts", function()
      local shortcuts = vim.tbl_deep_extend("force",
        vim.deepcopy(config.defaults.shortcuts),
        { next_point = false, comment = false })
      local built = keymaps.build_keymaps(shortcuts)
      for _, km in ipairs(built) do
        assert.is_not_equal(false, km.lhs)
      end
      -- Should have 2 fewer keymaps than default
      local default_built = keymaps.build_keymaps(config.defaults.shortcuts)
      assert.equals(#default_built - 2, #built)
    end)

    it("returns empty list when all shortcuts disabled", function()
      local shortcuts = vim.deepcopy(config.defaults.shortcuts)
      for k, v in pairs(shortcuts) do
        if k ~= "commit_viewer" and type(v) == "string" then
          shortcuts[k] = false
        end
      end
      local built = keymaps.build_keymaps(shortcuts)
      assert.equals(0, #built)
    end)

    it("respects custom shortcut overrides", function()
      local shortcuts = vim.tbl_extend("force", config.defaults.shortcuts, {
        next_point = "<leader>x",
        comment = "<leader>y",
      })
      local built = keymaps.build_keymaps(shortcuts)
      local found_x = false
      local found_y = false
      for _, km in ipairs(built) do
        if km.lhs == "<leader>x" then found_x = true end
        if km.lhs == "<leader>y" then found_y = true end
      end
      assert.is_true(found_x)
      assert.is_true(found_y)
    end)

    it("all keymaps have mode, lhs, rhs, and desc", function()
      local built = keymaps.build_keymaps(config.defaults.shortcuts)
      for _, km in ipairs(built) do
        assert.is_string(km.mode)
        assert.is_string(km.lhs)
        assert.is_not_nil(km.rhs)
        assert.is_string(km.desc)
      end
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

    it("sets up multiple buffers independently", function()
      local buf1 = vim.api.nvim_create_buf(false, true)
      local buf2 = vim.api.nvim_create_buf(false, true)

      -- Should not error
      keymaps.setup_buffer(buf1)
      keymaps.setup_buffer(buf2)

      vim.api.nvim_buf_delete(buf1, { force = true })
      vim.api.nvim_buf_delete(buf2, { force = true })
    end)
  end)

  describe("navigation functions", function()
    local state = require("raccoon.state")
    local original_notify

    before_each(function()
      state.reset()
      original_notify = vim.notify
      vim.notify = function() end
    end)

    after_each(function()
      vim.notify = original_notify
    end)

    it("next_point returns false when no session", function()
      local result = keymaps.next_point()
      assert.is_false(result)
    end)

    it("prev_point returns false when no session", function()
      local result = keymaps.prev_point()
      assert.is_false(result)
    end)

    it("comment_at_cursor does not error when no session", function()
      -- Should not error
      keymaps.comment_at_cursor()
    end)

    it("show_description does not error when no session", function()
      -- Should not error (just warns via ui module)
      keymaps.show_description()
    end)
  end)

  describe("merge_picker", function()
    local api = require("raccoon.api")
    local state = require("raccoon.state")
    local localcommits = require("raccoon.localcommits")
    local original_notify
    local original_config_load
    local original_load_shortcuts
    local original_get_token_for_owner
    local original_api_init
    local original_get_check_runs

    before_each(function()
      state.reset()
      original_notify = vim.notify
      original_config_load = config.load
      original_load_shortcuts = config.load_shortcuts
      original_get_token_for_owner = config.get_token_for_owner
      original_api_init = api.init
      original_get_check_runs = api.get_check_runs
      vim.notify = function() end
      state.start({
        owner = "owner",
        repo = "repo",
        number = 42,
        url = "https://github.com/owner/repo/pull/42",
      })
      state.set_pr({
        head = { sha = "abc123" },
      })
      state.set_commit_mode(false)
      localcommits._get_state().active = false
    end)

    after_each(function()
      vim.notify = original_notify
      config.load = original_config_load
      config.load_shortcuts = original_load_shortcuts
      config.get_token_for_owner = original_get_token_for_owner
      api.init = original_api_init
      api.get_check_runs = original_get_check_runs
      state.reset()
      localcommits._get_state().active = false
    end)

    it("uses picker navigation only and does not show footer hints", function()
      config.load = function()
        return { github_host = "https://github.com" }, nil
      end
      config.load_shortcuts = function()
        return vim.deepcopy(config.defaults.shortcuts)
      end
      config.get_token_for_owner = function()
        return "token"
      end
      api.init = function() end
      api.get_check_runs = function(_, _, _, _, callback)
        callback({ check_runs = {} }, nil)
      end

      keymaps.merge_picker()
      vim.wait(100, function()
        return current_float_window() ~= nil
      end)

      local win = current_float_window()
      assert.is_not_nil(win)
      local buf = vim.api.nvim_win_get_buf(win)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

      assert.is_true(has_buf_keymap(buf, "n", "j"))
      assert.is_true(has_buf_keymap(buf, "n", "k"))
      assert.is_true(has_buf_keymap(buf, "n", "<CR>"))
      assert.is_true(has_buf_keymap(buf, "n", " q"))
      assert.is_false(has_buf_keymap(buf, "n", "1"))
      assert.is_false(has_buf_keymap(buf, "n", "2"))
      assert.is_false(has_buf_keymap(buf, "n", "3"))

      for _, line in ipairs(lines) do
        assert.is_nil(line:match("%[1%]"))
        assert.is_nil(line:match("%[2%]"))
        assert.is_nil(line:match("%[3%]"))
        assert.is_nil(line:match("<leader>q"))
        assert.is_nil(line:match("j/k: navigate"))
        assert.is_nil(line:match("Enter: select"))
      end
    end)
  end)

  describe("keymap modes", function()
    local built

    before_each(function()
      built = keymaps.build_keymaps(config.defaults.shortcuts)
    end)

    it("all keymaps use valid modes", function()
      local valid_modes = { n = true, i = true, v = true, x = true, s = true, o = true, c = true, t = true }
      for _, km in ipairs(built) do
        assert.is_true(valid_modes[km.mode], "Invalid mode: " .. km.mode)
      end
    end)

    it("keymaps have non-empty lhs", function()
      for _, km in ipairs(built) do
        assert.is_true(#km.lhs > 0, "Empty lhs found")
      end
    end)

    it("keymaps have non-empty desc", function()
      for _, km in ipairs(built) do
        assert.is_true(#km.desc > 0, "Empty desc found")
      end
    end)
  end)

  describe("setup and clear cycle", function()
    it("can setup, clear, and setup again", function()
      keymaps.setup()
      keymaps.clear()
      keymaps.setup()
      keymaps.clear()
      -- Should not error
    end)

    it("clear is idempotent", function()
      keymaps.clear()
      keymaps.clear()
      keymaps.clear()
      -- Should not error
    end)

    it("setup is idempotent", function()
      keymaps.setup()
      keymaps.setup()
      keymaps.setup()
      keymaps.clear()
      -- Should not error
    end)
  end)
end)
