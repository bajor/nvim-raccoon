---@class RaccoonComments
---Comment management and display
local M = {}

local api = require("raccoon.api")
local config = require("raccoon.config")
local state = require("raccoon.state")

--- Get a valid line number from a comment, handling vim.NIL from JSON null
---@param comment table
---@return number|nil
local function get_comment_line(comment)
  -- Check each field, ensuring it's a real number (not vim.NIL or other types)
  for _, field in ipairs({ "line", "original_line", "position" }) do
    local val = comment[field]
    if type(val) == "number" and val > 0 then
      return val
    end
  end
  return nil
end

--- Namespace for comment highlights and extmarks
local ns_id = vim.api.nvim_create_namespace("raccoon_comments")

--- Sign group for comments
local sign_group = "RaccoonComment"

--- Define signs and highlight groups for comments
local function setup_highlights()
  -- Bright yellow/orange background for comment lines - very visible
  vim.api.nvim_set_hl(0, "RaccoonCommentLine", { bg = "#4a3d00", fg = "#ffcc00", bold = true })
  vim.api.nvim_set_hl(0, "RaccoonCommentLineResolved", { bg = "#1a3d1a", fg = "#88cc88" })
  vim.api.nvim_set_hl(0, "RaccoonCommentLinePending", { bg = "#4a2800", fg = "#ffaa00", bold = true })
  vim.api.nvim_set_hl(0, "RaccoonCommentSign", { fg = "#ffcc00", bold = true })

  -- Sign highlights with line highlighting
  vim.fn.sign_define("RaccoonComment", {
    text = "💬",
    texthl = "RaccoonCommentSign",
    linehl = "RaccoonCommentLine",
    numhl = "RaccoonCommentSign",
  })
  vim.fn.sign_define("RaccoonCommentResolved", {
    text = "✓",
    texthl = "DiagnosticOk",
    linehl = "RaccoonCommentLineResolved",
    numhl = "DiagnosticOk",
  })
  vim.fn.sign_define("RaccoonCommentPending", {
    text = "○",
    texthl = "RaccoonCommentSign",
    linehl = "RaccoonCommentLinePending",
    numhl = "RaccoonCommentSign",
  })
end

-- Initialize highlights and signs
setup_highlights()

