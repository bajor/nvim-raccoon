local commit_ui = require("raccoon.commit_ui")
local git = require("raccoon.git")
local localcommits = require("raccoon.localcommits")
local state = require("raccoon.state")

describe("raccoon.localcommits", function()
  before_each(function()
    state.reset()
  end)


  describe("initial state", function()
    it("starts inactive", function()
      local ls = localcommits._get_state()
      assert.is_false(ls.active)
    end)

    it("has empty commits", function()
      local ls = localcommits._get_state()
      assert.equals(0, #ls.branch_commits)
      assert.equals(0, #ls.base_commits)
    end)

    it("has nil repo_path", function()
      local ls = localcommits._get_state()
      assert.is_nil(ls.repo_path)
    end)

    it("has no poll timer", function()
      local ls = localcommits._get_state()
      assert.is_nil(ls.poll_timer)
    end)

    it("starts with loading_more false", function()
      local ls = localcommits._get_state()
      assert.is_false(ls.loading_more)
    end)

    it("starts with select_generation at 0", function()
      local ls = localcommits._get_state()
      assert.equals(0, ls.select_generation)
    end)

    it("has empty last_status_output", function()
      local ls = localcommits._get_state()
      assert.equals("", ls.last_status_output)
    end)

    it("has nil workdir_poll_timer", function()
      local ls = localcommits._get_state()
      assert.is_nil(ls.workdir_poll_timer)
    end)

    it("starts with nil popup_win", function()
      local ls = localcommits._get_state()
      assert.is_nil(ls.popup_win)
    end)
  end)

  describe("popup window helpers", function()
    it("sets and clears popup_win on local state", function()
      localcommits.set_popup_win(42)
      assert.equals(42, localcommits._get_state().popup_win)

      localcommits.clear_popup_win()
      assert.is_nil(localcommits._get_state().popup_win)
    end)
  end)

  describe("exit_local_mode", function()
    it("falls back to a normal buffer when the saved buffer was wiped", function()
      local ls = localcommits._get_state()
      local scratch = commit_ui.create_scratch_buf()

      vim.api.nvim_set_current_buf(scratch)
      commit_ui.lock_buf(scratch)

      ls.active = true
      ls.saved_buf = 999999
      ls.saved_laststatus = vim.o.laststatus

      localcommits.exit_local_mode()

      local current_buf = vim.api.nvim_get_current_buf()
      assert.is_true(vim.api.nvim_buf_is_valid(current_buf))
      assert.equals("", vim.bo[current_buf].buftype)
      assert.is_false(vim.bo[current_buf].modified)
    end)
  end)

  describe("context pass-through", function()
    local original_show_commit, original_diff_working_dir, original_list_files, original_get_commit_message
    local captured_context

    before_each(function()
      original_show_commit = git.show_commit
      original_diff_working_dir = git.diff_working_dir
      original_list_files = git.list_files
      original_get_commit_message = git.get_commit_message
      git.show_commit = function(_, _, ctx, cb)
        captured_context = ctx
        cb({}, nil)
      end
      git.diff_working_dir = function(_, ctx, cb)
        captured_context = ctx
        cb({}, nil)
      end
      git.list_files = function(_, _, cb) cb({}, nil) end
      git.get_commit_message = function(_, _, cb) cb("", nil) end
      local ls = localcommits._get_state()
      ls.branch_commits = { { sha = "aaaa", message = "commit 1" } }
      ls.active = true
      ls.repo_path = "/tmp/fake"
      ls.grid_bufs = {}
      ls.grid_wins = {}
      ls.all_hunks = {}
      ls.select_generation = 0
      ls.header_buf = vim.api.nvim_create_buf(false, true)
      ls.header_win = vim.api.nvim_open_win(ls.header_buf, false, {
        relative = "editor", row = 0, col = 0, width = 80, height = 1,
      })
    end)

    after_each(function()
      git.show_commit = original_show_commit
      git.diff_working_dir = original_diff_working_dir
      git.list_files = original_list_files
      git.get_commit_message = original_get_commit_message
      local ls = localcommits._get_state()
      pcall(vim.api.nvim_win_close, ls.header_win, true)
      pcall(vim.api.nvim_buf_delete, ls.header_buf, { force = true })
      state.reset()
    end)

    it("passes computed grid context to show_commit for SHA commits", function()
      local ls = localcommits._get_state()
      ls.grid_rows = 2
      local expected = commit_ui.compute_grid_context(2)
      localcommits._select_commit(1)
      assert.equals(expected, captured_context)
    end)

    it("passes computed grid context to diff_working_dir for working dir", function()
      local ls = localcommits._get_state()
      ls.branch_commits = { { sha = nil, message = "uncommitted changes" } }
      ls.grid_rows = 3
      local expected = commit_ui.compute_grid_context(3)
      localcommits._select_commit(1)
      assert.equals(expected, captured_context)
    end)
  end)
end)

describe("raccoon.git local commit functions", function()
  describe("log_all_commits", function()
    it("has log_all_commits function", function()
      assert.is_function(git.log_all_commits)
    end)

    it("returns commits for current repo", function()
      local done = false
      local result_commits = nil

      git.log_all_commits(vim.fn.getcwd(), 10, 0, function(commits, err)
        result_commits = commits
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_table(result_commits)
      assert.is_true(#result_commits > 0)
    end)

    it("each commit has sha and message", function()
      local done = false
      local result_commits = nil

      git.log_all_commits(vim.fn.getcwd(), 5, 0, function(commits, err)
        result_commits = commits
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)

      for _, commit in ipairs(result_commits) do
        assert.is_string(commit.sha)
        assert.equals(40, #commit.sha)
        assert.is_string(commit.message)
      end
    end)

    it("respects count parameter", function()
      local done = false
      local result_commits = nil

      git.log_all_commits(vim.fn.getcwd(), 3, 0, function(commits, err)
        result_commits = commits
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_true(#result_commits <= 3)
    end)

    it("respects skip parameter", function()
      local done = false
      local all_commits = nil
      local skipped_commits = nil

      -- Get first 5 commits
      git.log_all_commits(vim.fn.getcwd(), 5, 0, function(commits, err)
        all_commits = commits
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)

      -- Get commits starting from skip=2
      done = false
      git.log_all_commits(vim.fn.getcwd(), 3, 2, function(commits, err)
        skipped_commits = commits
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)

      -- Third commit (index 3) from all should be first from skipped
      if #all_commits >= 3 and #skipped_commits >= 1 then
        assert.equals(all_commits[3].sha, skipped_commits[1].sha)
      end
    end)

    it("handles non-git directory", function()
      local done = false
      local result_err = nil

      git.log_all_commits("/tmp", 10, 0, function(commits, err)
        result_err = err
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
    end)
  end)

  describe("status_porcelain", function()
    it("has status_porcelain function", function()
      assert.is_function(git.status_porcelain)
    end)

    it("returns a string for current repo", function()
      local done = false
      local result_output = nil

      git.status_porcelain(vim.fn.getcwd(), function(output, err)
        result_output = output
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_string(result_output)
    end)
  end)

  describe("diff_working_dir", function()
    it("has diff_working_dir function", function()
      assert.is_function(git.diff_working_dir)
    end)

    it("returns a table for current repo", function()
      local done = false
      local result_files = nil

      git.diff_working_dir(vim.fn.getcwd(), nil, function(files, err)
        result_files = files
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_table(result_files)
    end)
  end)

  describe("diff_working_dir_file", function()
    it("has diff_working_dir_file function", function()
      assert.is_function(git.diff_working_dir_file)
    end)
  end)

  describe("find_repo_root", function()
    it("has find_repo_root function", function()
      assert.is_function(git.find_repo_root)
    end)

    it("finds root for current repo", function()
      local done = false
      local result_root = nil

      git.find_repo_root(vim.fn.getcwd(), function(root, err)
        result_root = root
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_not_nil(result_root)
      assert.is_string(result_root)
      assert.is_true(#result_root > 0)
    end)

    it("returns error for non-git directory", function()
      local done = false
      local result_root = nil
      local result_err = nil

      git.find_repo_root("/tmp", function(root, err)
        result_root = root
        result_err = err
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_nil(result_root)
      assert.is_not_nil(result_err)
    end)
  end)
end)
