---@class RaccoonKeymaps
---Keymap management for PR review sessions
---All keymaps use <leader> prefix to avoid conflicts with Vim builtins
local M = {}

local api = require("raccoon.api")
local comments = require("raccoon.comments")
local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local diff = require("raccoon.diff")
local state = require("raccoon.state")
local thread_index = require("raccoon.thread_index")

local function popup_ui()
  return require("raccoon.ui")
end

--- Default keymap options
local default_opts = { noremap = true, silent = true }

--- Get a valid line number from a comment, handling vim.NIL from JSON null
---@param comment table
---@return number|nil
local function in_flat_diff_mode()
  return state.is_active() and not state.is_commit_mode() and not require("raccoon.localcommits").is_active()
end

local function flat_diff_only()
  vim.notify("Available only in flat diff review mode", vim.log.levels.INFO)
end

local function build_thread_index()
  local index, err = thread_index.build()
  if err then
    vim.notify("Thread data error: " .. err, vim.log.levels.ERROR)
    return nil
  end
  return index
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
  local index = build_thread_index()
  local line_map = index and index.line_state_by_file[file.filename] or {}
  for line in pairs(line_map) do
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

local function get_navigable_threads()
  local index = build_thread_index()
  if not index then
    return {}
  end
  return index.unresolved_threads or {}
end

local function goto_thread(thread, open_if_no_line)
  if not thread then
    return
  end
  comments.jump_to_thread(thread.thread_id, { open_window_if_no_line = open_if_no_line })
end

local function find_selected_thread_index(threads)
  local current_thread_id = state.get_selected_thread_id()
  if not current_thread_id then
    return nil
  end
  for idx, thread in ipairs(threads) do
    if thread.thread_id == current_thread_id then
      return idx
    end
  end
  return nil
end

--- Go to next comment thread (across files)
function M.next_thread()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return
  end

  if not in_flat_diff_mode() then
    flat_diff_only()
    return
  end

  local threads = get_navigable_threads()
  if #threads == 0 then
    vim.notify("No unresolved threads in this PR", vim.log.levels.INFO)
    return
  end

  local selected_idx = find_selected_thread_index(threads)
  if selected_idx then
    local next_idx = selected_idx < #threads and (selected_idx + 1) or 1
    if next_idx == 1 and selected_idx == #threads then
      vim.notify("Wrapped to first thread", vim.log.levels.INFO)
    end
    goto_thread(threads[next_idx], true)
    return
  end

  local current_file_idx = state.get_current_file_index()
  local current_line = vim.fn.line(".")
  for _, thread in ipairs(threads) do
    local thread_line = thread.line or math.huge
    if thread.file_index > current_file_idx
        or (thread.file_index == current_file_idx and thread_line > current_line)
    then
      goto_thread(thread, true)
      return
    end
  end
  vim.notify("Wrapped to first thread", vim.log.levels.INFO)
  goto_thread(threads[1], true)
end

