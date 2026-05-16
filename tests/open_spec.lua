local open = require("raccoon.open")
local state = require("raccoon.state")
local config = require("raccoon.config")
local api = require("raccoon.api")
local comments = require("raccoon.comments")
local commits = require("raccoon.commits")
local git = require("raccoon.git")

describe("raccoon.open", function()
  -- Reset state before each test
  before_each(function()
    state.reset()
    commits.clear_mode_restore_state()
  end)

  after_each(function()
    commits.clear_mode_restore_state()
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
      assert.equals("IN SYNC", status)
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
      vim.notify = function(_msg, level)
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

    it("blocks close when commit mode is hiding an unsent draft", function()
      state.start({
        owner = "test",
        repo = "test",
        number = 1,
        url = "https://github.com/test/test/pull/1",
        clone_path = "/tmp/test",
      })

      commits._set_mode_restore_state({
        session_key = state.get_url(),
        overlay = {
          kind = "editor",
          input_lines = { "hidden draft" },
        },
      }, nil)

      local notify_msg = nil
      local original_notify = vim.notify
      vim.notify = function(msg)
        notify_msg = msg
      end

      open.close_pr()

      vim.notify = original_notify

      assert.is_true(state.is_active())
      assert.equals("Cannot close review with unsent text; clear it or send it first", notify_msg)
    end)
  end)

  describe("sync", function()
    it("does nothing when no active session", function()
      -- Should not error
      open.sync()
    end)

    it("closes and restores a new-thread draft during manual sync without sending it", function()
      local clone_path = "/tmp/raccoon-open-sync"
      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = clone_path,
      })
      state.set_pr({
        number = 1,
        title = "Test PR",
        head = { ref = "feature", sha = "oldsha" },
        base = { ref = "main" },
      })
      state.set_files({
        {
          filename = "lua/a.lua",
          patch = "@@ -1,2 +1,3 @@\n line 1\n+line 2\n line 3",
        },
      })

      local file_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(file_buf, clone_path .. "/lua/a.lua")
      vim.api.nvim_buf_set_lines(file_buf, 0, -1, false, {
        "line 1",
        "line 2",
        "line 3",
      })
      vim.api.nvim_set_current_buf(file_buf)
      vim.api.nvim_win_set_cursor(0, { 2, 0 })

      comments.show_comment_thread()
      local editor_buf = vim.api.nvim_get_current_buf()
      local line_count = vim.api.nvim_buf_line_count(editor_buf)
      vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "draft new thread" })

      local original_notify = vim.notify
      local original_config_load = config.load
      local original_get_token_entry = config.get_token_entry
      local original_api_init = api.init
      local original_get_pr = api.get_pr
      local original_get_pr_files = api.get_pr_files
      local original_get_pr_comments = api.get_pr_comments
      local original_get_issue_comments = api.get_issue_comments
      local original_get_pr_reviews = api.get_pr_reviews
      local original_get_pr_review_threads = api.get_pr_review_threads
      local original_create_comment = api.create_comment
      local original_fetch_reset = git.fetch_reset
      local original_update_base_branch = git.update_base_branch

      local saw_unsent_text_during_fetch = nil
      local create_comment_called = false

      vim.notify = function() end
      config.load = function()
        return {
          github_host = "github.com",
          tokens = {
            test = "ghp_fake",
          },
        }, nil
      end
      config.get_token_entry = function()
        return { token = "ghp_fake" }
      end
      api.init = function() end
      api.get_pr = function(_owner, _repo, _number, _token, callback)
        callback({
          number = 1,
          title = "Test PR",
          head = { ref = "feature", sha = "newsha" },
          base = { ref = "main" },
        }, nil)
      end
      api.get_pr_files = function(_owner, _repo, _number, _token, callback)
        callback({
          {
            filename = "lua/a.lua",
            patch = "@@ -1,2 +1,3 @@\n line 1\n+line 2\n line 3",
          },
        }, nil)
      end
      api.get_pr_comments = function(_owner, _repo, _number, _token, callback)
        callback({}, nil)
      end
      api.get_issue_comments = function(_owner, _repo, _number, _token, callback)
        callback({}, nil)
      end
      api.get_pr_reviews = function(_owner, _repo, _number, _token, callback)
        callback({}, nil)
      end
      api.get_pr_review_threads = function(_owner, _repo, _number, _token, callback)
        callback({}, nil)
      end
      api.create_comment = function()
        create_comment_called = true
      end
      git.fetch_reset = function(_clone_path, _branch, _repo_url, callback)
        saw_unsent_text_during_fetch = comments.has_unsent_text()
        callback(true, nil)
      end
      git.update_base_branch = function(_clone_path, _base_branch, callback)
        callback(true, nil)
      end

      open.sync()

      vim.notify = original_notify
      config.load = original_config_load
      config.get_token_entry = original_get_token_entry
      api.init = original_api_init
      api.get_pr = original_get_pr
      api.get_pr_files = original_get_pr_files
      api.get_pr_comments = original_get_pr_comments
      api.get_issue_comments = original_get_issue_comments
      api.get_pr_reviews = original_get_pr_reviews
      api.get_pr_review_threads = original_get_pr_review_threads
      api.create_comment = original_create_comment
      git.fetch_reset = original_fetch_reset
      git.update_base_branch = original_update_base_branch

      assert.is_false(saw_unsent_text_during_fetch)
      assert.is_false(create_comment_called)

      local snapshot = comments.capture_ui_state()
      assert.equals("editor", snapshot.kind)
      assert.equals("new_thread", snapshot.editor_kind)
      assert.same({ "draft new thread" }, snapshot.input_lines)
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
