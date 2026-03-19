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
  end)

  describe("COMMIT_MESSAGE_MAX_LINES", function()
    it("has a default value", function()
      assert.is_number(commit_ui.COMMIT_MESSAGE_MAX_LINES)
      assert.equals(2, commit_ui.COMMIT_MESSAGE_MAX_LINES)
    end)

    it("caps header window height", function()
      local header_buf = vim.api.nvim_create_buf(false, true)
      local header_win = vim.api.nvim_open_win(header_buf, false, {
        relative = "editor", row = 0, col = 0, width = 40, height = 1,
      })
      vim.wo[header_win].wrap = true

      local original = commit_ui.COMMIT_MESSAGE_MAX_LINES
      commit_ui.COMMIT_MESSAGE_MAX_LINES = 2

      local s = { header_buf = header_buf, header_win = header_win, current_page = 1 }
      local commit = { message = "x" }

      commit_ui.update_header(s, commit, 1)
      assert.equals(2, vim.api.nvim_win_get_height(header_win))

      commit_ui.COMMIT_MESSAGE_MAX_LINES = original
      pcall(vim.api.nvim_win_close, header_win, true)
      pcall(vim.api.nvim_buf_delete, header_buf, { force = true })
    end)
  end)
end)
