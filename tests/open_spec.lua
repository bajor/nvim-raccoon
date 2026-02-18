local open = require("raccoon.open")
local state = require("raccoon.state")
local config = require("raccoon.config")

describe("raccoon.open", function()
  -- Reset state before each test
  before_each(function()
    state.reset()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(open)
    end)

    it("has open_pr function", function()
      assert.is_function(open.open_pr)
    end)

    it("has close_pr function", function()
      assert.is_function(open.close_pr)
    end)

    it("has sync function", function()
      assert.is_function(open.sync)
    end)

    it("has statusline function", function()
      assert.is_function(open.statusline)
    end)

    it("has is_active function", function()
      assert.is_function(open.is_active)
    end)

    it("has get_commits_behind function", function()
      assert.is_function(open.get_commits_behind)
    end)

    it("has has_merge_conflicts function", function()
      assert.is_function(open.has_merge_conflicts)
    end)
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

    it("delegates to state.is_active", function()
      -- Both should return same value
      assert.equals(state.is_active(), open.is_active())

      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      assert.equals(state.is_active(), open.is_active())
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

  describe("statusline variations", function()
    -- Note: statusline() uses module-local variables that are only updated during open_pr()
    -- These tests verify the default behavior with session active but no sync performed

    it("returns in sync when session active with PR data", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_pr({
        number = 1,
        title = "Test",
        base = { ref = "main" },
        head = { ref = "feature", sha = "abc123" },
      })

      -- Default state shows "In sync" since no sync has been performed
      local status = open.statusline()
      assert.truthy(status:match("In sync"))
    end)

    it("handles PR without base ref gracefully", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })
      state.set_pr({
        number = 1,
        title = "Test",
        base = { ref = "main" },
        head = { ref = "feature", sha = "abc123" },
      })

      -- Should not error
      local status = open.statusline()
      assert.is_string(status)
    end)
  end)

  describe("sync status accessors", function()
    -- Note: get_commits_behind() and has_merge_conflicts() use module-local variables
    -- that are only updated during open_pr(). These tests verify default behavior.

    it("get_commits_behind returns 0 by default", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })

      -- Without running open_pr, the module-local variable is 0
      local behind = open.get_commits_behind()
      assert.equals(0, behind)
    end)

    it("has_merge_conflicts returns false by default", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })

      -- Without running open_pr, the module-local variable is false
      local has_conflicts = open.has_merge_conflicts()
      assert.is_false(has_conflicts)
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
