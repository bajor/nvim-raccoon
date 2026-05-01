local open = require("raccoon.open")
local state = require("raccoon.state")
local config = require("raccoon.config")

describe("raccoon.open", function()
  -- Reset state before each test
  before_each(function()
    state.reset()
  end)


  describe("get_commits_behind", function()
    it("returns 0 when no session active", function()
      local behind = open.get_commits_behind()
      assert.equals(0, behind)
    end)

    it("returns 0 initially after starting session", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      local behind = open.get_commits_behind()
      assert.equals(0, behind)
    end)
  end)

  describe("has_merge_conflicts", function()
    it("returns false when no session active", function()
      local has_conflicts = open.has_merge_conflicts()
      assert.is_false(has_conflicts)
    end)

    it("returns false initially after starting session", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      local has_conflicts = open.has_merge_conflicts()
      assert.is_false(has_conflicts)
    end)
  end)

  describe("statusline", function()
    it("returns empty string when not active", function()
      local status = open.statusline()
      assert.equals("", status)
    end)

    it("returns in sync message when active with no issues", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })

      -- Set up minimal PR data
      state.set_pr({
        number = 1,
        title = "Test",
        base = { ref = "main" },
        head = { ref = "feature", sha = "abc123" },
      })

      local status = open.statusline()
      assert.equals("✓ In sync", status)
    end)

    it("returns empty when PR not set", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })

      -- PR not set
      local status = open.statusline()
      assert.equals("", status)
    end)
  end)

  describe("is_active", function()
    it("returns false when no session", function()
      assert.is_false(open.is_active())
    end)

    it("returns true when session active", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      assert.is_true(open.is_active())
    end)

  end)

  describe("close_pr", function()
    it("shows warning when no active session", function()
      -- Capture vim.notify calls
      local notify_called = false
      local notify_level = nil
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        notify_called = true
        notify_level = level
      end

      open.close_pr()

      vim.notify = original_notify

      assert.is_true(notify_called)
      assert.equals(vim.log.levels.WARN, notify_level)
    end)

    it("clears state when session active", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })

      assert.is_true(state.is_active())

      -- Mock vim.notify to avoid output
      local original_notify = vim.notify
      vim.notify = function() end

      open.close_pr()

      vim.notify = original_notify

      assert.is_false(state.is_active())
    end)

    it("notifies user on close", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })

      local notify_msg = nil
      local original_notify = vim.notify
      vim.notify = function(msg)
        notify_msg = msg
      end

      open.close_pr()

      vim.notify = original_notify

      assert.is_not_nil(notify_msg)
      assert.truthy(notify_msg:match("closed"))
    end)

    it("supports silent_success option", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })

      local notify_called = false
      local original_notify = vim.notify
      vim.notify = function()
        notify_called = true
      end

      open.close_pr({ silent_success = true })

      vim.notify = original_notify
      assert.is_false(notify_called)
    end)
  end)

  describe("close_all_sessions", function()
    local original_localcommits
    local original_commits
    local original_parallel_agents
    local original_ui

    before_each(function()
      original_localcommits = package.loaded["raccoon.localcommits"]
      original_commits = package.loaded["raccoon.commits"]
      original_parallel_agents = package.loaded["raccoon.parallel_agents"]
      original_ui = package.loaded["raccoon.ui"]
    end)

    after_each(function()
      package.loaded["raccoon.localcommits"] = original_localcommits
      package.loaded["raccoon.commits"] = original_commits
      package.loaded["raccoon.parallel_agents"] = original_parallel_agents
      package.loaded["raccoon.ui"] = original_ui
    end)

    it("warns when nothing is active", function()
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      package.loaded["raccoon.localcommits"] = {
        is_active = function() return false end,
        exit_local_mode = function() error("should not be called") end,
      }
      package.loaded["raccoon.commits"] = {
        exit_commit_mode = function() error("should not be called") end,
      }
      package.loaded["raccoon.parallel_agents"] = {
        get_running_count = function() return 0 end,
        kill_all = function() return { requested = 0, stopped = 0, errors = {} } end,
      }
      package.loaded["raccoon.ui"] = {
        has_open_windows = function() return false end,
        close_all_windows = function() error("should not be called") end,
      }

      local did_exit = open.close_all_sessions()
      vim.notify = original_notify

      assert.is_false(did_exit)
      assert.equals(1, #notifications)
      assert.equals(vim.log.levels.WARN, notifications[1].level)
      assert.truthy(notifications[1].msg:find("Nothing to exit", 1, true))
    end)

    it("kills agents and tears down active modes", function()
      local local_exit_calls = 0
      local commit_exit_calls = 0
      local close_windows_calls = 0
      local kill_calls = 0
      local closed_pr = 0

      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_commit_mode(true)

      package.loaded["raccoon.localcommits"] = {
        is_active = function() return true end,
        exit_local_mode = function(opts)
          local_exit_calls = local_exit_calls + 1
          assert.is_false(opts.resume_pr)
          assert.is_true(opts.silent)
        end,
      }
      package.loaded["raccoon.commits"] = {
        exit_commit_mode = function(opts)
          commit_exit_calls = commit_exit_calls + 1
          assert.is_false(opts.resume_sync)
          assert.is_true(opts.silent)
        end,
      }
      package.loaded["raccoon.parallel_agents"] = {
        get_running_count = function() return 2 end,
        kill_all = function()
          kill_calls = kill_calls + 1
          return { requested = 2, stopped = 2, errors = {} }
        end,
      }
      package.loaded["raccoon.ui"] = {
        has_open_windows = function() return true end,
        close_all_windows = function()
          close_windows_calls = close_windows_calls + 1
        end,
      }

      local original_close_pr = open.close_pr
      open.close_pr = function(opts)
        closed_pr = closed_pr + 1
        assert.is_true(opts.silent_success)
        assert.is_true(opts.suppress_empty_warning)
        state.stop()
        return true
      end

      local did_exit = open.close_all_sessions()
      open.close_pr = original_close_pr

      assert.is_true(did_exit)
      assert.equals(1, kill_calls)
      assert.equals(1, local_exit_calls)
      assert.equals(1, commit_exit_calls)
      assert.equals(1, closed_pr)
      assert.equals(1, close_windows_calls)
    end)

    it("resets exit guard when teardown raises", function()
      local notifications = {}
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        table.insert(notifications, { msg = msg, level = level })
      end

      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })

      package.loaded["raccoon.localcommits"] = {
        is_active = function() return false end,
        exit_local_mode = function() error("should not be called") end,
      }
      package.loaded["raccoon.commits"] = {
        exit_commit_mode = function() error("should not be called") end,
      }
      package.loaded["raccoon.parallel_agents"] = {
        get_running_count = function() return 0 end,
        kill_all = function() return { requested = 0, stopped = 0, errors = {} } end,
      }
      package.loaded["raccoon.ui"] = {
        has_open_windows = function() return false end,
        close_all_windows = function()
          error("boom")
        end,
      }

      local original_close_pr = open.close_pr
      open.close_pr = function()
        state.stop()
        return true
      end

      local first_exit = open.close_all_sessions()
      assert.is_false(first_exit)

      package.loaded["raccoon.ui"] = {
        has_open_windows = function() return false end,
        close_all_windows = function() end,
      }

      local second_exit = open.close_all_sessions()
      open.close_pr = original_close_pr
      vim.notify = original_notify

      assert.is_false(second_exit)

      local saw_exit_error = false
      local saw_nothing_warning = false
      for _, note in ipairs(notifications) do
        if note.level == vim.log.levels.ERROR and note.msg:find("Raccoon exit failed", 1, true) then
          saw_exit_error = true
        end
        if note.level == vim.log.levels.WARN and note.msg:find("Nothing to exit", 1, true) then
          saw_nothing_warning = true
        end
      end

      assert.is_true(saw_exit_error)
      assert.is_true(saw_nothing_warning)
    end)
  end)

  describe("sync", function()
    it("does nothing when no active session", function()
      -- Should not error
      open.sync()
    end)
  end)
