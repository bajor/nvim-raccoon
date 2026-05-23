---@class RaccoonReview
---Review submission functionality
local M = {}

local api = require("raccoon.api")
local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local INSERT_MODE = config.INSERT
local state = require("raccoon.state")
local ui = require("raccoon.ui")

--- Review event types
M.events = {
  APPROVE = "APPROVE",
  REQUEST_CHANGES = "REQUEST_CHANGES",
  COMMENT = "COMMENT",
}

--- Submit a review to GitHub
---@param event string Review event type
---@param body string Review body
---@param callback fun(err: string|nil)
function M.submit_review(event, body, callback)
  if not state.is_active() then
    callback("No active PR review session")
    return
  end

  local cfg, cfg_err = config.load()
  if cfg_err then
    callback("Config error: " .. cfg_err)
    return
  end

  local owner = state.get_owner()
  local repo = state.get_repo()
  local number = state.get_number()
  api.init(state.get_github_host() or cfg.github_host)
  local token = config.get_token_for_owner(cfg, owner)
  if not token then
    callback(string.format("No token configured for '%s'", owner))
    return
  end

  api.submit_review(owner, repo, number, event, body, token, function(_result, err)
    if err then
      callback(err)
    else
      callback(nil)
    end
  end)
end

--- Show the review submission UI
function M.show_submit_ui()
  if not state.is_active() then
    vim.notify("No active PR review session", vim.log.levels.WARN)
    return
  end

  local pr = state.get_pr()
  -- Build prompt lines
  local lines = {
    "Submit Review for PR #" .. (state.get_number() or "?"),
    "",
    "Title: " .. (pr and pr.title or "Unknown"),
    "Select review type:",
    "",
    "  [a] Approve",
    "  [r] Request changes",
    "  [c] Comment only",
  }
  ui.append_popup_footer(lines, {
    { literal = "a/r/c", label = "choose" },
    { key = "close", label = "close" },
  })

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Create floating window
  local width = 50
  local height = #lines

  local shortcuts = config.load_shortcuts()
  local win, float_buf = ui.create_floating_window({
    width = width,
    height = height,
    title = ui.decorate_popup_title("Submit Review", {
      { key = "close", label = "close" },
    }, shortcuts),
    border = "rounded",
  })
  if float_buf ~= buf then
    vim.api.nvim_win_set_buf(win, buf)
    pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
  end

  -- Handle key presses
  local function handle_selection(event)
    vim.api.nvim_win_close(win, true)
    M.prompt_review_body(event)
  end

  vim.keymap.set(NORMAL_MODE, "a", function()
    handle_selection(M.events.APPROVE)
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set(NORMAL_MODE, "r", function()
    handle_selection(M.events.REQUEST_CHANGES)
  end, { buffer = buf, noremap = true, silent = true })

  vim.keymap.set(NORMAL_MODE, "c", function()
    handle_selection(M.events.COMMENT)
  end, { buffer = buf, noremap = true, silent = true })

  ui.bind_popup_close_keys(buf, function()
    vim.api.nvim_win_close(win, true)
    vim.notify("Review cancelled", vim.log.levels.INFO)
  end, { shortcuts = shortcuts })
end

--- Prompt for review body and submit
---@param event string Review event type
function M.prompt_review_body(event)
  local event_name = event == M.events.APPROVE and "Approve"
    or event == M.events.REQUEST_CHANGES and "Request Changes"
    or "Comment"

  -- Create input buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "buftype", "nofile")
  vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

  -- Set initial content
  local initial = {
    "# " .. event_name .. " Review",
    "",
    "Enter your review message below:",
    "",
    "",
  }
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, initial)

  -- Create floating window
  local width = 70
  local height = 15

  local shortcuts = config.load_shortcuts()
  local win, float_buf = ui.create_floating_window({
    width = width,
    height = height,
    title = ui.decorate_popup_title(event_name, {
      { literal = "Ctrl-S", label = "submit" },
      { key = "close", label = "close" },
    }, shortcuts),
    border = "rounded",
  })
  if float_buf ~= buf then
    vim.api.nvim_win_set_buf(win, buf)
    pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
  end

  -- Move cursor to empty line and start insert
  vim.api.nvim_win_set_cursor(win, { 5, 0 })
  vim.cmd("startinsert")

  -- Submit on Ctrl-S
  vim.keymap.set({ NORMAL_MODE, INSERT_MODE }, "<C-s>", function()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    -- Skip header lines
    local body_lines = {}
    local skip = true
    for _, line in ipairs(lines) do
      local should_skip = skip and (line == "" or line:match("^#") or line:match("^Enter your review"))
      if not should_skip then
        skip = false
        table.insert(body_lines, line)
      end
    end
    local body = table.concat(body_lines, "\n"):gsub("^%s+", ""):gsub("%s+$", "")

    vim.api.nvim_win_close(win, true)

    -- Show loading
    vim.notify("Submitting review...", vim.log.levels.INFO)

    -- Submit the review
    M.submit_review(event, body, function(err)
      if err then
        vim.notify("Failed to submit review: " .. err, vim.log.levels.ERROR)
      else
        vim.notify("Review submitted successfully!", vim.log.levels.INFO)
      end
    end)
  end, { buffer = buf, noremap = true, silent = true })

  -- Cancel in normal mode
  ui.bind_popup_close_keys(buf, function()
    vim.api.nvim_win_close(win, true)
    vim.notify("Review cancelled", vim.log.levels.INFO)
  end, { shortcuts = shortcuts })
