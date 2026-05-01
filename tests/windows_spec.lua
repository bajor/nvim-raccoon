local loader = require("tests.helpers.loader")
local windows = loader.reload_from_cwd("raccoon.windows")

describe("raccoon.windows", function()
  local test_wins = {}

  local function open_float()
    local buf = vim.api.nvim_create_buf(false, true)
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor",
      width = 10,
      height = 5,
      row = 0,
      col = 0,
      style = "minimal",
    })
    table.insert(test_wins, win)
    return win
  end

  after_each(function()
    for _, win in ipairs(test_wins) do
      pcall(vim.api.nvim_win_close, win, true)
    end
    test_wins = {}
  end)

  describe("mark", function()
    it("marks a valid window", function()
      local win = open_float()
      windows.mark(win)
      assert.is_true(windows.is_marked(win))
    end)

    it("does not error on nil", function()
      assert.has_no.errors(function() windows.mark(nil) end)
    end)

    it("does not error on invalid window handle", function()
      assert.has_no.errors(function() windows.mark(99999) end)
    end)
  end)

  describe("is_marked", function()
    it("returns false for unmarked window", function()
      local win = open_float()
      assert.is_false(windows.is_marked(win))
    end)

    it("returns false for nil", function()
      assert.is_false(windows.is_marked(nil))
    end)

    it("returns false for invalid handle", function()
      assert.is_false(windows.is_marked(99999))
    end)
  end)

  describe("has_open", function()
    it("returns false when no windows are marked", function()
      assert.is_false(windows.has_open())
    end)

    it("returns true when a marked window is open", function()
      local win = open_float()
      windows.mark(win)
      assert.is_true(windows.has_open())
    end)

    it("returns false after marked window is closed", function()
      local win = open_float()
      windows.mark(win)
      vim.api.nvim_win_close(win, true)
      test_wins = {}
      assert.is_false(windows.has_open())
    end)
  end)

  describe("close_all", function()
    it("closes marked windows and returns count", function()
      local win1 = open_float()
      local win2 = open_float()
      windows.mark(win1)
      windows.mark(win2)
      local count = windows.close_all()
      assert.equals(2, count)
      assert.is_false(vim.api.nvim_win_is_valid(win1))
      assert.is_false(vim.api.nvim_win_is_valid(win2))
      test_wins = {}
    end)

    it("does not close unmarked windows", function()
      local marked = open_float()
      local unmarked = open_float()
      windows.mark(marked)
      windows.close_all()
      assert.is_false(vim.api.nvim_win_is_valid(marked))
      assert.is_true(vim.api.nvim_win_is_valid(unmarked))
      test_wins = { unmarked }
    end)

    it("returns 0 when no windows are marked", function()
      assert.equals(0, windows.close_all())
    end)

    it("handles already-closed windows gracefully", function()
      local win = open_float()
      windows.mark(win)
      vim.api.nvim_win_close(win, true)
      test_wins = {}
      assert.has_no.errors(function()
        local count = windows.close_all()
        assert.equals(0, count)
      end)
    end)
  end)
end)
