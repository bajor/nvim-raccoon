local commit_ui = require("raccoon.commit_ui")

local function byte_range(text, start_char, end_char)
  return {
    start_col = vim.str_byteindex(text, start_char),
    end_col = vim.str_byteindex(text, end_char),
  }
end

local function has_line_hl(marks, row, hl_group)
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if mark[2] == row and details.line_hl_group == hl_group then
      return true
    end
  end
  return false
end

local function has_inline_hl(marks, row, hl_group, range)
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if mark[2] == row and details.hl_group == hl_group then
      if not range or (mark[3] == range.start_col and details.end_col == range.end_col) then
        return true
      end
    end
  end
  return false
end

local function has_sign(marks, row, sign_pattern, hl_group)
  for _, mark in ipairs(marks) do
    local details = mark[4] or {}
    if mark[2] == row and details.sign_text and details.sign_text:match(sign_pattern)
        and details.sign_hl_group == hl_group then
      return true
    end
  end
  return false
end

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

    it("truncates CJK characters at display-width boundary", function()
      -- Each CJK char = 2 display columns. 5 chars = 10 cols.
      -- sidebar_width=9 → content_width=7, keep_width=4 → 2 CJK chars (4 cols) + "..."
      local text = "漢字測試文"
      local result = commit_ui.truncate_sidebar_text(text, 9)
      assert.truthy(result:find("%.%.%.$"))
      assert.truthy(vim.fn.strdisplaywidth(result) <= 7)
    end)

    it("truncates mixed ASCII and CJK correctly", function()
      -- "ab漢字cd" = 2 + 4 + 2 = 8 display cols
      -- sidebar_width=8 → content_width=6, keep_width=3 → "ab" (2 cols) fits, "ab漢" (4 cols) > 3
      local text = "ab漢字cd"
      local result = commit_ui.truncate_sidebar_text(text, 8)
      assert.truthy(result:find("%.%.%.$"))
      assert.truthy(vim.fn.strdisplaywidth(result) <= 6)
    end)

    it("truncates emoji at display-width boundary", function()
      -- Emoji are typically 2 display columns each
      local text = "hello🎉🎊🎈world"
      local result = commit_ui.truncate_sidebar_text(text, 12)
      -- content_width=10, keep_width=7
      assert.truthy(result:find("%.%.%.$"))
      assert.truthy(vim.fn.strdisplaywidth(result) <= 10)
    end)

    it("handles all double-width chars truncated to minimal width", function()
      local text = "漢字"
      -- sidebar_width=5 → content_width=3, text=4 cols → needs truncation
      -- keep_width = max(1, 3-3) = 1, but a CJK char is 2 cols wide
      -- binary search should return 0 chars, result = "" .. "..."
      local result = commit_ui.truncate_sidebar_text(text, 5)
      assert.is_string(result)
      assert.truthy(result:find("%.%.%.$"))
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
      -- Create a message much longer than the configured wrapping budget.
      local long_msg = string.rep("abcdefghij ", 10) -- 110 chars
      local commit = { message = "subject", full_message = long_msg }

      commit_ui.update_header(state, commit, 1)
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      assert.equals(1, #lines)
      -- Should end with ellipsis since it was truncated
      assert.truthy(lines[1]:find("%.%.%.$"))

      teardown_header(buf, win)
    end)

    it("truncates with the effective header line cap when terminal height is constrained", function()
      local buf, win = make_header(20)
      local saved_lines = vim.o.lines
      local ok, err = pcall(function()
        local state = { header_buf = buf, header_win = win, current_page = 1 }
        vim.o.lines = 5 -- floor(5/3) = 1 visible header line
        local commit = { full_message = string.rep("abcdefghij ", 3) } -- 33 cols: >20 but <60

        commit_ui.update_header(state, commit, 1)
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        assert.equals(1, #lines)
        assert.truthy(lines[1]:find("%.%.%.$"))
        assert.truthy(vim.fn.strdisplaywidth(lines[1]) <= 20)
      end)

      vim.o.lines = saved_lines
      teardown_header(buf, win)
      if not ok then error(err) end
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

  describe("apply_diff_highlights", function()
    it("renders exact inline replacement spans over faded changed-line backgrounds", function()
      local ns = vim.api.nvim_create_namespace("raccoon_test_commit_inline")
      local buf = vim.api.nvim_create_buf(false, true)
      local old_line = "local total_count = item.count"
      local new_line = "local total_size = item.count"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { old_line, new_line })

      commit_ui.apply_diff_highlights(ns, buf, {
        { type = "del", content = old_line },
        { type = "add", content = new_line },
      })

      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      assert.is_true(has_line_hl(marks, 0, "RaccoonDelete"))
      assert.is_true(has_line_hl(marks, 1, "RaccoonAdd"))
      assert.is_true(has_sign(marks, 0, "^%-", "RaccoonDeleteSign"))
      assert.is_true(has_sign(marks, 1, "^%+", "RaccoonAddSign"))
      assert.is_true(has_inline_hl(marks, 0, "RaccoonDeleteInline", byte_range(old_line, 12, 17)))
      assert.is_false(has_inline_hl(marks, 0, "Comment"))
      assert.is_true(has_inline_hl(marks, 1, "RaccoonAddInline", byte_range(new_line, 12, 16)))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("pairs shifted lines and keeps pure additions as full inline spans", function()
      local ns = vim.api.nvim_create_namespace("raccoon_test_commit_shifted")
      local buf = vim.api.nvim_create_buf(false, true)
      local old_line = "local api_client = request.client"
      local inserted_line = "local cache_hit = true"
      local new_line = "local api_server = request.client"
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { old_line, inserted_line, new_line })

      commit_ui.apply_diff_highlights(ns, buf, {
        { type = "del", content = old_line },
        { type = "add", content = inserted_line },
        { type = "add", content = new_line },
      })

      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      assert.is_true(has_inline_hl(marks, 1, "RaccoonAddInline", { start_col = 0, end_col = #inserted_line }))
      assert.is_true(has_inline_hl(marks, 2, "RaccoonAddInline", byte_range(new_line, 10, 16)))
      assert.is_true(has_inline_hl(marks, 0, "RaccoonDeleteInline", byte_range(old_line, 10, 16)))
      assert.is_true(has_line_hl(marks, 0, "RaccoonDelete"))
      assert.is_true(has_line_hl(marks, 1, "RaccoonAdd"))
      assert.is_true(has_line_hl(marks, 2, "RaccoonAdd"))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("keeps whole-line backgrounds in internal line mode", function()
      local ns = vim.api.nvim_create_namespace("raccoon_test_commit_line_mode")
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "old line", "new line" })

      commit_ui.apply_diff_highlights(ns, buf, {
        { type = "del", content = "old line" },
        { type = "add", content = "new line" },
      }, { mode = "line" })

      local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
      assert.is_true(has_line_hl(marks, 0, "RaccoonDelete"))
      assert.is_true(has_line_hl(marks, 1, "RaccoonAdd"))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  it("compute_grid_context matches rendered grid row height", function()
    local state = { grid_wins = {}, grid_bufs = {} }
    local saved_lines = vim.o.lines

    local function cleanup()
      vim.o.lines = saved_lines
      commit_ui.close_grid(state)
      commit_ui.close_win_pair(state, "header_win", "header_buf")
      commit_ui.close_win_pair(state, "sidebar_win", "sidebar_buf")
      commit_ui.close_win_pair(state, "filetree_win", "filetree_buf")
      pcall(vim.cmd, "only")
    end

    local ok, err = pcall(function()
      vim.o.lines = math.max(saved_lines, 36)
      commit_ui.create_grid_layout(state, 2, 2)

      local row_height = vim.api.nvim_win_get_height(state.grid_wins[1])
      local expected = math.max(3, math.floor(row_height / 2))
      local actual = commit_ui.compute_grid_context(2)

      assert.equals(expected, actual)
    end)

    cleanup()
    if not ok then error(err) end
  end)

  it("rebuild_grid keeps filetree and commit sidebar widths symmetric", function()
    local state = { grid_wins = {}, grid_bufs = {} }

    local function cleanup()
      commit_ui.close_grid(state)
      commit_ui.close_win_pair(state, "header_win", "header_buf")
      commit_ui.close_win_pair(state, "sidebar_win", "sidebar_buf")
      commit_ui.close_win_pair(state, "filetree_win", "filetree_buf")
      pcall(vim.cmd, "only")
    end

    local ok, err = pcall(function()
      commit_ui.create_grid_layout(state, 1, 2)

      local sidebar_width = vim.api.nvim_win_get_width(state.sidebar_win)
      pcall(vim.api.nvim_win_set_width, state.filetree_win, sidebar_width + 7)
      local pre_filetree = vim.api.nvim_win_get_width(state.filetree_win)
      local pre_sidebar = vim.api.nvim_win_get_width(state.sidebar_win)
      assert.is_true(pre_filetree ~= pre_sidebar)

      commit_ui.rebuild_grid(state, 1, 2, function() end)

      local post_filetree = vim.api.nvim_win_get_width(state.filetree_win)
      local post_sidebar = vim.api.nvim_win_get_width(state.sidebar_win)
      assert.equals(post_filetree, post_sidebar)
    end)

    cleanup()
    if not ok then error(err) end
  end)

  it("toggle_filetree_focus keeps sidebars symmetric for 1x2 layouts", function()
    local state = {
      active = true,
      grid_wins = {},
      grid_bufs = {},
      cached_line_paths = {},
      focus_target = "sidebar",
      preview_generation = 0,
      select_generation = 0,
    }

    local original_sidebar_width = commit_ui.SIDEBAR_WIDTH
    commit_ui.SIDEBAR_WIDTH = 30

    local function cleanup()
      commit_ui.SIDEBAR_WIDTH = original_sidebar_width
      commit_ui.close_grid(state)
      commit_ui.close_win_pair(state, "header_win", "header_buf")
      commit_ui.close_win_pair(state, "sidebar_win", "sidebar_buf")
      commit_ui.close_win_pair(state, "filetree_win", "filetree_buf")
      pcall(vim.cmd, "only")
    end

    local function assert_symmetric()
      local filetree_width = vim.api.nvim_win_get_width(state.filetree_win)
      local sidebar_width = vim.api.nvim_win_get_width(state.sidebar_win)
      assert.equals(filetree_width, sidebar_width)
    end

    local ok, err = pcall(function()
      commit_ui.create_grid_layout(state, 1, 2)
      assert_symmetric()

      local opts = {
        apply_keymaps = function() end,
        render_page = function() end,
        ns_id = vim.api.nvim_create_namespace("raccoon_test_toggle_ft"),
        get_repo_path = function() return nil end,
        get_sha = function() return nil end,
        get_is_working_dir = function() return false end,
      }

      commit_ui.toggle_filetree_focus(state, opts)
      assert_symmetric()

      commit_ui.toggle_filetree_focus(state, opts)
      assert_symmetric()
    end)

    cleanup()
    if not ok then error(err) end
  end)

  it("toggle_filetree_focus preserves header height for 1x2 layouts", function()
    local state = {
      active = true,
      grid_wins = {},
      grid_bufs = {},
      cached_line_paths = {},
      focus_target = "sidebar",
      preview_generation = 0,
      select_generation = 0,
    }

    local saved_lines = vim.o.lines

    local function cleanup()
      vim.o.lines = saved_lines
      commit_ui.close_grid(state)
      commit_ui.close_win_pair(state, "header_win", "header_buf")
      commit_ui.close_win_pair(state, "sidebar_win", "sidebar_buf")
      commit_ui.close_win_pair(state, "filetree_win", "filetree_buf")
      pcall(vim.cmd, "only")
    end

    local ok, err = pcall(function()
      vim.o.lines = math.max(saved_lines, 36)
      commit_ui.create_grid_layout(state, 1, 2)

      local initial_header_height = vim.api.nvim_win_get_height(state.header_win)
      assert.is_true(initial_header_height > 1)

      local opts = {
        apply_keymaps = function() end,
        render_page = function() end,
        ns_id = vim.api.nvim_create_namespace("raccoon_test_toggle_ft_header"),
        get_repo_path = function() return nil end,
        get_sha = function() return nil end,
        get_is_working_dir = function() return false end,
      }

      commit_ui.toggle_filetree_focus(state, opts)
      local filetree_header_height = vim.api.nvim_win_get_height(state.header_win)
      assert.equals(initial_header_height, filetree_header_height)

      commit_ui.toggle_filetree_focus(state, opts)
      local sidebar_header_height = vim.api.nvim_win_get_height(state.header_win)
      assert.equals(initial_header_height, sidebar_header_height)
    end)

    cleanup()
    if not ok then error(err) end
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
