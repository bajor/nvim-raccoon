---@class RaccoonComments
---Comment management and display
local M = {}

local api = require("raccoon.api")
local config = require("raccoon.config")
local diff = require("raccoon.diff")
local NORMAL_MODE = config.NORMAL
local state = require("raccoon.state")

local ns_id = vim.api.nvim_create_namespace("raccoon_comments")
local sign_group = "RaccoonComment"
local COMMENT_DIVIDER = "────────────────────────────────────────────────"

--- Show a read-only thread view in a floating window
--- Displays all comments for a given thread, or a single review body
---@param opts table {comments: table[], title: string}
function M.show_readonly_thread(opts)
  local thread_comments = opts and opts.comments
  if not thread_comments or #thread_comments == 0 then
    return
  end

  local shortcuts = config.load_shortcuts()
  local ui = require("raccoon.ui")
  local title = ui.decorate_popup_title(opts.title or "Thread", {
    { key = "close", label = "close" },
  }, shortcuts)

  local lines = {}
  for i, comment in ipairs(thread_comments) do
    local author = comment.user and comment.user.login or "unknown"
    local status = ""
    if comment.is_review and comment.state then
      status = " [" .. comment.state:lower() .. "]"
    elseif comment.resolved then
      status = " [resolved]"
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
    title = " " .. title .. " ",
    title_pos = "center",
  })

  vim.wo[win].wrap = true

  local function close_window()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  ui.bind_popup_close_keys(buf, close_window, { shortcuts = shortcuts })
end

local thread_index = require("raccoon.thread_index")

local picker_state = {
  kind = nil,
  win = nil,
  buf = nil,
  rows = nil,
  selected = 1,
}

local editor_state = {
  win = nil,
  buf = nil,
  input_start = nil,
  kind = nil,
  thread_id = nil,
  path = nil,
  line = nil,
  prefill_lines = nil,
  augroup = nil,
}

local open_new_thread_editor

