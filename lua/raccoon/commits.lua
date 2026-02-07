---@class RaccoonCommits
---Commit viewer mode: sidebar with commits, grid of diff hunks
local M = {}

local config = require("raccoon.config")
local diff = require("raccoon.diff")
local git = require("raccoon.git")
local keymaps = require("raccoon.keymaps")
local open = require("raccoon.open")
local state = require("raccoon.state")

--- Namespace for commit viewer highlights
local ns_id = vim.api.nvim_create_namespace("raccoon_commits")

--- Module-local state
local commit_state = {
  active = false,
  sidebar_win = nil,
  sidebar_buf = nil,
  pr_commits = {},
  base_commits = {},
  selected_index = 1,
  grid_wins = {},
  grid_bufs = {},
  all_hunks = {},
  current_page = 1,
  saved_buf = nil,
  saved_laststatus = nil,
  grid_rows = 2,
  grid_cols = 2,
  maximize_win = nil,
  maximize_buf = nil,
  focus_augroup = nil,
}

--- Commit mode keymaps (global)
local commit_mode_keymaps = {}

local SIDEBAR_WIDTH = 40

--- Reset module state
local function reset_state()
  commit_state = {
    active = false,
    sidebar_win = nil,
    sidebar_buf = nil,
    pr_commits = {},
    base_commits = {},
    selected_index = 1,
    grid_wins = {},
    grid_bufs = {},
    all_hunks = {},
    current_page = 1,
    saved_buf = nil,
    saved_laststatus = nil,
    grid_rows = 2,
    grid_cols = 2,
    maximize_win = nil,
    maximize_buf = nil,
    focus_augroup = nil,
  }
end

--- Create a scratch buffer
---@return number buf
local function create_scratch_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  return buf
end

--- Render a diff hunk into a buffer with highlights
---@param buf number Buffer ID
---@param hunk table Parsed hunk from diff.parse_patch
---@param filename string File name to show at bottom
local function render_hunk_to_buffer(buf, hunk, filename)
  local lines = {}
  for _, line_data in ipairs(hunk.lines) do
    table.insert(lines, line_data.content or "")
  end

  -- Add blank line and filename at bottom
  table.insert(lines, "")
  table.insert(lines, "── " .. filename)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Set filetype for syntax highlighting
  local ft = vim.filetype.match({ filename = filename })
  if ft then
    vim.bo[buf].filetype = ft
  end

  -- Apply diff highlights and gutter signs
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  local line_idx = 0
  for _, line_data in ipairs(hunk.lines) do
    if line_data.type == "add" then
      pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "RaccoonAdd", line_idx, 0, -1)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
        sign_text = "+",
        sign_hl_group = "RaccoonAddSign",
      })
    elseif line_data.type == "del" then
      pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "RaccoonDelete", line_idx, 0, -1)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
        sign_text = "-",
        sign_hl_group = "RaccoonDeleteSign",
      })
    end
    line_idx = line_idx + 1
  end

  -- Highlight filename line
  pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "Comment", #lines - 1, 0, -1)
end

