local state = require("raccoon.state")

describe("raccoon.state", function()
  before_each(function()
    state.reset()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(state)
    end)

    it("has session table", function()
      assert.is_table(state.session)
    end)

    it("has reset function", function()
      assert.is_function(state.reset)
    end)

    it("has start function", function()
      assert.is_function(state.start)
    end)

    it("has stop function", function()
      assert.is_function(state.stop)
    end)

    it("has is_active function", function()
      assert.is_function(state.is_active)
    end)
  end)

  describe("reset", function()
    it("resets session to initial state", function()
      state.session.active = true
      state.session.owner = "test"

      state.reset()

      assert.is_false(state.session.active)
      assert.is_nil(state.session.owner)
      assert.is_nil(state.session.pr)
      assert.equals(1, state.session.current_file)
    end)
  end)

  describe("start", function()
    it("starts a new session with options", function()
      state.start({
        owner = "test-owner",
        repo = "test-repo",
        number = 123,
        url = "https://github.com/test-owner/test-repo/pull/123",
        clone_path = "/tmp/test",
      })

      assert.is_true(state.session.active)
      assert.equals("test-owner", state.session.owner)
      assert.equals("test-repo", state.session.repo)
      assert.equals(123, state.session.number)
      assert.equals("/tmp/test", state.session.clone_path)
    end)
  end)

  describe("is_active", function()
    it("returns false when no session", function()
      assert.is_false(state.is_active())
    end)

    it("returns true when session is active", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      assert.is_true(state.is_active())
    end)
  end)

  describe("files", function()
    it("get_files returns empty array initially", function()
      local files = state.get_files()
      assert.is_table(files)
      assert.equals(0, #files)
    end)

    it("set_files and get_files work", function()
      local files = {
        { filename = "a.lua" },
        { filename = "b.lua" },
      }
      state.set_files(files)
      assert.equals(2, #state.get_files())
    end)

    it("get_current_file returns nil when no files", function()
      assert.is_nil(state.get_current_file())
    end)

    it("get_current_file returns first file", function()
      state.set_files({
        { filename = "first.lua" },
        { filename = "second.lua" },
      })
      local file = state.get_current_file()
      assert.is_not_nil(file)
      assert.equals("first.lua", file.filename)
    end)
  end)

  describe("navigation", function()
    before_each(function()
      state.set_files({
        { filename = "a.lua" },
        { filename = "b.lua" },
        { filename = "c.lua" },
      })
    end)

    it("next_file advances to next file", function()
      assert.equals(1, state.get_current_file_index())
      assert.is_true(state.next_file())
      assert.equals(2, state.get_current_file_index())
    end)

    it("next_file returns false at end", function()
      state.session.current_file = 3
      assert.is_false(state.next_file())
      assert.equals(3, state.get_current_file_index())
    end)

    it("prev_file goes to previous file", function()
      state.session.current_file = 3
      assert.is_true(state.prev_file())
      assert.equals(2, state.get_current_file_index())
    end)

    it("prev_file returns false at beginning", function()
      assert.equals(1, state.get_current_file_index())
      assert.is_false(state.prev_file())
      assert.equals(1, state.get_current_file_index())
    end)
  end)

  describe("comments", function()
    it("get_comments returns empty array for unknown file", function()
      local comments = state.get_comments("unknown.lua")
      assert.is_table(comments)
      assert.equals(0, #comments)
    end)

    it("set_comments and get_comments work", function()
      local comments = {
        { id = 1, body = "test" },
        { id = 2, body = "test2" },
      }
      state.set_comments("test.lua", comments)
      assert.equals(2, #state.get_comments("test.lua"))
    end)
  end)

  describe("getters", function()
    before_each(function()
      state.start({
        owner = "test-owner",
        repo = "test-repo",
        number = 456,
        clone_path = "/path/to/clone",
      })
    end)

    it("get_owner returns owner", function()
      assert.equals("test-owner", state.get_owner())
    end)

    it("get_repo returns repo", function()
      assert.equals("test-repo", state.get_repo())
    end)

    it("get_number returns number", function()
      assert.equals(456, state.get_number())
    end)

    it("get_clone_path returns clone path", function()
      assert.equals("/path/to/clone", state.get_clone_path())
    end)
  end)
end)
