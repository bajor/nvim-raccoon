local commits = require("raccoon.commits")
local config = require("raccoon.config")
local git = require("raccoon.git")
local state = require("raccoon.state")

describe("raccoon.commits", function()
  before_each(function()
    state.reset()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(commits)
    end)

    it("has toggle function", function()
      assert.is_function(commits.toggle)
    end)
  end)

  describe("toggle without active session", function()
    it("does nothing when no PR session", function()
      -- Should not error
      commits.toggle()
    end)
  end)
end)

describe("raccoon.git commit operations", function()
  describe("new functions exist", function()
    it("has unshallow_if_needed function", function()
      assert.is_function(git.unshallow_if_needed)
    end)

    it("has fetch_branch function", function()
      assert.is_function(git.fetch_branch)
    end)

    it("has log_commits function", function()
      assert.is_function(git.log_commits)
    end)

    it("has log_base_commits function", function()
      assert.is_function(git.log_base_commits)
    end)

    it("has show_commit function", function()
      assert.is_function(git.show_commit)
    end)
  end)

  describe("log_commits on current repo", function()
    it("returns commits for current repo", function()
      local done = false
      local result_commits = nil

      -- Use "main" as base branch — HEAD..origin/main may return 0 commits
      -- on the main branch itself, but should not error
      git.log_commits(vim.fn.getcwd(), "main", function(commits_list, err)
        result_commits = commits_list
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      -- Should return a table (possibly empty if on main branch)
      assert.is_table(result_commits)
    end)
  end)

  describe("log_base_commits on current repo", function()
    it("returns recent commits from base branch", function()
      local done = false
      local result_commits = nil

      git.log_base_commits(vim.fn.getcwd(), "main", 5, function(commits_list, err)
        result_commits = commits_list
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_table(result_commits)
      -- Should have at least some commits
      assert.is_true(#result_commits > 0)
    end)

    it("each commit has sha and message", function()
      local done = false
      local result_commits = nil

      git.log_base_commits(vim.fn.getcwd(), "main", 3, function(commits_list, err)
        result_commits = commits_list
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
  end)

  describe("show_commit on current repo", function()
    it("returns file diffs for a commit", function()
      local done = false
      local sha = nil

      -- First get a commit SHA
      git.log_base_commits(vim.fn.getcwd(), "main", 1, function(commits_list, err)
        if commits_list and #commits_list > 0 then
          sha = commits_list[1].sha
        end
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_not_nil(sha)

      -- Now get the diff for that commit
      done = false
      local result_files = nil

      git.show_commit(vim.fn.getcwd(), sha, function(files, err)
        result_files = files
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_table(result_files)

      -- Each file should have filename and patch
      for _, file in ipairs(result_files) do
        assert.is_string(file.filename)
        assert.is_string(file.patch)
      end
    end)
  end)

  describe("unshallow_if_needed", function()
    it("succeeds on non-shallow repo", function()
      local done = false
      local result_success = nil

      git.unshallow_if_needed(vim.fn.getcwd(), function(success, err)
        result_success = success
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_true(result_success)
    end)
  end)
end)

describe("raccoon.state commit mode", function()
  before_each(function()
    state.reset()
  end)

  it("is_commit_mode returns false by default", function()
    assert.is_false(state.is_commit_mode())
  end)

  it("set_commit_mode changes state", function()
    state.set_commit_mode(true)
    assert.is_true(state.is_commit_mode())
  end)

  it("reset clears commit mode", function()
    state.set_commit_mode(true)
    state.reset()
    assert.is_false(state.is_commit_mode())
  end)
end)

describe("raccoon.config commit_viewer defaults", function()
  it("has commit_viewer in defaults", function()
    assert.is_table(config.defaults.commit_viewer)
  end)

  it("has grid config with rows and cols", function()
    assert.is_table(config.defaults.commit_viewer.grid)
    assert.equals(2, config.defaults.commit_viewer.grid.rows)
    assert.equals(2, config.defaults.commit_viewer.grid.cols)
  end)

  it("has base_commits_count default", function()
    assert.equals(20, config.defaults.commit_viewer.base_commits_count)
  end)
end)
