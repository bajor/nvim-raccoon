---@class RaccoonGit
---Git operations using vim.fn.jobstart for async execution
local M = {}

--- Run a git command asynchronously
---@param args string[] Git command arguments
---@param opts table Options: cwd, on_exit(code, stdout, stderr)
---@return number job_id
local function run_git(args, opts)
  local stdout_data = {}
  local stderr_data = {}

  local job_id = vim.fn.jobstart({ "git", unpack(args) }, {
    cwd = opts.cwd,
    stdout_buffered = true,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stdout_data, line)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data then
        for _, line in ipairs(data) do
          if line ~= "" then
            table.insert(stderr_data, line)
          end
        end
      end
    end,
    on_exit = function(_, code)
      if opts.on_exit then
        vim.schedule(function()
          opts.on_exit(code, stdout_data, stderr_data)
        end)
      end
    end,
  })

  return job_id
end

--- Clone a repository
---@param url string Repository URL
---@param path string Destination path
---@param branch string|nil Branch to checkout (optional)
---@param callback fun(success: boolean, err: string|nil)
function M.clone(url, path, branch, callback)
  -- Ensure parent directory exists
  local parent = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(parent) == 0 then
    vim.fn.mkdir(parent, "p")
  end

  local args = { "clone", "--depth", "1" }
  if branch then
    table.insert(args, "--branch")
    table.insert(args, branch)
  end
  table.insert(args, url)
  table.insert(args, path)

  run_git(args, {
    on_exit = function(code, _, stderr)
      if code == 0 then
        callback(true, nil)
      else
        local err_msg = table.concat(stderr, "\n")
        if err_msg == "" then
          err_msg = "Git clone failed with code " .. code
        end
        callback(false, err_msg)
      end
    end,
  })
end

--- Update the remote URL (useful for adding/updating auth tokens)
---@param path string Repository path
---@param url string New remote URL
---@param callback fun(success: boolean, err: string|nil)
function M.set_remote_url(path, url, callback)
  run_git({ "remote", "set-url", "origin", url }, {
    cwd = path,
    on_exit = function(code, _, stderr)
      if code == 0 then
        callback(true, nil)
      else
        local err_msg = table.concat(stderr, "\n")
        callback(false, err_msg)
      end
    end,
  })
end

--- Fetch and reset to a remote branch (hard reset to match remote)
---@param path string Repository path
---@param branch string Branch name
---@param url string|nil Optional: update remote URL before fetching (for auth)
---@param callback fun(success: boolean, err: string|nil)
function M.fetch_reset(path, branch, url, callback)
  -- Handle optional url parameter (backwards compatibility)
  if type(url) == "function" then
    callback = url
    url = nil
  end

  local function do_fetch()
    run_git({ "fetch", "origin", branch }, {
      cwd = path,
      on_exit = function(fetch_code, _, fetch_stderr)
        if fetch_code ~= 0 then
          local err_msg = table.concat(fetch_stderr, "\n")
          if err_msg == "" then
            err_msg = "Git fetch failed with code " .. fetch_code
          end
          callback(false, err_msg)
          return
        end

        -- Then checkout the branch
        run_git({ "checkout", branch }, {
          cwd = path,
          on_exit = function(checkout_code, _, _)
            if checkout_code ~= 0 then
              -- Branch might not exist locally, try creating it
              run_git({ "checkout", "-b", branch, "origin/" .. branch }, {
                cwd = path,
                on_exit = function(create_code, _, _)
                  if create_code ~= 0 then
                    -- Already exists, just reset
                    run_git({ "reset", "--hard", "origin/" .. branch }, {
                      cwd = path,
                      on_exit = function(reset_code, _, reset_stderr)
                        if reset_code == 0 then
                          callback(true, nil)
                        else
                          local err_msg = table.concat(reset_stderr, "\n")
                          callback(false, err_msg)
                        end
                      end,
                    })
                  else
                    callback(true, nil)
                  end
                end,
              })
            else
              -- Reset to remote
              run_git({ "reset", "--hard", "origin/" .. branch }, {
                cwd = path,
                on_exit = function(reset_code, _, reset_stderr)
                  if reset_code == 0 then
                    callback(true, nil)
                  else
                    local err_msg = table.concat(reset_stderr, "\n")
                    callback(false, err_msg)
                  end
                end,
              })
            end
          end,
        })
      end,
    })
  end

  -- Update remote URL first if provided (to include auth token)
  if url then
    M.set_remote_url(path, url, function(success, err)
      if not success then
        -- Non-fatal, try fetching anyway
        vim.schedule(function()
          vim.notify("Warning: Could not update remote URL: " .. (err or ""), vim.log.levels.WARN)
        end)
      end
      do_fetch()
    end)
  else
    do_fetch()
  end