--- Calculate total pages
---@return number
local function total_pages()
  local cells = commit_state.grid_rows * commit_state.grid_cols
  if cells == 0 then return 1 end
  return math.max(1, math.ceil(#commit_state.all_hunks / cells))
end

--- Total navigable commits (PR + base)
---@return number
local function total_commits()
  return #commit_state.pr_commits + #commit_state.base_commits
end

--- Get commit by combined index (PR first, then base)
---@param index number 1-based index into combined list
---@return table|nil commit
local function get_commit(index)
  local pr_count = #commit_state.pr_commits
  if index <= pr_count then
    return commit_state.pr_commits[index]
  else
    return commit_state.base_commits[index - pr_count]
  end
end

--- Update the winbar page indicator on the sidebar
local function update_page_indicator()
  local win = commit_state.sidebar_win
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local pages = total_pages()
  if pages > 1 then
    vim.wo[win].winbar = string.format(" %d/%d ", commit_state.current_page, pages)
  else
    vim.wo[win].winbar = ""
  end
end

--- Render the current page of hunks into the grid
local function render_grid_page()
  local cells = commit_state.grid_rows * commit_state.grid_cols
  local start_idx = (commit_state.current_page - 1) * cells + 1

  for i, buf in ipairs(commit_state.grid_bufs) do
    if not vim.api.nvim_buf_is_valid(buf) then
      goto continue
    end

    local hunk_idx = start_idx + i - 1
    local hunk_data = commit_state.all_hunks[hunk_idx]

    if hunk_data then
      render_hunk_to_buffer(buf, hunk_data.hunk, hunk_data.filename)
    else
      -- Empty cell
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      vim.bo[buf].modifiable = false
      vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    end

    ::continue::
  end

  update_page_indicator()
end

--- Go to next page of hunks
local function next_page()
  if commit_state.current_page < total_pages() then
    commit_state.current_page = commit_state.current_page + 1
    render_grid_page()
  end
end

--- Go to previous page of hunks
local function prev_page()
  if commit_state.current_page > 1 then
    commit_state.current_page = commit_state.current_page - 1
    render_grid_page()
  end
end

--- Close the maximized hunk view
local function close_maximize()
  if commit_state.maximize_win and vim.api.nvim_win_is_valid(commit_state.maximize_win) then
    pcall(vim.api.nvim_win_close, commit_state.maximize_win, true)
  end
  commit_state.maximize_win = nil
  commit_state.maximize_buf = nil
end

--- Maximize a grid cell: show the full file diff in a floating window
---@param cell_num number 1-based grid cell index
local function maximize_cell(cell_num)
  local cells = commit_state.grid_rows * commit_state.grid_cols
  local start_idx = (commit_state.current_page - 1) * cells + 1
  local hunk_idx = start_idx + cell_num - 1
  local hunk_data = commit_state.all_hunks[hunk_idx]
  if not hunk_data then return end

  -- Collect all hunks from the same file
  local filename = hunk_data.filename
  local file_hunks = {}
  for _, h in ipairs(commit_state.all_hunks) do
    if h.filename == filename then
      table.insert(file_hunks, h)
    end
  end

  -- Build lines and track highlight info
  local lines = {}
  local hl_lines = {}
  for i, fh in ipairs(file_hunks) do
    if i > 1 then
      table.insert(lines, "")
      table.insert(hl_lines, { type = "ctx" })
      table.insert(lines, string.rep("─", 60))
      table.insert(hl_lines, { type = "sep" })
      table.insert(lines, "")
      table.insert(hl_lines, { type = "ctx" })
    end
    for _, line_data in ipairs(fh.hunk.lines) do
      table.insert(lines, line_data.content or "")
      table.insert(hl_lines, { type = line_data.type })
    end
  end

  -- Create floating window
  local width = math.floor(vim.o.columns * 0.85)
  local height = math.floor(vim.o.lines * 0.85)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = create_scratch_buf()
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Set filetype for syntax highlighting
  local ft = vim.filetype.match({ filename = filename })
  if ft then
    vim.bo[buf].filetype = ft
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
  })

  -- Apply diff highlights and gutter signs
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  for idx, hl in ipairs(hl_lines) do
    if hl.type == "add" then
      pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "RaccoonAdd", idx - 1, 0, -1)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, idx - 1, 0, {
        sign_text = "+",
        sign_hl_group = "RaccoonAddSign",
      })
    elseif hl.type == "del" then
      pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "RaccoonDelete", idx - 1, 0, -1)
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, idx - 1, 0, {
        sign_text = "-",
        sign_hl_group = "RaccoonDeleteSign",
      })
    elseif hl.type == "sep" then
      pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, "Comment", idx - 1, 0, -1)
    end
  end

  vim.wo[win].winbar = " " .. filename .. "%=%#Comment# <leader>q to exit %*"
  vim.wo[win].signcolumn = "yes:1"
  vim.wo[win].wrap = true

  -- Buffer-local keymaps to close
  local buf_opts = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set("n", "<leader>q", close_maximize, buf_opts)
  vim.keymap.set("n", "q", close_maximize, buf_opts)

  commit_state.maximize_win = win
  commit_state.maximize_buf = buf
end

