---@class RaccoonKeymaps
---Keymap management for PR review sessions.
---Review shortcuts use <leader> prefix by default; passthrough keymaps forward arbitrary keys to external plugins.
local M = {}

local api = require("raccoon.api")
local comments = require("raccoon.comments")
local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local diff = require("raccoon.diff")
local state = require("raccoon.state")

--- Default keymap options
local default_opts = { noremap = true, silent = true }

--- Get a valid line number from a comment, handling vim.NIL from JSON null
---@param comment table
---@return number|nil
local function get_comment_line(comment)
  for _, field in ipairs({ "line", "original_line", "position" }) do
    local val = comment[field]
    if type(val) == "number" and val > 0 then
      return val
    end
  end
  return nil
end

--- Get all points of interest (diffs and comments) for a file
---@param file table File data with filename and patch
---@return table[] points Sorted list of {line, type} where type is "diff" or "comment"
local function get_file_points(file)
  if not file then return {} end

  local points = {}
  local seen = {}

  -- Get diff hunks
  if file.patch then
    local changes = diff.get_changed_lines(file.patch)

    -- Group consecutive changed lines into hunks
    local all_lines = {}
    for _, line in ipairs(changes.added) do
      table.insert(all_lines, line)
    end
    for _, del in ipairs(changes.deleted) do
      if del.line_num then
        table.insert(all_lines, math.max(1, del.line_num))
      end
    end
    table.sort(all_lines)

    -- Get hunk start lines (first line of consecutive groups)
    local prev_line = nil
    for _, line in ipairs(all_lines) do
      if prev_line == nil or line > prev_line + 1 then
        if not seen[line] then
          table.insert(points, { line = line, type = "diff" })
          seen[line] = true
        end
      end
      prev_line = line
    end
  end

  -- Get comments
  local file_comments = state.get_comments(file.filename)
  for _, comment in ipairs(file_comments) do
    local line = get_comment_line(comment)
    if line and not seen[line] then
      table.insert(points, { line = line, type = "comment" })
      seen[line] = true
    end
  end

  -- Sort by line number
  table.sort(points, function(a, b) return a.line < b.line end)

  return points
end

--- Build a flat list of all points across all files
---@return table[] all_points List of {file_index, file, line, type}
local function get_all_points()
  local files = state.get_files()
  local all_points = {}

  for file_idx, file in ipairs(files) do
    local points = get_file_points(file)
    for _, point in ipairs(points) do
      table.insert(all_points, {
        file_index = file_idx,
        file = file,
        line = point.line,
        type = point.type,
      })
    end
  end

  return all_points
end

