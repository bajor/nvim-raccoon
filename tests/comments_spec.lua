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
  end)
end)