local function trim(text)
  return (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function current_buf_path(buf)
  local clone_path = state.get_clone_path()
  if not clone_path then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(buf or 0)
  if name:sub(1, #clone_path) ~= clone_path then
    return nil
  end
  return (name:sub(#clone_path + 2):gsub("\\", "/"))
end

local function is_flat_diff_mode()
  return state.is_active() and not state.is_commit_mode() and not require("raccoon.localcommits").is_active()
end

local function flat_diff_only_message()
  vim.notify("Available only in flat diff review mode", vim.log.levels.INFO)
end

function M.is_flat_diff_mode()
  return is_flat_diff_mode()
end

function M.warn_flat_diff_only()
  flat_diff_only_message()
end

local function build_index()
  local index, err = thread_index.build()
  if err then
    vim.notify("Thread data error: " .. err, vim.log.levels.ERROR)
    return nil
  end
  return index
end

local function editor_has_unsent_text()
  if not editor_state.buf or not vim.api.nvim_buf_is_valid(editor_state.buf) then
    return false
  end
  if not editor_state.input_start then
    return false
  end
  local lines = vim.api.nvim_buf_get_lines(editor_state.buf, editor_state.input_start - 1, -1, false)
  return trim(table.concat(lines, "\n")) ~= ""
end

function M.has_unsent_text()
  return editor_has_unsent_text()
end

local function close_active_editor(force)
  if editor_state.win and vim.api.nvim_win_is_valid(editor_state.win) then
    if not force and editor_has_unsent_text() then
      vim.notify("Cannot close with unsent text; clear it or send it first", vim.log.levels.WARN)
      return false
    end
    vim.api.nvim_win_close(editor_state.win, true)
  end
  if editor_state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, editor_state.augroup)
  end
  editor_state = {
    win = nil,
    buf = nil,
    input_start = nil,
    kind = nil,
    thread_id = nil,
    path = nil,
    line = nil,
    prefill_lines = nil,
    augroup = nil,
  }
  return true
end

function M.close_active_editor(force)
  return close_active_editor(force)
end

local function close_picker()
  if picker_state.win and vim.api.nvim_win_is_valid(picker_state.win) then
    vim.api.nvim_win_close(picker_state.win, true)
  end
  picker_state = {
    kind = nil,
    win = nil,
    buf = nil,
    rows = nil,
    selected = 1,
  }
end

function M.close_top_level_picker()
  close_picker()
end

function M.close_overlays(force)
  if not close_active_editor(force) then
    return false
  end
  close_picker()
  return true
end

local function ensure_review_context()
  local cfg, cfg_err = config.load()
  if cfg_err then
    return nil, "Config error: " .. cfg_err
  end
  local owner = state.get_owner()
  local token_entry = config.get_token_entry(cfg, owner)
  if not token_entry then
    return nil, string.format("No token configured for '%s'", owner)
  end
  api.init(state.get_github_host() or cfg.github_host)
  return {
    cfg = cfg,
    token = token_entry.token,
    owner = owner,
    repo = state.get_repo(),
    number = state.get_number(),
    pr = state.get_pr(),
  }, nil
end

local function build_badge(counts)
  local parts = {}
  if (counts.nr or 0) > 0 then
    table.insert(parts, "NR" .. counts.nr)
  end
  if (counts.u or 0) > 0 then
    table.insert(parts, "U" .. counts.u)
  end
  if (counts.i or 0) > 0 then
    table.insert(parts, "I" .. counts.i)
  end
  return "[" .. table.concat(parts, " ") .. "]"
end

local function normalize_preview(text, width)
  local preview = trim((text or ""):gsub("\n", " "):gsub("%s+", " "))
  if #preview > width then
    preview = preview:sub(1, width - 3) .. "..."
  end
  return preview
end

local function line_summary(bucket)
  if #bucket.threads > 0 then
    if #bucket.threads == 1 then
      return normalize_preview(bucket.threads[1].preview, 80)
    end
    return string.format("%d threads on this line", #bucket.threads)
  end
  if #bucket.issue_comments == 1 then
    return normalize_preview(bucket.issue_comments[1].body or "", 80)
  end
  return string.format("%d issue notes on this line", #bucket.issue_comments)
end

local function setup_override_highlights()
  vim.api.nvim_set_hl(0, "RaccoonCommentBadge", { default = true, bold = true })
  vim.api.nvim_set_hl(0, "RaccoonCommentBadgeStrong", { default = true, bold = true, link = "Title" })
  vim.api.nvim_set_hl(0, "RaccoonCommentTag", { default = true, bold = true })

  vim.fn.sign_define("RaccoonComment", {
    text = "T",
    texthl = "RaccoonCommentTag",
  })
  vim.fn.sign_define("RaccoonCommentPending", {
    text = "I",
    texthl = "RaccoonCommentTag",
  })
end

setup_override_highlights()

function M.clear_comments(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.fn.sign_unplace(sign_group, { buffer = buf })
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  end
end

function M.show_comments(buf, _comments)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local path = current_buf_path(buf)
  if not path then
    return
  end

  local index = build_index()
  if not index then
    return
  end

  M.clear_comments(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.opt_local.signcolumn = "yes:2"
  end)

  local line_map = index.line_state_by_file[path] or {}
  local line_count = vim.api.nvim_buf_line_count(buf)
  local ordered_lines = {}
  for line in pairs(line_map) do
    table.insert(ordered_lines, line)
  end
  table.sort(ordered_lines)

  for _, line in ipairs(ordered_lines) do
    if line <= line_count then
      local bucket = line_map[line]
      local sign_name = #bucket.threads > 0 and "RaccoonComment" or "RaccoonCommentPending"
      pcall(vim.fn.sign_place, 0, sign_group, sign_name, buf, { lnum = line, priority = 100 })
      local badge = build_badge(bucket.counts)
      local summary = line_summary(bucket)
      local badge_hl = (bucket.counts.nr or 0) > 0 and "RaccoonCommentBadgeStrong" or "RaccoonCommentBadge"
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line - 1, 0, {
        virt_text = {
          { " " .. badge, badge_hl },
          { " " .. summary, "Comment" },
        },
        virt_text_pos = "eol",
      })
    end
  end
end

function M.get_buffer_comments()
  local path = current_buf_path(0)
  if not path then
    return {}
  end
  return state.get_comments(path)
end

local function render_thread_lines(thread, include_reply, reply_label)
  local lines = {}
  for idx, comment in ipairs(thread.comments) do
    local author = comment.user and comment.user.login or "unknown"
    table.insert(lines, "@ " .. author)
    table.insert(lines, "")
    for body_line in (comment.body or ""):gmatch("[^\n]*") do
      table.insert(lines, body_line)
    end
    if idx < #thread.comments then
      table.insert(lines, "")
      table.insert(lines, COMMENT_DIVIDER)
      table.insert(lines, "")
    end
  end
  local reply_start = nil
  if include_reply then
    table.insert(lines, "")
    table.insert(lines, reply_label or "Reply")
    table.insert(lines, "")
    reply_start = #lines + 1
    table.insert(lines, "")
  end
  return lines, reply_start
end

local function build_editor_title(label, shortcuts, allow_send, allow_resolve, allow_unresolve)
  local hint_specs = {}
  if allow_send and config.is_enabled(shortcuts.comment_send) then
    table.insert(hint_specs, { key = "comment_send", label = "send" })
  end
  if allow_resolve and config.is_enabled(shortcuts.comment_resolve) then
    table.insert(hint_specs, { key = "comment_resolve", label = "resolve" })
  end
  if allow_unresolve and config.is_enabled(shortcuts.comment_unresolve) then
    table.insert(hint_specs, { key = "comment_unresolve", label = "unresolve" })
  end
  table.insert(hint_specs, { key = "sync", label = "sync" })
  table.insert(hint_specs, { key = "close", label = "close" })
  return require("raccoon.ui").decorate_popup_title(label, hint_specs, shortcuts)
end

local function editor_is_in_input_region(win, input_start)
  if not input_start or input_start < 1 then
    return false
  end
  if not win or not vim.api.nvim_win_is_valid(win) then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  return cursor and cursor[1] >= input_start or false
end

local function update_editor_editability(buf, win, input_start)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local can_edit = editor_is_in_input_region(win, input_start)
  vim.bo[buf].modifiable = can_edit
  if not can_edit then
    local mode = vim.api.nvim_get_mode().mode or ""
    if mode:sub(1, 1) == "i" then
      vim.cmd("stopinsert")
    end
  end
end

function M.refresh_editor_editability()
  update_editor_editability(editor_state.buf, editor_state.win, editor_state.input_start)
end

local function setup_editor_access_control(buf, win, input_start)
  if not input_start then
    vim.bo[buf].modifiable = false
    return nil
  end

  local group = vim.api.nvim_create_augroup("RaccoonEditorAccess" .. buf, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufEnter", "WinEnter" }, {
    group = group,
    buffer = buf,
    callback = function()
      update_editor_editability(buf, win, input_start)
    end,
  })

  update_editor_editability(buf, win, input_start)
  return group
end

local function open_editor_window(opts)
  close_picker()
  local ui = require("raccoon.ui")
  ui.close_description()
  ui.close_pr_list()

  local width = math.min(140, vim.o.columns - 6)
  local height = math.min(math.max(#opts.lines + 2, 10), vim.o.lines - 6)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, opts.lines)

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    title = " " .. opts.title .. " ",
    title_pos = "center",
  })

  editor_state = {
    win = win,
    buf = buf,
    input_start = opts.input_start,
    kind = opts.kind,
    thread_id = opts.thread_id,
    path = opts.path,
    line = opts.line,
    prefill_lines = opts.prefill_lines,
    augroup = nil,
  }

  if opts.input_start and opts.initial_input_lines and #opts.initial_input_lines > 0 then
    vim.api.nvim_buf_set_lines(buf, opts.input_start - 1, -1, false, opts.initial_input_lines)
  end

  local function close_current()
    close_active_editor(false)
  end

  local shortcuts = config.load_shortcuts()
  local km_opts = { buffer = buf, noremap = true, silent = true }

  if opts.on_send and config.is_enabled(shortcuts.comment_send) then
    vim.keymap.set(NORMAL_MODE, shortcuts.comment_send, opts.on_send, km_opts)
  end
  if opts.on_resolve and config.is_enabled(shortcuts.comment_resolve) then
    vim.keymap.set(NORMAL_MODE, shortcuts.comment_resolve, opts.on_resolve, km_opts)
  end
  if opts.on_unresolve and config.is_enabled(shortcuts.comment_unresolve) then
    vim.keymap.set(NORMAL_MODE, shortcuts.comment_unresolve, opts.on_unresolve, km_opts)
  end
  if config.is_enabled(shortcuts.sync) then
    vim.keymap.set(NORMAL_MODE, shortcuts.sync, function()
      require("raccoon.open").sync()
    end, km_opts)
  end
  ui.bind_popup_close_keys(buf, close_current, {
    shortcuts = shortcuts,
    keymap_opts = km_opts,
  })

  if opts.input_start then
    vim.api.nvim_win_set_cursor(win, { opts.input_start, 0 })
    editor_state.augroup = setup_editor_access_control(buf, win, opts.input_start)
    vim.cmd("startinsert")
    update_editor_editability(buf, win, opts.input_start)
  else
    editor_state.augroup = setup_editor_access_control(buf, win, opts.input_start)
  end
end

local function get_editor_input_lines()
  if not editor_state.buf or not vim.api.nvim_buf_is_valid(editor_state.buf) then
    return {}
  end
  if not editor_state.input_start then
    return {}
  end
  return vim.api.nvim_buf_get_lines(editor_state.buf, editor_state.input_start - 1, -1, false)
end

local function is_line_commentable(path, line)
  if type(line) ~= "number" or line < 1 then
    return false
  end
  for _, file in ipairs(state.get_files()) do
    if file.filename == path then
      return diff.is_line_in_review_context(file.patch, line)
    end
  end
  return false
end

---@return string
local function line_outside_diff_context_message()
  return "This line is outside the PR diff context; GitHub only allows review threads on changed lines and unchanged lines shown for context"
end

---@param path string
---@param line number
---@return boolean
local function can_start_new_thread(path, line)
  return is_line_commentable(path, line)
end

---@param path string
---@param line number
---@return string|nil
local function new_thread_disable_reason(path, line)
  if can_start_new_thread(path, line) then
    return nil
  end
  return line_outside_diff_context_message()
end

local function send_new_thread(path, line)
  local ctx, ctx_err = ensure_review_context()
  if ctx_err then
    vim.notify(ctx_err, vim.log.levels.ERROR)
    return
  end
  local lines = vim.api.nvim_buf_get_lines(editor_state.buf, editor_state.input_start - 1, -1, false)
  local body = trim(table.concat(lines, "\n"))
  if body == "" then
    vim.notify("Empty thread", vim.log.levels.WARN)
    return
  end
  local disable_reason = new_thread_disable_reason(path, line)
  if disable_reason then
    vim.notify(disable_reason, vim.log.levels.WARN)
    return
  end
  if not ctx.pr or not ctx.pr.head or not ctx.pr.head.sha then
    vim.notify("Missing PR data (commit_id)", vim.log.levels.ERROR)
    return
  end
  api.create_comment(ctx.owner, ctx.repo, ctx.number, {
    body = body,
    path = path,
    line = line,
    commit_id = ctx.pr.head.sha,
    side = "RIGHT",
  }, ctx.token, function(_result, err)
    vim.schedule(function()
      if err then
        vim.notify("Failed to send thread: " .. err, vim.log.levels.ERROR)
        return
      end
      close_active_editor(true)
      vim.notify("Thread sent", vim.log.levels.INFO)
      require("raccoon.open").sync()
    end)
  end)
end

---@param path string
---@param line number
---@param prefill_lines string[]
---@return boolean
local function open_new_thread_from_line(path, line, prefill_lines)
  local disable_reason = new_thread_disable_reason(path, line)
  if disable_reason then
    vim.notify(disable_reason, vim.log.levels.WARN)
    return false
  end
  open_new_thread_editor(path, line, prefill_lines or {})
  return true
end

open_new_thread_editor = function(path, line, prefill_lines, opts)
  opts = opts or {}
  local shortcuts = config.load_shortcuts()
  local lines = { "New thread on this line", "" }
  for _, extra in ipairs(prefill_lines or {}) do
    table.insert(lines, extra)
  end
  if #(prefill_lines or {}) > 0 then
    table.insert(lines, "")
  end
  local input_start = #lines + 1
  table.insert(lines, "")
  local allow_send = not opts.disable_send_reason
  open_editor_window({
    title = build_editor_title("New Thread L" .. tostring(line), shortcuts, allow_send, false, false),
    lines = lines,
    input_start = input_start,
    kind = "new_thread",
    path = path,
    line = line,
    prefill_lines = prefill_lines,
    initial_input_lines = opts.initial_input_lines,
    on_send = opts.disable_send_reason and nil or function()
      send_new_thread(path, line)
    end,
  })
  if opts.disable_send_reason then
    vim.notify(opts.disable_send_reason, vim.log.levels.WARN)
  end
end

local function open_thread_editor(thread_id, opts)
  opts = opts or {}
  local index = build_index()
  if not index then
    return
  end
  local thread = index.thread_by_id[thread_id]
  if not thread then
    vim.notify("Thread not found", vim.log.levels.WARN)
    return
  end

  state.set_selected_thread_id(thread.thread_id)

  local shortcuts = config.load_shortcuts()
  local preserved_reply = opts.initial_input_lines
  local include_reply = thread.resolved ~= true or (preserved_reply and #preserved_reply > 0)
  local reply_label = opts.disable_send_reason and "Reply (read-only)" or "Reply"
  local lines, input_start = render_thread_lines(thread, include_reply, reply_label)
  local allow_send = include_reply and not opts.disable_send_reason and not thread.resolved

  local function send_reply()
    if thread.resolved then
      vim.notify("Cannot reply on a resolved thread; unresolve it first", vim.log.levels.WARN)
      return
    end
    local ctx, ctx_err = ensure_review_context()
    if ctx_err then
      vim.notify(ctx_err, vim.log.levels.ERROR)
      return
    end
    local reply_lines = vim.api.nvim_buf_get_lines(editor_state.buf, input_start - 1, -1, false)
    local body = trim(table.concat(reply_lines, "\n"))
    if body == "" then
      vim.notify("Empty reply", vim.log.levels.WARN)
      return
    end
    api.reply_to_comment(
      ctx.owner,
      ctx.repo,
      ctx.number,
      thread.root_comment_id,
      body,
      ctx.token,
      function(_result, err)
        vim.schedule(function()
          if err then
            vim.notify("Failed to send reply: " .. err, vim.log.levels.ERROR)
            return
          end
          close_active_editor(true)
          vim.notify("Thread reply sent", vim.log.levels.INFO)
          require("raccoon.open").sync()
        end)
      end
    )
  end

  local function resolve_thread()
    if editor_has_unsent_text() then
      vim.notify("Cannot resolve with unsent text; clear it or send it first", vim.log.levels.WARN)
      return
    end
    local ctx, ctx_err = ensure_review_context()
    if ctx_err then
      vim.notify(ctx_err, vim.log.levels.ERROR)
      return
    end
    api.resolve_review_thread(thread.thread_id, ctx.token, function(err)
      vim.schedule(function()
        if err then
          vim.notify("Failed to resolve thread: " .. err, vim.log.levels.ERROR)
          return
        end
        close_active_editor(true)
        vim.notify("Thread resolved", vim.log.levels.INFO)
        require("raccoon.open").sync()
      end)
    end)
  end

  local function unresolve_thread()
    local ctx, ctx_err = ensure_review_context()
    if ctx_err then
      vim.notify(ctx_err, vim.log.levels.ERROR)
      return
    end
    api.unresolve_review_thread(thread.thread_id, ctx.token, function(err)
      vim.schedule(function()
        if err then
          vim.notify("Failed to unresolve thread: " .. err, vim.log.levels.ERROR)
          return
        end
        close_active_editor(true)
        vim.notify("Thread unresolved", vim.log.levels.INFO)
        require("raccoon.open").sync()
        vim.defer_fn(function()
          open_thread_editor(thread.thread_id)
        end, 250)
      end)
    end)
  end

  open_editor_window({
    title = build_editor_title(
      thread.path .. " " .. thread.line_label,
      shortcuts,
      allow_send,
      not thread.resolved,
      thread.resolved
    ),
    lines = lines,
    input_start = input_start,
    kind = "thread",
    thread_id = thread.thread_id,
    path = thread.path,
    line = thread.line,
    initial_input_lines = preserved_reply,
    on_send = allow_send and send_reply or nil,
    on_resolve = thread.resolved ~= true and resolve_thread or nil,
    on_unresolve = thread.resolved and unresolve_thread or nil,
  })
  if opts.disable_send_reason then
    vim.notify(opts.disable_send_reason, vim.log.levels.WARN)
  end
end

local function jump_to_path_and_line(path, line)
  local files = state.get_files()
  local target_file = nil
  local target_index = nil
  for idx, file in ipairs(files) do
    if file.filename == path then
      target_file = file
      target_index = idx
      break
    end
  end
  if not target_file then
    return false
  end
  state.goto_file(target_index)
  local buf = diff.open_file(target_file)
  if buf then
    M.show_comments(buf, state.get_comments(path))
  end
  if line then
    local line_count = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(line, line_count)), 0 })
    vim.cmd("normal! zz")
  end
  return true
end

function M.jump_to_thread(thread_id, opts)
  local index = build_index()
  if not index then
    return false
  end
  local thread = index.thread_by_id[thread_id]
  if not thread then
    return false
  end
  state.set_selected_thread_id(thread.thread_id)
  if not jump_to_path_and_line(thread.path, thread.line) then
    return false
  end
  if opts and opts.open_window then
    open_thread_editor(thread.thread_id)
  elseif (opts and opts.open_window_if_no_line) and not thread.line then
    open_thread_editor(thread.thread_id)
  end
  return true
end

local function first_changed_line(file)
  if not file or not file.patch then
    return nil
  end
  local changes = require("raccoon.diff").get_changed_lines(file.patch)
  local lines = {}
  for _, line in ipairs(changes.added or {}) do
    table.insert(lines, line)
  end
  for _, deleted in ipairs(changes.deleted or {}) do
    if deleted.line_num then
      table.insert(lines, math.max(1, deleted.line_num))
    end
  end
  table.sort(lines)
  return lines[1]
end

local function jump_to_file_target(path)
  local index = build_index()
  if not index then
    return false
  end
  for _, thread in ipairs(index.unresolved_threads) do
    if thread.path == path and thread.needs_reply then
      return M.jump_to_thread(thread.thread_id, { open_window_if_no_line = true })
    end
  end
  for _, thread in ipairs(index.unresolved_threads) do
    if thread.path == path then
      return M.jump_to_thread(thread.thread_id, { open_window_if_no_line = true })
    end
  end
  local first_issue_line = nil
  for _, issue_entry in ipairs(index.issue_entries or {}) do
    if issue_entry.path == path and (not first_issue_line or issue_entry.line < first_issue_line) then
      first_issue_line = issue_entry.line
    end
  end
  if first_issue_line then
    return jump_to_path_and_line(path, first_issue_line)
  end
  local file = nil
  for _, entry in ipairs(state.get_files()) do
    if entry.filename == path then
      file = entry
      break
    end
  end
  local changed_line = first_changed_line(file)
  return jump_to_path_and_line(path, changed_line or 1)
end

function M.jump_to_file(path)
  return jump_to_file_target(path)
end

local function set_picker_selection(win, row)
  if row and win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_win_set_cursor(win, { row, 0 })
  end
end

local function current_picker_row_index()
  if not picker_state.win or not vim.api.nvim_win_is_valid(picker_state.win) then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(picker_state.win)
  local row = cursor and cursor[1] or nil
  if not row or row < 1 or row > #(picker_state.rows or {}) then
    return nil
  end
  return row
end

local function open_picker(opts)
  if editor_state.win and vim.api.nvim_win_is_valid(editor_state.win) then
    if not close_active_editor(false) then
      return
    end
  end

  local ok_ui, ui = pcall(require, "raccoon.ui")
  if ok_ui and ui.close_description then
    ui.close_description()
  end
  if ok_ui and ui.close_pr_list then
    ui.close_pr_list()
  end

  if picker_state.kind == opts.kind and picker_state.win and vim.api.nvim_win_is_valid(picker_state.win) then
    close_picker()
    return
  end

  close_picker()

  local lines = {}
  for _, row in ipairs(opts.rows) do
    table.insert(lines, row.text)
  end
  local shortcuts = config.load_shortcuts()
  local footer_specs = {
    { literal = "Enter", label = "open" },
    { literal = "j/k", label = "navigate" },
    { key = "close", label = "close" },
  }
  if opts.refreshable then
    table.insert(footer_specs, 3, { key = "sync", label = "sync" })
  end
  local ui_mod = require("raccoon.ui")
  ui_mod.append_popup_footer(lines, footer_specs, shortcuts)

  local width = math.min(160, vim.o.columns - 6)
  local height = math.min(#lines + 2, vim.o.lines - 6)
  local win, buf = ui_mod.create_floating_window({
    width = width,
    height = height,
    title = opts.title,
    border = "rounded",
  })

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"

  picker_state = {
    kind = opts.kind,
    win = win,
    buf = buf,
    rows = opts.rows,
    selected = opts.selected or 1,
  }

  set_picker_selection(win, picker_state.selected)

  local km_opts = { buffer = buf, noremap = true, silent = true }
  local function move(delta)
    local max_row = #picker_state.rows
    local new_row = math.max(1, math.min(max_row, vim.fn.line(".") + delta))
    set_picker_selection(win, new_row)
  end

  vim.keymap.set(NORMAL_MODE, "j", function() move(1) end, km_opts)
  vim.keymap.set(NORMAL_MODE, "<Down>", function() move(1) end, km_opts)
  vim.keymap.set(NORMAL_MODE, "k", function() move(-1) end, km_opts)
  vim.keymap.set(NORMAL_MODE, "<Up>", function() move(-1) end, km_opts)
  vim.keymap.set(NORMAL_MODE, "<CR>", function()
    local row = picker_state.rows[vim.fn.line(".")]
    if row and row.on_select then
      close_picker()
      row.on_select()
    end
  end, km_opts)
  if opts.refreshable and config.is_enabled(shortcuts.sync) then
    vim.keymap.set(NORMAL_MODE, shortcuts.sync, function()
      require("raccoon.open").sync()
    end, km_opts)
  elseif config.is_enabled(shortcuts.sync) then
    vim.keymap.set(NORMAL_MODE, shortcuts.sync, function()
      vim.notify(
        "Refresh not available in this picker; close it and sync from the review buffer if needed",
        vim.log.levels.INFO
      )
    end, km_opts)
  end
  ui_mod.bind_popup_close_keys(buf, close_picker, {
    shortcuts = shortcuts,
    keymap_opts = km_opts,
    modes = { NORMAL_MODE, config.INSERT },
  })
end

function M.capture_ui_state()
  if editor_state.win and vim.api.nvim_win_is_valid(editor_state.win) then
    return {
      kind = "editor",
      editor_kind = editor_state.kind,
      thread_id = editor_state.thread_id,
      path = editor_state.path,
      line = editor_state.line,
      prefill_lines = editor_state.prefill_lines,
      input_lines = get_editor_input_lines(),
    }
  end

  if picker_state.win and vim.api.nvim_win_is_valid(picker_state.win) then
    local row_idx = current_picker_row_index() or picker_state.selected or 1
    local row = picker_state.rows and picker_state.rows[row_idx] or nil
    return {
      kind = "picker",
      picker_kind = picker_state.kind,
      row_key = row and row.key or nil,
      row_index = row_idx,
    }
  end

  return nil
end

local function restore_new_thread_snapshot(snapshot)
  local disable_reason = nil
  if not is_line_commentable(snapshot.path, snapshot.line) then
    disable_reason = "Thread is no longer commentable on this line; clear the text or close it"
  end
  open_new_thread_editor(
    snapshot.path,
    snapshot.line,
    snapshot.prefill_lines or {},
    { initial_input_lines = snapshot.input_lines, disable_send_reason = disable_reason }
  )
end

function M.restore_ui_state(snapshot)
  if not snapshot then
    return
  end

  if snapshot.kind == "editor" then
    close_active_editor(true)
    if snapshot.editor_kind == "thread" and snapshot.thread_id then
      local index = build_index()
      if not index or not index.thread_by_id[snapshot.thread_id] then
        vim.notify("Sync failed to restore thread window: thread no longer available", vim.log.levels.ERROR)
        return
      end
      local thread = index.thread_by_id[snapshot.thread_id]
      local disable_reason = nil
      if thread.resolved and snapshot.input_lines and #snapshot.input_lines > 0 then
        disable_reason = "Thread is now resolved; unresolve it or clear the text"
      end
      open_thread_editor(snapshot.thread_id, {
        initial_input_lines = snapshot.input_lines,
        disable_send_reason = disable_reason,
      })
      return
    end

    if snapshot.editor_kind == "new_thread" and snapshot.path and snapshot.line then
      restore_new_thread_snapshot(snapshot)
    end
    return
  end

  if snapshot.kind ~= "picker" then
    return
  end

  close_picker()
  if snapshot.picker_kind == "list_comments" then
    M.list_comments({ selection_key = snapshot.row_key, selected_index = snapshot.row_index })
  elseif snapshot.picker_kind == "list_threads" then
    M.list_threads({ selection_key = snapshot.row_key, selected_index = snapshot.row_index })
  elseif snapshot.picker_kind == "list_files" then
    M.list_files({ selection_key = snapshot.row_key, selected_index = snapshot.row_index })
  end
end

local function history_rows(index)
  local rows = {}
  for _, review in ipairs(index.review_bodies or {}) do
    table.insert(rows, {
      key = "review:" .. tostring(review.id or review.submitted_at or "?"),
      kind = "review",
      text = string.format(
        "[REVIEW] %s %s",
        review.user and review.user.login or "unknown",
        normalize_preview(review.body or "", 90)
      ),
      on_select = function()
        M.show_readonly_thread({ comments = { review }, title = " Review " })
      end,
    })
  end

  local grouped = {}
  for _, thread in ipairs(index.history_threads or {}) do
    local file_rows = grouped[thread.path]
    if not file_rows then
      file_rows = {}
      grouped[thread.path] = file_rows
    end
    table.insert(file_rows, thread)
  end

  local issue_rows_by_file = {}
  for _, issue in ipairs(index.issue_entries or {}) do
    local file_rows = issue_rows_by_file[issue.path]
    if not file_rows then
      file_rows = {}
      issue_rows_by_file[issue.path] = file_rows
    end
    table.insert(file_rows, issue)
  end

  for _, file in ipairs(state.get_files()) do
    local has_rows = (grouped[file.filename] and #grouped[file.filename] > 0)
      or (issue_rows_by_file[file.filename] and #issue_rows_by_file[file.filename] > 0)
    if has_rows then
      table.insert(rows, { text = "── " .. file.filename .. " ──" })
      local file_threads = grouped[file.filename] or {}
      for _, thread in ipairs(file_threads) do
        local tag = thread.needs_reply and "[NR]" or (thread.resolved and "[R]" or "[U]")
        table.insert(rows, {
          key = "thread:" .. thread.thread_id,
          kind = "thread",
          path = thread.path,
          line = thread.line,
          thread_id = thread.thread_id,
          resolved = thread.resolved,
          text = string.format(
            "%s %s %s %s",
            tag,
            thread.line_label,
            thread.latest_author,
            normalize_preview(thread.preview, 80)
          ),
          on_select = function()
            if thread.line then
              M.jump_to_thread(thread.thread_id, {})
            else
              open_thread_editor(thread.thread_id)
            end
          end,
        })
      end
      local file_issues = issue_rows_by_file[file.filename] or {}
      table.sort(file_issues, function(left, right)
        return left.line < right.line
      end)
      for _, issue in ipairs(file_issues) do
        table.insert(rows, {
          key = "issue:" .. tostring(issue.comment.id or issue.line),
          kind = "issue",
          path = issue.path,
          line = issue.line,
          text = string.format(
            "[I] L%d %s %s",
            issue.line,
            issue.comment.user and issue.comment.user.login or "unknown",
            normalize_preview(issue.comment.body or "", 80)
          ),
          on_select = function()
            jump_to_path_and_line(issue.path, issue.line)
          end,
        })
      end
    end
  end
  return rows
end

local function resolve_selected_row(rows, selection_key, selected_index)
  if selection_key then
    for row_idx, row in ipairs(rows) do
      if row.key == selection_key then
        return row_idx
      end
    end
  end
  if selected_index and selected_index >= 1 and selected_index <= #rows then
    return selected_index
  end
  return 1
end

function M.list_comments(opts)
  opts = opts or {}
  if not is_flat_diff_mode() then
    flat_diff_only_message()
    return
  end
  local index = build_index()
  if not index then
    return
  end
  local rows = history_rows(index)
  if #rows == 0 then
    vim.notify("No comments in this PR", vim.log.levels.INFO)
    return
  end
  local selected = resolve_selected_row(rows, opts.selection_key, opts.selected_index)
  if not opts.selection_key and not opts.selected_index then
    local current_thread_id = state.get_selected_thread_id()
    local current_path = current_buf_path(0)
    local current_line = vim.fn.line(".")
    for row_idx, row in ipairs(rows) do
      if current_thread_id and row.thread_id == current_thread_id then
        selected = row_idx
        break
      end
      if row.path == current_path and row.line == current_line then
        if row.kind == "thread" and row.resolved ~= true then
          selected = row_idx
          break
        end
        if row.kind == "thread" and selected == 1 then
          selected = row_idx
        elseif row.kind == "issue" and selected == 1 then
          selected = row_idx
        end
      elseif row.path == current_path and selected == 1 and row.kind ~= "review" then
        selected = row_idx
      end
    end
    if selected == 1 then
      for row_idx, row in ipairs(rows) do
        if row.kind ~= "review" then
          selected = row_idx
          break
        end
      end
    end
  end
  open_picker({
    kind = "list_comments",
    title = "All PR Comments",
    rows = rows,
    selected = selected,
    refreshable = true,
  })
end

function M.list_threads(opts)
  opts = opts or {}
  if not is_flat_diff_mode() then
    flat_diff_only_message()
    return
  end
  local index = build_index()
  if not index then
    return
  end
  local rows = {}
  local selected = 1
  local current_thread_id = state.get_selected_thread_id()
  local current_path = current_buf_path(0)
  local current_line = vim.fn.line(".")
  for row_idx, thread in ipairs(index.unresolved_threads) do
    if current_thread_id and thread.thread_id == current_thread_id then
      selected = row_idx
    elseif not current_thread_id and thread.path == current_path and thread.line == current_line then
      selected = row_idx
    elseif not current_thread_id and selected == 1 and thread.needs_reply then
      selected = row_idx
    end
    local tag = thread.needs_reply and "[NR]" or "[U]"
    table.insert(rows, {
      key = "thread:" .. thread.thread_id,
      text = string.format(
        "%s %s %s %s %s",
        tag,
        thread.path,
        thread.line_label,
        thread.latest_author,
        normalize_preview(thread.preview, 70)
      ),
      on_select = function()
        if thread.line then
          M.jump_to_thread(thread.thread_id, {})
        else
          open_thread_editor(thread.thread_id)
        end
      end,
    })
  end
  if #rows == 0 then
    vim.notify("No unresolved threads", vim.log.levels.INFO)
    return
  end
  open_picker({
    kind = "list_threads",
    title = "Unresolved Threads",
    rows = rows,
    selected = resolve_selected_row(rows, opts.selection_key, opts.selected_index or selected),
    refreshable = true,
  })
end

function M.list_files(opts)
  opts = opts or {}
  if not is_flat_diff_mode() then
    flat_diff_only_message()
    return
  end
  local index = build_index()
  if not index then
    return
  end
  local current_path = current_buf_path(0)
  local rows = {}
  local selected = 1
  for row_idx, file in ipairs(state.get_files()) do
    local counts = { nr = 0, u = 0, i = 0 }
    local line_map = index.line_state_by_file[file.filename] or {}
    for _, bucket in pairs(line_map) do
      counts.nr = counts.nr + (bucket.counts.nr or 0)
      counts.u = counts.u + (bucket.counts.u or 0)
      counts.i = counts.i + (bucket.counts.i or 0)
    end
    if current_path == file.filename then
      selected = row_idx
    end
    local badge = build_badge(counts)
    table.insert(rows, {
      key = "file:" .. file.filename,
      text = string.format("%-14s %s", badge, file.filename),
      on_select = function()
        jump_to_file_target(file.filename)
      end,
    })
  end
  open_picker({
    kind = "list_files",
    title = "Changed Files",
    rows = rows,
    selected = resolve_selected_row(rows, opts.selection_key, opts.selected_index or selected),
    refreshable = true,
  })
end

local function issue_prefill_lines(issue_comments)
  if #issue_comments == 0 then
    return {}
  end
  local lines = { "Context:", "" }
  for _, comment in ipairs(issue_comments) do
    local author = comment.user and comment.user.login or "unknown"
    local url = comment.html_url or comment.url or ""
    table.insert(lines, string.format("Related PR comment by @%s:", author))
    if url ~= "" then
      table.insert(lines, url)
    end
    local body = trim(comment.body or "")
    if body ~= "" then
      for body_line in body:gmatch("[^\n]+") do
        table.insert(lines, "> " .. body_line)
      end
    end
    table.insert(lines, "")
  end
  return lines
end

local function open_same_line_picker(path, line, line_state)
  local thread_rows = {}
  local selected_thread_id = state.get_selected_thread_id()
  local selected = 1
  table.sort(line_state.threads, function(left, right)
    if left.resolved ~= right.resolved then
      return left.resolved == false
    end
    if left.needs_reply ~= right.needs_reply then
      return left.needs_reply
    end
    return left.order < right.order
  end)
  for row_idx, thread in ipairs(line_state.threads) do
    if selected_thread_id and selected_thread_id == thread.thread_id then
      selected = row_idx
    end
    local tag = thread.resolved and "[R]" or (thread.needs_reply and "[NR]" or "[U]")
    table.insert(thread_rows, {
      key = "thread:" .. thread.thread_id,
      text = string.format(
        "%s %s %s %s",
        tag,
        thread.latest_author,
        thread.line_label,
        normalize_preview(thread.preview, 70)
      ),
      on_select = function()
        open_thread_editor(thread.thread_id)
      end,
    })
  end
  if can_start_new_thread(path, line) then
    table.insert(thread_rows, {
      key = "new_thread:" .. path .. ":" .. tostring(line),
      text = "[NEW] New thread on this line",
      on_select = function()
        open_new_thread_editor(path, line, {})
      end,
    })
  end
  open_picker({
    kind = "same_line",
    title = "Line " .. tostring(line),
    rows = thread_rows,
    selected = selected,
    refreshable = false,
  })
end

function M.show_comment_thread()
  if not is_flat_diff_mode() then
    flat_diff_only_message()
    return
  end
  local path = current_buf_path(0)
  if not path then
    vim.notify("Not in a PR file", vim.log.levels.WARN)
    return
  end
  local line = vim.fn.line(".")
  local index = build_index()
  if not index then
    return
  end
  local line_state = thread_index.get_comment_line_state(index, path, line)
  if not line_state then
    open_new_thread_from_line(path, line, {})
    return
  end
  if #line_state.threads > 0 then
    open_same_line_picker(path, line, line_state)
    return
  end
  open_new_thread_from_line(path, line, issue_prefill_lines(line_state.issue_comments))
end

--- Get the namespace ID
---@return number
function M.get_namespace()
  return ns_id
end

return M