end

--- Get the current branch name
---@param path string Repository path
---@param callback fun(branch: string|nil, err: string|nil)
function M.get_current_branch(path, callback)
  run_git({ "rev-parse", "--abbrev-ref", "HEAD" }, {
    cwd = path,
    on_exit = function(code, stdout, stderr)
      if code == 0 and #stdout > 0 then
        callback(stdout[1], nil)
      else
        local err_msg = table.concat(stderr, "\n")
        if err_msg == "" then
          err_msg = "Failed to get current branch"
        end
        callback(nil, err_msg)
      end
    end,
  })
end

--- Get the current commit SHA
---@param path string Repository path
---@param callback fun(sha: string|nil, err: string|nil)
function M.get_current_sha(path, callback)
  run_git({ "rev-parse", "HEAD" }, {
    cwd = path,
    on_exit = function(code, stdout, stderr)
      if code == 0 and #stdout > 0 then
        callback(stdout[1], nil)
      else
        local err_msg = table.concat(stderr, "\n")
        if err_msg == "" then
          err_msg = "Failed to get current SHA"
        end
        callback(nil, err_msg)
      end
    end,
  })
end

--- Check if a path is a git repository
---@param path string|nil Path to check
---@return boolean
function M.is_git_repo(path)
  if not path or path == "" then
    return false
  end
  local git_dir = vim.fs.joinpath(path, ".git")
  return vim.fn.isdirectory(git_dir) == 1
end

--- Get the remote URL for a repository
---@param path string Repository path
---@param callback fun(url: string|nil, err: string|nil)
function M.get_remote_url(path, callback)
  run_git({ "remote", "get-url", "origin" }, {
    cwd = path,
    on_exit = function(code, stdout, stderr)
      if code == 0 and #stdout > 0 then
        callback(stdout[1], nil)
      else
        local err_msg = table.concat(stderr, "\n")
        if err_msg == "" then
          err_msg = "Failed to get remote URL"
        end
        callback(nil, err_msg)
      end
    end,
  })
end

--- Parse owner/repo from a git remote URL
---@param url string|nil Git remote URL (SSH or HTTPS)
---@param host string|nil GitHub host to match (default: "github.com")
---@return string|nil repo_string "owner/repo" format, or nil if unparseable
function M.parse_repo_from_remote_url(url, host)
  if not url or url == "" then
    return nil
  end
  host = host or "github.com"
  local escaped_host = host:gsub("%.", "%%.")
  -- SSH: git@<host>:owner/repo.git
  local owner, repo = url:match("git@" .. escaped_host .. ":([^/]+)/(.+)$")
  if not owner then
    -- HTTPS: https://<host>/owner/repo.git (or https://token@<host>/...)
    owner, repo = url:match(escaped_host .. "/([^/]+)/(.+)$")
  end
  if owner and repo then
    return owner .. "/" .. repo:gsub("%.git$", "")
  end
  return nil
end

--- Build the clone path for a PR
---@param clone_root string Root directory for clones
---@param owner string Repository owner
---@param repo string Repository name
---@param pr_number number PR number
---@return string
function M.build_pr_path(clone_root, owner, repo, pr_number)
  local root = clone_root:gsub("[/\\]+$", "")
  return vim.fs.joinpath(root, owner, repo, "pr-" .. pr_number)
end

--- Check how many commits the current branch is behind the base branch
---@param path string Repository path
---@param base_branch string Base branch to compare against (e.g., "main")
---@param callback fun(behind: number|nil, err: string|nil)
function M.count_commits_behind(path, base_branch, callback)
  -- First fetch the base branch
  run_git({ "fetch", "origin", base_branch }, {
    cwd = path,
    on_exit = function(fetch_code, _, _)
      if fetch_code ~= 0 then
        callback(nil, "Failed to fetch base branch")
        return
      end

      -- Count commits behind
      run_git({ "rev-list", "--count", "HEAD..origin/" .. base_branch }, {
        cwd = path,
        on_exit = function(code, stdout, _)
          if code == 0 and #stdout > 0 then
            local behind = tonumber(stdout[1]) or 0
            callback(behind, nil)
          else
            callback(nil, "Failed to count commits behind")
          end
        end,
      })
    end,
  })
end

