-- Force-load from CWD to shadow any installed plugin copies
local function reload_from_cwd(mod)
  package.loaded[mod] = nil
  local cwd = vim.fn.getcwd()
  local path = cwd .. "/lua/" .. mod:gsub("%.", "/") .. ".lua"
  local fn, err = loadfile(path)
  if not fn then error("Failed to load " .. path .. ": " .. tostring(err)) end
  local result = fn()
  package.loaded[mod] = result
  return result
end

local commit_ui = reload_from_cwd("raccoon.commit_ui")

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

  describe("diff_line_to_file_line", function()
    it("returns 1 for nil hl_lines", function()
      assert.equals(1, commit_ui.diff_line_to_file_line(nil, 5))
    end)

    it("returns 1 for empty hl_lines", function()
      assert.equals(1, commit_ui.diff_line_to_file_line({}, 5))
    end)

    it("returns exact match for add line", function()
      local hl_lines = {
        { type = "ctx", line_num = 10 },
        { type = "add", line_num = 11 },
        { type = "ctx", line_num = 12 },
      }
      assert.equals(11, commit_ui.diff_line_to_file_line(hl_lines, 2))
    end)

    it("returns exact match for ctx line", function()
      local hl_lines = {
        { type = "ctx", line_num = 5 },
        { type = "ctx", line_num = 6 },
      }
      assert.equals(6, commit_ui.diff_line_to_file_line(hl_lines, 2))
    end)

    it("skips del lines and searches backward", function()
      local hl_lines = {
        { type = "ctx", line_num = 10 },
        { type = "del" },
        { type = "del" },
      }
      assert.equals(10, commit_ui.diff_line_to_file_line(hl_lines, 3))
    end)

    it("clamps cursor beyond hl_lines length", function()
      local hl_lines = {
        { type = "ctx", line_num = 7 },
        { type = "add", line_num = 8 },
      }
      assert.equals(8, commit_ui.diff_line_to_file_line(hl_lines, 100))
    end)

    it("returns 1 when all entries are del lines", function()
      local hl_lines = {
        { type = "del" },
        { type = "del" },
      }
      assert.equals(1, commit_ui.diff_line_to_file_line(hl_lines, 2))
    end)

    it("returns 1 when entries have no line_num", function()
      local hl_lines = {
        { type = "ctx" },
        { type = "add" },
      }
      assert.equals(1, commit_ui.diff_line_to_file_line(hl_lines, 2))
    end)

    it("finds nearest add/ctx backward from cursor", function()
      local hl_lines = {
        { type = "add", line_num = 1 },
        { type = "add", line_num = 2 },
        { type = "del" },
        { type = "del" },
        { type = "ctx", line_num = 3 },
      }
      -- cursor on line 4 (a del line), should search back to line 2
      assert.equals(2, commit_ui.diff_line_to_file_line(hl_lines, 4))
    end)
  end)
end)