end)

-- Edge case tests
describe("raccoon.open edge cases", function()
  local original_config_path
  local test_config_path = "/tmp/claude/raccoon-tests/open_test_config.json"

  before_each(function()
    state.reset()
    original_config_path = config.config_path
    vim.fn.mkdir("/tmp/claude/raccoon-tests", "p")
    local f = io.open(test_config_path, "w")
    f:write('{"tokens":{"test":"ghp_fake"}}')
    f:close()
    config.config_path = test_config_path
  end)

  after_each(function()
    config.config_path = original_config_path
    os.remove(test_config_path)
  end)

  describe("open_pr", function()
    it("handles invalid URL", function()
      -- Capture vim.notify error
      local error_msg = nil
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR then
          error_msg = msg
        end
      end

      open.open_pr("not-a-valid-url")

      vim.notify = original_notify

      assert.is_not_nil(error_msg)
      assert.truthy(error_msg:match("Invalid"))
    end)

    it("handles empty URL", function()
      local error_msg = nil
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR then
          error_msg = msg
        end
      end

      open.open_pr("")

      vim.notify = original_notify

      assert.is_not_nil(error_msg)
    end)

    it("handles GitHub issues URL (not PR)", function()
      local error_msg = nil
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR then
          error_msg = msg
        end
      end

      open.open_pr("https://github.com/owner/repo/issues/123")

      vim.notify = original_notify

      assert.is_not_nil(error_msg)
      assert.truthy(error_msg:match("Invalid"))
    end)
  end)

  describe("multiple sessions", function()
    it("previous session is closed before opening new one", function()
      state.start({
        owner = "test1",
        repo = "repo1",
        number = 1,
        url = "https://github.com/test1/repo1/pull/1",
        clone_path = "/tmp/test1",
      })

      assert.equals("test1", state.get_owner())

      -- Start new session overwrites
      state.start({
        owner = "test2",
        repo = "repo2",
        number = 2,
        url = "https://github.com/test2/repo2/pull/2",
        clone_path = "/tmp/test2",
      })

      assert.equals("test2", state.get_owner())
      assert.equals(2, state.get_number())
    end)
  end)



  describe("URL parsing", function()
    it("rejects GitLab URLs", function()
      local error_msg = nil
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR then
          error_msg = msg
        end
      end

      open.open_pr("https://gitlab.com/owner/repo/merge_requests/123")

      vim.notify = original_notify
      assert.is_not_nil(error_msg)
    end)

    it("rejects commit URLs", function()
      local error_msg = nil
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR then
          error_msg = msg
        end
      end

      open.open_pr("https://github.com/owner/repo/commit/abc123")

      vim.notify = original_notify
      assert.is_not_nil(error_msg)
    end)

    it("rejects branch URLs", function()
      local error_msg = nil
      local original_notify = vim.notify
      vim.notify = function(msg, level)
        if level == vim.log.levels.ERROR then
          error_msg = msg
        end
      end

      open.open_pr("https://github.com/owner/repo/tree/main")

      vim.notify = original_notify
      assert.is_not_nil(error_msg)
    end)
  end)
end)
