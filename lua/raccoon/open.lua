---@class RaccoonOpen
---PR opening functionality
local M = {}

local api = require("raccoon.api")
local comment_metadata = require("raccoon.comment_metadata")
local comments = require("raccoon.comments")
local config = require("raccoon.config")
local diff = require("raccoon.diff")
local git = require("raccoon.git")
local keymaps = require("raccoon.keymaps")
local state = require("raccoon.state")

--- Sync timer
local sync_timer = nil
local sync_interval_ms = nil
local sync_in_flight = false
local sync_generation = 0
local open_generation = 0

local function invalidate_sync()
  sync_generation = sync_generation + 1
  sync_in_flight = false
end

local function invalidate_open()
  open_generation = open_generation + 1
end

--- Last known commit SHA (to detect changes)
local last_known_sha = nil
local last_known_base_ref = nil
local last_known_base_sha = nil

local function remember_pr_snapshot(pr)
  last_known_sha = pr and pr.head and pr.head.sha or nil
  last_known_base_ref = pr and pr.base and pr.base.ref or nil
  last_known_base_sha = pr and pr.base and pr.base.sha or nil
end

local function matches_known_snapshot(pr)
  return pr
    and pr.head and pr.head.sha == last_known_sha
    and pr.base and pr.base.ref == last_known_base_ref
    and pr.base.sha == last_known_base_sha
end

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
    table.insert(parts, "%#RaccoonConflict# CONFLICTS %*")
  end

  -- Behind warning (yellow)
  if commits_behind > 0 then
    table.insert(parts, string.format("%%#RaccoonWarning# BEHIND %d %s %%*",
      commits_behind, pr.base.ref))
  end

  -- Build the statusline string
  local status_str
  if #parts > 0 then
    status_str = table.concat(parts, " ")
  elseif commits_behind == 0 and not has_conflicts then
    status_str = "%#RaccoonOk# IN SYNC %*"
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
    return file_part .. "CONFLICTS"
  elseif commits_behind > 0 then
    return file_part .. string.format("BEHIND %d %s", commits_behind, pr.base.ref)
  else
    return file_part .. "IN SYNC"
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

local function ensure_comments_bucket(map, path)
  local bucket = map[path]
  if not bucket then
    bucket = {}
    map[path] = bucket
  end
  return bucket
end

local function parse_issue_comment_body(comment)
  local body = comment.body or ""
  local file_path, line_num = body:match("^%*%*`([^:]+):(%d+)`%*%*")
  if not file_path or not line_num then
    return nil
  end

  return {
    id = comment.id,
    body = body:gsub("^%*%*`[^`]+`%*%*\n*", ""),
    path = file_path,
    line = tonumber(line_num),
    user = comment.user,
    created_at = comment.created_at,
    updated_at = comment.updated_at,
    issue_comment = true,
  }
end

local function validate_thread_metadata(review_comments, resolution_map)
  local function missing_thread_id_error(comment)
    return string.format(
      "could not retrieve review threads from GraphQL (missing thread id on review comment %s)",
      tostring(comment.id or "?")
    )
  end

  local function missing_root_comment_error(thread_id)
    return string.format(
      "could not retrieve review threads from GraphQL (missing root review comment for thread %s)",
      tostring(thread_id)
    )
  end

  if #review_comments == 0 then
    return nil
  end

  if not resolution_map or next(resolution_map) == nil then
    return "could not retrieve review threads from GraphQL"
  end

  local roots_by_thread = {}
  for _, comment in ipairs(review_comments) do
    local metadata = comment.id and resolution_map[comment.id] or nil
    if not metadata then
      return missing_thread_id_error(comment)
    end
    if type(metadata.thread_id) ~= "string" or metadata.thread_id == "" then
      return missing_thread_id_error(comment)
    end

    comment.resolved = metadata.isResolved == true
    comment.resolved_by = metadata.resolvedBy
    comment.thread_id = metadata.thread_id

    if comment.in_reply_to_id == nil or comment.in_reply_to_id == vim.NIL then
      roots_by_thread[metadata.thread_id] = true
    end
  end

  for _, comment in ipairs(review_comments) do
    if not roots_by_thread[comment.thread_id] then
      return missing_root_comment_error(comment.thread_id)
    end
  end

  return nil
end

