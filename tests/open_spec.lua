local open = require("raccoon.open")
local state = require("raccoon.state")
local config = require("raccoon.config")
local api = require("raccoon.api")
local comments = require("raccoon.comments")
local commits = require("raccoon.commits")
local diff = require("raccoon.diff")
local git = require("raccoon.git")
local thread_index = require("raccoon.thread_index")

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

  describe("incomplete GitHub patch recovery", function()
    local original_prepare_pr_diff
    local original_diff_pr_file
    local pr
    local revisions

    before_each(function()
      original_prepare_pr_diff = git.prepare_pr_diff
      original_diff_pr_file = git.diff_pr_file
      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = "/tmp/raccoon-patch-recovery",
      })
      state.set_pr({ base = { ref = "stale" }, head = { ref = "old" } })
      pr = {
        base = { ref = "main", sha = "base-tip" },
        head = { ref = "feature", sha = "head-sha" },
      }
      revisions = { base_sha = "base-sha", head_sha = "head-sha" }
    end)

    after_each(function()
      git.prepare_pr_diff = original_prepare_pr_diff
      git.diff_pr_file = original_diff_pr_file
    end)

    it("prepares once and replaces incomplete patches using immutable revisions", function()
      local files = {
        {
          filename = "lua/a.lua",
          additions = 1,
          deletions = 1,
        },
        {
          filename = "lua/b.lua",
          additions = 1,
          deletions = 1,
        },
      }
      local prepare_calls = 0
      git.prepare_pr_diff = function(path, base_branch, callback, base_revision, head_revision)
        assert.equals("/tmp/raccoon-patch-recovery", path)
        assert.equals("main", base_branch)
        assert.equals("base-tip", base_revision)
        assert.equals("head-sha", head_revision)
        prepare_calls = prepare_calls + 1
        callback(revisions, nil)
      end
      git.diff_pr_file = function(path, prepared, filename, previous_filename, callback)
        assert.equals("/tmp/raccoon-patch-recovery", path)
        assert.equals(revisions, prepared)
        assert.is_nil(previous_filename)
        callback("@@ -1 +1 @@\n-old\n+new", nil)
      end

      local unavailable
      open._recover_incomplete_patches(pr, files, function(result) unavailable = result end)

      assert.same({}, unavailable)
      assert.equals(1, prepare_calls)
      assert.is_true(require("raccoon.diff").is_file_patch_complete(files[1]))
      assert.is_true(require("raccoon.diff").is_file_patch_complete(files[2]))
    end)

    it("passes both paths when recovering a renamed file", function()
      local file = {
        filename = "lua/new.lua",
        previous_filename = "lua/old.lua",
        status = "renamed",
        additions = 1,
        deletions = 1,
      }
      git.prepare_pr_diff = function(_, _, callback) callback(revisions, nil) end
      git.diff_pr_file = function(_, prepared, filename, previous_filename, callback)
        assert.equals(revisions, prepared)
        assert.equals("lua/new.lua", filename)
        assert.equals("lua/old.lua", previous_filename)
        callback("@@ -1 +1 @@\n-old\n+new", nil)
      end

      local unavailable
      open._recover_incomplete_patches(pr, { file }, function(result) unavailable = result end)

      assert.same({}, unavailable)
      assert.is_nil(file.diff_unavailable)
    end)

    it("isolates one failed recovery and continues with the next file", function()
      local files = {
        { filename = "lua/a.lua", additions = 2, deletions = 2 },
        { filename = "lua/b.lua", additions = 1, deletions = 1 },
      }
      git.prepare_pr_diff = function(_, _, callback) callback(revisions, nil) end
      git.diff_pr_file = function(_, _, filename, _, callback)
        if filename == "lua/a.lua" then
          callback("@@ -1 +1 @@\n-old\n+new", nil)
        else
          callback("@@ -1 +1 @@\n-old\n+new", nil)
        end
      end

      local unavailable
      open._recover_incomplete_patches(pr, files, function(result) unavailable = result end)

      assert.same({ "lua/a.lua" }, unavailable)
      assert.is_true(files[1].diff_unavailable)
      assert.is_nil(files[1].patch)
      assert.is_nil(files[2].diff_unavailable)
      assert.is_true(diff.is_file_patch_complete(files[2]))
    end)

    it("clears every incomplete patch when local preparation fails", function()
      local files = {
        { filename = "lua/a.lua", additions = 1, deletions = 1, patch = "partial" },
        { filename = "lua/b.lua", additions = 1, deletions = 1 },
      }
      local diff_calls = 0
      git.prepare_pr_diff = function(_, _, callback) callback(nil, "missing base") end
      git.diff_pr_file = function() diff_calls = diff_calls + 1 end

      local unavailable
      open._recover_incomplete_patches(pr, files, function(result) unavailable = result end)

      assert.same({ "lua/a.lua", "lua/b.lua" }, unavailable)
      assert.equals(0, diff_calls)
      for _, file in ipairs(files) do
        assert.is_nil(file.patch)
        assert.is_true(file.diff_unavailable)
      end
    end)

    it("keeps complete API patches without preparing the repository", function()
      local file = {
        filename = "lua/a.lua",
        additions = 1,
        deletions = 1,
        patch = "@@ -1 +1 @@\n-old\n+new",
      }
      local prepare_calls = 0
      local git_calls = 0
      git.prepare_pr_diff = function() prepare_calls = prepare_calls + 1 end
      git.diff_pr_file = function() git_calls = git_calls + 1 end

      local unavailable
      open._recover_incomplete_patches(pr, { file }, function(result) unavailable = result end)

      assert.same({}, unavailable)
      assert.equals(0, prepare_calls)
      assert.equals(0, git_calls)
      assert.equals("@@ -1 +1 @@\n-old\n+new", file.patch)
    end)
  end)

  describe("diff availability warnings", function()
    it("reports GitHub's 3000-file response cap", function()
      local files = {}
      for index = 1, 3000 do
        files[index] = { filename = "file-" .. index }
      end
      local payload = { warnings = {} }

      open._append_diff_warnings(payload, { changed_files = 3001 }, files, {})

      assert.same({
        "GitHub returned 3000 of 3001 changed files; the remaining files are unavailable",
      }, payload.warnings)
    end)

    it("names files whose complete patch is unavailable", function()
      local payload = { warnings = {} }

      open._append_diff_warnings(payload, { changed_files = 2 }, {
        { filename = "lua/a.lua" },
        { filename = "lua/b.lua" },
      }, { "lua/a.lua", "lua/b.lua" })

      assert.same({
        "Complete diff unavailable for 2 file(s): lua/a.lua, lua/b.lua",
      }, payload.warnings)
    end)
  end)

  it("reloads an open review buffer from the synced checkout", function()
    local directory = vim.fn.tempname()
    local filename = directory .. "/file.lua"
    vim.fn.mkdir(directory, "p")
    vim.fn.writefile({ "new value" }, filename)
    local buf = vim.api.nvim_create_buf(false, false)
    vim.api.nvim_buf_set_name(buf, filename)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "stale value" })

    local reloaded = open._reload_review_file_buffer(buf)

    assert.is_true(reloaded)
    assert.same({ "new value" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    vim.api.nvim_buf_delete(buf, { force = true })
    vim.fn.delete(directory, "rf")
  end)

  it("pins a fresh clone to the exact initial PR head revision", function()
    local original_notify = vim.notify
    local original_is_git_repo = git.is_git_repo
    local original_clone = git.clone
    local original_fetch_reset = git.fetch_reset
    local revision = string.rep("a", 40)
    local completed = false

    vim.notify = function() end
    git.is_git_repo = function() return false end
    git.clone = function(url, path, branch, callback)
      assert.equals("https://example.test/repo.git", url)
      assert.equals("/tmp/raccoon-exact-open", path)
      assert.equals("feature", branch)
      callback(true, nil)
    end
    git.fetch_reset = function(path, branch, url, callback, exact_revision)
      assert.equals("/tmp/raccoon-exact-open", path)
      assert.equals("feature", branch)
      assert.equals("https://example.test/repo.git", url)
      assert.equals(revision, exact_revision)
      callback(true, nil)
    end

    open._prepare_repo(
      "/tmp/raccoon-exact-open",
      "https://example.test/repo.git",
      "feature",
      revision,
      function(err)
        assert.is_nil(err)
        completed = true
      end
    )

    vim.notify = original_notify
    git.is_git_repo = original_is_git_repo
    git.clone = original_clone
    git.fetch_reset = original_fetch_reset
    assert.is_true(completed)
  end)

  it("replaces a removed-file scratch buffer when sync makes the path present", function()
    local directory = vim.fn.tempname()
    local filename = directory .. "/file.lua"
    vim.fn.mkdir(directory, "p")
    local removed_buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(removed_buf, filename)
    vim.api.nvim_set_current_buf(removed_buf)
    vim.fn.writefile({ "present after sync" }, filename)

    local reloaded = open._reload_review_file_buffer(removed_buf)

    assert.is_false(reloaded)
    assert.is_false(vim.api.nvim_buf_is_valid(removed_buf))
    state.start({ owner = "test", repo = "repo", number = 1, clone_path = directory })
    local present_buf = diff.open_file({ filename = "file.lua", patch = "" })
    assert.is_not_nil(present_buf)
    assert.equals("", vim.bo[present_buf].buftype)
    assert.same({ "present after sync" }, vim.api.nvim_buf_get_lines(present_buf, 0, -1, false))

    vim.api.nvim_buf_delete(present_buf, { force = true })
    vim.fn.delete(directory, "rf")
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
    local function stub_empty_review_payload()
      local originals = {
        get_pr_comments = api.get_pr_comments,
        get_issue_comments = api.get_issue_comments,
        get_pr_reviews = api.get_pr_reviews,
        get_pr_review_threads = api.get_pr_review_threads,
      }
      api.get_pr_comments = function(_, _, _, _, callback) callback({}, nil) end
      api.get_issue_comments = function(_, _, _, _, callback) callback({}, nil) end
      api.get_pr_reviews = function(_, _, _, _, callback) callback({}, nil) end
      api.get_pr_review_threads = function(_, _, _, _, callback) callback({}, nil) end
      return function()
        for name, value in pairs(originals) do api[name] = value end
      end
    end

    it("does nothing when no active session", function()
      -- Should not error
      open.sync()
    end)

    it("preserves a selected filename when the changed-file list is reordered", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        clone_path = "/tmp/repo",
      })
      local files = {
        { filename = "lua/inserted.lua" },
        { filename = "lua/a.lua" },
        { filename = "lua/selected.lua" },
      }
      state.set_files(files)

      local selected, retained = open._select_synced_file(files, "lua/selected.lua", 2)

      assert.is_true(retained)
      assert.equals("lua/selected.lua", selected.filename)
      assert.equals(3, state.get_current_file_index())
    end)

    it("uses the nearest valid index when the selected file stops being changed", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        clone_path = "/tmp/repo",
      })
      local files = {
        { filename = "lua/a.lua" },
        { filename = "lua/c.lua" },
      }
      state.set_files(files)

      local selected, retained = open._select_synced_file(files, "lua/removed.lua", 2)

      assert.is_false(retained)
      assert.equals("lua/c.lua", selected.filename)
      assert.equals(2, state.get_current_file_index())
    end)

    it("keeps checkout, published state, and cached SHA unchanged when file loading fails", function()
      local old_pr = {
        number = 1,
        title = "Old PR",
        head = { ref = "feature", sha = "oldsha" },
        base = { ref = "main" },
      }
      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = "/tmp/raccoon-sync-transaction",
      })
      state.set_pr(old_pr)
      state.set_files({ { filename = "lua/old.lua", patch = "@@ -1 +1 @@\n-old\n+new" } })

      local original_notify = vim.notify
      local original_config_load = config.load
      local original_get_token_entry = config.get_token_entry
      local original_api_init = api.init
      local original_get_pr = api.get_pr
      local original_get_pr_files = api.get_pr_files
      local original_fetch_reset = git.fetch_reset
      local original_update_base_branch = git.update_base_branch
      local cached_sha = open._get_last_known_sha()
      local checkout_calls = 0
      local base_update_calls = 0

      vim.notify = function() end
      config.load = function() return { github_host = "github.com", tokens = {} }, nil end
      config.get_token_entry = function() return { token = "ghp_fake" } end
      api.init = function() end
      api.get_pr = function(_, _, _, _, callback)
        callback({
          number = 1,
          title = "New PR",
          head = { ref = "feature", sha = "newsha" },
          base = { ref = "develop" },
        }, nil)
      end
      git.fetch_reset = function()
        checkout_calls = checkout_calls + 1
      end
      git.update_base_branch = function()
        base_update_calls = base_update_calls + 1
      end
      api.get_pr_files = function(_, _, _, _, callback)
        callback(nil, "files unavailable")
      end

      open.sync()

      vim.notify = original_notify
      config.load = original_config_load
      config.get_token_entry = original_get_token_entry
      api.init = original_api_init
      api.get_pr = original_get_pr
      api.get_pr_files = original_get_pr_files
      git.fetch_reset = original_fetch_reset
      git.update_base_branch = original_update_base_branch

      assert.equals(0, checkout_calls)
      assert.equals(0, base_update_calls)
      assert.equals(old_pr, state.get_pr())
      assert.equals("lua/old.lua", state.get_current_file().filename)
      assert.equals(cached_sha, open._get_last_known_sha())
    end)

    it("does not checkout or publish files when the remote head changes during API reads", function()
      local old_pr = {
        number = 1,
        title = "Old PR",
        head = { ref = "feature", sha = "oldsha" },
        base = { ref = "main", sha = "base-old" },
      }
      local snapshot = {
        number = 1,
        title = "Snapshot A",
        head = { ref = "feature", sha = "sha-a" },
        base = { ref = "main", sha = "base-a" },
      }
      state.start({
        owner = "test", repo = "repo", number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = "/tmp/raccoon-sync-race",
      })
      state.set_pr(old_pr)
      state.set_files({ { filename = "old.lua", patch = "@@ -1 +1 @@\n-old\n+new" } })
      open._remember_pr_snapshot(old_pr)

      local original_notify = vim.notify
      local original_config_load = config.load
      local original_get_token_entry = config.get_token_entry
      local original_api_init = api.init
      local original_get_pr = api.get_pr
      local original_get_pr_files = api.get_pr_files
      local original_fetch_reset = git.fetch_reset
      local restore_payload = stub_empty_review_payload()
      local pr_calls = 0
      local checkout_calls = 0

      vim.notify = function() end
      config.load = function() return { github_host = "github.com", tokens = {} }, nil end
      config.get_token_entry = function() return { token = "ghp_fake" } end
      api.init = function() end
      api.get_pr = function(_, _, _, _, callback)
        pr_calls = pr_calls + 1
        if pr_calls == 1 then
          callback(snapshot, nil)
        else
          callback({
            number = 1,
            title = "Snapshot B",
            head = { ref = "feature", sha = "sha-b" },
            base = { ref = "main", sha = "base-a" },
          }, nil)
        end
      end
      api.get_pr_files = function(_, _, _, _, callback)
        callback({ { filename = "new.lua", patch = "@@ -1 +1 @@\n-old\n+new" } }, nil)
      end
      git.fetch_reset = function() checkout_calls = checkout_calls + 1 end

      open._sync_pr(false, false)

      vim.notify = original_notify
      config.load = original_config_load
      config.get_token_entry = original_get_token_entry
      api.init = original_api_init
      api.get_pr = original_get_pr
      api.get_pr_files = original_get_pr_files
      git.fetch_reset = original_fetch_reset
      restore_payload()

      assert.equals(2, pr_calls)
      assert.equals(0, checkout_calls)
      assert.equals(old_pr, state.get_pr())
      assert.equals("old.lua", state.get_current_file().filename)
      assert.equals("oldsha", open._get_last_known_sha())
    end)

    it("keeps published state when the exact checkout fails", function()
      local old_pr = {
        number = 1,
        title = "Old PR",
        head = { ref = "feature", sha = "oldsha" },
        base = { ref = "main", sha = "base-old" },
      }
      local new_pr = {
        number = 1,
        title = "New PR",
        head = { ref = "feature", sha = "newsha" },
        base = { ref = "main", sha = "base-new" },
      }
      state.start({
        owner = "test", repo = "repo", number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = "/tmp/raccoon-sync-checkout-failure",
      })
      state.set_pr(old_pr)
      state.set_files({ { filename = "old.lua", patch = "@@ -1 +1 @@\n-old\n+new" } })
      open._remember_pr_snapshot(old_pr)

      local original_notify = vim.notify
      local original_config_load = config.load
      local original_get_token_entry = config.get_token_entry
      local original_api_init = api.init
      local original_get_pr = api.get_pr
      local original_get_pr_files = api.get_pr_files
      local original_fetch_reset = git.fetch_reset
      local original_update_base_branch = git.update_base_branch
      local restore_payload = stub_empty_review_payload()
      local base_updates = 0

      vim.notify = function() end
      config.load = function() return { github_host = "github.com", tokens = {} }, nil end
      config.get_token_entry = function() return { token = "ghp_fake" } end
      api.init = function() end
      api.get_pr = function(_, _, _, _, callback) callback(new_pr, nil) end
      api.get_pr_files = function(_, _, _, _, callback)
        callback({ { filename = "new.lua", patch = "@@ -1 +1 @@\n-old\n+new" } }, nil)
      end
      git.fetch_reset = function(_, _, _, callback) callback(false, "exact revision unavailable") end
      git.update_base_branch = function() base_updates = base_updates + 1 end

      open._sync_pr(false, false)

      vim.notify = original_notify
      config.load = original_config_load
      config.get_token_entry = original_get_token_entry
      api.init = original_api_init
      api.get_pr = original_get_pr
      api.get_pr_files = original_get_pr_files
      git.fetch_reset = original_fetch_reset
      git.update_base_branch = original_update_base_branch
      restore_payload()

      assert.equals(0, base_updates)
      assert.equals(old_pr, state.get_pr())
      assert.equals("old.lua", state.get_current_file().filename)
      assert.equals("oldsha", open._get_last_known_sha())
    end)

    it("syncs a changed base snapshot when the head SHA is unchanged", function()
      local old_pr = {
        number = 1,
        title = "Old base",
        head = { ref = "feature", sha = "same-head" },
        base = { ref = "main", sha = "base-old" },
      }
      local new_pr = {
        number = 1,
        title = "New base",
        changed_files = 0,
        head = { ref = "feature", sha = "same-head" },
        base = { ref = "develop", sha = "base-new" },
      }
      state.start({
        owner = "test", repo = "repo", number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = "/tmp/raccoon-sync-base-change",
      })
      state.set_pr(old_pr)
      state.set_files({})
      open._remember_pr_snapshot(old_pr)

      local original_notify = vim.notify
      local original_config_load = config.load
      local original_get_token_entry = config.get_token_entry
      local original_api_init = api.init
      local original_get_pr = api.get_pr
      local original_get_pr_files = api.get_pr_files
      local original_fetch_reset = git.fetch_reset
      local original_update_base_branch = git.update_base_branch
      local restore_payload = stub_empty_review_payload()
      local checkout_calls = 0

      vim.notify = function() end
      config.load = function() return { github_host = "github.com", tokens = {} }, nil end
      config.get_token_entry = function() return { token = "ghp_fake" } end
      api.init = function() end
      api.get_pr = function(_, _, _, _, callback) callback(new_pr, nil) end
      api.get_pr_files = function(_, _, _, _, callback) callback({}, nil) end
      git.fetch_reset = function(_, _, _, callback, revision)
        assert.equals("same-head", revision)
        checkout_calls = checkout_calls + 1
        callback(true, nil)
      end
      git.update_base_branch = function(_, base_branch, callback)
        assert.equals("develop", base_branch)
        callback(true, nil)
      end

      open._sync_pr(true, false)

      vim.notify = original_notify
      config.load = original_config_load
      config.get_token_entry = original_get_token_entry
      api.init = original_api_init
      api.get_pr = original_get_pr
      api.get_pr_files = original_get_pr_files
      git.fetch_reset = original_fetch_reset
      git.update_base_branch = original_update_base_branch
      restore_payload()

      assert.equals(1, checkout_calls)
      assert.equals(new_pr, state.get_pr())
      assert.equals("same-head", open._get_last_known_sha())
    end)

    it("suppresses overlapping syncs and ignores callbacks after the session closes", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = "/tmp/raccoon-sync-generation",
      })
      state.set_pr({
        number = 1,
        title = "Old PR",
        head = { ref = "feature", sha = "oldsha" },
        base = { ref = "main" },
      })
      state.set_files({ { filename = "lua/a.lua", patch = "@@ -1 +1 @@\n-old\n+new" } })

      local original_notify = vim.notify
      local original_config_load = config.load
      local original_get_token_entry = config.get_token_entry
      local original_api_init = api.init
      local original_get_pr = api.get_pr
      local original_get_pr_files = api.get_pr_files
      local original_fetch_reset = git.fetch_reset
      local callbacks = {}
      local file_calls = 0
      local checkout_calls = 0
      local notifications = {}

      vim.notify = function(message) table.insert(notifications, message) end
      config.load = function() return { github_host = "github.com", tokens = {} }, nil end
      config.get_token_entry = function() return { token = "ghp_fake" } end
      api.init = function() end
      api.get_pr = function(_, _, number, _, callback) callbacks[number] = callback end
      api.get_pr_files = function() file_calls = file_calls + 1 end
      git.fetch_reset = function() checkout_calls = checkout_calls + 1 end

      open.sync()
      open.sync()

      assert.equals(1, #callbacks)
      assert.equals("PR sync already in progress", notifications[#notifications])
      open.close_pr()
      callbacks[1]({
        number = 1,
        title = "New PR",
        head = { ref = "feature", sha = "newsha" },
        base = { ref = "main" },
      }, nil)

      vim.notify = original_notify
      config.load = original_config_load
      config.get_token_entry = original_get_token_entry
      api.init = original_api_init
      api.get_pr = original_get_pr
      api.get_pr_files = original_get_pr_files
      git.fetch_reset = original_fetch_reset

      assert.is_false(state.is_active())
      assert.equals(0, file_calls)
      assert.equals(0, checkout_calls)
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
      git.fetch_reset = function(_clone_path, _branch, _repo_url, callback, revision)
        assert.equals("newsha", revision)
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

    it("keeps file-level review comments at GitHub's file placement during sync", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = "/tmp/raccoon-open-file-comment-sync",
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
      local original_fetch_reset = git.fetch_reset
      local original_update_base_branch = git.update_base_branch

      local sync_completed = false

      vim.notify = function(message)
        if message == "PR synced - new commits loaded" then
          sync_completed = true
        end
      end
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
          base = { ref = "develop" },
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
        callback({
          {
            id = 41,
            body = "<!-- raccoon:file-line 10 -->\npersisted body",
            path = "lua/a.lua",
            subject_type = "file",
            diff_hunk = "",
            line = 1,
            original_line = 1,
            position = 1,
            resolved = false,
            in_reply_to_id = vim.NIL,
            created_at = "2026-01-01T00:00:00Z",
            user = { login = "reviewer" },
          },
        }, nil)
      end
      api.get_issue_comments = function(_owner, _repo, _number, _token, callback)
        callback({}, nil)
      end
      api.get_pr_reviews = function(_owner, _repo, _number, _token, callback)
        callback({}, nil)
      end
      api.get_pr_review_threads = function(_owner, _repo, _number, _token, callback)
        callback({
          [41] = {
            thread_id = "thread-file-1",
            isResolved = false,
            resolvedBy = vim.NIL,
          },
        }, nil)
      end
      git.fetch_reset = function(_clone_path, _branch, _repo_url, callback, revision)
        assert.equals("newsha", revision)
        callback(true, nil)
      end
      git.update_base_branch = function(_clone_path, base_branch, callback)
        assert.equals("develop", base_branch)
        callback(true, nil)
      end

      open.sync()
      vim.wait(1000, function()
        return sync_completed
      end, 10)

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
      git.fetch_reset = original_fetch_reset
      git.update_base_branch = original_update_base_branch

      assert.is_true(sync_completed)

      local file_comments = state.get_comments("lua/a.lua")
      assert.equals(1, #file_comments)
      assert.equals("persisted body", file_comments[1].body)
      assert.equals(1, file_comments[1].line)

      local index, err = thread_index.build()
      assert.is_nil(err)
      assert.equals(1, index.thread_by_id["thread-file-1"].line)
      assert.equals("FILE", index.thread_by_id["thread-file-1"].line_label)
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
    it("ignores stale callbacks after switching to another PR", function()
      local original_notify = vim.notify
      local original_config_load = config.load
      local original_get_token_entry = config.get_token_entry
      local original_api_init = api.init
      local original_get_pr = api.get_pr
      local original_is_git_repo = git.is_git_repo
      local callbacks = {}
      local prepare_calls = 0

      vim.notify = function() end
      config.load = function()
        return {
          clone_root = "/tmp/raccoon-open-generation",
          github_host = "github.com",
          sync_interval = 300,
          tokens = {},
        }, nil
      end
      config.get_token_entry = function() return { token = "ghp_fake", login = "test" } end
      api.init = function() end
      api.get_pr = function(_, _, _, _, callback) table.insert(callbacks, callback) end
      git.is_git_repo = function()
        prepare_calls = prepare_calls + 1
        return true
      end

      local first_url = "https://github.com/test/repo/pull/1"
      local second_url = "https://github.com/test/repo/pull/2"
      comments.close_overlays(true)
      open.open_pr(first_url)
      open.open_pr(second_url)
      callbacks[1]({
        number = 1,
        title = "Stale PR",
        head = { ref = "feature-a", sha = "sha-a" },
        base = { ref = "main", sha = "base-a" },
      }, nil)

      vim.notify = original_notify
      config.load = original_config_load
      config.get_token_entry = original_get_token_entry
      api.init = original_api_init
      api.get_pr = original_get_pr
      git.is_git_repo = original_is_git_repo

      assert.is_function(callbacks[1])
      assert.is_function(callbacks[2])
      assert.equals(0, prepare_calls)
      assert.equals(second_url, state.get_url())
      assert.is_nil(state.get_pr())
    end)

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
