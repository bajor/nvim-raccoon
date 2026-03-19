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

    it("displays full_message when available", function()
      local state = {
        header_buf = buf, header_win = win, current_page = 1,
      }
      local commit = {
        message = "feat: add login",
        full_message = "feat: add login\nThis adds the login flow with OAuth support.\nIncludes token refresh logic.",
      }

      commit_ui.update_header(state, commit, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(3, #lines)
      assert.truthy(lines[1]:find("feat: add login"))
      assert.truthy(lines[2]:find("This adds the login flow"))
      assert.truthy(lines[3]:find("Includes token refresh"))
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

    it("truncates message exceeding max length", function()
      local original = commit_ui.MAX_COMMIT_MESSAGE_LENGTH
      commit_ui.MAX_COMMIT_MESSAGE_LENGTH = 20

      local state = {
        header_buf = buf, header_win = win, current_page = 1,
      }
      local commit = { message = "a]long message that exceeds the maximum length limit for display" }

      commit_ui.update_header(state, commit, 1)

      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local full_text = table.concat(lines, "\n")
      -- Truncated to 20 chars + "..."
      assert.truthy(full_text:find("%.%.%.$"))

      commit_ui.MAX_COMMIT_MESSAGE_LENGTH = original
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
  end)

  describe("MAX_COMMIT_MESSAGE_LENGTH", function()
    it("has a default value", function()
      assert.is_number(commit_ui.MAX_COMMIT_MESSAGE_LENGTH)
      assert.equals(2000, commit_ui.MAX_COMMIT_MESSAGE_LENGTH)
    end)
  end)
end)