local function build_review_payload(owner, repo, number, token, callback)
  api.get_pr_comments(owner, repo, number, token, function(review_comments, comments_err)
    if comments_err then
      callback(nil, "Could not fetch review comments: " .. comments_err)
      return
    end

    api.get_issue_comments(owner, repo, number, token, function(issue_comments, issue_err)
      api.get_pr_reviews(owner, repo, number, token, function(reviews, reviews_err)
        api.get_pr_review_threads(owner, repo, number, token, function(resolution_map, res_err)
          if res_err and #(review_comments or {}) > 0 then
            callback(nil, "could not retrieve review threads from GraphQL")
            return
          end

          local metadata_err = validate_thread_metadata(review_comments or {}, resolution_map or {})
          if metadata_err then
            callback(nil, metadata_err)
            return
          end

          local payload = {
            comments_by_path = {},
            review_bodies = {},
            warnings = {},
          }

          for _, comment in ipairs(review_comments or {}) do
            comment_metadata.normalize_file_level_comment(comment)
            if comment.path then
              table.insert(ensure_comments_bucket(payload.comments_by_path, comment.path), comment)
            end
          end

          if issue_err then
            table.insert(payload.warnings, "Could not fetch issue comments: " .. issue_err)
          else
            for _, issue_comment in ipairs(issue_comments or {}) do
              local parsed = parse_issue_comment_body(issue_comment)
              if parsed then
                table.insert(ensure_comments_bucket(payload.comments_by_path, parsed.path), parsed)
              end
            end
          end

          if reviews_err then
            table.insert(payload.warnings, "Could not fetch reviews: " .. reviews_err)
          else
            for _, review in ipairs(reviews or {}) do
              if review.body and review.body ~= "" then
                table.insert(payload.review_bodies, {
                  id = review.id,
                  body = review.body,
                  user = review.user,
                  state = review.state,
                  submitted_at = review.submitted_at,
                  is_review = true,
                })
              end
            end
          end

          callback(payload, nil)
        end)
      end)
    end)
  end)
end

local function apply_review_payload(files, payload)
  for _, file in ipairs(files or {}) do
    state.set_comments(file.filename, payload.comments_by_path[file.filename] or {})
  end
  state.set_comments("_reviews", payload.review_bodies or {})
end

local function same_pr_snapshot(expected, actual)
  return type(expected) == "table"
    and type(actual) == "table"
    and type(expected.head) == "table"
    and type(actual.head) == "table"
    and type(expected.base) == "table"
    and type(actual.base) == "table"
    and expected.head.sha == actual.head.sha
    and expected.head.ref == actual.head.ref
    and expected.base.sha == actual.base.sha
    and expected.base.ref == actual.base.ref
end

local function verify_pr_snapshot(owner, repo, number, token, expected, callback)
  api.get_pr(owner, repo, number, token, function(current, err)
    if err then
      callback(false, err)
    elseif not same_pr_snapshot(expected, current) then
      callback(false, "Pull request changed while its data was loading; retry")
    else
      callback(true, nil)
    end
  end)
end

local function recover_incomplete_patches(pr, files, callback)
  local clone_path = state.get_clone_path()
  local base_branch = pr and pr.base and pr.base.ref or nil
  local unavailable = {}
  local incomplete = {}

  for _, file in ipairs(files) do
    if not diff.is_file_patch_complete(file) then
      table.insert(incomplete, file)
    end
  end

  if #incomplete == 0 then
    callback(unavailable)
    return
  end

  local revisions
  local index = 1
  local function recover_next()
    if index > #incomplete then
      callback(unavailable)
      return
    end

    local file = incomplete[index]
    index = index + 1
    local previous_filename = file.status == "renamed" and file.previous_filename or nil
    git.diff_pr_file(clone_path, revisions, file.filename, previous_filename, function(patch, err)
      file.patch = not err and patch or nil
      if not diff.is_file_patch_complete(file) then
        file.patch = nil
        file.diff_unavailable = true
        table.insert(unavailable, file.filename)
      else
        file.diff_unavailable = nil
      end
      recover_next()
    end)
  end

  git.prepare_pr_diff(clone_path, base_branch, function(prepared_revisions)
    if prepared_revisions then
      revisions = prepared_revisions
      recover_next()
      return
    end
    for _, file in ipairs(incomplete) do
      file.patch = nil
      file.diff_unavailable = true
      table.insert(unavailable, file.filename)
    end
    callback(unavailable)
  end, pr.base.sha, pr.head.sha)
