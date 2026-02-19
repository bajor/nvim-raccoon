local git = require("raccoon.git")

describe("raccoon.git", function()
  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(git)
    end)

    it("has clone function", function()
      assert.is_function(git.clone)
    end)

    it("has fetch_reset function", function()
      assert.is_function(git.fetch_reset)
    end)

    it("has get_current_branch function", function()
      assert.is_function(git.get_current_branch)
    end)

    it("has get_current_sha function", function()
      assert.is_function(git.get_current_sha)
    end)

    it("has is_git_repo function", function()
      assert.is_function(git.is_git_repo)
    end)

    it("has get_remote_url function", function()
      assert.is_function(git.get_remote_url)
    end)

    it("has build_pr_path function", function()
      assert.is_function(git.build_pr_path)
    end)
  end)

  describe("build_pr_path", function()
    it("builds correct path", function()
      local path = git.build_pr_path("/home/user/repos", "owner", "repo", 123)
      assert.equals("/home/user/repos/owner/repo/pr-123", path)
    end)

    it("handles different PR numbers", function()
      local path = git.build_pr_path("/tmp/prs", "org", "project", 1)
      assert.equals("/tmp/prs/org/project/pr-1", path)
    end)

    it("handles large PR numbers", function()
      local path = git.build_pr_path("/data", "company", "app", 99999)
      assert.equals("/data/company/app/pr-99999", path)
    end)
  end)

  describe("parse_repo_from_remote_url", function()
    it("parses SSH remote URL", function()
      assert.equals("bajor/nvim-raccoon", git.parse_repo_from_remote_url("git@github.com:bajor/nvim-raccoon.git"))
    end)

    it("parses HTTPS remote URL", function()
      assert.equals("bajor/nvim-raccoon", git.parse_repo_from_remote_url("https://github.com/bajor/nvim-raccoon.git"))
    end)

    it("handles URL without .git suffix", function()
      assert.equals("bajor/nvim-raccoon", git.parse_repo_from_remote_url("https://github.com/bajor/nvim-raccoon"))
    end)

    it("handles SSH URL without .git suffix", function()
      assert.equals("bajor/nvim-raccoon", git.parse_repo_from_remote_url("git@github.com:bajor/nvim-raccoon"))
    end)

    it("returns nil for empty string", function()
      assert.is_nil(git.parse_repo_from_remote_url(""))
    end)

    it("returns nil for nil", function()
      assert.is_nil(git.parse_repo_from_remote_url(nil))
    end)

    it("returns nil for non-GitHub URL", function()
      assert.is_nil(git.parse_repo_from_remote_url("git@gitlab.com:owner/repo.git"))
    end)

    it("handles orgs with hyphens and dots", function()
      assert.equals("my-org/my.repo", git.parse_repo_from_remote_url("git@github.com:my-org/my.repo.git"))
    end)

    it("parses GHE SSH remote URL with matching host", function()
      assert.equals("owner/repo", git.parse_repo_from_remote_url("git@github.mycompany.com:owner/repo.git", "github.mycompany.com"))
    end)

    it("parses GHE HTTPS remote URL with matching host", function()
      assert.equals("owner/repo", git.parse_repo_from_remote_url("https://github.mycompany.com/owner/repo.git", "github.mycompany.com"))
    end)

    it("parses GHE HTTPS URL with token", function()
      assert.equals("owner/repo", git.parse_repo_from_remote_url("https://ghp_xxx@github.mycompany.com/owner/repo.git", "github.mycompany.com"))
    end)

    it("returns nil for GHE URL without matching host", function()
      assert.is_nil(git.parse_repo_from_remote_url("git@github.mycompany.com:owner/repo.git"))
    end)

    it("parses GHE URL with subdomain host", function()
      assert.equals("team/project", git.parse_repo_from_remote_url("git@git.corp.example.com:team/project.git", "git.corp.example.com"))
    end)

    it("parses SSH URL with hyphenated host", function()
      assert.equals("team/project", git.parse_repo_from_remote_url("git@github-enterprise.acme.com:team/project.git", "github-enterprise.acme.com"))
    end)

    it("parses HTTPS URL with hyphenated host", function()
      assert.equals("team/project", git.parse_repo_from_remote_url("https://github-enterprise.acme.com/team/project.git", "github-enterprise.acme.com"))
    end)
  end)

  describe("is_git_repo", function()
    it("returns true for git repository", function()
      -- The project root should be a git repo
      local project_root = vim.fn.getcwd()
      assert.is_true(git.is_git_repo(project_root))
    end)

    it("returns false for non-git directory", function()
      assert.is_false(git.is_git_repo("/tmp"))
    end)

    it("returns false for non-existent directory", function()
      assert.is_false(git.is_git_repo("/nonexistent/path/12345"))
    end)
  end)

  -- Integration tests for actual git operations
  describe("get_current_branch", function()
    it("gets branch name for current repo", function()
      local done = false
      local result_branch = nil

      git.get_current_branch(vim.fn.getcwd(), function(branch, err)
        result_branch = branch
        done = true
      end)

      -- Wait for async operation
      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done)
      assert.is_not_nil(result_branch)
      -- Should be a valid branch name (non-empty string)
      assert.is_string(result_branch)
      assert.is_true(#result_branch > 0)
    end)
  end)

  describe("get_current_sha", function()
    it("gets SHA for current repo", function()
      local done = false
      local result_sha = nil

      git.get_current_sha(vim.fn.getcwd(), function(sha, err)
        result_sha = sha
        done = true
      end)

      -- Wait for async operation
      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done)
      assert.is_not_nil(result_sha)
      -- SHA should be 40 hex characters
      assert.equals(40, #result_sha)
      assert.is_truthy(result_sha:match("^[0-9a-f]+$"))
    end)
  end)

  describe("get_remote_url", function()
    it("gets remote URL for current repo", function()
      local done = false
      local result_url = nil

      git.get_remote_url(vim.fn.getcwd(), function(url, err)
        result_url = url
        done = true
      end)

      -- Wait for async operation
      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done)
      -- Remote URL might not exist for a fresh repo
      -- Just check the callback was called
    end)
  end)