--- Go to previous comment thread (across files)
function M.prev_thread()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return
  end

  if not in_flat_diff_mode() then
    flat_diff_only()
    return
  end

  local threads = get_navigable_threads()
  if #threads == 0 then
    vim.notify("No unresolved threads in this PR", vim.log.levels.INFO)
    return
  end

  local selected_idx = find_selected_thread_index(threads)
  if selected_idx then
    local prev_idx = selected_idx > 1 and (selected_idx - 1) or #threads
    if prev_idx == #threads and selected_idx == 1 then
      vim.notify("Wrapped to last thread", vim.log.levels.INFO)
    end
    goto_thread(threads[prev_idx], true)
    return
  end

  local current_file_idx = state.get_current_file_index()
  local current_line = vim.fn.line(".")
  for i = #threads, 1, -1 do
    local thread = threads[i]
    local thread_line = thread.line or math.huge
    if thread.file_index < current_file_idx
        or (thread.file_index == current_file_idx and thread_line < current_line)
    then
      goto_thread(thread, true)
      return
    end
  end

  vim.notify("Wrapped to last thread", vim.log.levels.INFO)
  goto_thread(threads[#threads], true)
end

function M.next_needs_reply_thread()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return
  end

  if not in_flat_diff_mode() then
    flat_diff_only()
    return
  end

  local all_threads = get_navigable_threads()
  local threads = {}
  for _, thread in ipairs(all_threads) do
    if thread.needs_reply then
      table.insert(threads, thread)
    end
  end
  if #threads == 0 then
    vim.notify("No unresolved threads need your reply", vim.log.levels.INFO)
    return
  end

  local selected_idx = find_selected_thread_index(threads)
  if selected_idx then
    local next_idx = selected_idx < #threads and (selected_idx + 1) or 1
    if next_idx == 1 and selected_idx == #threads then
      vim.notify("Wrapped to first needs-reply thread", vim.log.levels.INFO)
    end
    goto_thread(threads[next_idx], true)
    return
  end

  local current_file_idx = state.get_current_file_index()
  local current_line = vim.fn.line(".")
  for _, thread in ipairs(threads) do
    local thread_line = thread.line or math.huge
    if thread.file_index > current_file_idx
        or (thread.file_index == current_file_idx and thread_line > current_line)
    then
      goto_thread(thread, true)
      return
    end
  end

  vim.notify("Wrapped to first needs-reply thread", vim.log.levels.INFO)
  goto_thread(threads[1], true)
end

function M.next_file()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end
  if not in_flat_diff_mode() then
    flat_diff_only()
    return false
  end

  local files = state.get_files()
  if #files == 0 then
    return false
  end

  if not state.next_file() then
    state.goto_file(1)
  end
  local file = state.get_current_file()
  return file and comments.jump_to_file(file.filename) or false
end

function M.prev_file()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end
  if not in_flat_diff_mode() then
    flat_diff_only()
    return false
  end

  local files = state.get_files()
  if #files == 0 then
    return false
  end

  if not state.prev_file() then
    state.goto_file(#files)
  end
  local file = state.get_current_file()
  return file and comments.jump_to_file(file.filename) or false
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

function M.list_threads()
  comments.list_threads()
end

function M.list_files()
  comments.list_files()
end

function M.sync()
  if state.is_active() then
    local open = require("raccoon.open")
    open.sync()
    return
  end
  local ui = require("raccoon.ui")
  if ui.is_pr_list_open() then
    ui.refresh_pr_list()
    return
  end
  vim.notify("No active raccoon view to sync", vim.log.levels.WARN)
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

  if state.is_commit_mode() or require("raccoon.localcommits").is_active() then
    flat_diff_only()
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

      local shortcuts = config.load_shortcuts()
      local merge_options = {
        { method = "merge", label = "Merge", detail = "Create a merge commit" },
        { method = "squash", label = "Squash", detail = "Squash and merge" },
        { method = "rebase", label = "Rebase", detail = "Rebase and merge" },
      }
      local lines = {
        "  " .. ci_status,
        "",
        string.format("  %-8s - %s", merge_options[1].label, merge_options[1].detail),
        string.format("  %-8s - %s", merge_options[2].label, merge_options[2].detail),
        string.format("  %-8s - %s", merge_options[3].label, merge_options[3].detail),
      }

      local ui_mod = popup_ui()
      local title = ui_mod.decorate_popup_title("Merge PR #" .. number, {
        { literal = "Enter", label = "select" },
        { literal = "j/k", label = "navigate" },
        { key = "close", label = "close" },
      }, shortcuts)
      local width
      lines, width = ui_mod.fit_popup_lines(lines, {
        title = title,
        min_width = 36,
        max_width = math.max(36, vim.o.columns - 8),
      })
      local height = math.min(math.max(1, #lines), vim.o.lines - 6)
      local win, float_buf = ui_mod.create_floating_window({
        width = width,
        height = height,
        title = title,
        border = "rounded",
        wrap = false,
      })
      local buf = float_buf

      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_buf_set_option(buf, "modifiable", false)

      -- Highlight the title and CI status
      vim.api.nvim_buf_call(buf, function()
        -- Highlight CI status based on content
        if ci_status:find("failed") then
          vim.fn.matchadd("ErrorMsg", "CI:.*failed.*")
        elseif ci_status:find("pending") then
          vim.fn.matchadd("WarningMsg", "CI:.*pending.*")
        elseif ci_status:find("passed") then
          vim.fn.matchadd("DiagnosticOk", "CI:.*passed.*")
        end
        vim.fn.matchadd("Bold", "^  Merge")
        vim.fn.matchadd("Bold", "^  Squash")
        vim.fn.matchadd("Bold", "^  Rebase")
      end)

      local function do_merge(method)
        vim.api.nvim_win_close(win, true)
        vim.cmd("Raccoon " .. method)
      end

      local km_opts = { buffer = buf, noremap = true, silent = true }
      local option_rows = { 3, 4, 5 }
      local selected = 1
      local function set_selected()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_set_cursor(win, { option_rows[selected], 0 })
        end
      end
      local close_win = function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end
      ui_mod.bind_picker_navigation_keys(buf, {
        move_down = function()
          if selected < #merge_options then
            selected = selected + 1
            set_selected()
          end
        end,
        move_up = function()
          if selected > 1 then
            selected = selected - 1
            set_selected()
          end
        end,
        select = function()
          do_merge(merge_options[selected].method)
        end,
      }, {
        keymap_opts = km_opts,
      })
      ui_mod.bind_popup_close_keys(buf, close_win, {
        shortcuts = shortcuts,
        keymap_opts = { buffer = buf, noremap = true, silent = true, nowait = true },
      })
      set_selected()
    end)
  end)
end

--- Build PR review keymaps from config shortcuts
---@param shortcuts table Shortcut bindings from config
---@return table[] keymaps
function M.build_keymaps(shortcuts)
  local n = NORMAL_MODE
  local function map(lhs, rhs, desc)
    return { mode = n, lhs = lhs, rhs = rhs, desc = desc }
  end
  local all = {
    map(shortcuts.next_point, function() M.next_point() end, "Raccoon: Next diff/comment (flat diff only)"),
    map(shortcuts.prev_point, function() M.prev_point() end, "Raccoon: Previous diff/comment (flat diff only)"),
    map(shortcuts.next_file, function() M.next_file() end, "Raccoon: Next file (flat diff only)"),
    map(shortcuts.prev_file, function() M.prev_file() end, "Raccoon: Previous file (flat diff only)"),
    map(shortcuts.next_thread, function() M.next_thread() end, "Raccoon: Next unresolved thread (flat diff only)"),
    map(shortcuts.prev_thread, function() M.prev_thread() end, "Raccoon: Previous unresolved thread (flat diff only)"),
    map(
      shortcuts.next_needs_reply_thread,
      function() M.next_needs_reply_thread() end,
      "Raccoon: Next needs-reply thread (flat diff only)"
    ),
    map(shortcuts.comment, function() M.comment_at_cursor() end, "Raccoon: Comment at cursor (flat diff only)"),
    map(shortcuts.description, function() M.show_description() end, "Raccoon: Show PR description"),
    map(shortcuts.list_comments, function() M.list_comments() end, "Raccoon: List PR comments (flat diff only)"),
    map(shortcuts.list_files, function() M.list_files() end, "Raccoon: List changed files (flat diff only)"),
    map(shortcuts.list_threads, function() M.list_threads() end, "Raccoon: List unresolved threads (flat diff only)"),
    map(shortcuts.sync, function() M.sync() end, "Raccoon: Sync current view"),
    map(shortcuts.merge, function() M.merge_picker() end, "Raccoon: Merge PR (flat diff only)"),
    map(shortcuts.commit_viewer_toggle, function()
      require("raccoon.commits").toggle()
    end, "Raccoon: Toggle commit viewer"),
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

--- Setup all keymaps for PR review mode
function M.setup()
  local shortcuts = config.load_shortcuts()
  M.keymaps = M.build_keymaps(shortcuts)
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
