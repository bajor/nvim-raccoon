---@class RaccoonOpen
---PR opening functionality
local M = {}

local api = require("raccoon.api")
local comments = require("raccoon.comments")
local config = require("raccoon.config")
local diff = require("raccoon.diff")
local git = require("raccoon.git")
local keymaps = require("raccoon.keymaps")
local state = require("raccoon.state")

--- Sync timer (runs every 5 minutes)
local sync_timer = nil
local SYNC_INTERVAL_MS = 5 * 60 * 1000 -- 5 minutes

--- Last known commit SHA (to detect changes)
local last_known_sha = nil

--- How many commits behind base branch
local commits_behind = 0
local has_conflicts = false

--- Get how many commits behind base branch
---@return number
function M.get_commits_behind()
  return commits_behind
end

--- Get if there are merge conflicts
---@return boolean
function M.has_merge_conflicts()
  return has_conflicts
end

--- Setup the statusline highlight groups
local function setup_statusline_highlight()
  -- Yellow/orange for out of sync (same as comment highlight)
  vim.api.nvim_set_hl(0, "RaccoonWarning", { fg = "#ffcc00", bg = "#4a3d00", bold = true })
  -- Red for conflicts
  vim.api.nvim_set_hl(0, "RaccoonConflict", { fg = "#ffffff", bg = "#8b0000", bold = true })
  -- Green for in sync
  vim.api.nvim_set_hl(0, "RaccoonOk", { fg = "#88cc88", bg = "#1a3d1a", bold = true })
end

