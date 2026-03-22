local commit_ui = require("raccoon.commit_ui")

describe("raccoon.commit_ui", function()
  describe("compute_effective_sidebar_width", function()
    it("keeps the requested width when it fits", function()
      assert.equals(30, commit_ui.compute_effective_sidebar_width(2, 30))
    end)

    it("clamps oversized sidebars symmetrically", function()
      local expected = math.floor((vim.o.columns - 2 - 3) / 2)
      assert.equals(expected, commit_ui.compute_effective_sidebar_width(2, 50))
    end)
  end)

  describe("create_grid_layout", function()
    it("applies the same effective width to both sidebars", function()
      local original_sidebar_width = commit_ui.SIDEBAR_WIDTH
      local state = { grid_wins = {}, grid_bufs = {} }

      commit_ui.SIDEBAR_WIDTH = 50
      commit_ui.create_grid_layout(state, 2, 2)

      assert.equals(state.sidebar_width, vim.api.nvim_win_get_width(state.filetree_win))
      assert.equals(state.sidebar_width, vim.api.nvim_win_get_width(state.sidebar_win))
      assert.equals(vim.api.nvim_win_get_width(state.filetree_win), vim.api.nvim_win_get_width(state.sidebar_win))

      commit_ui.close_grid(state)
      commit_ui.close_win_pair(state, "header_win", "header_buf")
      commit_ui.close_win_pair(state, "sidebar_win", "sidebar_buf")
      commit_ui.close_win_pair(state, "filetree_win", "filetree_buf")
      vim.cmd("only")
      commit_ui.SIDEBAR_WIDTH = original_sidebar_width
    end)
  end)

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
end)