--- Get the current file path relative to clone root
---@return string|nil
local function get_current_file_path()
  local clone_path = state.get_clone_path()
  if not clone_path then
    return nil
  end

  local current_file = vim.fn.expand("%:p")
  if current_file:sub(1, #clone_path) == clone_path then
    return current_file:sub(#clone_path + 2) -- +2 to skip the trailing /
  end
  return nil
end

--- Show comments in the sign column and as virtual text
---@param buf number Buffer ID
---@param comments table[] Comments for this file
function M.show_comments(buf, comments)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Clear existing comment displays
  M.clear_comments(buf)

  -- Ensure sign column is visible
  vim.api.nvim_buf_call(buf, function()
    vim.opt_local.signcolumn = "yes:2"
  end)

  -- Get buffer line count to avoid placing signs on non-existent lines
  local line_count = vim.api.nvim_buf_line_count(buf)

  for _, comment in ipairs(comments or {}) do
    local line = get_comment_line(comment)
    if line and line <= line_count then
      -- Place sign with high priority
      local sign_name = "RaccoonComment"
      if comment.resolved then
        sign_name = "RaccoonCommentResolved"
      elseif comment.pending then
        sign_name = "RaccoonCommentPending"
      end

      -- Priority 100 to ensure we're above most other signs
      pcall(vim.fn.sign_place, 0, sign_group, sign_name, buf, { lnum = line, priority = 100 })

      -- Add virtual text preview with bright highlight
      local preview = comment.body or ""
      preview = preview:gsub("\n", " "):sub(1, 50)
      if #(comment.body or "") > 50 then
        preview = preview .. "..."
      end

      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line - 1, 0, {
        virt_text = { { "  💬 " .. preview, "RaccoonCommentSign" } },
        virt_text_pos = "eol",
      })
    end
  end
end

--- Clear comment displays from a buffer
---@param buf number Buffer ID
function M.clear_comments(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.fn.sign_unplace(sign_group, { buffer = buf })
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  end
end

--- Get comments for the current buffer
---@return table[] comments
function M.get_buffer_comments()
  local path = get_current_file_path()
  if not path then
    return {}
  end
  return state.get_comments(path)
end

--- Find the next comment after the current line
---@return table|nil comment
---@return number|nil line
function M.find_next_comment()
  local comments = M.get_buffer_comments()
  local current_line = vim.fn.line(".")

  local next_comment = nil
  local next_line = math.huge

  for _, comment in ipairs(comments) do
    local line = get_comment_line(comment)
    if line and line > current_line and line < next_line then
      next_comment = comment
      next_line = line
    end
  end

  if next_comment then
    return next_comment, next_line
  end
  return nil, nil
end

--- Find the previous comment before the current line
---@return table|nil comment
---@return number|nil line
function M.find_prev_comment()
  local comments = M.get_buffer_comments()
  local current_line = vim.fn.line(".")

  local prev_comment = nil
  local prev_line = 0

  for _, comment in ipairs(comments) do
    local line = get_comment_line(comment)
    if line and line < current_line and line > prev_line then
      prev_comment = comment
      prev_line = line
    end
  end

  if prev_comment then
    return prev_comment, prev_line
  end
  return nil, nil
end

--- Jump to next comment
---@return boolean success
function M.next_comment()
  local comment, line = M.find_next_comment()
  if comment and line then
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    M.show_comment_popup(comment)
    return true
  end
  vim.notify("No more comments below", vim.log.levels.INFO)
  return false
end

--- Jump to previous comment
---@return boolean success
function M.prev_comment()
  local comment, line = M.find_prev_comment()
  if comment and line then
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    M.show_comment_popup(comment)
    return true
  end
  vim.notify("No more comments above", vim.log.levels.INFO)
  return false
end

--- Show a comment in a floating window
---@param comment table Comment data
function M.show_comment_popup(comment)
  if not comment then
    return
  end

  local lines = {}
  table.insert(lines, "Author: " .. (comment.user and comment.user.login or "unknown"))
  table.insert(lines, "")

  -- Split body into lines
  for line in (comment.body or ""):gmatch("[^\n]+") do
    table.insert(lines, line)
  end

  -- Calculate window dimensions
  local max_width = 120
  local width = 0
  for _, line in ipairs(lines) do
    width = math.max(width, #line)
  end
  width = math.min(width + 2, max_width)
  local height = math.min(#lines, 30)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " Comment ",
    title_pos = "center",
  })

  -- Close on <leader>q or Esc
  vim.keymap.set("n", "<leader>q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })
end

--- Divider line for separating comments in thread view
local COMMENT_DIVIDER = "────────────────────────────────────────────────"
local NEW_COMMENT_HEADER = "── New Comment ──────────────────────────────────"

--- Show a read-only thread view in a floating window
--- Displays all comments for a given thread, or a single review body
---@param opts table {comments: table[], title: string}
function M.show_readonly_thread(opts)
  local thread_comments = opts.comments
  if not thread_comments or #thread_comments == 0 then
    return
  end

  local lines = {}
  for i, comment in ipairs(thread_comments) do
    local author = comment.user and comment.user.login or "unknown"
    local status = ""
    if comment.is_review and comment.state then
      status = " [" .. comment.state:lower() .. "]"
    elseif comment.resolved then
      status = " [resolved]"
    elseif comment.pending then
      status = " [pending]"
    end

    table.insert(lines, "@ " .. author .. status)
    table.insert(lines, "")

    for body_line in (comment.body or ""):gmatch("[^\n]*") do
      table.insert(lines, body_line)
    end

    if i < #thread_comments then
      table.insert(lines, "")
      table.insert(lines, COMMENT_DIVIDER)
      table.insert(lines, "")
    end
  end

  local width = math.min(140, vim.o.columns - 4)
  local height = math.min(#lines + 2, 50)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = opts.title or " Thread ",
    title_pos = "center",
  })

  vim.wo[win].wrap = true

  local keymap_opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("n", "<leader>q", function()
    vim.api.nvim_win_close(win, true)
  end, keymap_opts)
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, keymap_opts)
end

--- Show threaded comment view for the current line
--- Allows viewing, editing existing comments, and adding new ones
function M.show_comment_thread()
  if not state.is_active() then
    vim.notify("No active PR review session", vim.log.levels.WARN)
    return
  end

  local path = get_current_file_path()
  if not path then
    vim.notify("Not in a PR file", vim.log.levels.WARN)
    return
  end

  local current_line = vim.fn.line(".")
  local file_comments = state.get_comments(path)

  -- Find comments for this line
  local line_comments = {}
  for _, comment in ipairs(file_comments) do
    local comment_line = get_comment_line(comment)
    if comment_line and comment_line == current_line then
      table.insert(line_comments, comment)
    end
  end

  -- Build buffer content with comment sections
  local lines = {}
  local comment_map = {} -- Maps buffer line ranges to comment data

  for i, comment in ipairs(line_comments) do
    local author = comment.user and comment.user.login or "unknown"
    local start_line = #lines + 1

    -- Add author header
    table.insert(lines, "@ " .. author .. (comment.pending and " [pending]" or ""))
    table.insert(lines, "")

    -- Add comment body (split into lines)
    local body_start = #lines + 1
    for body_line in (comment.body or ""):gmatch("[^\n]*") do
      table.insert(lines, body_line)
    end
    local body_end = #lines

    -- Track this comment's editable region
    comment_map[i] = {
      comment = comment,
      body_start = body_start,
      body_end = body_end,
      start_line = start_line,
    }

    -- Add divider if not last comment
    if i < #line_comments then
      table.insert(lines, "")
      table.insert(lines, COMMENT_DIVIDER)
      table.insert(lines, "")
    end
  end

  -- Add section for new comment
  if #line_comments > 0 then
    table.insert(lines, "")
    table.insert(lines, NEW_COMMENT_HEADER)
  else
    table.insert(lines, "@ New Comment")
  end
  table.insert(lines, "")
  local new_comment_start = #lines + 1
  table.insert(lines, "") -- Empty line for new comment

  -- Calculate window dimensions
  local width = 140
  local height = math.min(#lines + 2, 50)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
  vim.api.nvim_buf_set_option(buf, "modifiable", true)

  -- Create floating window
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = string.format(
      " Comments on L%d (<leader>s=save, <leader>r=resolve, <leader>u=unresolve, <leader>q=close) ",
      current_line
    ),
    title_pos = "center",
  })

  -- Helper to find which comment section cursor is in
  local function get_cursor_section()
    local cursor_line = vim.fn.line(".")

    -- Check if in new comment section
    if cursor_line >= new_comment_start then
      return { type = "new", start = new_comment_start }
    end

    -- Check existing comments
    for i, info in pairs(comment_map) do
      if cursor_line >= info.body_start and cursor_line <= info.body_end then
        return { type = "existing", index = i, info = info }
      end
    end

    return nil
  end

  -- Helper to extract body from a section
  local function get_section_body(start_line, end_line)
    local section_lines = vim.api.nvim_buf_get_lines(buf, start_line - 1, end_line, false)
    return table.concat(section_lines, "\n")
  end

  -- Save function
  local function save_comment()
    local section = get_cursor_section()
    if not section then
      vim.notify("Move cursor to a comment section to save", vim.log.levels.WARN)
      return
    end

    local cfg, cfg_err = config.load()
    if cfg_err then
      vim.notify("Config error: " .. cfg_err, vim.log.levels.ERROR)
      return
    end

    local owner = state.get_owner()
    local repo = state.get_repo()
    local number = state.get_number()
    local pr = state.get_pr()
    local token = config.get_token_for_owner(cfg, owner)

    if section.type == "new" then
      -- Get all lines from new_comment_start to end
      local all_lines = vim.api.nvim_buf_get_lines(buf, new_comment_start - 1, -1, false)
      local body = table.concat(all_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")

      if body == "" then
        vim.notify("Empty comment", vim.log.levels.WARN)
        return
      end

      vim.notify("Submitting new comment...", vim.log.levels.INFO)

      -- Helper for success
      local function on_success(result, is_line_comment)
        local new_comment = {
          id = result and result.id,
          path = path,
          line = current_line,
          body = body,
          pending = false,
          is_issue_comment = not is_line_comment,
          user = { login = cfg.github_username or "you" },
        }
        table.insert(file_comments, new_comment)
        state.set_comments(path, file_comments)

        local msg = is_line_comment and "Comment added!" or "Comment added (as PR comment - line not in diff)"
        vim.notify(msg, vim.log.levels.INFO)
        vim.api.nvim_win_close(win, true)
      end

      -- Try line-level comment first
      api.create_comment(owner, repo, number, {
        body = body,
        path = path,
        line = current_line,
        commit_id = pr.head.sha,
        side = "RIGHT",
      }, token, function(result, err)
        vim.schedule(function()
          if err then
            if err:find("422") then
              -- Fallback to PR issue comment
              vim.notify("Line not in diff, submitting as PR comment...", vim.log.levels.INFO)
              local formatted_body = string.format("**`%s:%d`**\n\n%s", path, current_line, body)

              api.create_issue_comment(owner, repo, number, formatted_body, token, function(issue_result, issue_err)
                vim.schedule(function()
                  if issue_err then
                    vim.notify("Failed: " .. issue_err, vim.log.levels.ERROR)
                    return
                  end
                  on_success(issue_result, false)
                end)
              end)
            else
              vim.notify("Failed: " .. err, vim.log.levels.ERROR)
            end
            return
          end

          on_success(result, true)
        end)
      end)

    elseif section.type == "existing" then
      local info = section.info
      local comment = info.comment

      -- Get updated body
      local body = get_section_body(info.body_start, info.body_end):gsub("^%s+", ""):gsub("%s+$", "")

      if body == comment.body then
        vim.notify("No changes", vim.log.levels.INFO)
        return
      end

      if not comment.id then
        vim.notify("Cannot edit pending comment - submit it first", vim.log.levels.WARN)
        return
      end

      vim.notify("Updating comment...", vim.log.levels.INFO)

      api.update_comment(owner, repo, comment.id, body, token, function(_result, err)
        vim.schedule(function()
          if err then
            vim.notify("Failed: " .. err, vim.log.levels.ERROR)
            return
          end

          -- Update local state
          comment.body = body
          vim.notify("Comment updated!", vim.log.levels.INFO)
          vim.api.nvim_win_close(win, true)
        end)
      end)
    end
  end

  -- Resolve thread function
  local function resolve_thread()
    if #line_comments == 0 then
      vim.notify("No comments to resolve", vim.log.levels.WARN)
      return
    end

    local thread_id = line_comments[1].thread_id
    if not thread_id then
      vim.notify("Cannot resolve thread: thread_id not found", vim.log.levels.ERROR)
      return
    end

    local cfg, cfg_err = config.load()
    if cfg_err then
      vim.notify("Config error: " .. cfg_err, vim.log.levels.ERROR)
      return
    end

    local owner = state.get_owner()
    local token = config.get_token_for_owner(cfg, owner)

    vim.notify("Resolving thread...", vim.log.levels.INFO)

    api.resolve_review_thread(thread_id, token, function(err)
      vim.schedule(function()
        if err then
          vim.notify("Failed to resolve thread: " .. err, vim.log.levels.ERROR)
          return
        end

        -- Toggle resolved status on all comments in this thread
        local all_resolved = true
        for _, comment in ipairs(line_comments) do
          if not comment.resolved then
            all_resolved = false
            break
          end
        end

        local new_status = not all_resolved
        for _, comment in ipairs(line_comments) do
          comment.resolved = new_status
        end

        -- Update state
        state.set_comments(path, file_comments)

        -- Refresh the current buffer's comment display
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(b) then
            local name = vim.api.nvim_buf_get_name(b)
            if name:find(path, 1, true) then
              M.show_comments(b, file_comments)
              break
            end
          end
        end

        local msg = new_status and "Thread resolved" or "Thread unresolved"
        vim.notify(msg, vim.log.levels.INFO)
        pcall(vim.api.nvim_win_close, win, true)
      end)
    end)
  end

  -- Unresolve thread function (explicit unresolve, not toggle)
  local function unresolve_thread()
    if #line_comments == 0 then
      vim.notify("No comments to unresolve", vim.log.levels.WARN)
      return
    end

    local thread_id = line_comments[1].thread_id
    if not thread_id then
      vim.notify("Cannot unresolve thread: thread_id not found", vim.log.levels.ERROR)
      return
    end

    local cfg, cfg_err = config.load()
    if cfg_err then
      vim.notify("Config error: " .. cfg_err, vim.log.levels.ERROR)
      return
    end

    local owner = state.get_owner()
    local token = config.get_token_for_owner(cfg, owner)

    vim.notify("Unresolving thread...", vim.log.levels.INFO)

    api.unresolve_review_thread(thread_id, token, function(err)
      vim.schedule(function()
        if err then
          vim.notify("Failed to unresolve thread: " .. err, vim.log.levels.ERROR)
          return
        end

        -- Check if any are resolved
        local any_resolved = false
        for _, comment in ipairs(line_comments) do
          if comment.resolved then
            any_resolved = true
            break
          end
        end

        if not any_resolved then
          vim.notify("Thread already unresolved", vim.log.levels.INFO)
          return
        end

        -- Unresolve all comments
        for _, comment in ipairs(line_comments) do
          comment.resolved = false
        end

        -- Update state
        state.set_comments(path, file_comments)

        -- Refresh the current buffer's comment display
        for _, b in ipairs(vim.api.nvim_list_bufs()) do
          if vim.api.nvim_buf_is_valid(b) then
            local name = vim.api.nvim_buf_get_name(b)
            if name:find(path, 1, true) then
              M.show_comments(b, file_comments)
              break
            end
          end
        end

        vim.notify("Thread unresolved", vim.log.levels.INFO)
        pcall(vim.api.nvim_win_close, win, true)
      end)
    end)
  end

  -- Keymaps
  vim.keymap.set("n", "<leader>s", save_comment, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<leader>r", resolve_thread, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<leader>u", unresolve_thread, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<leader>q", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })

  -- Position cursor in new comment section if no existing comments
  if #line_comments == 0 then
    vim.api.nvim_win_set_cursor(win, { new_comment_start, 0 })
    vim.cmd("startinsert")
  end
end

--- Create a new comment at the current line
function M.create_comment()
  if not state.is_active() then
    vim.notify("No active PR review session", vim.log.levels.WARN)
    return
  end

  local path = get_current_file_path()
  if not path then
    vim.notify("Not in a PR file", vim.log.levels.WARN)
    return
  end

  local line = vim.fn.line(".")

  -- Create input buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Create floating window for comment input
  local width = 120
  local height = 20
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "cursor",
    row = 1,
    col = 0,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " New Comment (<leader>s=save, <leader>q=cancel) ",
    title_pos = "center",
  })

  -- Start in insert mode
  vim.cmd("startinsert")

  -- Track if submitted (to distinguish q from w)
  local submitted = false

  -- Save and submit function
  local function save_and_submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local body = table.concat(lines, "\n")

    if body:match("^%s*$") then
      vim.notify("Empty comment, not saved", vim.log.levels.WARN)
      return
    end

    -- Load config for token
    local cfg, cfg_err = config.load()
    if cfg_err then
      vim.notify("Config error: " .. cfg_err, vim.log.levels.ERROR)
      return
    end

    -- Get PR info
    local owner = state.get_owner()
    local repo = state.get_repo()
    local number = state.get_number()
    local pr = state.get_pr()
    local token = config.get_token_for_owner(cfg, owner)

    if not pr or not pr.head or not pr.head.sha then
      vim.notify("Missing PR data (commit_id)", vim.log.levels.ERROR)
      return
    end

    vim.notify("Submitting comment...", vim.log.levels.INFO)
    submitted = true

    -- Helper to handle successful submission
    local function on_success(result, is_line_comment)
      -- Add to local state
      local new_comment = {
        id = result and result.id,
        path = path,
        line = line,
        body = body,
        pending = false,
        is_issue_comment = not is_line_comment,
        user = { login = cfg.github_username or "you" },
      }
      local comments = state.get_comments(path)
      table.insert(comments, new_comment)
      state.set_comments(path, comments)

      local msg = is_line_comment and "Comment submitted!" or "Comment submitted (as PR comment - line not in diff)"
      vim.notify(msg, vim.log.levels.INFO)

      -- Close window and refresh display
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
      for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) then
          local name = vim.api.nvim_buf_get_name(b)
          if name:find(path, 1, true) then
            M.show_comments(b, state.get_comments(path))
            break
          end
        end
      end
    end

    -- Try line-level comment first
    api.create_comment(owner, repo, number, {
      body = body,
      path = path,
      line = line,
      commit_id = pr.head.sha,
      side = "RIGHT",
    }, token, function(result, err)
      vim.schedule(function()
        if err then
          -- Check if it's a 422 error (line not in diff)
          if err:find("422") then
            -- Fall back to PR issue comment with file/line reference
            vim.notify("Line not in diff, submitting as PR comment...", vim.log.levels.INFO)
            local formatted_body = string.format("**`%s:%d`**\n\n%s", path, line, body)

            api.create_issue_comment(owner, repo, number, formatted_body, token, function(issue_result, issue_err)
              vim.schedule(function()
                if issue_err then
                  vim.notify("Failed to submit: " .. issue_err, vim.log.levels.ERROR)
                  submitted = false
                  return
                end
                on_success(issue_result, false)
              end)
            end)
          else
            vim.notify("Failed to submit: " .. err, vim.log.levels.ERROR)
            submitted = false
          end
          return
        end

        on_success(result, true)
      end)
    end)
  end

  -- Keymap: <leader>s to save and submit (works in normal mode)
  vim.keymap.set("n", "<leader>s", function()
    save_and_submit()
  end, { buffer = buf, noremap = true, silent = true })

  -- Keymap: <leader>q to cancel
  vim.keymap.set("n", "<leader>q", function()
    if not submitted then
      vim.notify("Comment cancelled", vim.log.levels.INFO)
    end
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })

  -- Also allow Escape to cancel
  vim.keymap.set("n", "<Esc>", function()
    if not submitted then
      vim.notify("Comment cancelled", vim.log.levels.INFO)
    end
    vim.api.nvim_win_close(win, true)
  end, { buffer = buf, noremap = true, silent = true })
