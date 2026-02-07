---@class RaccoonUI
---UI components for Raccoon plugin
local M = {}

local api = require("raccoon.api")
local config = require("raccoon.config")

--- Current floating window state
M.state = {
  win = nil,
  buf = nil,
  prs = {},
  selected = 1,
  error_line_count = 0,
  description_win = nil,
}

--- Create a centered floating window
---@param opts table Options: width, height, title, border, width_pct, height_pct
---@return number win_id, number buf_id
function M.create_floating_window(opts)
  opts = opts or {}

  -- Calculate size (use percentage if provided, otherwise fixed values)
  local ui_width = vim.o.columns
  local ui_height = vim.o.lines
  local width = opts.width_pct and math.floor(ui_width * opts.width_pct) or (opts.width or 60)
  local height = opts.height_pct and math.floor(ui_height * opts.height_pct) or (opts.height or 20)
  local title = opts.title or ""

  -- Calculate position (centered)
  local col = math.floor((ui_width - width) / 2)
  local row = math.floor((ui_height - height) / 2)

  -- Create buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].swapfile = false

  -- Window options
  local win_opts = {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = opts.border or "rounded",
  }

  -- Only add title options if title is provided
  if title ~= "" then
    win_opts.title = " " .. title .. " "
    win_opts.title_pos = "center"
  end

  -- Create window
  local win = vim.api.nvim_open_win(buf, true, win_opts)

  -- Set window options
  vim.wo[win].cursorline = true
  vim.wo[win].wrap = false
  vim.wo[win].scrolloff = 3

  return win, buf
end

--- Close the PR list window
function M.close_pr_list()
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    vim.api.nvim_win_close(M.state.win, true)
  end
  M.state.win = nil
  M.state.buf = nil
end