--- Select a commit and load its hunks into the grid
---@param index number Index into the combined commit list (1-based)
local function select_commit(index)
  if index < 1 or index > total_commits() then
    return
  end

  commit_state.selected_index = index
  commit_state.current_page = 1

  local commit = get_commit(index)
  local clone_path = state.get_clone_path()
  if not clone_path then return end

  git.show_commit(clone_path, commit.sha, function(files, err)
    if err then
      vim.notify("Failed to get commit diff: " .. err, vim.log.levels.ERROR)
      return
    end

    -- Parse all files into flat hunk list
    commit_state.all_hunks = {}
    for _, file in ipairs(files or {}) do
      local hunks = diff.parse_patch(file.patch)
      for _, hunk in ipairs(hunks) do
        table.insert(commit_state.all_hunks, { hunk = hunk, filename = file.filename })
      end
    end

    if #commit_state.all_hunks == 0 then
      -- No diff hunks — clear grid
      for _, buf in ipairs(commit_state.grid_bufs) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  No changes in this commit" })
          vim.bo[buf].modifiable = false
        end
      end
      return
    end

    render_grid_page()
  end)
end

--- Update sidebar selection highlight and show full commit message
local function update_sidebar_selection()
  local buf = commit_state.sidebar_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local sel_ns = vim.api.nvim_create_namespace("raccoon_commit_sel")
  vim.api.nvim_buf_clear_namespace(buf, sel_ns, 0, -1)

  local idx = commit_state.selected_index
  if idx < 1 or idx > total_commits() then return end

  -- Sidebar layout: header at 0, PR commits at 1..N,
  -- blank at N+1, base header at N+2, base commits at N+3..
  local pr_count = #commit_state.pr_commits
  local base_count = #commit_state.base_commits
  local line_idx = idx
  if idx > pr_count then
    line_idx = idx + 2 -- skip blank separator + base header
  end
  pcall(vim.api.nvim_buf_add_highlight, buf, sel_ns, "Visual", line_idx, 0, -1)

  -- Update detail section at bottom with full commit message
  -- Detail starts after: header + pr commits + blank + header + base commits
  local detail_start = 1 + pr_count + 2 + base_count -- 0-based line index
  local commit = get_commit(idx)
  local detail_lines = { "", "──────────────────────────────────────" }
  if commit then
    -- Word-wrap the full message to sidebar width
    local msg = commit.message or ""
    local sha = commit.sha and commit.sha:sub(1, 7) or ""
    table.insert(detail_lines, sha)
    for line in (msg .. "\n"):gmatch("([^\n]*)\n") do
      if #line <= SIDEBAR_WIDTH - 2 then
        table.insert(detail_lines, line)
      else
        -- Wrap long lines
        local pos = 1
        while pos <= #line do
          table.insert(detail_lines, line:sub(pos, pos + SIDEBAR_WIDTH - 3))
          pos = pos + SIDEBAR_WIDTH - 2
        end
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, detail_start, -1, false, detail_lines)
  vim.bo[buf].modifiable = false

  -- Highlight detail separator and sha
  local hl_ns = vim.api.nvim_create_namespace("raccoon_commit_hl")
  pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, "Comment", detail_start + 1, 0, -1)
  if commit then
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, "Title", detail_start + 2, 0, -1)
  end

  if commit_state.sidebar_win and vim.api.nvim_win_is_valid(commit_state.sidebar_win) then
    pcall(vim.api.nvim_win_set_cursor, commit_state.sidebar_win, { line_idx + 1, 0 })
  end
end