end

--- Track comment list window for toggle behavior
local comment_list_win = nil

--- List all comments across all PR files (toggle behavior)
function M.list_comments()
  -- Toggle: if window is open, close it
  if comment_list_win and vim.api.nvim_win_is_valid(comment_list_win) then
    vim.api.nvim_win_close(comment_list_win, true)
    comment_list_win = nil
    return
  end

  if not state.is_active() then
    vim.notify("No active PR review session", vim.log.levels.WARN)
    return
  end

  -- Collect all comments from all files
  local all_comments = {}
  local total_count = 0

  -- Iterate through all file paths with comments (skip _reviews, handled separately)
  for file_path, file_comments in pairs(state.session.comments) do
    if file_path ~= "_reviews" and #file_comments > 0 then
      for _, comment in ipairs(file_comments) do
        table.insert(all_comments, {
          file = file_path,
          comment = comment,
        })
        total_count = total_count + 1
      end
    end
  end

  -- Collect review bodies (general review comments from bots, etc.)
  local reviews = state.session.comments["_reviews"] or {}
  total_count = total_count + #reviews

  if total_count == 0 then
    vim.notify("No comments in this PR", vim.log.levels.INFO)
    return
  end

  -- Sort by file path, then by line number
  table.sort(all_comments, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    local line_a = get_comment_line(a.comment) or 0
    local line_b = get_comment_line(b.comment) or 0
    return line_a < line_b
  end)

  -- Build display lines grouped by file
  local lines = {}
  local line_to_entry = {} -- Maps display line number to comment entry
  local current_file = nil

  for _, entry in ipairs(all_comments) do
    -- Add file header if new file
    if entry.file ~= current_file then
      if current_file ~= nil then
        table.insert(lines, "") -- Blank line between files
      end
      table.insert(lines, "── " .. entry.file .. " ──")
      current_file = entry.file
    end

    local comment = entry.comment
    local line_num = get_comment_line(comment) or 0
    local author = comment.user and comment.user.login or "unknown"
    local preview = (comment.body or ""):gsub("\n", " "):sub(1, 60)
    local status = comment.pending and " [pending]" or (comment.resolved and " [resolved]" or "")

    table.insert(lines, string.format("  L%-4d %s: %s%s", line_num, author, preview, status))
    line_to_entry[#lines] = entry
  end

  -- Add review bodies section if any exist
  if #reviews > 0 then
    if #lines > 0 then
      table.insert(lines, "")
    end
    table.insert(lines, "── Reviews ──")
    for _, review in ipairs(reviews) do
      local author = review.user and review.user.login or "unknown"
      local state_str = review.state and string.format(" [%s]", review.state:lower()) or ""
      local preview = (review.body or ""):gsub("\n", " "):sub(1, 60)
      table.insert(lines, string.format("  %s%s: %s", author, state_str, preview))
      line_to_entry[#lines] = { review = review }
    end
  end

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Create floating window
  local width = math.min(160, vim.o.columns - 4)
  local height = math.min(#lines + 2, 40)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = (vim.o.lines - height) / 2,
    col = (vim.o.columns - width) / 2,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " All PR Comments (" .. total_count .. ") ",
    title_pos = "center",
  })

  -- Track window for toggle behavior
  comment_list_win = win

  -- Add syntax highlighting for file headers
  vim.api.nvim_buf_call(buf, function()
    vim.fn.matchadd("Title", "^── .* ──$")
    vim.fn.matchadd("Number", "L%d\\+")
    vim.fn.matchadd("Comment", "\\[pending\\]")
    vim.fn.matchadd("DiagnosticOk", "\\[resolved\\]")
  end)

  -- Helper to close window and clear tracker
  local function close_list()
    vim.api.nvim_win_close(win, true)
    comment_list_win = nil
  end

  -- View thread on Enter
  vim.keymap.set("n", "<CR>", function()
    local cursor_line = vim.fn.line(".")
    local entry = line_to_entry[cursor_line]
    if not entry then
      return
    end

    if entry.review then
      M.show_readonly_thread({
        comments = { entry.review },
        title = " Review ",
      })
    elseif entry.file and entry.comment then
      local target_line = get_comment_line(entry.comment)
      local thread = {}
      for _, e in ipairs(all_comments) do
        if e.file == entry.file and get_comment_line(e.comment) == target_line then
          table.insert(thread, e.comment)
        end
      end
      if #thread == 0 then
        thread = { entry.comment }
      end
      M.show_readonly_thread({
        comments = thread,
        title = string.format(" %s L%d (%d comments, <leader>q=close) ", entry.file, target_line or 0, #thread),
      })
    end
  end, { buffer = buf, noremap = true, silent = true })

  -- Close on <leader>q or Esc
  vim.keymap.set("n", "<leader>q", close_list, { buffer = buf, noremap = true, silent = true })
  vim.keymap.set("n", "<Esc>", close_list, { buffer = buf, noremap = true, silent = true })
end

--- Toggle resolved status of comment at current line
function M.toggle_resolved()
  local comments = M.get_buffer_comments()
  local current_line = vim.fn.line(".")

  for _, comment in ipairs(comments) do
    local line = get_comment_line(comment)
    if line and line == current_line then
      comment.resolved = not comment.resolved
      vim.notify(
        comment.resolved and "Comment marked resolved" or "Comment marked unresolved",
        vim.log.levels.INFO
      )
      -- Refresh display
      M.show_comments(vim.api.nvim_get_current_buf(), comments)
      return
    end
  end

  vim.notify("No comment on this line", vim.log.levels.INFO)
end

--- Get pending comments for submission
---@return table[] pending_comments
function M.get_pending_comments()
  local all_pending = {}
  local files = state.get_files()

  for _, file in ipairs(files) do
    local comments = state.get_comments(file.filename)
    for _, comment in ipairs(comments) do
      if comment.pending then
        table.insert(all_pending, {
          path = file.filename,
          line = comment.line,
          body = comment.body,
        })
      end
    end
  end

  return all_pending
end

--- Submit pending comments to GitHub
---@param callback fun(err: string|nil)
function M.submit_comments(callback)
  local cfg, cfg_err = config.load()
  if cfg_err then
    callback("Config error: " .. cfg_err)
    return
  end

  local pending = M.get_pending_comments()
  if #pending == 0 then
    callback(nil) -- No comments to submit
    return
  end

  local owner = state.get_owner()
  local repo = state.get_repo()
  local number = state.get_number()
  local pr = state.get_pr()
  local token = config.get_token_for_owner(cfg, owner)

  if not pr or not pr.head or not pr.head.sha then
    callback("Missing PR data (commit_id)")
    return
  end

  -- Submit each comment
  local submitted_count = 0
  local errors = {}

  for _, comment in ipairs(pending) do
    api.create_comment(owner, repo, number, {
      path = comment.path,
      line = comment.line,
      body = comment.body,
      commit_id = pr.head.sha,
      side = "RIGHT",
    }, token, function(result, err)
      submitted_count = submitted_count + 1
      if err then
        table.insert(errors, err)
      else
        -- Mark comment as no longer pending
        local file_comments = state.get_comments(comment.path)
        for _, fc in ipairs(file_comments) do
          if fc.line == comment.line and fc.pending then
            fc.pending = false
            fc.id = result and result.id
            break
          end
        end
      end

      if submitted_count == #pending then
        if #errors > 0 then
          callback("Some comments failed: " .. table.concat(errors, "; "))
        else
          callback(nil)
        end
      end
    end)
  end
end

--- Get the namespace ID
---@return number
function M.get_namespace()
  return ns_id
end

return M