--- Update the statusline to show sync status
local function update_statusline()
  setup_statusline_highlight()
  local pr = state.get_pr()
  if not pr then return end

  local parts = {}

  -- File count indicator
  local files = state.get_files()
  if #files > 0 then
    table.insert(parts, string.format("[%d/%d]", state.get_current_file_index(), #files))
  end

  -- Conflict warning (highest priority - red)
  if has_conflicts then
    table.insert(parts, "%#RaccoonConflict# ⛔ MERGE CONFLICTS %*")
  end

  -- Behind warning (yellow)
  if commits_behind > 0 then
    local plural = commits_behind == 1 and "commit" or "commits"
    table.insert(parts, string.format("%%#RaccoonWarning# ⚠ %d %s behind %s %%*",
      commits_behind, plural, pr.base.ref))
  end

  -- Build the statusline string
  local status_str
  if #parts > 0 then
    status_str = table.concat(parts, " ")
  elseif commits_behind == 0 and not has_conflicts then
    status_str = "%#RaccoonOk# ✓ In sync with " .. pr.base.ref .. " %*"
  else
    return -- No status to show
  end

  -- Set window-local statusline
  vim.wo.statusline = status_str
end

--- Get sync status for lualine/statusline integration
--- Usage in lualine: { require('raccoon').statusline, cond = require('raccoon').is_active }
---@return string
function M.statusline()
  if not state.is_active() then
    return ""
  end

  local pr = state.get_pr()
  if not pr then return "" end

  -- File count prefix
  local files = state.get_files()
  local file_part = ""
  if #files > 0 then
    file_part = string.format("[%d/%d] ", state.get_current_file_index(), #files)
  end

  if has_conflicts then
    return file_part .. "⛔ CONFLICTS"
  elseif commits_behind > 0 then
    local plural = commits_behind == 1 and "commit" or "commits"
    return file_part .. string.format("⚠ %d %s behind %s", commits_behind, plural, pr.base.ref)
  else
    return file_part .. "✓ In sync"
  end
end

--- Check if PR review is active (for lualine cond)
---@return boolean
function M.is_active()
  return state.is_active()
end

--- Show a loading notification
---@param msg string
local function notify_loading(msg)
  vim.notify(msg, vim.log.levels.INFO)
end

--- Show an error notification
---@param msg string
local function notify_error(msg)
  vim.notify(msg, vim.log.levels.ERROR)
end

--- Show a success notification
---@param msg string
local function notify_success(msg)
  vim.notify(msg, vim.log.levels.INFO)
end

--- Open the first file in the PR with diff highlighting
local function open_first_file()
  local file = state.get_current_file()
  if not file then
    notify_error("No files in this PR")
    return
  end

  -- Setup all PR review keymaps
  keymaps.setup()

  -- Open file with diff highlighting
  local buf = diff.open_file(file)
  if buf then
    -- Show any existing comments
    local file_comments = state.get_comments(file.filename)
    if #file_comments > 0 then
      comments.show_comments(buf, file_comments)
    end
    notify_success(string.format("Opened %s (1/%d files) - Use ]f/[f to navigate", file.filename, #state.get_files()))
  end
end

--- Fetch PR data and files
---@param owner string
---@param repo string
---@param number number
---@param token string
---@param callback fun(err: string|nil)
local function fetch_pr_data(owner, repo, number, token, callback)
  notify_loading("Fetching PR data...")

  -- Fetch PR details
  api.get_pr(owner, repo, number, token, function(pr, pr_err)
    if pr_err then
      callback(pr_err)
      return
    end

    state.set_pr(pr)

    -- Fetch files
    api.get_pr_files(owner, repo, number, token, function(files, files_err)
      if files_err then
        callback(files_err)
        return
      end

      state.set_files(files)

      -- Fetch review comments (line-level)
      api.get_pr_comments(owner, repo, number, token, function(review_comments, comments_err)
        if comments_err then
          vim.notify("Warning: Could not fetch review comments: " .. comments_err, vim.log.levels.WARN)
        else
          -- Index comments by file path
          for _, comment in ipairs(review_comments or {}) do
            if comment.path then
              local file_comments = state.get_comments(comment.path)
              table.insert(file_comments, comment)
              state.set_comments(comment.path, file_comments)
            end
          end
        end

        -- Also fetch issue comments (general PR comments)
        api.get_issue_comments(owner, repo, number, token, function(issue_comments, issue_err)
          if issue_err then
            vim.notify("Warning: Could not fetch issue comments: " .. issue_err, vim.log.levels.WARN)
          else
            -- Parse issue comments that have file:line references in body
            -- Format: **`file:line`**\n\ncomment body
            for _, comment in ipairs(issue_comments or {}) do
              local body = comment.body or ""
              local file_path, line_num = body:match("^%*%*`([^:]+):(%d+)`%*%*")
              if file_path and line_num then
                -- Extract actual comment body (after the file reference)
                local actual_body = body:gsub("^%*%*`[^`]+`%*%*\n*", "")
                local parsed_comment = {
                  id = comment.id,
                  body = actual_body,
                  path = file_path,
                  line = tonumber(line_num),
                  user = comment.user,
                  created_at = comment.created_at,
                  updated_at = comment.updated_at,
                  issue_comment = true, -- Mark as issue comment
                }
                local file_comments = state.get_comments(file_path)
                table.insert(file_comments, parsed_comment)
                state.set_comments(file_path, file_comments)
              end
            end
          end

          -- Fetch PR reviews (includes review bodies from bots like qodo-code-review)
          api.get_pr_reviews(owner, repo, number, token, function(reviews, reviews_err)
            if reviews_err then
              vim.notify("Warning: Could not fetch reviews: " .. reviews_err, vim.log.levels.WARN)
            else
              -- Store review bodies as general comments under "_reviews" key
              local review_bodies = {}
              for _, review in ipairs(reviews or {}) do
                if review.body and review.body ~= "" then
                  table.insert(review_bodies, {
                    id = review.id,
                    body = review.body,
                    user = review.user,
                    state = review.state, -- APPROVED, CHANGES_REQUESTED, COMMENTED, etc.
                    submitted_at = review.submitted_at,
                    is_review = true,
                  })
                end
              end
              if #review_bodies > 0 then
                state.set_comments("_reviews", review_bodies)
              end
            end

          -- Fetch thread resolution status via GraphQL
          api.get_pr_review_threads(owner, repo, number, token, function(resolution_map, res_err)
            if res_err then
              vim.notify("Warning: Could not fetch thread resolution: " .. res_err, vim.log.levels.WARN)
            elseif resolution_map then
              -- Apply resolution status to stored comments
              for _, file in ipairs(files) do
                local file_comments = state.get_comments(file.filename)
                for _, comment in ipairs(file_comments) do
                  if comment.id and resolution_map[comment.id] then
                    comment.resolved = resolution_map[comment.id].isResolved
                    comment.resolved_by = resolution_map[comment.id].resolvedBy
                    comment.thread_id = resolution_map[comment.id].thread_id
                  end
                end
              end
            end

            callback(nil)
          end)
          end)
        end)
      end)
    end)
  end)
end

--- Stop the sync timer
local function stop_sync_timer()
  if sync_timer then
    sync_timer:stop()
    sync_timer:close()
    sync_timer = nil
  end
end

--- Sync the PR with remote (fetch latest, update files/comments)
---@param silent boolean If true, don't show notifications unless something changed
---@param force boolean If true, bypass SHA cache and always re-fetch
local function sync_pr(silent, force)
  if not state.is_active() then
    return
  end

  local cfg, cfg_err = config.load()
  if cfg_err then
    if not silent then
      notify_error("Config error: " .. cfg_err)
    end
    return
  end

  local owner = state.get_owner()
  local repo = state.get_repo()
  local number = state.get_number()
  local clone_path = state.get_clone_path()
  local pr = state.get_pr()

  if not owner or not repo or not number or not clone_path or not pr then
    return
  end

  local branch = pr.head.ref
  local token = config.get_token_for_owner(cfg, owner)
  local repo_url = string.format("https://%s@github.com/%s/%s.git", token, owner, repo)

  -- Check remote for updates first
  api.get_pr(owner, repo, number, token, function(new_pr, pr_err)
    if pr_err then
      if not silent then
        notify_error("Sync failed: " .. pr_err)
      end
      return
    end

    -- Check if SHA changed (skip check if force = true)
    local new_sha = new_pr.head.sha
    if new_sha == last_known_sha and not force then
      -- No changes
      if not silent then
        vim.notify("PR is up to date", vim.log.levels.INFO)
      end
      return
    end

    -- Do full sync
    if not silent then
      if force and new_sha == last_known_sha then
        notify_loading("Syncing PR...")
      else
        notify_loading("Syncing PR (new commits detected)...")
      end
    end

    -- Update local repo
    git.fetch_reset(clone_path, branch, repo_url, function(success, err)
      if not success then
        notify_error("Sync failed: " .. (err or "git error"))
        return
      end

      -- Also update base branch to keep it current
      local base_branch = pr.base.ref
      git.update_base_branch(clone_path, base_branch, function(base_success, base_err)
        if not base_success then
          -- Non-fatal, just warn
          vim.notify("Warning: Could not update base branch: " .. (base_err or ""), vim.log.levels.WARN)
        end
      end)

      -- Update PR data
      state.set_pr(new_pr)
      last_known_sha = new_sha

      -- Re-fetch files
      api.get_pr_files(owner, repo, number, token, function(files, files_err)
        if files_err then
          notify_error("Failed to fetch files: " .. files_err)
          return
        end

        state.set_files(files)

        -- Preserve local state (resolved, pending) before clearing
        local local_state = {}
        for _, file in ipairs(files) do
          local file_comments = state.get_comments(file.filename)
          for _, comment in ipairs(file_comments) do
            if comment.id and (comment.resolved ~= nil or comment.pending) then
              local_state[comment.id] = {
                resolved = comment.resolved,
                pending = comment.pending,
              }
            end
          end
          state.set_comments(file.filename, {})
        end

        -- Re-fetch review comments
        api.get_pr_comments(owner, repo, number, token, function(new_comments, comments_err)
          if not comments_err then
            for _, comment in ipairs(new_comments or {}) do
              if comment.path then
                -- Restore local state if it exists
                if comment.id and local_state[comment.id] then
                  comment.resolved = local_state[comment.id].resolved
                  comment.pending = local_state[comment.id].pending
                end
                local file_comments = state.get_comments(comment.path)
                table.insert(file_comments, comment)
                state.set_comments(comment.path, file_comments)
              end
            end
          end

          -- Also fetch issue comments
          api.get_issue_comments(owner, repo, number, token, function(issue_comments, issue_err)
            if not issue_err then
              for _, comment in ipairs(issue_comments or {}) do
                local body = comment.body or ""
                local file_path, line_num = body:match("^%*%*`([^:]+):(%d+)`%*%*")
                if file_path and line_num then
                  local actual_body = body:gsub("^%*%*`[^`]+`%*%*\n*", "")
                  local parsed_comment = {
                    id = comment.id,
                    body = actual_body,
                    path = file_path,
                    line = tonumber(line_num),
                    user = comment.user,
                    created_at = comment.created_at,
                    updated_at = comment.updated_at,
                    issue_comment = true,
                  }
                  -- Restore local state if it exists
                  if parsed_comment.id and local_state[parsed_comment.id] then
                    parsed_comment.resolved = local_state[parsed_comment.id].resolved
                    parsed_comment.pending = local_state[parsed_comment.id].pending
                  end
                  local file_comments = state.get_comments(file_path)
                  table.insert(file_comments, parsed_comment)
                  state.set_comments(file_path, file_comments)
                end
              end
            end

            -- Fetch thread resolution status via GraphQL (overwrites local state)
            api.get_pr_review_threads(owner, repo, number, token, function(resolution_map, res_err)
              if res_err then
                vim.notify("Warning: Could not fetch thread resolution: " .. res_err, vim.log.levels.WARN)
              elseif resolution_map then
                -- Apply server-side resolution status (overwrites local)
                for _, file in ipairs(files) do
                  local file_comments = state.get_comments(file.filename)
                  for _, comment in ipairs(file_comments) do
                    if comment.id and resolution_map[comment.id] then
                      comment.resolved = resolution_map[comment.id].isResolved
                      comment.resolved_by = resolution_map[comment.id].resolvedBy
                      comment.thread_id = resolution_map[comment.id].thread_id
                    end
                  end
                end
              end

              -- Refresh current file display
              local current_file = state.get_current_file()
              if current_file then
                local buf = vim.api.nvim_get_current_buf()
                diff.apply_highlights(buf, current_file.patch)
                comments.show_comments(buf, state.get_comments(current_file.filename))
              end

              vim.notify("PR synced - new commits loaded", vim.log.levels.INFO)
            end)
          end)
        end)
      end)
    end)
  end)
end

--- Start the periodic sync timer
local function start_sync_timer()
  stop_sync_timer()

  sync_timer = vim.uv.new_timer()
  sync_timer:start(SYNC_INTERVAL_MS, SYNC_INTERVAL_MS, vim.schedule_wrap(function()
    sync_pr(true) -- silent sync
  end))
end

--- Manual sync command (bypasses SHA cache)
function M.sync()
  sync_pr(false, true)
end

--- Pause the sync timer (e.g., when entering commit viewer mode)
function M.pause_sync()
  stop_sync_timer()
end

--- Resume the sync timer (e.g., when exiting commit viewer mode)
function M.resume_sync()
  if state.is_active() then
    start_sync_timer()
  end
end

--- Clone or update the repository
---@param clone_path string
---@param repo_url string
---@param branch string
---@param callback fun(err: string|nil)
local function prepare_repo(clone_path, repo_url, branch, callback)
  if git.is_git_repo(clone_path) then
    notify_loading("Updating repository...")
    -- Pass URL to update remote with auth token
    git.fetch_reset(clone_path, branch, repo_url, function(success, err)
      if success then
        callback(nil)
      else
        callback(err or "Failed to update repository")
      end
    end)
  else
    notify_loading("Cloning repository...")
    git.clone(repo_url, clone_path, branch, function(success, err)
      if success then
        callback(nil)
      else
        callback(err or "Failed to clone repository")
      end
    end)
  end
end

--- Open a PR for review
---@param url string GitHub PR URL
function M.open_pr(url)
  -- Parse URL
  local owner, repo, number = api.parse_pr_url(url)
  if not owner or not repo or not number then
    notify_error("Invalid PR URL: " .. url)
    return
  end

  -- Load config
  local cfg, cfg_err = config.load()
  if cfg_err then
    notify_error("Config error: " .. cfg_err)
    return
  end

  -- Build clone path
  local clone_path = git.build_pr_path(cfg.clone_root, owner, repo, number)

  -- Start session
  state.start({
    owner = owner,
    repo = repo,
    number = number,
    url = url,
    clone_path = clone_path,
  })

  -- Resolve token for this owner
  local token = config.get_token_for_owner(cfg, owner)

  notify_loading(string.format("Opening PR #%d from %s/%s...", number, owner, repo))

  -- First, fetch PR data to get the branch name
  api.get_pr(owner, repo, number, token, function(pr, pr_err)
    if pr_err then
      notify_error("Failed to fetch PR: " .. pr_err)
      state.reset()
      return
    end

    state.set_pr(pr)

    local branch = pr.head.ref
    -- Use token in URL for HTTPS authentication
    local repo_url = string.format("https://%s@github.com/%s/%s.git", token, owner, repo)

    -- Clone or update the repo
    prepare_repo(clone_path, repo_url, branch, function(repo_err)
      if repo_err then
        notify_error("Repository error: " .. repo_err)
        state.reset()
        return
      end

      local base_branch = pr.base.ref

      -- Update local base branch to match origin (keeps it current for future use)
      git.update_base_branch(clone_path, base_branch, function(base_success, base_err)
        if not base_success then
          -- Non-fatal, just warn
          vim.notify("Warning: Could not update base branch: " .. (base_err or ""), vim.log.levels.WARN)
        end
      end)

      -- Check sync status with base branch (behind count + conflicts)
      git.get_sync_status(clone_path, base_branch, function(sync_status)
        if sync_status.checked then
          commits_behind = sync_status.behind
          has_conflicts = sync_status.has_conflicts
          state.set_sync_status(sync_status)
        else
          commits_behind = 0
          has_conflicts = false
        end
      end)

      -- Fetch files and comments
      fetch_pr_data(owner, repo, number, token, function(data_err)
        if data_err then
          notify_error("Failed to fetch PR data: " .. data_err)
          state.reset()
          return
        end

        -- Change to clone directory
        vim.cmd("cd " .. vim.fn.fnameescape(clone_path))

        -- Store initial SHA for change detection
        last_known_sha = pr.head.sha

        -- Start periodic sync timer (every 5 mins)
        start_sync_timer()

        -- Open the first file
        open_first_file()

        -- Update statusline (show warning if behind base)
        vim.defer_fn(update_statusline, 100)

        notify_success(string.format(
          "PR #%d: %s (%d files) - auto-sync enabled",
          number,
          pr.title:sub(1, 40),
          #state.get_files()
        ))
      end)
    end)
  end)
end

--- Close the current PR review session
function M.close_pr()
  if not state.is_active() then
    vim.notify("No active PR review session", vim.log.levels.WARN)
    return
  end

  -- Stop sync timer
  stop_sync_timer()
  last_known_sha = nil
  commits_behind = 0
  has_conflicts = false

  -- Reset statusline to default
  vim.wo.statusline = ""

  -- Clear all PR review keymaps
  keymaps.clear()

  state.stop()
  vim.notify("PR review session closed", vim.log.levels.INFO)
end

return M
