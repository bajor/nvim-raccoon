local commit_ui = require("raccoon.commit_ui")

describe("raccoon.commit_ui", function()
  -- Shared header window helper
  local function make_header(width)
    width = width or 80
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].modifiable = true
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor", row = 0, col = 0, width = width, height = 1,
    })
    vim.wo[win].wrap = true
    return buf, win
  end

  local function teardown_header(buf, win)
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  it("header shows subject then updates to full multiline body", function()
    local buf, win = make_header(80)

    local state = { header_buf = buf, header_win = win, current_page = 1 }
    local commit = { message = "feat: add login" }

    -- Initially only subject is available
    commit_ui.update_header(state, commit, 1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("feat: add login", lines[1])

    -- Async fetch completes — full_message now available
    commit.full_message = "feat: add login\n\nAdds OAuth2 flow\nwith refresh tokens"
    commit_ui.update_header(state, commit, 1)
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals(1, #lines)
    assert.truthy(lines[1]:find("feat: add login"))
    assert.truthy(lines[1]:find("Adds OAuth2 flow"))
    assert.truthy(lines[1]:find("with refresh tokens"))

    teardown_header(buf, win)
  end)

  describe("truncate_sidebar_text", function()
    it("returns short text unchanged", function()
      assert.equals("hello", commit_ui.truncate_sidebar_text("hello", 20))
    end)

    it("returns nil as empty string", function()
      assert.equals("", commit_ui.truncate_sidebar_text(nil, 20))
    end)

    it("returns empty string unchanged", function()
      assert.equals("", commit_ui.truncate_sidebar_text("", 20))
    end)

    it("truncates long text with ellipsis", function()
      local text = "this is a very long sidebar entry"
      local result = commit_ui.truncate_sidebar_text(text, 15)
      -- content_width = 15 - 2 = 13, keep_width = 13 - 3 = 10
      assert.truthy(result:find("%.%.%.$"))
      assert.truthy(vim.fn.strdisplaywidth(result) <= 13)
    end)

    it("text exactly at content_width passes through", function()
      -- sidebar_width=12 → content_width=10
      local text = "0123456789" -- exactly 10 display cols
      assert.equals(text, commit_ui.truncate_sidebar_text(text, 12))
    end)

    it("handles very small sidebar_width", function()
      local result = commit_ui.truncate_sidebar_text("hello world", 3)
      -- content_width = max(1, 3-2) = 1, keep_width = max(1, 1-3) = 1
      -- truncated to 1 char + "..." = 4 cols (ellipsis can exceed content_width at extremes)
      assert.is_string(result)
      assert.truthy(result:find("%.%.%.$"))
    end)

    it("handles sidebar_width of 1", function()
      local result = commit_ui.truncate_sidebar_text("hello", 1)
      assert.is_string(result)
    end)

    it("uses default sidebar_width when nil", function()
      -- Should not error when sidebar_width is omitted
      local result = commit_ui.truncate_sidebar_text("hello")
      assert.is_string(result)
    end)
  end)

  describe("update_header", function()
    it("handles nil commit gracefully", function()
      local buf, win = make_header(80)
      local state = { header_buf = buf, header_win = win, current_page = 1 }

      commit_ui.update_header(state, nil, 1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(1, #lines)
      -- With single page, no page prefix, just empty-ish content
      assert.equals("", lines[1])

      teardown_header(buf, win)
    end)

    it("shows page prefix when pages > 1 with nil commit", function()
      local buf, win = make_header(80)
      local state = { header_buf = buf, header_win = win, current_page = 2 }

      commit_ui.update_header(state, nil, 3)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.truthy(lines[1]:find("2/3"))

      teardown_header(buf, win)
    end)

    it("truncates long messages that exceed max display width", function()
      -- Use a narrow window to force truncation
      local buf, win = make_header(20)
      local state = { header_buf = buf, header_win = win, current_page = 1 }
      -- COMMIT_MESSAGE_MAX_LINES=2, win_width=20 → max_display_width=40
      -- Create a message much longer than 40 display columns
      local long_msg = string.rep("abcdefghij ", 10) -- 110 chars
      local commit = { message = "subject", full_message = long_msg }

      commit_ui.update_header(state, commit, 1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(1, #lines)
      -- Should end with ellipsis since it was truncated
      assert.truthy(lines[1]:find("%.%.%.$"))

      teardown_header(buf, win)
    end)

    it("shows page prefix with commit message", function()
      local buf, win = make_header(80)
      local state = { header_buf = buf, header_win = win, current_page = 1 }
      local commit = { message = "feat: stuff" }

      commit_ui.update_header(state, commit, 3)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.truthy(lines[1]:find("1/3"))
      assert.truthy(lines[1]:find("feat: stuff"))

      teardown_header(buf, win)
    end)
  end)

  it("sidebar widths stay symmetric when requested width is too large", function()
    local cols = 2
    local huge_width = 9999
    local result = commit_ui.compute_effective_sidebar_width(cols, huge_width)

    -- Must not exceed the symmetric maximum
    local separators = cols + 1
    local max_width = math.floor((vim.o.columns - cols - separators) / 2)
    assert.equals(max_width, result)

    -- Both sides would get the same value (function is deterministic)
    assert.equals(result, commit_ui.compute_effective_sidebar_width(cols, huge_width))

    -- A small width that fits should pass through unchanged
    assert.equals(10, commit_ui.compute_effective_sidebar_width(cols, 10))
  end)
end)