--- Check if merging with base branch would have conflicts
---@param path string Repository path
---@param base_branch string Base branch to check against
---@param callback fun(has_conflicts: boolean, conflict_files: string[]|nil, err: string|nil)
function M.check_merge_conflicts(path, base_branch, callback)
  -- Get merge-base first
  run_git({ "merge-base", "HEAD", "origin/" .. base_branch }, {
    cwd = path,
    on_exit = function(base_code, base_stdout, _)
      if base_code ~= 0 or #base_stdout == 0 then
        callback(false, nil, "Failed to find merge base")
        return
      end

      local merge_base = base_stdout[1]

      -- Use git merge-tree to check for conflicts without actually merging
      run_git({ "merge-tree", merge_base, "HEAD", "origin/" .. base_branch }, {
        cwd = path,
        on_exit = function(_, stdout, _)
          local conflict_files = {}
          local in_conflict = false

          for _, line in ipairs(stdout) do
            -- merge-tree outputs conflict markers
            if line:match("^changed in both") or line:match("^CONFLICT") then
              in_conflict = true
            end
            -- Extract file names from conflict output
            local file = line:match("^%s+base%s+%d+%s+%x+%s+(.+)$")
            if not file then
              file = line:match("CONFLICT.*: (.+)$")
            end
            if file and not vim.tbl_contains(conflict_files, file) then
              table.insert(conflict_files, file)
            end
          end

          -- Also try a simpler check - if merge-tree output contains "<<<" markers
          local output_str = table.concat(stdout, "\n")
          if output_str:match("<<<<<<") or output_str:match("changed in both") then
            in_conflict = true
          end

          callback(in_conflict, in_conflict and conflict_files or nil, nil)
        end,
      })
    end,
  })
end