end

local function append_diff_warnings(payload, pr, files, unavailable)
  if type(pr.changed_files) == "number" and pr.changed_files > #files then
    table.insert(payload.warnings, string.format(
      "GitHub returned %d of %d changed files; the remaining files are unavailable",
      #files,
      pr.changed_files
    ))
  end
  if #unavailable > 0 then
    table.insert(payload.warnings, string.format(
      "Complete diff unavailable for %d file(s): %s",
      #unavailable,
      table.concat(unavailable, ", ")
    ))
  end
end

M._same_pr_snapshot = same_pr_snapshot
M._recover_incomplete_patches = recover_incomplete_patches
M._append_diff_warnings = append_diff_warnings

local function resolve_viewer_login(cfg, owner, host, callback)
  local token_entry = config.get_token_entry(cfg, owner)
  if not token_entry then
    callback(nil, string.format("No token configured for '%s'. Add it to tokens in config.", owner))
    return
  end

  if token_entry.login and token_entry.login ~= "" then
    callback(token_entry.login, nil)
    return
  end

  api.get_viewer(token_entry.token, callback, host)
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

  local opened = comments.jump_to_file(file.filename)
  if opened then
    local shortcuts = config.load_shortcuts()
    local nav_hint = ""
    if config.is_enabled(shortcuts.next_file) and config.is_enabled(shortcuts.prev_file) then
      nav_hint = " - Use " .. shortcuts.next_file .. "/" .. shortcuts.prev_file .. " to navigate"
    end
    notify_success(string.format("Opened %s (1/%d files)%s", file.filename, #state.get_files(), nav_hint))
  end
end

--- Fetch PR files and review data for one exact PR snapshot.
---@param pr table
---@param owner string
---@param repo string
---@param number number
---@param token string
---@param is_current fun(): boolean
---@param callback fun(err: string|nil)
local function fetch_pr_data(pr, owner, repo, number, token, is_current, callback)
  notify_loading("Fetching PR data...")

  api.get_pr_files(owner, repo, number, token, function(files, files_err)
    if not is_current() then return end
    if files_err then
      callback(files_err)
      return
    end

    build_review_payload(owner, repo, number, token, function(payload, payload_err)
      if not is_current() then return end
      if payload_err then
        callback(payload_err)
        return
      end

      verify_pr_snapshot(owner, repo, number, token, pr, function(stable, snapshot_err)
        if not is_current() then return end
        if not stable then
          callback(snapshot_err)
          return
        end

        recover_incomplete_patches(pr, files, function(unavailable)
          if not is_current() then return end
          append_diff_warnings(payload, pr, files, unavailable)
          state.set_pr(pr)
          state.set_files(files)
          apply_review_payload(files, payload)
          for _, warning in ipairs(payload.warnings or {}) do
            vim.notify("Warning: " .. warning, vim.log.levels.WARN)
          end
          callback(nil)
        end)
      end)
    end)
  end)
end

local function find_file_index(files, filename)
  if not filename then return nil end
  for index, file in ipairs(files) do
    if file.filename == filename then
      return index
    end
  end
  return nil
end

local function select_synced_file(files, previous_filename, previous_index)
  local selected_index = find_file_index(files, previous_filename)
  if not selected_index and #files > 0 then
    selected_index = math.min(math.max(previous_index or 1, 1), #files)
  end
  if selected_index then
    state.goto_file(selected_index)
  end
  return selected_index and files[selected_index] or nil,
    selected_index and files[selected_index].filename == previous_filename or false
end

M._select_synced_file = select_synced_file

--- Stop the sync timer
local function stop_sync_timer()
  if sync_timer then
    sync_timer:stop()
    sync_timer:close()
    sync_timer = nil
  end
end

---@param snapshot table|nil
local function restore_overlay_snapshot(snapshot)
  if snapshot then
    comments.restore_ui_state(snapshot)
  end
end

---@param clone_path string
---@param filename string
---@return number|nil
local function find_review_file_buffer(clone_path, filename)
  local target_path = vim.fs.joinpath(clone_path, filename)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == target_path then
      return buf
    end
  end
  return nil
end

local function reload_review_file_buffer(buf)
  if vim.bo[buf].buftype == "nofile" then
    local filename = vim.api.nvim_buf_get_name(buf)
    if filename ~= "" and vim.fn.filereadable(filename) == 1 then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
    return false
  end
  return pcall(vim.api.nvim_buf_call, buf, function()
    vim.cmd("silent noautocmd edit!")
  end)
end

M._reload_review_file_buffer = reload_review_file_buffer

local function refresh_synced_buffer(buf, file, retained)
  if retained then
    if buf and reload_review_file_buffer(buf) then
      diff.apply_highlights(buf, file.patch)
      comments.show_comments(buf, state.get_comments(file.filename))
      return
    end
  end

  if buf and not retained then
    reload_review_file_buffer(buf)
    diff.clear_highlights(buf)
    comments.clear_comments(buf)
  end
  if file then
    local selected_buf = diff.open_file(file)
    if selected_buf then
      comments.show_comments(selected_buf, state.get_comments(file.filename))
    end
  end
end

--- Sync the PR with remote (fetch latest, update files/comments)
---@param silent boolean If true, don't show notifications unless something changed
---@param force boolean If true, bypass SHA cache and always re-fetch
local function sync_pr(silent, force)
  if not state.is_active() then return end
  if silent and comments.has_unsent_text() then return end
  if sync_in_flight then
    if not silent then vim.notify("PR sync already in progress", vim.log.levels.INFO) end
    return
  end

  sync_in_flight = true
  sync_generation = sync_generation + 1
  local generation = sync_generation
  local session_url = state.get_url()
  local finished = false
  local overlay_snapshot = force and comments.capture_ui_state() or nil
  if overlay_snapshot then comments.close_overlays(true) end

  local function is_current()
    return generation == sync_generation and state.is_active() and state.get_url() == session_url
  end

  local function finish()
    if finished then return end
    finished = true
    if generation == sync_generation then sync_in_flight = false end
  end

  local function continue_if_current()
    if is_current() then return true end
    finish()
    return false
  end

  local function fail(message, quiet)
    if not quiet then notify_error(message) end
    if is_current() then restore_overlay_snapshot(overlay_snapshot) end
    finish()
  end

  local cfg, cfg_err = config.load()
  if cfg_err then
    fail("Config error: " .. cfg_err, silent)
    return
  end

  local owner = state.get_owner()
  local repo = state.get_repo()
  local number = state.get_number()
  local clone_path = state.get_clone_path()
  local pr = state.get_pr()
  local github_host = state.get_github_host() or cfg.github_host
  if not owner or not repo or not number or not clone_path or not pr then
    fail("Sync failed: incomplete review session", silent)
    return
  end

  api.init(github_host)
  local token_entry = config.get_token_entry(cfg, owner)
  if not token_entry then
    fail(string.format("No token configured for '%s'. Add it to tokens in config.", owner), false)
    return
  end
  local token = token_entry.token
  local repo_url = string.format("https://%s@%s/%s/%s.git", token, github_host, owner, repo)

  api.get_pr(owner, repo, number, token, function(new_pr, pr_err)
    if not continue_if_current() then return end
    if pr_err then
      fail("Sync failed: " .. pr_err, silent)
      return
    end

    local new_sha = new_pr.head.sha
    local snapshot_unchanged = matches_known_snapshot(new_pr)
    if snapshot_unchanged and not force then
      if not silent then vim.notify("PR is up to date", vim.log.levels.INFO) end
      restore_overlay_snapshot(overlay_snapshot)
      finish()
      return
    end

    if not silent then
      local message = force and snapshot_unchanged and "Syncing PR..."
        or "Syncing PR (new commits detected)..."
      notify_loading(message)
    end

    -- Finish all fallible API reads before mutating the local checkout.
    api.get_pr_files(owner, repo, number, token, function(files, files_err)
      if not continue_if_current() then return end
      if files_err then
        fail("Failed to fetch files: " .. files_err, false)
        return
      end

      build_review_payload(owner, repo, number, token, function(payload, payload_err)
        if not continue_if_current() then return end
        if payload_err then
          fail("Sync failed: " .. payload_err, false)
          return
        end

        verify_pr_snapshot(owner, repo, number, token, new_pr, function(stable, snapshot_err)
          if not continue_if_current() then return end
          if not stable then
            fail("Sync failed: " .. snapshot_err, false)
            return
          end

          local previous_file = state.get_current_file()
          local previous_filename = previous_file and previous_file.filename or nil
          local previous_index = state.get_current_file_index()
          local previous_buf = previous_filename
            and find_review_file_buffer(clone_path, previous_filename) or nil

          git.fetch_reset(clone_path, new_pr.head.ref, repo_url, function(success, err)
            if not continue_if_current() then return end
            if not success then
              fail("Sync failed: " .. (err or "git error"), false)
              return
            end

            local base_branch = new_pr.base.ref
            git.update_base_branch(clone_path, base_branch, function(base_success, base_err)
              if not continue_if_current() then return end
              if not base_success then
                vim.notify("Warning: Could not update base branch: " .. (base_err or ""), vim.log.levels.WARN)
              end

              recover_incomplete_patches(new_pr, files, function(unavailable)
                if not continue_if_current() then return end
                append_diff_warnings(payload, new_pr, files, unavailable)
                state.set_pr(new_pr)
                state.set_files(files)
                apply_review_payload(files, payload)
                local current_file, retained = select_synced_file(files, previous_filename, previous_index)
                remember_pr_snapshot(new_pr)
                for _, warning in ipairs(payload.warnings or {}) do
                  vim.notify("Warning: " .. warning, vim.log.levels.WARN)
                end

                local flat_review = not state.is_commit_mode()
                  and not require("raccoon.localcommits").is_active()
                if flat_review then refresh_synced_buffer(previous_buf, current_file, retained) end
                if state.is_commit_mode() then require("raccoon.commits").refresh_after_sync() end

                restore_overlay_snapshot(overlay_snapshot)
                finish()
                vim.notify("PR synced - new commits loaded", vim.log.levels.INFO)
              end)
            end)
          end, new_sha)
        end)
      end)
    end)
  end)
end


M._sync_pr = sync_pr
M._remember_pr_snapshot = remember_pr_snapshot

--- Start the periodic sync timer
local function start_sync_timer()
  stop_sync_timer()
  if not sync_interval_ms then return end

  sync_timer = vim.uv.new_timer()
  sync_timer:start(sync_interval_ms, sync_interval_ms, vim.schedule_wrap(function()
    sync_pr(true) -- silent sync
  end))
end

--- Manual sync command (bypasses SHA cache)
function M.sync()
  sync_pr(false, true)
end

function M._get_last_known_sha()
  return last_known_sha
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
---@param revision string
---@param callback fun(err: string|nil)
local function prepare_repo(clone_path, repo_url, branch, revision, callback)
  local function checkout_revision()
    git.fetch_reset(clone_path, branch, repo_url, function(success, err)
      if success then
        callback(nil)
      else
        callback(err or "Failed to update repository")
      end
    end, revision)
  end

  if git.is_git_repo(clone_path) then
    notify_loading("Updating repository...")
    checkout_revision()
  else
    notify_loading("Cloning repository...")
    git.clone(repo_url, clone_path, branch, function(success, err)
      if success then
        checkout_revision()
      else
        callback(err or "Failed to clone repository")
      end
    end)
  end
end

M._prepare_repo = prepare_repo

--- Open a PR for review
---@param url string GitHub PR URL
function M.open_pr(url)
  if state.is_active() and state.get_url() == url then
    vim.notify("PR is already open", vim.log.levels.INFO)
    return
  end

  local commits = require("raccoon.commits")
  if state.is_active() and (comments.has_unsent_text() or commits.has_hidden_review_draft()) then
    vim.notify("Cannot switch PRs with unsent text; clear it or send it first", vim.log.levels.WARN)
    return
  end

  -- Load config first (needed for github_host)
  local cfg, cfg_err = config.load()
  if cfg_err then
    notify_error("Config error: " .. cfg_err)
    return
  end

  -- Parse URL (extract host from URL for multi-host support)
  local owner, repo, number, url_host = api.parse_pr_url(url)
  if not owner or not repo or not number or not url_host then
    notify_error("Invalid PR URL: " .. url)
    return
  end

  -- Initialize API URLs for the host from the URL
  api.init(url_host)

  -- Set sync interval from config (clamped to 10s minimum)
  local interval_s = math.max(10, cfg.sync_interval or 300)
  sync_interval_ms = interval_s * 1000

  -- Build clone path
  local clone_path = git.build_pr_path(cfg.clone_root, owner, repo, number)

  -- Resolve token for this owner
  local token_entry = config.get_token_entry(cfg, owner)
  if not token_entry then
    vim.notify(string.format("No token configured for '%s'. Add it to tokens in config.", owner), vim.log.levels.ERROR)
    return
  end
  local token = token_entry.token

  if state.is_active() then M.close_pr() end

  -- Start session
  stop_sync_timer()
  invalidate_sync()
  invalidate_open()
  local generation = open_generation
  state.start({
    owner = owner,
    repo = repo,
    number = number,
    url = url,
    viewer_login = token_entry.login,
    github_host = url_host,
    clone_path = clone_path,
  })

  local function is_current_open()
    return generation == open_generation
      and state.is_active()
      and state.get_url() == url
  end

  local function fail_open(message)
    if not is_current_open() then return end
    notify_error(message)
    invalidate_open()
    state.reset()
  end

  notify_loading(string.format("Opening PR #%d from %s/%s...", number, owner, repo))

  -- First, fetch PR data to get the branch name
  api.get_pr(owner, repo, number, token, function(pr, pr_err)
    if not is_current_open() then return end
    if pr_err then
      fail_open("Failed to fetch PR: " .. pr_err)
      return
    end

    state.set_pr(pr)

    local branch = pr.head.ref
    -- Use token in URL for HTTPS authentication
    local repo_url = string.format("https://%s@%s/%s/%s.git", token, url_host, owner, repo)

    -- Clone or update the repo
    prepare_repo(clone_path, repo_url, branch, pr.head.sha, function(repo_err)
      if not is_current_open() then return end
      if repo_err then
        fail_open("Repository error: " .. repo_err)
        return
      end

      local base_branch = pr.base.ref

      local function load_review()
        local function load_files()
          resolve_viewer_login(cfg, owner, url_host, function(login, login_err)
            if not is_current_open() then return end
            if login_err then
              fail_open("Failed to determine viewer login: " .. login_err)
              return
            end

            state.set_viewer_login(login)

            -- Fetch files and comments
            fetch_pr_data(pr, owner, repo, number, token, is_current_open, function(data_err)
              if not is_current_open() then return end
              if data_err then
                fail_open("Failed to fetch PR data: " .. data_err)
                return
              end

              -- Change to clone directory
              vim.cmd("cd " .. vim.fn.fnameescape(clone_path))

              -- Store initial SHA for change detection
              remember_pr_snapshot(pr)

              -- Start periodic sync timer
              start_sync_timer()

              -- Open the first file
              open_first_file()

              -- Update statusline (show warning if behind base)
              vim.defer_fn(function()
                if is_current_open() then update_statusline() end
              end, 100)

              notify_success(string.format(
                "PR #%d: %s (%d files) - auto-sync enabled",
                number,
                pr.title:sub(1, 40),
                #state.get_files()
              ))
            end)
          end)
        end

        -- Finish base-status Git operations before patch recovery can fetch or unshallow.
        git.get_sync_status(clone_path, base_branch, function(sync_status)
          if not is_current_open() then return end
          if sync_status.checked then
            commits_behind = sync_status.behind
            has_conflicts = sync_status.has_conflicts
            state.set_sync_status(sync_status)
          else
            commits_behind = 0
            has_conflicts = false
          end
          load_files()
        end)
      end

      -- Patch recovery needs the three-dot base ref to exist locally.
      git.update_base_branch(clone_path, base_branch, function(base_success, base_err)
        if not is_current_open() then return end
        if not base_success then
          vim.notify("Warning: Could not update base branch: " .. (base_err or ""), vim.log.levels.WARN)
        end
        load_review()
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

  local commits = require("raccoon.commits")
  if comments.has_unsent_text() or commits.has_hidden_review_draft() then
    vim.notify("Cannot close review with unsent text; clear it or send it first", vim.log.levels.WARN)
    return
  end

  -- Stop sync timer
  stop_sync_timer()
  invalidate_sync()
  invalidate_open()
  remember_pr_snapshot(nil)
  commits_behind = 0
  has_conflicts = false

  -- Reset statusline to default
  vim.wo.statusline = ""

  -- Clear all PR review keymaps
  keymaps.clear()
  commits.clear_mode_restore_state()

  state.stop()
  vim.notify("PR review session closed", vim.log.levels.INFO)
end

return M