end)

-- Command format tests (mock_jobstart)
describe("raccoon.git command format", function()
  local mocks = require("tests.helpers.mocks")
  local recorded

  before_each(function()
    recorded = mocks.mock_jobstart({})
  end)

  after_each(function()
    mocks.restore()
  end)

  it("clone includes core.longpaths flag", function()
    git.clone("https://github.com/o/r.git", "/tmp/dest", "main", function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("^git %-c core%.longpaths=true %-c color%.ui=false clone"))
  end)

  it("get_current_branch includes core.longpaths flag", function()
    git.get_current_branch("/tmp", function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("^git %-c core%.longpaths=true %-c color%.ui=false rev%-parse"))
  end)

  it("get_current_sha includes core.longpaths flag", function()
    git.get_current_sha("/tmp", function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("^git %-c core%.longpaths=true %-c color%.ui=false rev%-parse HEAD"))
  end)

  it("clone without branch omits --branch flag", function()
    git.clone("https://github.com/o/r.git", "/tmp/dest", nil, function() end)
    assert.equals(1, #recorded)
    assert.is_nil(recorded[1].cmd:match("%-%-branch"))
  end)

  it("clone with branch includes --branch flag", function()
    git.clone("https://github.com/o/r.git", "/tmp/dest", "feat", function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("%-%-branch feat"))
  end)
end)

-- Long-path error enhancement tests
describe("raccoon.git long-path error enhancement", function()
  local mocks = require("tests.helpers.mocks")

  after_each(function()
    mocks.restore()
  end)

  it("appends OS-level guidance when stderr contains 'File name too long'", function()
    mocks.mock_jobstart({
      ["clone"] = {
        exit_code = 128,
        stderr = { "error: unable to create file deep/path: File name too long", "fatal: unable to checkout working tree" },
      },
    })

    local done = false
    local result_err = nil

    git.clone("https://github.com/o/r.git", "/tmp/dest", "main", function(success, err)
      result_err = err
      done = true
    end)

    vim.wait(5000, function() return done end)

    assert.is_true(done)
    assert.truthy(result_err:match("File name too long"))
    assert.truthy(result_err:match("Windows long%-path support"))
    assert.truthy(result_err:match("LongPathsEnabled"))
  end)

  it("does not modify stderr when no long-path error present", function()
    mocks.mock_jobstart({
      ["clone"] = {
        exit_code = 128,
        stderr = { "fatal: repository not found" },
      },
    })

    local done = false
    local result_err = nil

    git.clone("https://github.com/o/r.git", "/tmp/dest", "main", function(success, err)
      result_err = err
      done = true
    end)

    vim.wait(5000, function() return done end)

    assert.is_true(done)
    assert.equals("fatal: repository not found", result_err)
    assert.is_nil(result_err:match("Windows long%-path support"))
  end)
end)

-- Git error handling tests
describe("raccoon.git error handling", function()
  describe("get_current_branch error cases", function()
    it("handles non-existent directory", function()
      -- vim.fn.jobstart throws an error when cwd doesn't exist
      -- This is acceptable behavior - we just verify it doesn't silently succeed
      local ok, err = pcall(function()
        git.get_current_branch("/nonexistent/path/12345", function() end)
      end)

      -- Either throws an error OR calls callback with error (both acceptable)
      if ok then
        -- Wait for async callback if jobstart didn't throw
        local done = false
        local result_err = nil
        git.get_current_branch("/nonexistent/path/12345", function(branch, err)
          result_err = err
          done = true
        end)
        vim.wait(5000, function() return done end)
        assert.is_not_nil(result_err)
      else
        -- Threw error - acceptable for invalid directory
        assert.is_truthy(err)
      end
    end)

    it("handles non-git directory", function()
      local done = false
      local result_err = nil
      local result_branch = nil

      -- /tmp is unlikely to be a git repo
      git.get_current_branch("/tmp", function(branch, err)
        result_branch = branch
        result_err = err
        done = true
      end)

      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done)
      -- Either error or nil branch expected
      if result_branch then
        -- If branch returned, it should be valid
        assert.is_string(result_branch)
      end
    end)
  end)

  describe("get_current_sha error cases", function()
    it("handles non-existent directory", function()
      -- vim.fn.jobstart throws an error when cwd doesn't exist
      local ok, err = pcall(function()
        git.get_current_sha("/nonexistent/path/12345", function() end)
      end)

      -- Either throws an error OR calls callback with error (both acceptable)
      if ok then
        local done = false
        local result_err = nil
        git.get_current_sha("/nonexistent/path/12345", function(sha, err)
          result_err = err
          done = true
        end)
        vim.wait(5000, function() return done end)
        assert.is_not_nil(result_err)
      else
        assert.is_truthy(err)
      end
    end)

    it("handles non-git directory", function()
      local done = false
      local result_sha = nil

      git.get_current_sha("/tmp", function(sha, err)
        result_sha = sha
        done = true
      end)

      vim.wait(5000, function()
        return done
      end)

      assert.is_true(done)
      -- Should be nil or empty for non-git dir
    end)
  end)

  describe("get_remote_url error cases", function()
    it("handles non-existent directory", function()
      -- vim.fn.jobstart throws an error when cwd doesn't exist
      local ok, err = pcall(function()
        git.get_remote_url("/nonexistent/path/12345", function() end)
      end)

      -- Either throws an error OR calls callback with error (both acceptable)
      if ok then
        local done = false
        local result_err = nil
        git.get_remote_url("/nonexistent/path/12345", function(url, err)
          result_err = err
          done = true
        end)
        vim.wait(5000, function() return done end)
        assert.is_not_nil(result_err)
      else
        assert.is_truthy(err)
      end
    end)
  end)
end)