--- Navigate to a point (opens file if needed)
---@param point table {file_index, file, line, type}
local function goto_point(point)
  local current_file_idx = state.get_current_file_index()

  -- Switch file if needed
  if point.file_index ~= current_file_idx then
    state.session.current_file = point.file_index
    local buf = diff.open_file(point.file)
    if buf then
      -- Show comments for new file
      local file_comments = state.get_comments(point.file.filename)
      if #file_comments > 0 then
        comments.show_comments(buf, file_comments)
      end
    end
  end

  -- Go to line (clamped to valid range to prevent "cursor position outside buffer" errors)
  local line_count = vim.api.nvim_buf_line_count(0)
  local target_line = math.max(1, math.min(point.line, line_count))
  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  vim.cmd("normal! zz")

  -- Show what we landed on with position in file
  local file_points = get_file_points(point.file)
  local point_idx = 1
  for i, p in ipairs(file_points) do
    if p.line == point.line then
      point_idx = i
      break
    end
  end
  local type_str = point.type == "comment" and "comment" or "change"
  vim.notify(string.format("[%d/%d] %s:%d (%s)",
    point_idx, #file_points, point.file.filename, point.line, type_str))
end

--- Go to next point of interest (diff or comment, across files)
function M.next_point()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end

  local all_points = get_all_points()
  if #all_points == 0 then
    diff.next_file()
    return
  end

  local current_file_idx = state.get_current_file_index()
  local current_line = vim.fn.line(".")

  -- Find next point after current position
  for _, point in ipairs(all_points) do
    if point.file_index > current_file_idx or
       (point.file_index == current_file_idx and point.line > current_line) then
      goto_point(point)
      return
    end
  end

  -- No next point found - go to next file
  diff.next_file()
end

--- Go to previous point of interest (diff or comment, across files)
function M.prev_point()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end

  local all_points = get_all_points()
  if #all_points == 0 then
    diff.prev_file()
    return
  end

  local current_file_idx = state.get_current_file_index()
  local current_line = vim.fn.line(".")

  -- Find previous point before current position (iterate in reverse)
  for i = #all_points, 1, -1 do
    local point = all_points[i]
    if point.file_index < current_file_idx or
       (point.file_index == current_file_idx and point.line < current_line) then
      goto_point(point)
      return
    end
  end

  -- No previous point found - go to previous file
  diff.prev_file()
end

--- Get all comment threads across all files (comments only, no diffs)
---@return table[] comment_points List of {file_index, file, line, type="comment"}
local function get_all_comment_points()
  local files = state.get_files()
  local comment_points = {}

  for file_idx, file in ipairs(files) do
    local file_comments = state.get_comments(file.filename)
    local seen = {}

    for _, comment in ipairs(file_comments) do
      local line = get_comment_line(comment)
      if line and not seen[line] then
        table.insert(comment_points, {
          file_index = file_idx,
          file = file,
          line = line,
          type = "comment",
        })
        seen[line] = true
      end
    end
  end

  -- Sort by file index, then by line
  table.sort(comment_points, function(a, b)
    if a.file_index ~= b.file_index then
      return a.file_index < b.file_index
    end
    return a.line < b.line
  end)

  return comment_points
end

--- Go to next comment thread (across files)
function M.next_thread()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return
  end

  local comment_points = get_all_comment_points()
  if #comment_points == 0 then
    vim.notify("No comment threads in this PR", vim.log.levels.INFO)
    return
  end

  local current_file_idx = state.get_current_file_index()
  local current_line = vim.fn.line(".")

  -- Find next comment after current position
  for _, point in ipairs(comment_points) do
    if point.file_index > current_file_idx or
       (point.file_index == current_file_idx and point.line > current_line) then
      goto_point(point)
      return
    end
  end

  -- Wrap around to first comment
  vim.notify("Wrapped to first thread", vim.log.levels.INFO)
  goto_point(comment_points[1])
end

--- Go to previous comment thread (across files)
function M.prev_thread()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return
  end

  local comment_points = get_all_comment_points()
  if #comment_points == 0 then
    vim.notify("No comment threads in this PR", vim.log.levels.INFO)
    return
  end

  local current_file_idx = state.get_current_file_index()
  local current_line = vim.fn.line(".")

  -- Find previous comment before current position (iterate in reverse)
  for i = #comment_points, 1, -1 do
    local point = comment_points[i]
    if point.file_index < current_file_idx or
       (point.file_index == current_file_idx and point.line < current_line) then
      goto_point(point)
      return
    end
  end

  -- Wrap around to last comment
  vim.notify("Wrapped to last thread", vim.log.levels.INFO)
  goto_point(comment_points[#comment_points])
end

--- Open or create comment at current line
function M.comment_at_cursor()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return
  end

  -- Just delegate to show_comment_thread - it handles both cases
  comments.show_comment_thread()
end

--- Show PR description in floating window
function M.show_description()
  local ui = require("raccoon.ui")
  ui.show_description()
end

--- Show all PR comments
function M.list_comments()
  comments.list_comments()
end

--- Format CI check status for display
---@param check_runs table Check runs response from GitHub API
---@return string status_line Formatted status line
local function format_ci_status(check_runs)
  if not check_runs or not check_runs.check_runs then
    return "CI: Unable to fetch status"
  end

  local passed, failed, pending = 0, 0, 0
  for _, run in ipairs(check_runs.check_runs) do
    if run.conclusion == "success" then
      passed = passed + 1
    elseif run.conclusion == "failure" or run.conclusion == "timed_out" then
      failed = failed + 1
    elseif run.status == "in_progress" or run.status == "queued" or not run.conclusion then
      pending = pending + 1
    end
  end

  local total = passed + failed + pending
  if total == 0 then
    return "CI: No checks configured"
  end

  local parts = {}
  if passed > 0 then table.insert(parts, passed .. " passed") end
  if failed > 0 then table.insert(parts, failed .. " failed") end
  if pending > 0 then table.insert(parts, pending .. " pending") end

  return "CI: " .. table.concat(parts, ", ")
end

--- Show merge type picker and merge PR
function M.merge_picker()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return
  end

  -- Check for conflicts first
  local sync_status = state.get_sync_status()
  if sync_status.has_conflicts then
    vim.notify("Cannot merge: PR has merge conflicts", vim.log.levels.ERROR)
    return
  end

  local pr = state.get_pr()
  local number = state.get_number()
  local owner = state.get_owner()
  local repo = state.get_repo()
  local cfg, cfg_err = config.load()
  if cfg_err then
    vim.notify("Config error: " .. cfg_err, vim.log.levels.ERROR)
    return
  end
  api.init(state.get_github_host() or cfg.github_host)
  local token = config.get_token_for_owner(cfg, owner)
  if not token then
    vim.notify(string.format("No token configured for '%s'. Add it to tokens in config.", owner), vim.log.levels.ERROR)
    return
  end

  -- Fetch check runs first, then show picker
  vim.notify("Fetching CI status...", vim.log.levels.INFO)
  api.get_check_runs(owner, repo, pr.head.sha, token, function(check_runs, err)
    vim.schedule(function()
      local ci_status
      if err then
        ci_status = "CI: Failed to fetch (" .. err:sub(1, 30) .. ")"
      else
        ci_status = format_ci_status(check_runs)
      end

      -- Create picker buffer with CI status
      local lines = {
        "Select merge method for PR #" .. number .. ":",
        "",
        "  " .. ci_status,
        "",
        "  [1] Merge        - Create a merge commit",
        "  [2] Squash       - Squash and merge",
        "  [3] Rebase       - Rebase and merge",
        "",
        "  [q] Cancel",
      }

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_option(buf, "modifiable", false)

      local width = 50
      local height = #lines + 1

      local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        row = math.floor((vim.o.lines - height) / 2),
        col = math.floor((vim.o.columns - width) / 2),
        width = width,
        height = height,
        style = "minimal",
        border = "rounded",
        title = " Merge PR ",
        title_pos = "center",
      })

      -- Highlight the title and CI status
      vim.api.nvim_buf_call(buf, function()
        vim.fn.matchadd("Title", "^Select merge method.*")
        vim.fn.matchadd("Number", "\\[1\\]\\|\\[2\\]\\|\\[3\\]")
        vim.fn.matchadd("Comment", "\\[q\\]")
        -- Highlight CI status based on content
        if ci_status:find("failed") then
          vim.fn.matchadd("ErrorMsg", "CI:.*failed.*")
        elseif ci_status:find("pending") then
          vim.fn.matchadd("WarningMsg", "CI:.*pending.*")
        elseif ci_status:find("passed") then
          vim.fn.matchadd("DiagnosticOk", "CI:.*passed.*")
        end
      end)

      local function do_merge(method)
        vim.api.nvim_win_close(win, true)
        vim.cmd("Raccoon " .. method)
      end

      -- Keymaps for selection (adjusted line numbers for CI status line)
      local km_opts = { buffer = buf, noremap = true, silent = true }
      vim.keymap.set(NORMAL_MODE, "1", function() do_merge("merge") end, km_opts)
      vim.keymap.set(NORMAL_MODE, "2", function() do_merge("squash") end, km_opts)
      vim.keymap.set(NORMAL_MODE, "3", function() do_merge("rebase") end, km_opts)
      vim.keymap.set(NORMAL_MODE, "<CR>", function()
        local cursor_line = vim.fn.line(".")
        if cursor_line == 5 then do_merge("merge")
        elseif cursor_line == 6 then do_merge("squash")
        elseif cursor_line == 7 then do_merge("rebase")
        end
      end, { buffer = buf, noremap = true, silent = true })
      local shortcuts = config.load_shortcuts()
      local close_win = function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end
      local close_opts = { buffer = buf, noremap = true, silent = true, nowait = true }
      if config.is_enabled(shortcuts.close) then
        vim.keymap.set(NORMAL_MODE, shortcuts.close, close_win, close_opts)
      end
      vim.keymap.set(NORMAL_MODE, "<Esc>", close_win, close_opts)
    end)
  end)
end

--- Build PR review keymaps from config shortcuts
---@param shortcuts table Shortcut bindings from config
---@return table[] keymaps
function M.build_keymaps(shortcuts)
  local n = NORMAL_MODE
  local all = {
    { mode = n, lhs = shortcuts.next_point, rhs = function() M.next_point() end, desc = "Next diff/comment" },
    { mode = n, lhs = shortcuts.prev_point, rhs = function() M.prev_point() end, desc = "Previous diff/comment" },
    { mode = n, lhs = shortcuts.next_file, rhs = function() diff.next_file() end, desc = "Next file" },
    { mode = n, lhs = shortcuts.prev_file, rhs = function() diff.prev_file() end, desc = "Previous file" },
    { mode = n, lhs = shortcuts.next_thread, rhs = function() M.next_thread() end, desc = "Next comment thread" },
    { mode = n, lhs = shortcuts.prev_thread, rhs = function() M.prev_thread() end, desc = "Previous comment thread" },
    { mode = n, lhs = shortcuts.comment, rhs = function() M.comment_at_cursor() end, desc = "Comment at cursor" },
    { mode = n, lhs = shortcuts.description, rhs = function() M.show_description() end, desc = "Show PR description" },
    { mode = n, lhs = shortcuts.list_comments, rhs = function() M.list_comments() end, desc = "List all PR comments" },
    { mode = n, lhs = shortcuts.merge, rhs = function() M.merge_picker() end, desc = "Merge PR (pick method)" },
    { mode = n, lhs = shortcuts.commit_viewer, rhs = function()
      require("raccoon.commits").toggle()
    end, desc = "Toggle commit viewer" },
  }
  local result = {}
  for _, km in ipairs(all) do
    if config.is_enabled(km.lhs) then
      table.insert(result, km)
    end
  end
  return result
end

--- Current active keymaps (built from config at setup time)
M.keymaps = {}

--- Cached passthrough keymaps (loaded from config at setup time)
M.passthrough_keymaps = {}

--- Delay (ms) before re-registering raccoon keymaps after a passthrough fires.
--- Must be long enough for nvim_feedkeys ("m" mode) to fully resolve the external
--- plugin's mapping. Most plugins complete within a single event-loop tick (~1ms),
--- but vim.schedule can race with queued keys, so we use vim.defer_fn instead.
local PASSTHROUGH_RESTORE_DELAY_MS = 50

--- Remove all raccoon buffer-local keymaps from a buffer.
--- This clears both regular review keymaps and passthrough wrappers so that
--- fed keys can resolve against global plugin mappings without prefix conflicts.
---@param buf number Buffer ID
local function remove_all_raccoon_keymaps(buf)
  for _, km in ipairs(M.keymaps) do
    pcall(vim.keymap.del, km.mode, km.lhs, { buffer = buf })
  end
  for _, pt in ipairs(M.passthrough_keymaps) do
    pcall(vim.keymap.del, pt.mode, pt.key, { buffer = buf })
  end
end

--- Re-register all raccoon buffer-local keymaps on a buffer.
--- Forward-declared because setup_passthrough_keymap and this function are mutually recursive.
---@type fun(buf: number)
local restore_all_raccoon_keymaps

--- Setup a single passthrough keymap on a buffer.
--- Removes ALL raccoon buffer-local keymaps and feeds the original key so external
--- plugins can handle it. The buffer stays read-only (modifiable=false) — passthrough
--- only solves keymap shadowing, not buffer writability. Removing all raccoon keymaps
--- (not just this wrapper) is necessary because same-prefix keymaps (e.g. <leader>j
--- when passthrough is <leader>dd) shadow global plugin mappings during feedkeys
--- resolution. After PASSTHROUGH_RESTORE_DELAY_MS, re-registers all raccoon keymaps.
---@param buf number Buffer ID
---@param mode string Vim mode ("n", "v", etc.)
---@param key string Key sequence (e.g. "gcc", "<leader>f")
local function setup_passthrough_keymap(buf, mode, key)
  vim.keymap.set(mode, key, function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local ok, err = pcall(function()
      remove_all_raccoon_keymaps(buf)
      local escaped = vim.api.nvim_replace_termcodes(key, true, false, true)
      vim.api.nvim_feedkeys(escaped, "m", false)
    end)
    if not ok then
      vim.notify("Raccoon passthrough error (" .. key .. "): " .. tostring(err), vim.log.levels.WARN)
    end
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(buf) then
        restore_all_raccoon_keymaps(buf)
      end
    end, PASSTHROUGH_RESTORE_DELAY_MS)
  end, { buffer = buf, noremap = true, silent = true, desc = "Raccoon passthrough: " .. key })
end

restore_all_raccoon_keymaps = function(buf)
  for _, km in ipairs(M.keymaps) do
    local opts = vim.tbl_extend("force", default_opts, { desc = km.desc, buffer = buf })
    pcall(function() vim.keymap.set(km.mode, km.lhs, km.rhs, opts) end)
  end
  for _, pt in ipairs(M.passthrough_keymaps) do
    setup_passthrough_keymap(buf, pt.mode, pt.key)
  end
end

--- Build keymaps table and cache passthrough keymaps for buffer-local registration.
--- Does NOT set global keymaps — keymaps are only active on raccoon-managed buffers.
function M.setup()
  local shortcuts = config.load_shortcuts()
  M.keymaps = M.build_keymaps(shortcuts)
  M.passthrough_keymaps = config.load_passthrough_keymaps()
end

--- Clear the keymaps and passthrough tables.
--- Buffer-local keymaps are automatically cleaned up when buffers are deleted.
function M.clear()
  M.keymaps = {}
  M.passthrough_keymaps = {}
end

--- Setup buffer-local keymaps for a specific buffer
---@param buf number Buffer ID
function M.setup_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Auto-build on first call: open_file() in diff.lua calls setup_buffer() before
  -- open_first_file() has a chance to call setup(), so we lazily initialize here.
  -- This is safe because clear() only runs during close_pr(), which also deletes
  -- all raccoon buffers — no stale buffer can trigger an unintended re-init.
  if #M.keymaps == 0 then
    M.setup()
  end

  restore_all_raccoon_keymaps(buf)
end

return M
