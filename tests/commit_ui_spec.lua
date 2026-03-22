local commit_ui = require("raccoon.commit_ui")

describe("raccoon.commit_ui", function()
  describe("setup_focus_lock", function()
    it("clears stale popup_win handles", function()
      local state = {
        active = true,
        maximize_win = nil,
        sidebar_win = vim.api.nvim_get_current_win(),
        filetree_win = nil,
        focus_target = "sidebar",
        popup_win = 99999,
      }

      local augroup = commit_ui.setup_focus_lock(state, "RaccoonTestFocusLock")
      vim.api.nvim_exec_autocmds("WinEnter", { group = augroup })

      assert.is_nil(state.popup_win)
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end)

    it("closes unexpected split windows", function()
      local sidebar_win = vim.api.nvim_get_current_win()
      local state = {
        active = true,
        maximize_win = nil,
        sidebar_win = sidebar_win,
        filetree_win = nil,
        header_win = nil,
        grid_wins = {},
        focus_target = "sidebar",
      }

      local augroup = commit_ui.setup_focus_lock(state, "RaccoonTestWinGuard")

      -- Create an unexpected split (simulates file explorer opening)
      vim.cmd("vsplit")
      local rogue_win = vim.api.nvim_get_current_win()
      assert.not_equals(sidebar_win, rogue_win)

      -- WinNew fires synchronously but the close is scheduled
      vim.wait(100, function() return not vim.api.nvim_win_is_valid(rogue_win) end)
      assert.is_false(vim.api.nvim_win_is_valid(rogue_win))

      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end)

    it("allows floating windows through the guard", function()
      local sidebar_win = vim.api.nvim_get_current_win()
      local state = {
        active = true,
        maximize_win = nil,
        sidebar_win = sidebar_win,
        filetree_win = nil,
        header_win = nil,
        grid_wins = {},
        focus_target = "sidebar",
      }

      local augroup = commit_ui.setup_focus_lock(state, "RaccoonTestFloatGuard")

      -- Create a floating window (like maximize or popup)
      local buf = vim.api.nvim_create_buf(false, true)
      local float_win = vim.api.nvim_open_win(buf, true, {
        relative = "editor", row = 1, col = 1, width = 10, height = 5,
      })

      vim.wait(100, function() return false end)
      assert.is_true(vim.api.nvim_win_is_valid(float_win))

      pcall(vim.api.nvim_win_close, float_win, true)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
      pcall(vim.api.nvim_del_augroup_by_id, augroup)
    end)
  end)

  describe("update_header", function()
    local buf, win

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].modifiable = true
      win = vim.api.nvim_open_win(buf, false, {
        relative = "editor", row = 0, col = 0, width = 80, height = 1,
      })
      vim.wo[win].wrap = true
    end)

    after_each(function()
      pcall(vim.api.nvim_win_close, win, true)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("displays full_message joined into single line", function()
      local state = {
        header_buf = buf, header_win = win, current_page = 1,
      }
      local commit = {
        message = "feat: add login",
        full_message = "feat: add login\nshort body",
      }

      commit_ui.update_header(state, commit, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(1, #lines)
      assert.truthy(lines[1]:find("feat: add login"))
      assert.truthy(lines[1]:find("short body"))
    end)

    it("falls back to message when full_message is nil", function()
      local state = {
        header_buf = buf, header_win = win, current_page = 1,
      }
      local commit = { message = "fix: null check" }

      commit_ui.update_header(state, commit, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(1, #lines)
      assert.truthy(lines[1]:find("fix: null check"))
    end)

    it("shows page indicator for multi-page commits", function()
      local state = {
        header_buf = buf, header_win = win, current_page = 2,
      }
      local commit = { message = "test commit" }

      commit_ui.update_header(state, commit, 3)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.truthy(lines[1]:find("2/3"))
    end)

    it("handles nil commit gracefully", function()
      local state = {
        header_buf = buf, header_win = win, current_page = 1,
      }

      commit_ui.update_header(state, nil, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(1, #lines)
    end)

    it("handles commit with both message and full_message nil", function()
      local state = {
        header_buf = buf, header_win = win, current_page = 1,
      }
      local commit = {}

      commit_ui.update_header(state, commit, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(1, #lines)
    end)

    it("joins multiline message with blank-line separators", function()
      local state = {
        header_buf = buf, header_win = win, current_page = 1,
      }
      local commit = {
        full_message = "feat: add login\n\nLonger body paragraph\nwith details",
      }

      commit_ui.update_header(state, commit, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(1, #lines)
      assert.truthy(lines[1]:find("feat: add login"))
      assert.truthy(lines[1]:find("Longer body paragraph"))
      assert.truthy(lines[1]:find("with details"))
    end)

    it("has no leading space when pages <= 1", function()
      local state = {
        header_buf = buf, header_win = win, current_page = 1,
      }
      local commit = { message = "test" }

      commit_ui.update_header(state, commit, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals("test", lines[1])
    end)
  end)

  describe("COMMIT_MESSAGE_MAX_LINES", function()
    it("has a default value", function()
      assert.is_number(commit_ui.COMMIT_MESSAGE_MAX_LINES)
      assert.equals(2, commit_ui.COMMIT_MESSAGE_MAX_LINES)
    end)

    it("caps header window height at max_lines for long messages", function()
      local header_buf = vim.api.nvim_create_buf(false, true)
      local header_win = vim.api.nvim_open_win(header_buf, false, {
        relative = "editor", row = 0, col = 0, width = 20, height = 1,
      })
      vim.wo[header_win].wrap = true

      local original = commit_ui.COMMIT_MESSAGE_MAX_LINES
      commit_ui.COMMIT_MESSAGE_MAX_LINES = 2

      local s = { header_buf = header_buf, header_win = header_win, current_page = 1 }
      -- 60 chars in 20-col window = 3 visual lines, capped to max_lines=2
      local commit = { message = string.rep("abcdefghij", 6) }

      commit_ui.update_header(s, commit, 1)
      assert.equals(2, vim.api.nvim_win_get_height(header_win))

      commit_ui.COMMIT_MESSAGE_MAX_LINES = original
      pcall(vim.api.nvim_win_close, header_win, true)
      pcall(vim.api.nvim_buf_delete, header_buf, { force = true })
    end)

    it("uses height 1 for short messages even when max_lines is larger", function()
      local header_buf = vim.api.nvim_create_buf(false, true)
      local header_win = vim.api.nvim_open_win(header_buf, false, {
        relative = "editor", row = 0, col = 0, width = 80, height = 1,
      })
      vim.wo[header_win].wrap = true

      local original = commit_ui.COMMIT_MESSAGE_MAX_LINES
      commit_ui.COMMIT_MESSAGE_MAX_LINES = 3

      local s = { header_buf = header_buf, header_win = header_win, current_page = 1 }
      local commit = { message = "short" }

      commit_ui.update_header(s, commit, 1)
      assert.equals(1, vim.api.nvim_win_get_height(header_win))

      commit_ui.COMMIT_MESSAGE_MAX_LINES = original
      pcall(vim.api.nvim_win_close, header_win, true)
      pcall(vim.api.nvim_buf_delete, header_buf, { force = true })
    end)
  end)

  describe("truncate_to_display_width", function()
    it("returns full text when within limit", function()
      assert.equals("hello", commit_ui.truncate_to_display_width("hello", 10))
    end)

    it("truncates text exceeding limit", function()
      assert.equals("hel", commit_ui.truncate_to_display_width("hello", 3))
    end)

    it("returns empty string for zero max_width", function()
      assert.equals("", commit_ui.truncate_to_display_width("hello", 0))
    end)

    it("handles empty input", function()
      assert.equals("", commit_ui.truncate_to_display_width("", 10))
    end)

    it("handles wide characters correctly", function()
      -- CJK characters are 2 display columns each
      local cjk = "中文测试"
      local result = commit_ui.truncate_to_display_width(cjk, 4)
      -- Should fit exactly 2 CJK characters (4 columns)
      assert.equals("中文", result)
    end)

    it("does not split a wide character at boundary", function()
      -- "a" is 1 col, "中" is 2 cols — budget of 2 fits "a" + nothing more (next char needs 2)
      assert.equals("a", commit_ui.truncate_to_display_width("a中b", 2))
    end)
  end)

  describe("update_header truncation", function()
    local buf, win

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].modifiable = true
      win = vim.api.nvim_open_win(buf, false, {
        relative = "editor", row = 0, col = 0, width = 20, height = 1,
      })
      vim.wo[win].wrap = true
    end)

    after_each(function()
      pcall(vim.api.nvim_win_close, win, true)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("truncates long message with ellipsis", function()
      local original = commit_ui.COMMIT_MESSAGE_MAX_LINES
      commit_ui.COMMIT_MESSAGE_MAX_LINES = 1

      local state = { header_buf = buf, header_win = win, current_page = 1 }
      -- 30 chars in a 20-col window with max_lines=1 → must truncate
      local commit = { message = "this is a very long commit msg" }

      commit_ui.update_header(state, commit, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.truthy(lines[1]:find("%.%.%.$"))

      commit_ui.COMMIT_MESSAGE_MAX_LINES = original
    end)

    it("does not truncate short message", function()
      local original = commit_ui.COMMIT_MESSAGE_MAX_LINES
      commit_ui.COMMIT_MESSAGE_MAX_LINES = 1

      local state = { header_buf = buf, header_win = win, current_page = 1 }
      local commit = { message = "short" }

      commit_ui.update_header(state, commit, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals("short", lines[1])

      commit_ui.COMMIT_MESSAGE_MAX_LINES = original
    end)
  end)

  describe("fetch_and_display_commit_message", function()
    local buf, win, git

    before_each(function()
      buf = vim.api.nvim_create_buf(false, true)
      vim.bo[buf].modifiable = true
      win = vim.api.nvim_open_win(buf, false, {
        relative = "editor", row = 0, col = 0, width = 80, height = 1,
      })
      vim.wo[win].wrap = true
      git = require("raccoon.git")
    end)

    after_each(function()
      pcall(vim.api.nvim_win_close, win, true)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end)

    it("handles nil commit gracefully", function()
      local s = {
        header_buf = buf, header_win = win, current_page = 1,
        select_generation = 1,
      }

      -- Should not error
      commit_ui.fetch_and_display_commit_message(s, nil, "/tmp", 1, function() return 1 end)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(1, #lines)
    end)

    it("skips fetch when full_message is already cached", function()
      local fetch_called = false
      local orig = git.get_commit_message
      git.get_commit_message = function() fetch_called = true end

      local s = {
        header_buf = buf, header_win = win, current_page = 1,
        select_generation = 1,
      }
      local commit = { sha = "abc123", message = "subject", full_message = "subject\nbody" }

      commit_ui.fetch_and_display_commit_message(s, commit, "/tmp", 1, function() return 1 end)

      assert.is_false(fetch_called)
      git.get_commit_message = orig
    end)

    it("skips fetch when commit has no sha", function()
      local fetch_called = false
      local orig = git.get_commit_message
      git.get_commit_message = function() fetch_called = true end

      local s = {
        header_buf = buf, header_win = win, current_page = 1,
        select_generation = 1,
      }
      local commit = { message = "working directory changes" }

      commit_ui.fetch_and_display_commit_message(s, commit, "/tmp", 1, function() return 1 end)

      assert.is_false(fetch_called)
      git.get_commit_message = orig
    end)

    it("does not set full_message when callback returns empty string", function()
      local orig = git.get_commit_message
      git.get_commit_message = function(_, _, cb) cb("", nil) end

      local s = {
        header_buf = buf, header_win = win, current_page = 1,
        select_generation = 1,
      }
      local commit = { sha = "abc123", message = "subject" }

      commit_ui.fetch_and_display_commit_message(s, commit, "/tmp", 1, function() return 1 end)

      assert.is_nil(commit.full_message)
      git.get_commit_message = orig
    end)

    it("ignores stale callback when select_generation has changed", function()
      local captured_cb
      local orig = git.get_commit_message
      git.get_commit_message = function(_, _, cb) captured_cb = cb end

      local s = {
        header_buf = buf, header_win = win, current_page = 1,
        select_generation = 1,
      }
      local commit = { sha = "abc123", message = "subject" }

      commit_ui.fetch_and_display_commit_message(s, commit, "/tmp", 1, function() return 1 end)

      -- Simulate user navigating to a different commit before callback fires
      s.select_generation = 2

      captured_cb("subject\nfull body text", nil)

      assert.is_nil(commit.full_message)
      git.get_commit_message = orig
    end)

    it("notifies on error and does not set full_message", function()
      local orig = git.get_commit_message
      git.get_commit_message = function(_, _, cb) cb(nil, "git error") end

      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.WARN and msg:match("git error") then
          notified = true
        end
      end

      local s = {
        header_buf = buf, header_win = win, current_page = 1,
        select_generation = 1,
      }
      local commit = { sha = "abc123", message = "subject" }

      commit_ui.fetch_and_display_commit_message(s, commit, "/tmp", 1, function() return 1 end)

      assert.is_nil(commit.full_message)
      assert.is_true(notified)

      vim.notify = orig_notify
      git.get_commit_message = orig
    end)
  end)
end)
