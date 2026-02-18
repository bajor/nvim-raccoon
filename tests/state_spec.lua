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

  describe("PR data", function()
    it("set_pr and get_pr work", function()
      local pr = {
        number = 123,
        title = "Test PR",
        body = "PR description",
        head = { ref = "feature-branch", sha = "abc123" },
        base = { ref = "main" },
        user = { login = "testuser" },
      }
      state.set_pr(pr)
      local retrieved = state.get_pr()
      assert.is_not_nil(retrieved)
      assert.equals(123, retrieved.number)
      assert.equals("Test PR", retrieved.title)
      assert.equals("feature-branch", retrieved.head.ref)
    end)

    it("get_pr returns nil when not set", function()
      assert.is_nil(state.get_pr())
    end)
  end)

  describe("buffers", function()
    it("add_buffer adds buffer to session", function()
      assert.equals(0, #state.session.buffers)
      state.add_buffer(1)
      assert.equals(1, #state.session.buffers)
      state.add_buffer(2)
      assert.equals(2, #state.session.buffers)
    end)

    it("add_buffer allows duplicate buffers", function()
      state.add_buffer(1)
      state.add_buffer(1)
      assert.equals(2, #state.session.buffers)
    end)
  end)

  describe("stop", function()
    it("resets session after stop", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        clone_path = "/tmp/test",
      })
      state.set_pr({ title = "Test" })
      state.set_files({ { filename = "test.lua" } })

      state.stop()

      assert.is_false(state.is_active())
      assert.is_nil(state.get_pr())
      assert.equals(0, #state.get_files())
    end)

    it("clears buffers on stop", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      -- Note: We can't easily test buffer deletion without creating real buffers
      -- but we can verify the session is reset
      state.add_buffer(99999) -- fake buffer id
      state.stop()
      assert.equals(0, #state.session.buffers)
    end)
  end)

  describe("sync_status", function()
    it("has default sync status", function()
      local sync = state.get_sync_status()
      assert.is_table(sync)
      assert.equals(0, sync.behind)
      assert.is_false(sync.has_conflicts)
      assert.is_table(sync.conflict_files)
      assert.is_false(sync.checked)
    end)

    it("set_sync_status updates sync status", function()
      local new_status = {
        behind = 5,
        has_conflicts = true,
        conflict_files = { "file1.lua", "file2.lua" },
        checked = true,
      }
      state.set_sync_status(new_status)

      local sync = state.get_sync_status()
      assert.equals(5, sync.behind)
      assert.is_true(sync.has_conflicts)
      assert.equals(2, #sync.conflict_files)
      assert.is_true(sync.checked)
    end)

    it("reset clears sync status", function()
      state.set_sync_status({ behind = 10, has_conflicts = true, checked = true })
      state.reset()

      local sync = state.get_sync_status()
      assert.equals(0, sync.behind)
      assert.is_false(sync.has_conflicts)
      assert.is_false(sync.checked)
    end)
  end)

  describe("get_statusline_component", function()
    it("returns empty string when not active", function()
      assert.equals("", state.get_statusline_component())
    end)

    it("returns empty string when sync not checked", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      assert.equals("", state.get_statusline_component())
    end)

    it("returns in sync message when up to date", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_sync_status({ behind = 0, has_conflicts = false, checked = true })
      local component = state.get_statusline_component()
      assert.matches("In sync", component)
    end)

    it("shows behind count", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_sync_status({ behind = 3, has_conflicts = false, checked = true })
      local component = state.get_statusline_component()
      assert.matches("3 behind", component)
    end)

    it("shows conflicts warning", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_sync_status({ behind = 0, has_conflicts = true, checked = true })
      local component = state.get_statusline_component()
      assert.matches("CONFLICTS", component)
    end)

    it("shows conflicts instead of behind when both exist", function()
      -- Conflicts take priority - if there are conflicts, behind count is less relevant
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_sync_status({ behind = 2, has_conflicts = true, checked = true })
      local component = state.get_statusline_component()
      assert.matches("CONFLICTS", component)
      -- Behind is not shown when conflicts exist (conflicts take priority)
      assert.not_matches("behind", component)
    end)

    it("shows file count indicator when files exist", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_files({ { filename = "a.lua" }, { filename = "b.lua" }, { filename = "c.lua" } })
      state.set_sync_status({ behind = 0, has_conflicts = false, checked = true })
      local component = state.get_statusline_component()
      assert.matches("%[1/3%]", component)
      assert.matches("In sync", component)
    end)

    it("updates file count when navigating files", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_files({ { filename = "a.lua" }, { filename = "b.lua" } })
      state.set_sync_status({ behind = 0, has_conflicts = false, checked = true })

      state.next_file()
      local component = state.get_statusline_component()
      assert.matches("%[2/2%]", component)
    end)

    it("shows file count with sync warnings", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_files({ { filename = "a.lua" }, { filename = "b.lua" } })
      state.set_sync_status({ behind = 5, has_conflicts = false, checked = true })
      local component = state.get_statusline_component()
      assert.matches("%[1/2%]", component)
      assert.matches("5 behind", component)
    end)

    it("shows no file count when no files", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_sync_status({ behind = 0, has_conflicts = false, checked = true })
      local component = state.get_statusline_component()
      assert.not_matches("%[%d+/%d+%]", component)
      assert.matches("In sync", component)
    end)
  end)

  describe("edge cases", function()
    it("get_current_file returns nil for out of bounds index", function()
      state.set_files({ { filename = "test.lua" } })
      state.session.current_file = 5
      assert.is_nil(state.get_current_file())
    end)

    it("get_current_file returns nil for zero index", function()
      state.set_files({ { filename = "test.lua" } })
      state.session.current_file = 0
      assert.is_nil(state.get_current_file())
    end)

    it("get_current_file returns nil for negative index", function()
      state.set_files({ { filename = "test.lua" } })
      state.session.current_file = -1
      assert.is_nil(state.get_current_file())
    end)

    it("comments for different files are isolated", function()
      state.set_comments("file1.lua", { { id = 1, body = "comment1" } })
      state.set_comments("file2.lua", { { id = 2, body = "comment2" } })

      local comments1 = state.get_comments("file1.lua")
      local comments2 = state.get_comments("file2.lua")

      assert.equals(1, #comments1)
      assert.equals(1, #comments2)
      assert.equals(1, comments1[1].id)
      assert.equals(2, comments2[1].id)
    end)

    it("navigation at boundaries stays in bounds", function()
      state.set_files({ { filename = "only.lua" } })

      -- Try to go prev from first (should fail)
      assert.is_false(state.prev_file())
      assert.equals(1, state.get_current_file_index())

      -- Try to go next from last (should fail)
      assert.is_false(state.next_file())
      assert.equals(1, state.get_current_file_index())
    end)
  end)

  describe("github_host", function()
    it("defaults to nil", function()
      assert.is_nil(state.get_github_host())
    end)

    it("is set by start()", function()
      state.start({
        owner = "o", repo = "r", number = 1, url = "u",
        github_host = "github.acme.com",
        clone_path = "/tmp",
      })
      assert.equals("github.acme.com", state.get_github_host())
    end)

    it("is cleared by reset()", function()
      state.start({
        owner = "o", repo = "r", number = 1, url = "u",
        github_host = "github.acme.com",
        clone_path = "/tmp",
      })
      state.reset()
      assert.is_nil(state.get_github_host())
    end)
  end)
end)
