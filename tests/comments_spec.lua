local comments = require("raccoon.comments")
local state = require("raccoon.state")

describe("raccoon.comments", function()
  before_each(function()
    state.reset()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(comments)
    end)

    it("has show_comments function", function()
      assert.is_function(comments.show_comments)
    end)

    it("has clear_comments function", function()
      assert.is_function(comments.clear_comments)
    end)

    it("has get_buffer_comments function", function()
      assert.is_function(comments.get_buffer_comments)
    end)

    it("has find_next_comment function", function()
      assert.is_function(comments.find_next_comment)
    end)

    it("has find_prev_comment function", function()
      assert.is_function(comments.find_prev_comment)
    end)

    it("has next_comment function", function()
      assert.is_function(comments.next_comment)
    end)

    it("has prev_comment function", function()
      assert.is_function(comments.prev_comment)
    end)

    it("has show_comment_popup function", function()
      assert.is_function(comments.show_comment_popup)
    end)

    it("has create_comment function", function()
      assert.is_function(comments.create_comment)
    end)

    it("has list_comments function", function()
      assert.is_function(comments.list_comments)
    end)

    it("has toggle_resolved function", function()
      assert.is_function(comments.toggle_resolved)
    end)

    it("has get_pending_comments function", function()
      assert.is_function(comments.get_pending_comments)
    end)

    it("has submit_comments function", function()
      assert.is_function(comments.submit_comments)
    end)

    it("has get_namespace function", function()
      assert.is_function(comments.get_namespace)
    end)

    it("has show_readonly_thread function", function()
      assert.is_function(comments.show_readonly_thread)
    end)
  end)

  describe("get_namespace", function()
    it("returns a namespace ID", function()
      local ns = comments.get_namespace()
      assert.is_number(ns)
      assert.is_true(ns > 0)
    end)
  end)

  describe("get_buffer_comments", function()
    it("returns empty array when no session", function()
      local result = comments.get_buffer_comments()
      assert.is_table(result)
      assert.equals(0, #result)
    end)
  end)

  describe("find_next_comment", function()
    it("returns nil when no comments", function()
      local comment, line = comments.find_next_comment()
      assert.is_nil(comment)
      assert.is_nil(line)
    end)
  end)

  describe("find_prev_comment", function()
    it("returns nil when no comments", function()
      local comment, line = comments.find_prev_comment()
      assert.is_nil(comment)
      assert.is_nil(line)
    end)
  end)

  describe("get_pending_comments", function()
    it("returns empty array when no session", function()
      local pending = comments.get_pending_comments()
      assert.is_table(pending)
      assert.equals(0, #pending)
    end)

    it("returns empty array when no pending comments", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_files({ { filename = "test.lua" } })
      state.set_comments("test.lua", {
        { line = 1, body = "not pending", pending = false },
      })

      local pending = comments.get_pending_comments()
      assert.is_table(pending)
      assert.equals(0, #pending)
    end)

    it("returns pending comments", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_files({ { filename = "test.lua" } })
      state.set_comments("test.lua", {
        { line = 1, body = "pending comment", pending = true },
        { line = 2, body = "not pending", pending = false },
        { line = 3, body = "another pending", pending = true },
      })

      local pending = comments.get_pending_comments()
      assert.is_table(pending)
      assert.equals(2, #pending)
    end)
  end)

  describe("show_comments", function()
    it("handles nil buffer", function()
      -- Should not error
      comments.show_comments(nil, {})
    end)

    it("handles invalid buffer", function()
      -- Should not error
      comments.show_comments(-1, {})
    end)

    it("handles nil comments", function()
      local buf = vim.api.nvim_create_buf(false, true)
      -- Should not error
      comments.show_comments(buf, nil)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles empty comments", function()
      local buf = vim.api.nvim_create_buf(false, true)
      -- Should not error
      comments.show_comments(buf, {})
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("clear_comments", function()
    it("handles nil buffer", function()
      -- Should not error
      comments.clear_comments(nil)
    end)

    it("handles invalid buffer", function()
      -- Should not error
      comments.clear_comments(-1)
    end)
  end)

  describe("create_comment", function()
    it("warns when no active session", function()
      -- Should not error, just warn
      comments.create_comment()
    end)
  end)
end)

-- Comment navigation tests with actual data
describe("raccoon.comments navigation", function()
  local mock_comments = {
    { id = 1, path = "src/main.lua", line = 10, body = "Fix this", user = { login = "reviewer1" } },
    { id = 2, path = "src/main.lua", line = 25, body = "Also here", user = { login = "reviewer1" } },
    { id = 3, path = "src/main.lua", line = 50, body = "Third comment", user = { login = "reviewer2" } },
  }

  before_each(function()
    state.reset()
    state.start({
      owner = "test",
      repo = "test",
      number = 1,
      url = "https://github.com/test/test/pull/1",
      clone_path = "/tmp/test",
    })
    state.set_files({
      { filename = "src/main.lua", status = "modified" },
    })
    state.set_comments("src/main.lua", mock_comments)
  end)

  after_each(function()
    state.reset()
  end)

  describe("get_buffer_comments with data", function()
    it("returns comments for current file", function()
      -- State starts at file index 1 by default
      local file_comments = state.get_comments("src/main.lua")
      assert.equals(3, #file_comments)
    end)

    it("returns comments sorted by line", function()
      local file_comments = state.get_comments("src/main.lua")
      assert.equals(10, file_comments[1].line)
      assert.equals(25, file_comments[2].line)
      assert.equals(50, file_comments[3].line)
    end)

    it("returns empty for non-existent file", function()
      local file_comments = state.get_comments("nonexistent.lua")
      assert.is_table(file_comments)
      assert.equals(0, #file_comments)
    end)
  end)

  describe("comment count tracking", function()
    it("counts comments per file", function()
      local file_comments = state.get_comments("src/main.lua")
      assert.equals(3, #file_comments)
    end)

    it("can add more comments", function()
      local file_comments = state.get_comments("src/main.lua")
      table.insert(file_comments, {
        id = 4,
        path = "src/main.lua",
        line = 100,
        body = "New comment",
        user = { login = "reviewer3" },
      })
      state.set_comments("src/main.lua", file_comments)

      local updated = state.get_comments("src/main.lua")
      assert.equals(4, #updated)
    end)

    it("can clear comments for file", function()
      state.set_comments("src/main.lua", {})
      local file_comments = state.get_comments("src/main.lua")
      assert.equals(0, #file_comments)
    end)
  end)
end)

-- Multi-file comment tests
describe("raccoon.comments multi-file", function()
  before_each(function()
    state.reset()
    state.start({
      owner = "test",
      repo = "test",
      number = 1,
      url = "https://github.com/test/test/pull/1",
      clone_path = "/tmp/test",
    })
    state.set_files({
      { filename = "src/main.lua", status = "modified" },
      { filename = "src/utils.lua", status = "added" },
      { filename = "tests/test.lua", status = "modified" },
    })
    state.set_comments("src/main.lua", {
      { id = 1, path = "src/main.lua", line = 10, body = "Main comment 1" },
      { id = 2, path = "src/main.lua", line = 20, body = "Main comment 2" },
    })
    state.set_comments("src/utils.lua", {
      { id = 3, path = "src/utils.lua", line = 5, body = "Utils comment" },
    })
    -- tests/test.lua has no comments
  end)

  after_each(function()
    state.reset()
  end)

  describe("comments across files", function()
    it("tracks comments per file independently", function()
      local main_comments = state.get_comments("src/main.lua")
      local utils_comments = state.get_comments("src/utils.lua")
      local test_comments = state.get_comments("tests/test.lua")

      assert.equals(2, #main_comments)
      assert.equals(1, #utils_comments)
      assert.equals(0, #test_comments)
    end)

    it("file index is tracked", function()
      -- State starts at file index 1 by default
      assert.equals(1, state.get_current_file_index())

      -- Navigate to next file
      state.next_file()
      assert.equals(2, state.get_current_file_index())
    end)

    it("can get current file", function()
      -- State starts at file index 1 by default
      local file = state.get_current_file()
      assert.equals("src/main.lua", file.filename)
    end)
  end)

  describe("pending comments tracking", function()
    it("pending flag defaults to false", function()
      local main_comments = state.get_comments("src/main.lua")
      for _, comment in ipairs(main_comments) do
        -- Comments from API don't have pending flag
        assert.is_nil(comment.pending)
      end
    end)

    it("can mark comments as pending", function()
      local main_comments = state.get_comments("src/main.lua")
      main_comments[1].pending = true
      state.set_comments("src/main.lua", main_comments)

      local pending = comments.get_pending_comments()
      assert.equals(1, #pending)
      -- get_pending_comments returns simplified objects with path, line, body
      assert.equals("src/main.lua", pending[1].path)
      assert.equals(10, pending[1].line)
    end)
  end)
end)

-- Comment edge cases
describe("raccoon.comments edge cases", function()
  before_each(function()
    state.reset()
  end)

  describe("empty state handling", function()
    it("get_pending_comments returns empty when no files", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({})

      local pending = comments.get_pending_comments()
      assert.equals(0, #pending)
    end)

    it("handles file with nil comments", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({ { filename = "test.lua" } })
      -- Don't set comments for file

      local file_comments = state.get_comments("test.lua")
      assert.is_table(file_comments)
      assert.equals(0, #file_comments)
    end)
  end)

  describe("comment body content", function()
    it("handles empty comment body", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({ { filename = "test.lua" } })
      state.set_comments("test.lua", {
        { id = 1, path = "test.lua", line = 1, body = "" },
      })

      local file_comments = state.get_comments("test.lua")
      assert.equals(1, #file_comments)
      assert.equals("", file_comments[1].body)
    end)

    it("handles multiline comment body", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({ { filename = "test.lua" } })
      local multiline = "Line 1\nLine 2\nLine 3"
      state.set_comments("test.lua", {
        { id = 1, path = "test.lua", line = 1, body = multiline },
      })

      local file_comments = state.get_comments("test.lua")
      assert.equals(multiline, file_comments[1].body)
    end)

    it("handles unicode in comment body", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({ { filename = "test.lua" } })
      local unicode = "Great work! 🎉 日本語テスト"
      state.set_comments("test.lua", {
        { id = 1, path = "test.lua", line = 1, body = unicode },
      })

      local file_comments = state.get_comments("test.lua")
      assert.equals(unicode, file_comments[1].body)
    end)
  end)

  describe("comment line numbers", function()
    it("handles line 1", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({ { filename = "test.lua" } })
      state.set_comments("test.lua", {
        { id = 1, path = "test.lua", line = 1, body = "First line" },
      })

      local file_comments = state.get_comments("test.lua")
      assert.equals(1, file_comments[1].line)
    end)

    it("handles very large line numbers", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({ { filename = "test.lua" } })
      state.set_comments("test.lua", {
        { id = 1, path = "test.lua", line = 99999, body = "Far down" },
      })

      local file_comments = state.get_comments("test.lua")
      assert.equals(99999, file_comments[1].line)
    end)

    it("handles comments with original_line instead of line", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({ { filename = "test.lua" } })
      state.set_comments("test.lua", {
        { id = 1, path = "test.lua", original_line = 42, body = "Outdated comment" },
      })

      local file_comments = state.get_comments("test.lua")
      assert.equals(42, file_comments[1].original_line)
    end)

    it("handles comments with position instead of line", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({ { filename = "test.lua" } })
      state.set_comments("test.lua", {
        { id = 1, path = "test.lua", position = 15, body = "Old API style" },
      })

      local file_comments = state.get_comments("test.lua")
      assert.equals(15, file_comments[1].position)
    end)

    it("handles comments with nil line (vim.NIL from JSON null)", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_files({ { filename = "test.lua" } })
      -- Simulate vim.NIL by using a non-number type
      state.set_comments("test.lua", {
        { id = 1, path = "test.lua", line = vim.NIL, original_line = 30, body = "Outdated" },
      })

      local file_comments = state.get_comments("test.lua")
      -- line is vim.NIL, but original_line should be accessible
      assert.equals(30, file_comments[1].original_line)
    end)
  end)
end)

-- show_readonly_thread tests
describe("raccoon.comments show_readonly_thread", function()
  -- Helper to close all floating windows after each test
  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local config = vim.api.nvim_win_get_config(win)
      if config.relative and config.relative ~= "" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  it("does nothing with nil comments", function()
    local win_count = #vim.api.nvim_list_wins()
    comments.show_readonly_thread({ comments = nil, title = " Test " })
    assert.equals(win_count, #vim.api.nvim_list_wins())
  end)

  it("does nothing with empty comments", function()
    local win_count = #vim.api.nvim_list_wins()
    comments.show_readonly_thread({ comments = {}, title = " Test " })
    assert.equals(win_count, #vim.api.nvim_list_wins())
  end)

  it("opens a floating window for a single comment", function()
    local win_count = #vim.api.nvim_list_wins()
    comments.show_readonly_thread({
      comments = {
        { body = "Hello world", user = { login = "alice" } },
      },
      title = " Thread ",
    })
    assert.equals(win_count + 1, #vim.api.nvim_list_wins())
  end)

  it("renders author header and body", function()
    comments.show_readonly_thread({
      comments = {
        { body = "Fix this bug", user = { login = "bob" } },
      },
      title = " Thread ",
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("@ bob", lines[1])
    assert.equals("", lines[2])
    assert.equals("Fix this bug", lines[3])
  end)

  it("shows pending status", function()
    comments.show_readonly_thread({
      comments = {
        { body = "Draft", user = { login = "alice" }, pending = true },
      },
      title = " Thread ",
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("@ alice [pending]", lines[1])
  end)

  it("shows resolved status", function()
    comments.show_readonly_thread({
      comments = {
        { body = "Done", user = { login = "alice" }, resolved = true },
      },
      title = " Thread ",
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("@ alice [resolved]", lines[1])
  end)

  it("shows review state", function()
    comments.show_readonly_thread({
      comments = {
        { body = "LGTM", user = { login = "alice" }, is_review = true, state = "APPROVED" },
      },
      title = " Review ",
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("@ alice [approved]", lines[1])
  end)

  it("renders multiple comments with dividers", function()
    comments.show_readonly_thread({
      comments = {
        { body = "First", user = { login = "alice" } },
        { body = "Second", user = { login = "bob" } },
      },
      title = " Thread ",
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

    -- First comment
    assert.equals("@ alice", lines[1])
    assert.equals("First", lines[3])

    -- Find divider
    local has_divider = false
    for _, line in ipairs(lines) do
      if line:match("^────") then
        has_divider = true
        break
      end
    end
    assert.is_true(has_divider)

    -- Second comment present
    local has_bob = false
    for _, line in ipairs(lines) do
      if line == "@ bob" then
        has_bob = true
        break
      end
    end
    assert.is_true(has_bob)
  end)

  it("creates a read-only buffer", function()
    comments.show_readonly_thread({
      comments = {
        { body = "Test", user = { login = "alice" } },
      },
      title = " Thread ",
    })

    local buf = vim.api.nvim_get_current_buf()
    assert.is_false(vim.api.nvim_buf_get_option(buf, "modifiable"))
  end)

  it("renders multiline comment body", function()
    comments.show_readonly_thread({
      comments = {
        { body = "Line one\nLine two\nLine three", user = { login = "alice" } },
      },
      title = " Thread ",
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- All three body lines should appear in the buffer
    local found = {}
    for _, line in ipairs(lines) do
      if line == "Line one" or line == "Line two" or line == "Line three" then
        found[line] = true
      end
    end
    assert.is_true(found["Line one"])
    assert.is_true(found["Line two"])
    assert.is_true(found["Line three"])
  end)

  it("handles missing user gracefully", function()
    comments.show_readonly_thread({
      comments = {
        { body = "No user", user = nil },
      },
      title = " Thread ",
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("@ unknown", lines[1])
  end)

  it("handles nil body gracefully", function()
    comments.show_readonly_thread({
      comments = {
        { body = nil, user = { login = "alice" } },
      },
      title = " Thread ",
    })

    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("@ alice", lines[1])
  end)

  it("uses provided title", function()
    comments.show_readonly_thread({
      comments = {
        { body = "Test", user = { login = "alice" } },
      },
      title = " Custom Title ",
    })

    local win = vim.api.nvim_get_current_win()
    local config = vim.api.nvim_win_get_config(win)
    -- nvim_win_get_config returns title as nested table {{text}}
    assert.equals(" Custom Title ", config.title[1][1])
  end)

  it("uses default title when not provided", function()
    comments.show_readonly_thread({
      comments = {
        { body = "Test", user = { login = "alice" } },
      },
    })

    local win = vim.api.nvim_get_current_win()
    local config = vim.api.nvim_win_get_config(win)
    assert.equals(" Thread ", config.title[1][1])
  end)

  it("closes on q keypress", function()
    comments.show_readonly_thread({
      comments = {
        { body = "Test", user = { login = "alice" } },
      },
      title = " Thread ",
    })

    local win_count = #vim.api.nvim_list_wins()
    -- Simulate pressing q
    vim.api.nvim_feedkeys("q", "x", false)
    assert.equals(win_count - 1, #vim.api.nvim_list_wins())
  end)
end)
