local git = require("raccoon.git")
local localcommits = require("raccoon.localcommits")
local state = require("raccoon.state")

describe("raccoon.localcommits", function()
  before_each(function()
    state.reset()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(localcommits)
    end)

    it("has toggle function", function()
      assert.is_function(localcommits.toggle)
    end)

    it("has _get_state for testing", function()
      assert.is_function(localcommits._get_state)
    end)
  end)

  describe("initial state", function()
    it("starts inactive", function()
      local ls = localcommits._get_state()
      assert.is_false(ls.active)
    end)

    it("has empty commits", function()
      local ls = localcommits._get_state()
      assert.equals(0, #ls.commits)
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