-- Git path edge cases
describe("raccoon.git path edge cases", function()
  describe("build_pr_path edge cases", function()
    it("handles empty clone root", function()
      local path = git.build_pr_path("", "owner", "repo", 1)
      assert.equals("/owner/repo/pr-1", path)
    end)

    it("handles trailing slash in clone root", function()
      local path = git.build_pr_path("/tmp/repos/", "owner", "repo", 1)
      -- Should not have double slashes
      assert.is_nil(path:match("//"))
    end)

    it("handles special characters in owner", function()
      local path = git.build_pr_path("/tmp", "my-org", "repo", 1)
      assert.equals("/tmp/my-org/repo/pr-1", path)
    end)

    it("handles special characters in repo", function()
      local path = git.build_pr_path("/tmp", "owner", "my_repo.js", 1)
      assert.equals("/tmp/owner/my_repo.js/pr-1", path)
    end)

    it("handles numbers in owner/repo", function()
      local path = git.build_pr_path("/tmp", "org123", "repo456", 789)
      assert.equals("/tmp/org123/repo456/pr-789", path)
    end)

    it("handles very long paths", function()
      local long_owner = string.rep("a", 100)
      local long_repo = string.rep("b", 100)
      local path = git.build_pr_path("/tmp", long_owner, long_repo, 99999)
      assert.truthy(path:match(long_owner))
      assert.truthy(path:match(long_repo))
      assert.truthy(path:match("pr%-99999"))
    end)
  end)

  describe("is_git_repo edge cases", function()
    it("handles nil path", function()
      -- Should not crash
      local result = git.is_git_repo(nil)
      assert.is_false(result)
    end)

    it("handles empty path", function()
      local result = git.is_git_repo("")
      assert.is_false(result)
    end)

    it("handles path with spaces", function()
      -- Path with spaces should be handled gracefully
      local result = git.is_git_repo("/tmp/path with spaces")
      assert.is_false(result)
    end)

    it("handles relative path", function()
      -- Current directory is likely a git repo
      local result = git.is_git_repo(".")
      -- Result depends on where tests run
      assert.is_boolean(result)
    end)
  end)
end)

-- Git function availability tests
describe("raccoon.git functions", function()
  describe("additional functions", function()
    it("has set_remote_url function", function()
      assert.is_function(git.set_remote_url)
    end)

    it("has count_commits_behind function", function()
      assert.is_function(git.count_commits_behind)
    end)

    it("has check_merge_conflicts function", function()
      assert.is_function(git.check_merge_conflicts)
    end)

    it("has get_sync_status function", function()
      assert.is_function(git.get_sync_status)
    end)
  end)

  describe("async operation patterns", function()
    it("clone accepts callback", function()
      -- Just verify function signature, don't actually clone
      assert.is_function(git.clone)
    end)

    it("fetch_reset accepts callback", function()
      assert.is_function(git.fetch_reset)
    end)

    it("get_sync_status accepts callback", function()
      assert.is_function(git.get_sync_status)
    end)
  end)
end)
