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

  describe("commit_subject", function()
    it("returns full message when no newline", function()
      assert.equals("Fix login bug", commit_ui.commit_subject("Fix login bug"))
    end)

    it("returns first line from multiline message", function()
      assert.equals("Fix login bug", commit_ui.commit_subject("Fix login bug\n\nAdded null check"))
    end)

    it("handles empty string", function()
      assert.equals("", commit_ui.commit_subject(""))
    end)

    it("handles message with only newlines", function()
      assert.equals("", commit_ui.commit_subject("\n\nsome body"))
    end)
  end)
end)
