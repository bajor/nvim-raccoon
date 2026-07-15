local git = require("raccoon.git")
local diff = require("raccoon.diff")

describe("raccoon.git", function()

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
      local dir = vim.fn.tempname()
      vim.fn.mkdir(dir, "p")
      assert.is_false(git.is_git_repo(dir))
      vim.fn.delete(dir, "rf")
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

describe("raccoon.git pull-request diff recovery", function()
  local root

  local function run_git_sync(cwd, args)
    local command = { "git", "-c", "core.longpaths=true" }
    if cwd then
      table.insert(command, "-C")
      table.insert(command, cwd)
    end
    for _, arg in ipairs(args) do table.insert(command, arg) end
    local output = vim.fn.system(command)
    assert.equals(0, vim.v.shell_error, output)
    return vim.trim(output)
  end

  local function write_lines(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
  end

  after_each(function()
    if root then vim.fn.delete(root, "rf") end
  end)

  it("recovers a renamed and edited file from a fresh shallow clone", function()
    root = vim.fn.tempname()
    local remote = vim.fs.joinpath(root, "remote.git")
    local source = vim.fs.joinpath(root, "source")
    local clone = vim.fs.joinpath(root, "clone")
    vim.fn.mkdir(root, "p")

    run_git_sync(nil, { "init", "--bare", remote })
    run_git_sync(nil, { "init", source })
    run_git_sync(source, { "config", "user.email", "test@example.com" })
    run_git_sync(source, { "config", "user.name", "Raccoon Test" })
    run_git_sync(source, { "branch", "-M", "main" })

    local common_lines = {}
    for index = 1, 10 do
      table.insert(common_lines, string.format("local value_%d = %d", index, index))
    end
    local old_path = vim.fs.joinpath(source, "lua", "old.lua")
    write_lines(old_path, common_lines)
    run_git_sync(source, { "add", "lua/old.lua" })
    run_git_sync(source, { "commit", "-m", "common" })
    local common_sha = run_git_sync(source, { "rev-parse", "HEAD" })
    run_git_sync(source, { "branch", "feature" })

    write_lines(vim.fs.joinpath(source, "base-only.txt"), { "base advanced" })
    run_git_sync(source, { "add", "base-only.txt" })
    run_git_sync(source, { "commit", "-m", "advance base" })
    run_git_sync(source, { "remote", "add", "origin", remote })
    run_git_sync(source, { "push", "origin", "main" })

    run_git_sync(source, { "checkout", "feature" })
    vim.fn.mkdir(vim.fs.joinpath(source, "lua", "renamed"), "p")
    run_git_sync(source, { "mv", "lua/old.lua", "lua/renamed/new.lua" })
    local changed_lines = vim.deepcopy(common_lines)
    changed_lines[5] = "local value_5 = 50"
    write_lines(vim.fs.joinpath(source, "lua", "renamed", "new.lua"), changed_lines)
    run_git_sync(source, { "commit", "-am", "rename and edit" })
    local head_sha = run_git_sync(source, { "rev-parse", "HEAD" })
    run_git_sync(source, { "push", "origin", "feature" })

    run_git_sync(nil, {
      "clone", "--depth", "1", "--branch", "feature", "file://" .. remote, clone,
    })
    assert.equals("true", run_git_sync(clone, { "rev-parse", "--is-shallow-repository" }))
    local missing_base = vim.fn.system({
      "git", "-C", clone, "show-ref", "--verify", "--quiet", "refs/remotes/origin/main",
    })
    assert.equals("", missing_base)
    assert.not_equals(0, vim.v.shell_error)

    local revisions, prepare_err
    git.prepare_pr_diff(clone, "main", function(result, err)
      revisions, prepare_err = result, err or false
    end)
    vim.wait(10000, function() return prepare_err ~= nil end)

    assert.is_false(prepare_err)
    assert.same({ base_sha = common_sha, head_sha = head_sha }, revisions)
    assert.equals("false", run_git_sync(clone, { "rev-parse", "--is-shallow-repository" }))
    run_git_sync(clone, { "show-ref", "--verify", "refs/remotes/origin/main" })

    local patch, patch_err
    git.diff_pr_file(
      clone,
      revisions,
      "lua/renamed/new.lua",
      "lua/old.lua",
      function(result, err) patch, patch_err = result, err or false end
    )
    vim.wait(10000, function() return patch_err ~= nil end)

    assert.is_false(patch_err)
    assert.matches("%-local value_5 = 5", patch)
    assert.matches("%+local value_5 = 50", patch)
    assert.same({ additions = 1, deletions = 1, complete = true }, diff.get_patch_stats(patch))
  end)

  it("keeps the current branch and revision when an exact checkout cannot resolve", function()
    root = vim.fn.tempname()
    local remote = vim.fs.joinpath(root, "remote.git")
    local source = vim.fs.joinpath(root, "source")
    local clone = vim.fs.joinpath(root, "clone")
    vim.fn.mkdir(root, "p")

    run_git_sync(nil, { "init", "--bare", remote })
    run_git_sync(nil, { "init", source })
    run_git_sync(source, { "config", "user.email", "test@example.com" })
    run_git_sync(source, { "config", "user.name", "Raccoon Test" })
    run_git_sync(source, { "branch", "-M", "main" })
    write_lines(vim.fs.joinpath(source, "file.txt"), { "initial" })
    run_git_sync(source, { "add", "file.txt" })
    run_git_sync(source, { "commit", "-m", "initial" })
    run_git_sync(source, { "branch", "feature" })
    run_git_sync(source, { "remote", "add", "origin", remote })
    run_git_sync(source, { "push", "--all", "origin" })
    run_git_sync(nil, { "clone", "--branch", "main", "file://" .. remote, clone })
    local original_sha = run_git_sync(clone, { "rev-parse", "HEAD" })

    local success, result_err
    git.fetch_reset(clone, "feature", nil, function(ok, err)
      success, result_err = ok, err or false
    end, string.rep("f", 40))
    vim.wait(10000, function() return success ~= nil end)

    assert.is_false(success)
    assert.is_not_false(result_err)
    assert.equals("main", run_git_sync(clone, { "branch", "--show-current" }))
    assert.equals(original_sha, run_git_sync(clone, { "rev-parse", "HEAD" }))
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
    assert.truthy(recorded[1].cmd:match("^git %-c core%.longpaths=true clone"))
  end)

  it("get_current_branch includes core.longpaths flag", function()
    git.get_current_branch("/tmp", function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("^git %-c core%.longpaths=true rev%-parse"))
  end)

  it("get_current_sha includes core.longpaths flag", function()
    git.get_current_sha("/tmp", function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("^git %-c core%.longpaths=true rev%-parse HEAD"))
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

  it("show_commit includes -U flag when context is provided", function()
    git.show_commit("/tmp", "abc123", 20, function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("%-U20"))
  end)

  it("show_commit omits -U flag when context is nil", function()
    git.show_commit("/tmp", "abc123", nil, function() end)
    assert.equals(1, #recorded)
    assert.is_nil(recorded[1].cmd:match("%-U%d"))
  end)

  it("show_commit places -U flag before the SHA", function()
    git.show_commit("/tmp", "abc123", 15, function() end)
    assert.equals(1, #recorded)
    local u_pos = recorded[1].cmd:find("%-U15")
    local sha_pos = recorded[1].cmd:find("abc123")
    assert.is_true(u_pos < sha_pos)
  end)

  it("fetch_reset pins the checkout to an exact PR head revision", function()
    local revision = string.rep("c", 40)
    local done = false

    git.fetch_reset("/tmp", "feature", nil, function(success)
      assert.is_true(success)
      done = true
    end, revision)
    vim.wait(5000, function() return done end)

    assert.is_true(done)
    assert.equals(2, #recorded)
    assert.matches("fetch origin feature$", recorded[1].cmd)
    assert.matches("checkout %-f %-B feature " .. revision .. "$", recorded[2].cmd)
  end)

  it("prepare_pr_diff resolves immutable revisions from a fetched origin base", function()
    local head_sha = string.rep("a", 40)
    local base_sha = string.rep("b", 40)
    mocks.restore()
    recorded = mocks.mock_jobstart({
      ["rev%-parse %-%-is%-shallow%-repository"] = { stdout = { "false" } },
      ["rev%-parse %-%-verify HEAD%^%{commit%}"] = { stdout = { head_sha } },
      ["merge%-base origin/main " .. head_sha] = { stdout = { base_sha } },
    })
    local revisions, result_err

    git.prepare_pr_diff("/tmp", "main", function(result, err)
      revisions, result_err = result, err or false
    end)
    vim.wait(5000, function() return result_err ~= nil end)

    assert.is_false(result_err)
    assert.same({ base_sha = base_sha, head_sha = head_sha }, revisions)
    assert.equals(4, #recorded)
    assert.matches(
      "fetch origin %+refs/heads/main:refs/remotes/origin/main$",
      recorded[2].cmd
    )
  end)

  it("prepare_pr_diff rejects missing coordinates before starting git", function()
    local result_err

    git.prepare_pr_diff("/tmp", "", function(_, err) result_err = err end)

    assert.equals(0, #recorded)
    assert.matches("Missing pull%-request diff coordinates", result_err)
  end)

  it("diff_pr_file compares immutable revisions and includes both rename paths", function()
    local revisions = { head_sha = string.rep("a", 40), base_sha = string.rep("b", 40) }
    local done = false

    git.diff_pr_file("/tmp", revisions, "lua/new.lua", "lua/old.lua", function(_, err)
      assert.is_nil(err)
      done = true
    end)
    vim.wait(5000, function() return done end)

    assert.is_true(done)
    assert.equals(1, #recorded)
    assert.matches(
      "%-%-literal%-pathspecs diff %-%-no%-ext%-diff %-%-find%-renames %-%-unified=3 "
        .. revisions.base_sha .. " " .. revisions.head_sha .. " %-%- lua/old%.lua lua/new%.lua$",
      recorded[1].cmd
    )
  end)

  it("diff_pr_file rejects missing coordinates without starting git", function()
    local result_err

    git.diff_pr_file("/tmp", {}, "lua/raccoon/diff.lua", nil,
      function(_, err) result_err = err end)

    assert.equals(0, #recorded)
    assert.matches("Missing pull%-request diff coordinates", result_err)
  end)

  it("diff_working_dir includes -U flag when context is provided", function()
    git.diff_working_dir("/tmp", 15, function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("%-U15"))
  end)

  it("diff_working_dir places -U flag before HEAD", function()
    git.diff_working_dir("/tmp", 15, function() end)
    assert.equals(1, #recorded)
    local u_pos = recorded[1].cmd:find("%-U15")
    local head_pos = recorded[1].cmd:find("HEAD")
    assert.is_true(u_pos < head_pos)
  end)

  it("diff_working_dir omits -U flag when context is nil", function()
    git.diff_working_dir("/tmp", nil, function() end)
    assert.equals(1, #recorded)
    assert.is_nil(recorded[1].cmd:match("%-U%d"))
  end)

  it("show_commit omits -U flag when context is 0", function()
    git.show_commit("/tmp", "abc123", 0, function() end)
    assert.equals(1, #recorded)
    assert.is_nil(recorded[1].cmd:match("%-U"))
  end)

  it("show_commit omits -U flag when context is negative", function()
    git.show_commit("/tmp", "abc123", -5, function() end)
    assert.equals(1, #recorded)
    assert.is_nil(recorded[1].cmd:match("%-U"))
  end)

  it("show_commit floors fractional context values", function()
    git.show_commit("/tmp", "abc123", 11.7, function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("%-U11"))
    assert.is_nil(recorded[1].cmd:match("%-U11%."))
  end)

  it("diff_working_dir omits -U flag when context is 0", function()
    git.diff_working_dir("/tmp", 0, function() end)
    assert.equals(1, #recorded)
    assert.is_nil(recorded[1].cmd:match("%-U"))
  end)

  it("diff_working_dir omits -U flag when context is negative", function()
    git.diff_working_dir("/tmp", -5, function() end)
    assert.equals(1, #recorded)
    assert.is_nil(recorded[1].cmd:match("%-U"))
  end)

  it("diff_working_dir floors fractional context values", function()
    git.diff_working_dir("/tmp", 7.9, function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("%-U7"))
    assert.is_nil(recorded[1].cmd:match("%-U7%."))
  end)

  it("get_commit_message uses --format=%B with the SHA", function()
    git.get_commit_message("/tmp", "abc123def", function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("log %-1 %-%-format=%%B abc123def"))
  end)

  it("get_commit_message includes core.longpaths flag", function()
    git.get_commit_message("/tmp", "abc123", function() end)
    assert.equals(1, #recorded)
    assert.truthy(recorded[1].cmd:match("^git %-c core%.longpaths=true"))
  end)

  it("get_commit_message calls callback with error for nil SHA", function()
    local result_msg, result_err
    git.get_commit_message("/tmp", nil, function(msg, err)
      result_msg = msg
      result_err = err
    end)
    assert.equals(0, #recorded)
    assert.is_nil(result_msg)
    assert.equals("Invalid commit SHA", result_err)
  end)

  it("get_commit_message calls callback with error for empty SHA", function()
    local result_msg, result_err
    git.get_commit_message("/tmp", "", function(msg, err)
      result_msg = msg
      result_err = err
    end)
    assert.equals(0, #recorded)
    assert.is_nil(result_msg)
    assert.equals("Invalid commit SHA", result_err)
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
      assert.equals("owner/repo/pr-1", path)
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

  end)
end)