--- Calculate relative time string
---@param iso_date string ISO 8601 date string
---@return string
local function relative_time(iso_date)
  if not iso_date then
    return ""
  end
  -- Parse ISO date (e.g., "2026-01-03T12:34:56Z")
  local year, month, day, hour, min, sec = iso_date:match("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not year then
    return ""
  end

  local pr_time = os.time({
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = tonumber(sec),
  })

  -- os.time({...}) interprets fields as local time, so use the same
  -- interpretation for "now" to get a correct UTC-vs-UTC diff
  local now = os.time(os.date("!*t"))
  local diff = now - pr_time

  if diff < 60 then
    return "just now"
  elseif diff < 3600 then
    local mins = math.floor(diff / 60)
    return mins == 1 and "1 min ago" or mins .. " mins ago"
  elseif diff < 86400 then
    local hours = math.floor(diff / 3600)
    return hours == 1 and "1 hour ago" or hours .. " hours ago"
  else
    local days = math.floor(diff / 86400)
    return days == 1 and "1 day ago" or days .. " days ago"
  end
end

--- Render the PR list in the buffer
---@param prs table[] List of PRs
---@param buf_width number Buffer width for formatting
local function render_pr_list(prs, buf_width)
  local lines = {}
  local highlights = {}
  buf_width = buf_width or 60

  if #prs == 0 then
    table.insert(lines, "")
    table.insert(lines, "  No open pull requests found")
    table.insert(lines, "")
    table.insert(lines, "  Press 'r' to refresh, '<leader>q' to close")
  else
    -- Group by repo (preserve order with array)
    local by_repo = {}
    local repo_order = {}
    for _, pr in ipairs(prs) do
      local repo = pr.base.repo and pr.base.repo.full_name or "unknown"
      if not by_repo[repo] then
        by_repo[repo] = {}
        table.insert(repo_order, repo)
      end
      table.insert(by_repo[repo], pr)
    end

    local line_idx = 0
    for i, repo in ipairs(repo_order) do
      local repo_prs = by_repo[repo]

      -- Separator line before each repo (except first)
      if i > 1 then
        table.insert(lines, string.rep("─", buf_width - 4))
        line_idx = line_idx + 1
      end

      -- Repo header
      table.insert(lines, " " .. repo)
      table.insert(highlights, { line = line_idx, col = 0, end_col = #repo + 2, hl = "Title" })
      line_idx = line_idx + 1

      -- Empty line after header
      table.insert(lines, "")
      line_idx = line_idx + 1

      for _, pr in ipairs(repo_prs) do
        -- PR number and full title (bold)
        local title_line = string.format("  #%d  %s", pr.number, pr.title)
        table.insert(lines, title_line)
        table.insert(highlights, { line = line_idx, col = 0, end_col = #title_line, hl = "Bold" })
        line_idx = line_idx + 1

        -- Info line: author and relative time (not bold)
        local author = pr.user and pr.user.login or "unknown"
        local updated = relative_time(pr.updated_at)
        local info_line = string.format("       by %s • %s", author, updated)
        table.insert(lines, info_line)
        line_idx = line_idx + 1

        -- Empty line between PRs
        table.insert(lines, "")
        line_idx = line_idx + 1
      end
    end
  end

  -- Footer separator
  table.insert(lines, string.rep("─", buf_width - 4))
  table.insert(lines, " Enter: open │ <leader>q: close │ r: refresh │ j/k: navigate")

  return lines, highlights
end

--- Update the selection highlight
local function update_selection()
  if not M.state.buf or not vim.api.nvim_buf_is_valid(M.state.buf) then
    return
  end

  -- Clear existing selection namespace
  local ns = vim.api.nvim_create_namespace("raccoon_selection")
  vim.api.nvim_buf_clear_namespace(M.state.buf, ns, 0, -1)

  -- Find the line for the selected PR
  -- New layout: separator (if not first repo) + repo header + empty + (title + info + empty) per PR
  local line_idx = 0
  local selected_line = nil

  local by_repo = {}
  local repo_order = {}
  for _, pr in ipairs(M.state.prs) do
    local repo = pr.base.repo and pr.base.repo.full_name or "unknown"
    if not by_repo[repo] then
      by_repo[repo] = {}
      table.insert(repo_order, repo)
    end
    table.insert(by_repo[repo], pr)
  end

  local pr_idx = 0
  for i, repo in ipairs(repo_order) do
    local repo_prs = by_repo[repo]
    -- Separator line (if not first repo)
    if i > 1 then
      line_idx = line_idx + 1
    end
    line_idx = line_idx + 1 -- Repo header
    line_idx = line_idx + 1 -- Empty line after header

    for _ in ipairs(repo_prs) do
      pr_idx = pr_idx + 1
      if pr_idx == M.state.selected then
        selected_line = line_idx
      end
      line_idx = line_idx + 3 -- title + info + empty line
    end
  end

  -- Set cursor to selected line (offset by error lines at top)
  if selected_line and M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    local offset = M.state.error_line_count or 0
    vim.api.nvim_win_set_cursor(M.state.win, { selected_line + 1 + offset, 0 })
  end
end

--- Apply highlights to the buffer
---@param buf number Buffer handle
---@param highlights table[] List of highlight specs
local function apply_highlights(buf, highlights)
  local ns = vim.api.nvim_create_namespace("raccoon_highlights")
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  for _, hl in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(buf, ns, hl.hl, hl.line, hl.col, hl.end_col)
  end
end

--- Show the PR list picker
--- Opens a floating window with all open PRs from configured repos
function M.show_pr_list()
  -- Toggle: if already open, close it
  if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
    M.close_pr_list()
    return
  end

  -- Create floating window
  local win, buf = M.create_floating_window({
    width_pct = 0.7,
    height_pct = 0.8,
    title = "Pull Requests",
    border = "rounded",
  })

  -- Store state
  M.state.win = win
  M.state.buf = buf
  M.state.prs = {}
  M.state.selected = 1

  -- Show loading state
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "  Loading..." })
  vim.bo[buf].modifiable = false

  -- Setup buffer-local keymaps
  local opts = { buffer = buf, noremap = true, silent = true }

  local function move_down()
    if M.state.selected < #M.state.prs then
      M.state.selected = M.state.selected + 1
      update_selection()
    end
  end

  local function move_up()
    if M.state.selected > 1 then
      M.state.selected = M.state.selected - 1
      update_selection()
    end
  end

  vim.keymap.set("n", "j", move_down, opts)
  vim.keymap.set("n", "<Down>", move_down, opts)
  vim.keymap.set("n", "k", move_up, opts)
  vim.keymap.set("n", "<Up>", move_up, opts)

  -- Open selected PR on Enter
  vim.keymap.set("n", "<CR>", function()
    local pr = M.state.prs[M.state.selected]
    if not pr then return end

    local url = pr.html_url
    if not url then return end

    M.close_pr_list()

    local open = require("raccoon.open")
    open.open_pr(url)
  end, opts)

  -- Close on <leader>q or Esc
  vim.keymap.set("n", "<leader>q", function() M.close_pr_list() end, opts)
  vim.keymap.set("n", "<Esc>", function() M.close_pr_list() end, opts)

  -- Refresh on r
  vim.keymap.set("n", "r", function() M.refresh_pr_list() end, opts)

  -- Fetch and display PRs
  M.refresh_pr_list()
end

--- Refresh the PR list
function M.refresh_pr_list()
  if not M.state.buf or not vim.api.nvim_buf_is_valid(M.state.buf) then
    return
  end

  -- Show loading message
  vim.bo[M.state.buf].modifiable = true
  vim.api.nvim_buf_set_lines(M.state.buf, 0, -1, false, { "  Loading..." })
  vim.bo[M.state.buf].modifiable = false

  M.fetch_all_prs(function(prs, errors)
    if not M.state.buf or not vim.api.nvim_buf_is_valid(M.state.buf) then
      return
    end

    M.state.prs = prs or {}
    M.state.selected = 1
    M.state.error_line_count = 0

    -- Get window width for formatting
    local win_width = 60
    if M.state.win and vim.api.nvim_win_is_valid(M.state.win) then
      win_width = vim.api.nvim_win_get_width(M.state.win)
    end

    -- Build error lines if any tokens failed
    local error_lines = {}
    local error_highlights = {}
    if errors and #errors > 0 then
      for _, e in ipairs(errors) do
        local line = string.format("  [%s] %s", e.key, e.err)
        table.insert(error_lines, line)
        table.insert(error_highlights, {
          line = #error_lines - 1,
          col = 0,
          end_col = #line,
          hl = "WarningMsg",
        })
      end
      table.insert(error_lines, "")
      M.state.error_line_count = #error_lines
    end

    local lines, highlights = render_pr_list(prs, win_width)

    -- Offset PR highlights by error lines count
    if #error_lines > 0 then
      for _, hl in ipairs(highlights) do
        hl.line = hl.line + #error_lines
      end
    end

    -- Combine error lines + PR lines
    local all_lines = {}
    for _, line in ipairs(error_lines) do
      table.insert(all_lines, line)
    end
    for _, line in ipairs(lines) do
      table.insert(all_lines, line)
    end

    -- Combine highlights
    local all_highlights = {}
    for _, hl in ipairs(error_highlights) do
      table.insert(all_highlights, hl)
    end
    for _, hl in ipairs(highlights) do
      table.insert(all_highlights, hl)
    end

    vim.bo[M.state.buf].modifiable = true
    vim.api.nvim_buf_set_lines(M.state.buf, 0, -1, false, all_lines)
    vim.bo[M.state.buf].modifiable = false

    apply_highlights(M.state.buf, all_highlights)
    update_selection()
  end)
end

--- Fetch all open PRs involving the user, trying each configured token
---@param callback fun(prs: table[], errors: table[])
function M.fetch_all_prs(callback)
  local cfg, err = config.load()
  if err then
    callback({}, { { key = "config", err = err } })
    return
  end

  -- Collect unique tokens: {key, token} pairs
  local token_entries = {}
  local seen = {}

  if cfg.tokens and type(cfg.tokens) == "table" then
    for key, token in pairs(cfg.tokens) do
      if not seen[token] then
        table.insert(token_entries, { key = key, token = token })
        seen[token] = true
      end
    end
  end

  if cfg.github_token and cfg.github_token ~= "" and not seen[cfg.github_token] then
    table.insert(token_entries, {
      key = cfg.github_username or "github_token",
      token = cfg.github_token,
    })
  end

  if #token_entries == 0 then
    callback({}, { { key = "config", err = "No tokens configured" } })
    return
  end

  local all_prs = {}
  local all_errors = {}
  local pending = #token_entries
  local seen_pr = {}

  for _, entry in ipairs(token_entries) do
    api.search_user_prs(entry.key, entry.token, function(prs, api_err)
      pending = pending - 1

      if api_err then
        table.insert(all_errors, { key = entry.key, err = api_err })
      elseif prs then
        for _, pr in ipairs(prs) do
          -- Deduplicate by html_url
          if pr.html_url and not seen_pr[pr.html_url] then
            seen_pr[pr.html_url] = true
            table.insert(all_prs, pr)
          end
        end
      end

      if pending == 0 then
        callback(all_prs, all_errors)
      end
    end)
  end
end

--- Show PR description in a floating window (toggle)
function M.show_description()
  -- If description window is already open, close it (toggle off)
  if M.state.description_win and vim.api.nvim_win_is_valid(M.state.description_win) then
    vim.api.nvim_win_close(M.state.description_win, true)
    M.state.description_win = nil
    return
  end

  local state = require("raccoon.state")

  if not state.is_active() then
    vim.notify("No active PR review session", vim.log.levels.WARN)
    return
  end

  local pr = state.get_pr()
  if not pr then
    vim.notify("No PR data available", vim.log.levels.WARN)
    return
  end

  -- Parse description into lines
  local body = pr.body or "(No description)"
  local desc_lines = vim.split(body, "\n", { plain = true })

  -- Build content
  local lines = {
    string.format("PR #%d: %s", pr.number, pr.title),
    string.format("Author: %s", pr.user and pr.user.login or "unknown"),
    string.format("Branch: %s → %s", pr.head.ref, pr.base.ref),
    "",
    "─────────────────────────────────────────────────────────",
    "",
  }

  for _, line in ipairs(desc_lines) do
    table.insert(lines, line)
  end

  -- Calculate window size
  local max_width = 80
  local width = math.min(max_width, vim.o.columns - 10)
  local height = math.min(#lines + 2, vim.o.lines - 10)

  -- Create floating window
  local win, buf = M.create_floating_window({
    width = width,
    height = height,
    title = "PR Description",
    border = "rounded",
  })

  -- Store window handle for toggle
  M.state.description_win = win

  -- Set content
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "markdown"
  vim.wo[win].wrap = true

  -- Close keymaps (also clear state)
  local opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("n", "<leader>q", function()
    vim.api.nvim_win_close(win, true)
    M.state.description_win = nil
  end, opts)
  vim.keymap.set("n", "<Esc>", function()
    vim.api.nvim_win_close(win, true)
    M.state.description_win = nil
  end, opts)
end

return M