end

--- Quick approve - approve without comments
---@param force? boolean If true, approve even if out of sync
function M.quick_approve(force)
  if not state.is_active() then
    vim.notify("No active PR review session", vim.log.levels.WARN)
    return
  end

  -- Check if branch is behind (unless force is true)
  local open = require("raccoon.open")
  local behind = open.get_commits_behind()
  if behind > 0 and not force then
    local pr = state.get_pr()
    local base = pr and pr.base and pr.base.ref or "base"
    local msg = "Cannot approve: branch is %d commit(s) behind %s. "
      .. "Run :Raccoon sync first, or use :Raccoon approve! to force."
    vim.notify(string.format(msg, behind, base), vim.log.levels.ERROR)
    return
  end

  vim.notify("Approving PR...", vim.log.levels.INFO)

  M.submit_review(M.events.APPROVE, "", function(err)
    if err then
      vim.notify("Failed to approve: " .. err, vim.log.levels.ERROR)
    else
      vim.notify("PR approved!", vim.log.levels.INFO)
    end
  end)
end

--- Get the current review status summary
---@return table summary { files_reviewed, total_files, pr_title }
function M.get_status()
  local files = state.get_files()
  local pr = state.get_pr()

  return {
    files_reviewed = state.get_current_file_index(),
    total_files = #files,
    pr_title = pr and pr.title,
    pr_number = state.get_number(),
    owner = state.get_owner(),
    repo = state.get_repo(),
  }
end

--- Show review status
function M.show_status()
  if not state.is_active() then
    vim.notify("No active PR review session", vim.log.levels.WARN)
    return
  end

  local status = M.get_status()
  local lines = {
    "PR Review Status",
    "",
    string.format("PR: #%d - %s", status.pr_number or 0, status.pr_title or "Unknown"),
    string.format("Repo: %s/%s", status.owner or "?", status.repo or "?"),
    "",
    string.format("Files: %d/%d reviewed", status.files_reviewed, status.total_files),
  }

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)

  -- Create floating window
  local width = 50
  local height = #lines

  local shortcuts = config.load_shortcuts()
  local win, float_buf = ui.create_floating_window({
    width = width,
    height = height,
    title = ui.decorate_popup_title("Review Status", {
      { key = "close", label = "close" },
    }, shortcuts),
    border = "rounded",
  })
  if float_buf ~= buf then
    vim.api.nvim_win_set_buf(win, buf)
    pcall(vim.api.nvim_buf_delete, float_buf, { force = true })
  end

  ui.bind_popup_close_keys(buf, function()
    vim.api.nvim_win_close(win, true)
  end, { shortcuts = shortcuts })
end

return M