--- Render the sidebar with commit lists
local function render_sidebar()
  local buf = commit_state.sidebar_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = {}
  local highlights = {}

  -- PR branch commits header
  table.insert(lines, "── PR Branch ──")
  table.insert(highlights, { line = #lines - 1, hl = "Title" })

  for _, commit in ipairs(commit_state.pr_commits) do
    local msg = commit.message
    if #msg > SIDEBAR_WIDTH - 2 then
      msg = msg:sub(1, SIDEBAR_WIDTH - 5) .. "..."
    end
    table.insert(lines, "  " .. msg)
  end

  -- Separator
  table.insert(lines, "")
  table.insert(lines, "── Base Branch ──")
  table.insert(highlights, { line = #lines - 1, hl = "Title" })

  for _, commit in ipairs(commit_state.base_commits) do
    local msg = commit.message
    if #msg > SIDEBAR_WIDTH - 2 then
      msg = msg:sub(1, SIDEBAR_WIDTH - 5) .. "..."
    end
    table.insert(lines, "  " .. msg)
    table.insert(highlights, { line = #lines - 1, hl = "Comment" })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Apply highlights
  local hl_ns = vim.api.nvim_create_namespace("raccoon_commit_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, hl.hl, hl.line, 0, -1)
  end

  update_sidebar_selection()
end

--- Move selection up in sidebar
local function move_up()
  if commit_state.selected_index > 1 then
    commit_state.selected_index = commit_state.selected_index - 1
    update_sidebar_selection()
    select_commit(commit_state.selected_index)
  end
end

--- Move selection down in sidebar
local function move_down()
  if commit_state.selected_index < total_commits() then
    commit_state.selected_index = commit_state.selected_index + 1
    update_sidebar_selection()
    select_commit(commit_state.selected_index)
  end
end

--- Close all grid windows and buffers
local function close_grid()
  for _, win in ipairs(commit_state.grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  commit_state.grid_wins = {}
  commit_state.grid_bufs = {}
end

--- Close the sidebar
local function close_sidebar()
  if commit_state.sidebar_win and vim.api.nvim_win_is_valid(commit_state.sidebar_win) then
    pcall(vim.api.nvim_win_close, commit_state.sidebar_win, true)
  end
  commit_state.sidebar_win = nil
  commit_state.sidebar_buf = nil
end

--- Create the grid layout (grid cells + sidebar)
---@param rows number Grid rows
---@param cols number Grid columns
local function create_grid_layout(rows, cols)
  commit_state.grid_rows = rows
  commit_state.grid_cols = cols

  -- Start with single window
  vim.cmd("only")

  -- Create sidebar on the right
  vim.cmd("vsplit")
  vim.cmd("wincmd L")
  commit_state.sidebar_win = vim.api.nvim_get_current_win()
  commit_state.sidebar_buf = create_scratch_buf()
  vim.api.nvim_win_set_buf(commit_state.sidebar_win, commit_state.sidebar_buf)
  vim.api.nvim_win_set_width(commit_state.sidebar_win, SIDEBAR_WIDTH)
  vim.wo[commit_state.sidebar_win].cursorline = true
  vim.wo[commit_state.sidebar_win].wrap = false
  vim.wo[commit_state.sidebar_win].number = false
  vim.wo[commit_state.sidebar_win].relativenumber = false
  vim.wo[commit_state.sidebar_win].signcolumn = "no"

  -- Go to main area (left of sidebar)
  vim.cmd("wincmd h")
  local main_win = vim.api.nvim_get_current_win()

  -- Create grid: first create rows by horizontal splitting
  local row_wins = { main_win }
  for _ = 2, rows do
    vim.api.nvim_set_current_win(row_wins[#row_wins])
    vim.cmd("split")
    table.insert(row_wins, vim.api.nvim_get_current_win())
  end

  -- For each row, create columns by vertical splitting
  local grid_wins = {}
  local grid_bufs = {}
  for _, row_win in ipairs(row_wins) do
    vim.api.nvim_set_current_win(row_win)
    local col_wins = { row_win }
    for _ = 2, cols do
      vim.cmd("vsplit")
      table.insert(col_wins, vim.api.nvim_get_current_win())
    end
    for _, win in ipairs(col_wins) do
      local buf = create_scratch_buf()
      vim.api.nvim_win_set_buf(win, buf)
      vim.wo[win].wrap = true
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = "yes:1"
      table.insert(grid_wins, win)
      table.insert(grid_bufs, buf)
    end
  end

  -- Reverse to reading order: top-left=1, top-right=2, bottom-left=3, etc.
  local n = #grid_wins
  for i = 1, math.floor(n / 2) do
    grid_wins[i], grid_wins[n - i + 1] = grid_wins[n - i + 1], grid_wins[i]
    grid_bufs[i], grid_bufs[n - i + 1] = grid_bufs[n - i + 1], grid_bufs[i]
  end

  commit_state.grid_wins = grid_wins
  commit_state.grid_bufs = grid_bufs

  -- Set cell number labels in winbar (no background highlight)
  for i, win in ipairs(grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winbar = "%=" .. i
      vim.wo[win].winhl = "WinBar:Normal,WinBarNC:Normal"
    end
  end

  -- Blend sidebar winbar background
  if vim.api.nvim_win_is_valid(commit_state.sidebar_win) then
    vim.wo[commit_state.sidebar_win].winhl = "WinBar:Normal,WinBarNC:Normal"
  end

  -- Equalize grid windows, then restore sidebar width and even row heights
  vim.cmd("wincmd =")
  if vim.api.nvim_win_is_valid(commit_state.sidebar_win) then
    vim.api.nvim_win_set_width(commit_state.sidebar_win, SIDEBAR_WIDTH)
  end
  local total_height = vim.o.lines - vim.o.cmdheight - 1
  local row_height = math.floor(total_height / rows)
  for _, win in ipairs(grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_height(win, row_height)
    end
  end

  -- Focus sidebar
  if vim.api.nvim_win_is_valid(commit_state.sidebar_win) then
    vim.api.nvim_set_current_win(commit_state.sidebar_win)
  end
end

--- Force focus back to sidebar (prevents leaving sidebar window)
local function lock_to_sidebar()
  local win = commit_state.sidebar_win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

--- Setup commit mode keymaps
local function setup_keymaps()
  local opts = { noremap = true, silent = true }
  local nop = function() end

  commit_mode_keymaps = {
    { mode = "n", lhs = "<leader>cm", rhs = function() M.toggle() end, desc = "Exit commit viewer" },
    { mode = "n", lhs = "<leader>j", rhs = next_page, desc = "Next page of hunks" },
    { mode = "n", lhs = "<leader>k", rhs = prev_page, desc = "Previous page of hunks" },
    { mode = "n", lhs = "<leader>l", rhs = next_page, desc = "Next page of hunks" },
    -- Block window-switching keys
    { mode = "n", lhs = "<C-w>h", rhs = nop, desc = "Blocked in commit mode" },
    { mode = "n", lhs = "<C-w>j", rhs = nop, desc = "Blocked in commit mode" },
    { mode = "n", lhs = "<C-w>k", rhs = nop, desc = "Blocked in commit mode" },
    { mode = "n", lhs = "<C-w>l", rhs = nop, desc = "Blocked in commit mode" },
    { mode = "n", lhs = "<C-w>w", rhs = nop, desc = "Blocked in commit mode" },
    { mode = "n", lhs = "<C-w><C-w>", rhs = nop, desc = "Blocked in commit mode" },
    { mode = "n", lhs = "<C-w>H", rhs = nop, desc = "Blocked in commit mode" },
    { mode = "n", lhs = "<C-w>J", rhs = nop, desc = "Blocked in commit mode" },
    { mode = "n", lhs = "<C-w>K", rhs = nop, desc = "Blocked in commit mode" },
    { mode = "n", lhs = "<C-w>L", rhs = nop, desc = "Blocked in commit mode" },
  }

  -- Add <leader>m<N> keymaps for each grid cell
  local cells = commit_state.grid_rows * commit_state.grid_cols
  for i = 1, cells do
    table.insert(commit_mode_keymaps, {
      mode = "n",
      lhs = "<leader>m" .. i,
      rhs = function() maximize_cell(i) end,
      desc = "Maximize grid cell " .. i,
    })
  end

  for _, km in ipairs(commit_mode_keymaps) do
    vim.keymap.set(km.mode, km.lhs, km.rhs, vim.tbl_extend("force", opts, { desc = km.desc }))
  end

  -- Sidebar-local keymaps
  if commit_state.sidebar_buf and vim.api.nvim_buf_is_valid(commit_state.sidebar_buf) then
    local buf_opts = { buffer = commit_state.sidebar_buf, noremap = true, silent = true }
    vim.keymap.set("n", "j", move_down, buf_opts)
    vim.keymap.set("n", "k", move_up, buf_opts)
    vim.keymap.set("n", "<Down>", move_down, buf_opts)
    vim.keymap.set("n", "<Up>", move_up, buf_opts)
    vim.keymap.set("n", "<CR>", function() select_commit(commit_state.selected_index) end, buf_opts)
  end

  -- Autocmd to snap focus back to sidebar if user somehow leaves it
  commit_state.focus_augroup = vim.api.nvim_create_augroup("RaccoonCommitFocus", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = commit_state.focus_augroup,
    callback = function()
      if not commit_state.active then return end
      local cur_win = vim.api.nvim_get_current_win()
      -- Allow maximize floating window
      if cur_win == commit_state.maximize_win then return end
      if cur_win ~= commit_state.sidebar_win then
        vim.schedule(lock_to_sidebar)
      end
    end,
  })
end

--- Clear commit mode keymaps
local function clear_keymaps()
  for _, km in ipairs(commit_mode_keymaps) do
    pcall(vim.keymap.del, km.mode, km.lhs)
  end
  commit_mode_keymaps = {}
end

--- Enter commit viewer mode
local function enter_commit_mode()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return
  end

  local pr = state.get_pr()
  if not pr then
    vim.notify("No PR data", vim.log.levels.WARN)
    return
  end

  -- Save current buffer and settings for restore
  commit_state.saved_buf = vim.api.nvim_get_current_buf()
  commit_state.saved_laststatus = vim.o.laststatus
  vim.o.laststatus = 3

  -- Clear PR review keymaps and pause sync
  keymaps.clear()
  open.pause_sync()
  state.set_commit_mode(true)
  commit_state.active = true

  -- Load config for grid dimensions
  local cfg = config.load()
  local rows = 2
  local cols = 2
  local base_count = 20
  if cfg and cfg.commit_viewer then
    if cfg.commit_viewer.grid then
      rows = cfg.commit_viewer.grid.rows or rows
      cols = cfg.commit_viewer.grid.cols or cols
    end
    base_count = cfg.commit_viewer.base_commits_count or base_count
  end

  local clone_path = state.get_clone_path()
  local base_branch = pr.base.ref

  vim.notify("Entering commit viewer mode...", vim.log.levels.INFO)

  -- Unshallow if needed, then fetch base branch, then fetch commits
  git.unshallow_if_needed(clone_path, function(_, unshallow_err)
    if unshallow_err then
      vim.notify("Warning: unshallow failed: " .. unshallow_err, vim.log.levels.WARN)
    end

    -- Fetch base branch to ensure origin/<base_branch> ref exists
    -- (shallow single-branch clones only track the PR branch)
    git.fetch_branch(clone_path, base_branch, function(_, fetch_err)
      if fetch_err then
        vim.notify("Failed to fetch base branch: " .. fetch_err, vim.log.levels.ERROR)
        M.toggle()
        return
      end

      -- Fetch PR commits and base commits in parallel
      local pending = 2

      local function on_both_ready()
        if #commit_state.pr_commits == 0 then
          vim.notify("No commits found on PR branch", vim.log.levels.WARN)
          M.toggle()
          return
        end

        create_grid_layout(rows, cols)
        render_sidebar()
        setup_keymaps()
        select_commit(1)
        vim.notify(string.format("Commit viewer: %d PR commits, %d base commits",
          #commit_state.pr_commits, #commit_state.base_commits))
      end

      local function check_done()
        pending = pending - 1
        if pending == 0 then
          vim.schedule(on_both_ready)
        end
      end

      git.log_commits(clone_path, base_branch, function(commits, err)
        if err then
          vim.notify("Failed to get PR commits: " .. err, vim.log.levels.ERROR)
          commit_state.pr_commits = {}
        else
          commit_state.pr_commits = commits or {}
        end
        check_done()
      end)

      git.log_base_commits(clone_path, base_branch, base_count, function(commits, err)
        if err then
          commit_state.base_commits = {}
        else
          commit_state.base_commits = commits or {}
        end
        check_done()
      end)
    end)
  end)
end

--- Exit commit viewer mode
local function exit_commit_mode()
  -- Remove focus lock first (before closing windows)
  if commit_state.focus_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, commit_state.focus_augroup)
  end

  close_maximize()
  clear_keymaps()
  close_grid()
  close_sidebar()

  state.set_commit_mode(false)

  -- Restore laststatus
  if commit_state.saved_laststatus then
    vim.o.laststatus = commit_state.saved_laststatus
  end

  -- Restore: close all windows, open saved buffer
  vim.cmd("only")
  if commit_state.saved_buf and vim.api.nvim_buf_is_valid(commit_state.saved_buf) then
    vim.api.nvim_set_current_buf(commit_state.saved_buf)
  end

  -- Restore PR review keymaps and resume sync
  keymaps.setup()
  open.resume_sync()

  reset_state()
  vim.notify("Exited commit viewer mode", vim.log.levels.INFO)
end

--- Toggle commit viewer mode
function M.toggle()
  if commit_state.active then
    exit_commit_mode()
  else
    enter_commit_mode()
  end
end

return M