--- Update the local base branch to match origin (without checking it out)
--- This ensures the local base branch is up to date for future branch creation
---@param path string Repository path
---@param base_branch string Base branch name (e.g., "main")
---@param callback fun(success: boolean, err: string|nil)
function M.update_base_branch(path, base_branch, callback)
  -- Use fetch with refspec to update local branch without checkout
  -- git fetch origin main:main
  run_git({ "fetch", "origin", base_branch .. ":" .. base_branch }, {
    cwd = path,
    on_exit = function(code, _, stderr)
      if code == 0 then
        callback(true, nil)
      else
        -- If fetch with refspec fails (e.g., branch doesn't exist locally), force update it
        run_git({ "branch", "-f", base_branch, "origin/" .. base_branch }, {
          cwd = path,
          on_exit = function(branch_code, _, branch_stderr)
            if branch_code == 0 then
              callback(true, nil)
            else
              local err_msg = table.concat(branch_stderr, "\n")
              if err_msg == "" then
                err_msg = table.concat(stderr, "\n")
              end
              callback(false, err_msg)
            end
          end,
        })
      end
    end,
  })
end

--- Get full sync status (behind count + conflict check)
---@param path string Repository path
---@param base_branch string Base branch
---@param callback fun(status: table) status = {behind: number, has_conflicts: boolean, conflict_files: string[]}
function M.get_sync_status(path, base_branch, callback)
  local status = {
    behind = 0,
    has_conflicts = false,
    conflict_files = {},
    checked = false,
  }

  -- Fetch base branch first
  run_git({ "fetch", "origin", base_branch }, {
    cwd = path,
    on_exit = function(fetch_code, _, _)
      if fetch_code ~= 0 then
        status.error = "Failed to fetch"
        callback(status)
        return
      end

      -- Count commits behind
      run_git({ "rev-list", "--count", "HEAD..origin/" .. base_branch }, {
        cwd = path,
        on_exit = function(code, stdout, _)
          if code == 0 and #stdout > 0 then
            status.behind = tonumber(stdout[1]) or 0
          end

          -- Check for conflicts
          M.check_merge_conflicts(path, base_branch, function(has_conflicts, conflict_files, _)
            status.has_conflicts = has_conflicts
            status.conflict_files = conflict_files or {}
            status.checked = true
            callback(status)
          end)
        end,
      })
    end,
  })
end

--- Unshallow the repository if it is a shallow clone
---@param path string Repository path
---@param callback fun(success: boolean, err: string|nil)
function M.unshallow_if_needed(path, callback)
  run_git({ "rev-parse", "--is-shallow-repository" }, {
    cwd = path,
    on_exit = function(code, stdout, _)
      if code == 0 and stdout[1] == "true" then
        run_git({ "fetch", "--unshallow" }, {
          cwd = path,
          on_exit = function(unshallow_code, _, stderr)
            if unshallow_code == 0 then
              callback(true, nil)
            else
              callback(false, table.concat(stderr, "\n"))
            end
          end,
        })
      else
        callback(true, nil)
      end
    end,
  })
end

--- Fetch a specific branch from origin
---@param path string Repository path
---@param branch string Branch name to fetch
---@param callback fun(success: boolean, err: string|nil)
function M.fetch_branch(path, branch, callback)
  -- Use explicit refspec to create origin/<branch> tracking ref
  -- (plain "git fetch origin <branch>" only updates FETCH_HEAD in single-branch clones)
  local refspec = "+refs/heads/" .. branch .. ":refs/remotes/origin/" .. branch
  run_git({ "fetch", "origin", refspec }, {
    cwd = path,
    on_exit = function(code, _, stderr)
      if code == 0 then
        callback(true, nil)
      else
        callback(false, table.concat(stderr, "\n"))
      end
    end,
  })
end

--- Get commit log for PR branch (commits not on base)
---@param path string Repository path
---@param base_branch string Base branch (e.g., "main")
---@param callback fun(commits: table[]|nil, err: string|nil)
function M.log_commits(path, base_branch, callback)
  run_git({ "log", "--format=%H %s", "--reverse", "origin/" .. base_branch .. "..HEAD" }, {
    cwd = path,
    on_exit = function(code, stdout, stderr)
      if code ~= 0 then
        callback(nil, table.concat(stderr, "\n"))
        return
      end
      local commits = {}
      for _, line in ipairs(stdout) do
        local sha = line:sub(1, 40)
        local message = line:sub(42)
        if #sha == 40 then
          table.insert(commits, { sha = sha, message = message })
        end
      end
      callback(commits, nil)
    end,
  })
end

--- Get recent commits from the base branch
---@param path string Repository path
---@param base_branch string Base branch
---@param count number Number of commits to fetch
---@param callback fun(commits: table[]|nil, err: string|nil)
function M.log_base_commits(path, base_branch, count, callback)
  run_git({ "log", "--format=%H %s", "-n", tostring(count), "origin/" .. base_branch }, {
    cwd = path,
    on_exit = function(code, stdout, stderr)
      if code ~= 0 then
        callback(nil, table.concat(stderr, "\n"))
        return
      end
      local commits = {}
      for _, line in ipairs(stdout) do
        local sha = line:sub(1, 40)
        local message = line:sub(42)
        if #sha == 40 then
          table.insert(commits, { sha = sha, message = message })
        end
      end
      callback(commits, nil)
    end,
  })
end

--- Get diff for a single commit, split into per-file patches
---@param path string Repository path
---@param sha string Commit SHA
---@param callback fun(files: table[]|nil, err: string|nil)
function M.show_commit(path, sha, callback)
  -- Use diff-tree instead of show: -m --first-parent handles merge commits
  -- (git show produces empty combined diff for clean merges)
  run_git({ "diff-tree", "-p", "-m", "--first-parent", "--no-commit-id", sha }, {
    cwd = path,
    on_exit = function(code, stdout, stderr)
      if code ~= 0 then
        callback(nil, table.concat(stderr, "\n"))
        return
      end
      local files = {}
      local current_file = nil
      local current_lines = {}

      for _, line in ipairs(stdout) do
        if line:match("^diff %-%-git ") then
          -- Save previous file
          if current_file then
            table.insert(files, { filename = current_file, patch = table.concat(current_lines, "\n") })
          end
          -- Extract filename from "diff --git a/path b/path"
          -- For deletions b-path is dev/null, so fall back to a-path
          local a_path, b_path = line:match("^diff %-%-git a/(.+) b/(.+)$")
          current_file = (b_path ~= "dev/null" and b_path) or a_path
          current_lines = {}
        elseif current_file and line:match("^@@") then
          table.insert(current_lines, line)
        elseif current_file and #current_lines > 0 then
          table.insert(current_lines, line)
        end
      end

      -- Save last file
      if current_file then
        table.insert(files, { filename = current_file, patch = table.concat(current_lines, "\n") })
      end

      callback(files, nil)
    end,
  })
end

--- Get full-context diff for a single file in a commit
---@param path string Repository path
---@param sha string Commit SHA
---@param filename string File path within the repo
---@param callback fun(patch: string|nil, err: string|nil)
function M.show_commit_file(path, sha, filename, callback)
  run_git({ "diff-tree", "-p", "-m", "--first-parent", "--no-commit-id", "-U99999", sha, "--", filename }, {
    cwd = path,
    on_exit = function(code, stdout, stderr)
      if code ~= 0 then
        callback(nil, table.concat(stderr, "\n"))
        return
      end
      local lines = {}
      local in_patch = false
      for _, line in ipairs(stdout) do
        if line:match("^@@") then
          in_patch = true
        end
        if in_patch then
          table.insert(lines, line)
        end
      end
      callback(table.concat(lines, "\n"), nil)
    end,
  })
end

return M
