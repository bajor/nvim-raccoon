---@class RaccoonKeymaps
---Keymap management for PR review sessions
---All keymaps use <leader> prefix to avoid conflicts with Vim builtins
local M = {}

local api = require("raccoon.api")
local comments = require("raccoon.comments")
local config = require("raccoon.config")
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
  local token = config.get_token_for_owner(cfg, owner)

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
      vim.keymap.set("n", "1", function() do_merge("merge") end, { buffer = buf, noremap = true, silent = true })
      vim.keymap.set("n", "2", function() do_merge("squash") end, { buffer = buf, noremap = true, silent = true })
      vim.keymap.set("n", "3", function() do_merge("rebase") end, { buffer = buf, noremap = true, silent = true })
      vim.keymap.set("n", "<CR>", function()
        local cursor_line = vim.fn.line(".")
        if cursor_line == 5 then do_merge("merge")
        elseif cursor_line == 6 then do_merge("squash")
        elseif cursor_line == 7 then do_merge("rebase")
        end
      end, { buffer = buf, noremap = true, silent = true })
      local close_win = function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end
      vim.keymap.set("n", "<leader>q", close_win, { buffer = buf, noremap = true, silent = true, nowait = true })
      vim.keymap.set("n", "<Esc>", close_win, { buffer = buf, noremap = true, silent = true, nowait = true })
    end)
  end)
end

--- All PR review keymaps (simplified)
M.keymaps = {
  { mode = "n", lhs = "<leader>j", rhs = function() M.next_point() end, desc = "Next diff/comment" },
  { mode = "n", lhs = "<leader>k", rhs = function() M.prev_point() end, desc = "Previous diff/comment" },
  { mode = "n", lhs = "<leader>nf", rhs = function() diff.next_file() end, desc = "Next file" },
  { mode = "n", lhs = "<leader>pf", rhs = function() diff.prev_file() end, desc = "Previous file" },
  { mode = "n", lhs = "<leader>nt", rhs = function() M.next_thread() end, desc = "Next comment thread" },
  { mode = "n", lhs = "<leader>pt", rhs = function() M.prev_thread() end, desc = "Previous comment thread" },
  { mode = "n", lhs = "<leader>c", rhs = function() M.comment_at_cursor() end, desc = "Comment at cursor" },
  { mode = "n", lhs = "<leader>dd", rhs = function() M.show_description() end, desc = "Show PR description" },
  { mode = "n", lhs = "<leader>ll", rhs = function() M.list_comments() end, desc = "List all PR comments" },
  { mode = "n", lhs = "<leader>rr", rhs = function() M.merge_picker() end, desc = "Merge PR (pick method)" },
}

--- Setup all keymaps for PR review mode
function M.setup()
  for _, km in ipairs(M.keymaps) do
    local opts = vim.tbl_extend("force", default_opts, { desc = km.desc })
    vim.keymap.set(km.mode, km.lhs, km.rhs, opts)
  end
end

--- Clear all PR review keymaps
function M.clear()
  for _, km in ipairs(M.keymaps) do
    pcall(vim.keymap.del, km.mode, km.lhs)
  end
end

--- Setup buffer-local keymaps for a specific buffer
---@param buf number Buffer ID
function M.setup_buffer(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  for _, km in ipairs(M.keymaps) do
    local opts = vim.tbl_extend("force", default_opts, { desc = km.desc, buffer = buf })
    vim.keymap.set(km.mode, km.lhs, km.rhs, opts)
  end
end

return M
