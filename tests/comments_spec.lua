local comments = require("raccoon.comments")
local diff = require("raccoon.diff")
local state = require("raccoon.state")

describe("raccoon.comments", function()
  before_each(function()
    state.reset()
  end)

  describe("get_namespace", function()
    it("returns a namespace ID", function()
      local ns = comments.get_namespace()
      assert.is_number(ns)
      assert.is_true(ns > 0)
    end)
  end)

  describe("basic guards", function()
    it("returns empty buffer comments without an active session", function()
      assert.same({}, comments.get_buffer_comments())
    end)

    it("has no unsent text when no editor is open", function()
      assert.is_false(comments.has_unsent_text())
    end)
  end)

  describe("flat diff mode helpers", function()
    it("reports flat diff mode only for an active non-commit review session", function()
      assert.is_false(comments.is_flat_diff_mode())

      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = "/tmp/repo",
      })
      assert.is_true(comments.is_flat_diff_mode())

      state.set_commit_mode(true)
      assert.is_false(comments.is_flat_diff_mode())
    end)
  end)

  describe("buffer safety", function()
    it("ignores invalid buffers when showing comments", function()
      comments.show_comments(-1, {})
    end)

    it("ignores invalid buffers when clearing comments", function()
      comments.clear_comments(-1)
    end)
  end)

  it("reports failed file navigation when the target cannot be opened", function()
    state.start({
      owner = "test",
      repo = "repo",
      number = 1,
      url = "https://github.com/test/repo/pull/1",
      clone_path = "/tmp/repo",
    })
    state.set_files({ { filename = "missing.lua", patch = "@@ -1 +1 @@\n-old\n+new" } })
    local original_open_file = diff.open_file
    diff.open_file = function() return nil end

    local opened = comments.jump_to_file("missing.lua")

    diff.open_file = original_open_file
    assert.is_false(opened)
  end)
end)
