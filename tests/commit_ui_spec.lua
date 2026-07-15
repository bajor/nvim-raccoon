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

describe("raccoon.commit_ui inline diff rendering", function()
  local diff = require("raccoon.diff")
  local git = require("raccoon.git")

  local function get_marks(buf, ns_id)
    return vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
  end

  local function find_mark(marks, row, field, value)
    for _, mark in ipairs(marks) do
      if mark[2] == row and mark[4][field] == value then return mark end
    end
    return nil
  end

  local function close_buffer(buf)
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  it("renders subdued rows, signs, and exact bright ranges in grid buffers", function()
    local ns_id = vim.api.nvim_create_namespace("raccoon_test_commit_inline_grid")
    local buf = vim.api.nvim_create_buf(false, true)
    local hunk = diff.parse_patch(table.concat({
      "@@ -1 +1 @@",
      "-local target = old_value",
      "+local target = new_value",
    }, "\n"))[1]

    commit_ui.render_hunk_to_buffer(ns_id, buf, hunk, "test.lua")

    local marks = get_marks(buf, ns_id)
    local deletion_row = find_mark(marks, 0, "line_hl_group", "RaccoonDelete")
    local addition_row = find_mark(marks, 1, "line_hl_group", "RaccoonAdd")
    local deletion_range = find_mark(marks, 0, "hl_group", "RaccoonDeleteInline")
    local addition_range = find_mark(marks, 1, "hl_group", "RaccoonAddInline")
    assert.is_not_nil(deletion_row)
    assert.equals("- ", deletion_row[4].sign_text)
    assert.is_not_nil(addition_row)
    assert.equals("+ ", addition_row[4].sign_text)
    assert.is_not_nil(deletion_range)
    assert.equals(200, deletion_range[4].priority)
    assert.is_true(deletion_range[3] < deletion_range[4].end_col)
    assert.is_not_nil(addition_range)
    assert.equals(200, addition_range[4].priority)
    assert.is_true(addition_range[3] < addition_range[4].end_col)

    close_buffer(buf)
  end)

  it("renders over-limit grid rows with subdued backgrounds and no bright ranges", function()
    local ns_id = vim.api.nvim_create_namespace("raccoon_test_commit_inline_suppressed")
    local buf = vim.api.nvim_create_buf(false, true)
    local old_content = string.rep("a", 1000) .. "x"
    local new_content = string.rep("a", 1000) .. "y"
    local hunk = diff.parse_patch(table.concat({
      "@@ -1 +1 @@",
      "-" .. old_content,
      "+" .. new_content,
    }, "\n"))[1]

    commit_ui.render_hunk_to_buffer(ns_id, buf, hunk, "test.lua")

    local marks = get_marks(buf, ns_id)
    assert.is_not_nil(find_mark(marks, 0, "line_hl_group", "RaccoonDelete"))
    assert.is_not_nil(find_mark(marks, 1, "line_hl_group", "RaccoonAdd"))
    assert.is_nil(find_mark(marks, 0, "hl_group", "RaccoonDeleteInline"))
    assert.is_nil(find_mark(marks, 1, "hl_group", "RaccoonAddInline"))

    close_buffer(buf)
  end)

  it("removes trailing carriage returns from rendered hunk lines", function()
    local ns_id = vim.api.nvim_create_namespace("raccoon_test_commit_inline_crlf")
    local buf = vim.api.nvim_create_buf(false, true)
    local hunk = diff.parse_patch(table.concat({
      "@@ -1 +1 @@",
      "-local target = old_value",
      "+local target = new_value",
    }, "\r\n"))[1]

    commit_ui.render_hunk_to_buffer(ns_id, buf, hunk, "test.lua")

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.same({ "local target = old_value", "local target = new_value" }, lines)
    local marks = get_marks(buf, ns_id)
    assert.is_not_nil(find_mark(marks, 0, "hl_group", "RaccoonDeleteInline"))
    assert.is_not_nil(find_mark(marks, 1, "hl_group", "RaccoonAddInline"))

    close_buffer(buf)
  end)

  it("uses strong line highlights when inline planning falls back", function()
    local ns_id = vim.api.nvim_create_namespace("raccoon_test_commit_inline_fallback")
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "before", "after" })
    local hunk = diff.parse_patch("@@ -1 +1 @@\n-before\n+after")[1]
    local original_get_inline_ranges = diff.get_inline_ranges
    diff.get_inline_ranges = function() return nil end

    local ok, err = pcall(commit_ui.apply_diff_highlights, ns_id, buf, hunk.lines)
    diff.get_inline_ranges = original_get_inline_ranges

    if not ok then
      close_buffer(buf)
      error(err)
    end
    local marks = get_marks(buf, ns_id)
    assert.is_not_nil(find_mark(marks, 0, "line_hl_group", "RaccoonDeleteInline"))
    assert.is_not_nil(find_mark(marks, 1, "line_hl_group", "RaccoonAddInline"))
    assert.is_nil(find_mark(marks, 0, "hl_group", "RaccoonDeleteInline"))
    assert.is_nil(find_mark(marks, 1, "hl_group", "RaccoonAddInline"))

    close_buffer(buf)
  end)

  it("batches preview planning without crossing hunk boundaries and clears stale marks", function()
    local ns_id = vim.api.nvim_create_namespace("raccoon_test_commit_inline_preview")
    local buf = vim.api.nvim_create_buf(false, true)
    local state = {
      grid_bufs = { buf },
      grid_wins = {},
      commit_files = { ["test.lua"] = true },
      preview_generation = 0,
    }
    local original_show_commit_file = git.show_commit_file
    local patch = table.concat({
      "@@ -1 +1,0 @@",
      "-local target = old_value",
      "@@ -10,0 +10 @@",
      "+local target = new_value",
    }, "\r\n")
    git.show_commit_file = function(_, _, _, callback) callback(patch, nil) end

    commit_ui.render_file_preview(state, {
      ns_id = ns_id,
      repo_path = "/tmp/repo",
      sha = "abc123",
      filename = "test.lua",
      is_working_dir = false,
    })

    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.same({ "local target = old_value", "...", "local target = new_value" }, lines)
    local marks = get_marks(buf, ns_id)
    local deletion_range = find_mark(marks, 0, "hl_group", "RaccoonDeleteInline")
    local addition_range = find_mark(marks, 2, "hl_group", "RaccoonAddInline")
    assert.equals(0, deletion_range[3])
    assert.equals(#lines[1], deletion_range[4].end_col)
    assert.equals(0, addition_range[3])
    assert.equals(#lines[3], addition_range[4].end_col)
    for _, mark in ipairs(marks) do assert.not_equals(1, mark[2]) end

    git.show_commit_file = function(_, _, _, callback) callback(nil, "missing") end
    commit_ui.render_file_preview(state, {
      ns_id = ns_id,
      repo_path = "/tmp/repo",
      sha = "abc123",
      filename = "test.lua",
      is_working_dir = false,
    })
    assert.equals(0, #get_marks(buf, ns_id))

    git.show_commit_file = original_show_commit_file
    close_buffer(buf)
  end)

  it("falls back for the whole preview when batch planning fails", function()
    local ns_id = vim.api.nvim_create_namespace("raccoon_test_commit_inline_preview_fallback")
    local buf = vim.api.nvim_create_buf(false, true)
    local state = {
      grid_bufs = { buf },
      grid_wins = {},
      commit_files = { ["test.lua"] = true },
      preview_generation = 0,
    }
    local original_show_commit_file = git.show_commit_file
    local original_get_inline_range_groups = diff.get_inline_range_groups
    local patch = table.concat({
      "@@ -1 +1 @@",
      "-old one",
      "+new one",
      "@@ -10 +10 @@",
      "-old two",
      "+new two",
    }, "\n")
    git.show_commit_file = function(_, _, _, callback) callback(patch, nil) end
    diff.get_inline_range_groups = function(line_groups)
      assert.equals(2, #line_groups)
      return nil
    end

    local ok, err = pcall(commit_ui.render_file_preview, state, {
      ns_id = ns_id,
      repo_path = "/tmp/repo",
      sha = "abc123",
      filename = "test.lua",
      is_working_dir = false,
    })

    diff.get_inline_range_groups = original_get_inline_range_groups
    git.show_commit_file = original_show_commit_file
    if not ok then
      close_buffer(buf)
      error(err)
    end
    local marks = get_marks(buf, ns_id)
    assert.is_not_nil(find_mark(marks, 0, "line_hl_group", "RaccoonDeleteInline"))
    assert.is_not_nil(find_mark(marks, 1, "line_hl_group", "RaccoonAddInline"))
    assert.is_not_nil(find_mark(marks, 3, "line_hl_group", "RaccoonDeleteInline"))
    assert.is_not_nil(find_mark(marks, 4, "line_hl_group", "RaccoonAddInline"))
    assert.is_nil(find_mark(marks, 0, "hl_group", "RaccoonDeleteInline"))
    assert.is_nil(find_mark(marks, 4, "hl_group", "RaccoonAddInline"))

    close_buffer(buf)
  end)

  it("falls back across every visible commit and local grid cell", function()
    local ns_id = vim.api.nvim_create_namespace("raccoon_test_commit_inline_grid_fallback")
    local bufs = {
      vim.api.nvim_create_buf(false, true),
      vim.api.nvim_create_buf(false, true),
    }
    local first = diff.parse_patch("@@ -1 +1 @@\n-old one\n+new one")[1]
    local second = diff.parse_patch("@@ -1 +1 @@\n-old two\n+new two")[1]
    local state = {
      grid_rows = 1,
      grid_cols = 2,
      current_page = 1,
      grid_bufs = bufs,
      grid_wins = {},
      all_hunks = {
        { hunk = first, filename = "one.lua" },
        { hunk = second, filename = "two.lua" },
      },
    }
    local original_get_inline_range_groups = diff.get_inline_range_groups
    local planning_calls = 0
    diff.get_inline_range_groups = function(line_groups)
      planning_calls = planning_calls + 1
      assert.equals(2, #line_groups)
      return nil
    end

    local ok, err = pcall(commit_ui.render_grid_page, state, ns_id, function() return nil end, 1)
    diff.get_inline_range_groups = original_get_inline_range_groups

    if not ok then
      for _, buf in ipairs(bufs) do close_buffer(buf) end
      error(err)
    end
    assert.equals(1, planning_calls)
    for _, buf in ipairs(bufs) do
      local marks = get_marks(buf, ns_id)
      assert.is_not_nil(find_mark(marks, 0, "line_hl_group", "RaccoonDeleteInline"))
      assert.is_not_nil(find_mark(marks, 1, "line_hl_group", "RaccoonAddInline"))
      assert.is_nil(find_mark(marks, 0, "hl_group", "RaccoonDeleteInline"))
      assert.is_nil(find_mark(marks, 1, "hl_group", "RaccoonAddInline"))
      close_buffer(buf)
    end
  end)

  it("renders maximize spans and clears them when working changes disappear", function()
    local ns_id = vim.api.nvim_create_namespace("raccoon_test_commit_inline_maximize")
    local state = { grid_rows = 1, grid_cols = 1 }
    local original_show_commit_file = git.show_commit_file
    local original_diff_working_dir_file = git.diff_working_dir_file
    local original_get_inline_range_groups = diff.get_inline_range_groups
    local patch = table.concat({
      "@@ -1 +1 @@",
      "-local value = before",
      "+local value = after",
      "@@ -10 +10 @@",
      "-local other = left",
      "+local other = right",
    }, "\n")
    git.show_commit_file = function(_, _, _, callback) callback(patch, nil) end

    commit_ui.open_maximize({
      ns_id = ns_id,
      repo_path = "/tmp/repo",
      sha = "abc123",
      filename = "test.lua",
      commit_message = "change value",
      generation = 1,
      get_generation = function() return 1 end,
      state = state,
      is_working_dir = false,
    })

    assert.is_true(vim.api.nvim_buf_is_valid(state.maximize_buf))
    assert.same({
      "local value = before",
      "local value = after",
      "...",
      "local other = left",
      "local other = right",
    }, vim.api.nvim_buf_get_lines(state.maximize_buf, 0, -1, false))
    local marks = get_marks(state.maximize_buf, ns_id)
    assert.is_not_nil(find_mark(marks, 0, "hl_group", "RaccoonDeleteInline"))
    assert.is_not_nil(find_mark(marks, 1, "hl_group", "RaccoonAddInline"))
    assert.is_not_nil(find_mark(marks, 3, "hl_group", "RaccoonDeleteInline"))
    assert.is_not_nil(find_mark(marks, 4, "hl_group", "RaccoonAddInline"))

    vim.api.nvim_win_set_cursor(state.maximize_win, { 1, 0 })
    local next_change = vim.api.nvim_replace_termcodes("<leader>j", true, false, true)
    vim.api.nvim_feedkeys(next_change, "x", false)
    assert.equals(4, vim.api.nvim_win_get_cursor(state.maximize_win)[1])

    state.maximize_workdir_opts = {
      ns_id = ns_id,
      repo_path = "/tmp/repo",
      filename = "test.lua",
    }
    diff.get_inline_range_groups = function(line_groups)
      assert.equals(2, #line_groups)
      return nil
    end
    git.diff_working_dir_file = function(_, _, callback)
      callback(table.concat({
        "@@ -1,2 +1,2 @@",
        " context",
        "-old one",
        "+new one",
        "@@ -10 +10 @@",
        "-old two",
        "+new two",
      }, "\n"), nil)
    end
    commit_ui.refresh_maximize(state)
    assert.same({ "context", "old one", "new one", "...", "old two", "new two" },
      vim.api.nvim_buf_get_lines(state.maximize_buf, 0, -1, false))
    marks = get_marks(state.maximize_buf, ns_id)
    assert.is_not_nil(find_mark(marks, 1, "line_hl_group", "RaccoonDeleteInline"))
    assert.is_not_nil(find_mark(marks, 5, "line_hl_group", "RaccoonAddInline"))
    assert.is_nil(find_mark(marks, 1, "hl_group", "RaccoonDeleteInline"))
    assert.is_nil(find_mark(marks, 5, "hl_group", "RaccoonAddInline"))

    vim.api.nvim_win_set_cursor(state.maximize_win, { 2, 0 })
    vim.api.nvim_feedkeys(next_change, "x", false)
    assert.equals(5, vim.api.nvim_win_get_cursor(state.maximize_win)[1])

    local refresh_callbacks = {}
    diff.get_inline_range_groups = original_get_inline_range_groups
    git.diff_working_dir_file = function(_, _, callback)
      table.insert(refresh_callbacks, callback)
    end
    commit_ui.refresh_maximize(state)
    commit_ui.refresh_maximize(state)
    refresh_callbacks[2]("@@ -1 +1 @@\n-second\n+latest", nil)
    refresh_callbacks[1]("@@ -1 +1 @@\n-first\n+stale", nil)
    assert.same({ "second", "latest" },
      vim.api.nvim_buf_get_lines(state.maximize_buf, 0, -1, false))

    git.diff_working_dir_file = function(_, _, callback) callback("", nil) end
    commit_ui.refresh_maximize(state)
    assert.equals(0, #get_marks(state.maximize_buf, ns_id))
    assert.same({}, state.maximize_change_starts)

    git.show_commit_file = original_show_commit_file
    git.diff_working_dir_file = original_diff_working_dir_file
    diff.get_inline_range_groups = original_get_inline_range_groups
    commit_ui.close_win_pair(state, "maximize_win", "maximize_buf")
    assert.is_nil(state.maximize_change_starts)
  end)
end)
