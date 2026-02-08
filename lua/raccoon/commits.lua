---@class RaccoonCommits
---Commit viewer mode: sidebar with commits, grid of diff hunks
local M = {}

local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
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
  header_win = nil,
  header_buf = nil,
  filetree_win = nil,
  filetree_buf = nil,
  select_generation = 0,
}

--- Commit mode keymaps (global)
local commit_mode_keymaps = {}

local SIDEBAR_WIDTH = 40

-- Forward declaration (defined after create_grid_layout)
local render_filetree

--- Clamp a config value to an integer within [min_val, max_val], or return default
---@param val any
---@param default number
---@param min_val number
---@param max_val number
---@return number
local function clamp_int(val, default, min_val, max_val)
  if type(val) ~= "number" then return default end
  val = math.floor(val)
  if val < min_val then return min_val end
  if val > max_val then return max_val end
  return val
end

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
    header_win = nil,
    header_buf = nil,
    filetree_win = nil,
    filetree_buf = nil,
    select_generation = 0,
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

--- Block keys that shouldn't work in commit mode buffers (sidebar, grid, header).
--- Allows: j/k, motion, scrolling, leader-prefixed keys (global, unaffected).
---@param buf number Buffer ID
local function lock_buf(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local opts = { buffer = buf, noremap = true, silent = true }
  local nop = function() end
  local blocked = {
    "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "R",
    "d", "x", "p", "P", "u", "<C-r>",
    "q", "Q", "gQ",
    "ZZ", "ZQ",
    "<C-z>",
    ":",
  }
  for _, key in ipairs(blocked) do
    vim.keymap.set(NORMAL_MODE, key, nop, opts)
  end
end

--- Block editing keys and commit-mode navigation in the maximize floating window.
--- Allows: all vim navigation, scrolling, search, q/<leader>q (close), : (ex commands).
--- Blocks: page nav, cell maximize, editing, insert — so maximize is fully isolated.
---@param buf number Buffer ID
local function lock_maximize_buf(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local shortcuts = config.load_shortcuts()
  local opts = { buffer = buf, noremap = true, silent = true }
  local nop = function() end
  local blocked = {
    -- Insert/editing keys
    "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "R",
    "d", "x", "p", "P", "u", "<C-r>",
    "Q", "gQ",
    "ZZ", "ZQ",
    "<C-z>",
  }
  -- Only block commit-mode navigation keys that are enabled
  for _, key in ipairs({
    shortcuts.commit_mode.next_page, shortcuts.commit_mode.prev_page,
    shortcuts.commit_mode.next_page_alt, shortcuts.commit_mode.exit,
  }) do
    if config.is_enabled(key) then
      table.insert(blocked, key)
    end
  end
  for _, key in ipairs(blocked) do
    vim.keymap.set(NORMAL_MODE, key, nop, opts)
  end
  -- Block all cell maximize keys (only if maximize_prefix is enabled)
  if config.is_enabled(shortcuts.commit_mode.maximize_prefix) then
    local cells = commit_state.grid_rows * commit_state.grid_cols
    for i = 1, cells do
      vim.keymap.set(NORMAL_MODE, shortcuts.commit_mode.maximize_prefix .. i, nop, opts)
    end
  end
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
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
        line_hl_group = "RaccoonAdd",
        sign_text = "+",
        sign_hl_group = "RaccoonAddSign",
      })
    elseif line_data.type == "del" then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
        line_hl_group = "RaccoonDelete",
        sign_text = "-",
        sign_hl_group = "RaccoonDeleteSign",
      })
    end
    line_idx = line_idx + 1
  end
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

--- Update the header bar with commit message and page indicator
local function update_header()
  local buf = commit_state.header_buf
  local win = commit_state.header_win
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  local commit = get_commit(commit_state.selected_index)
  local pages = total_pages()
  local show_pages = pages > 1
  local page_str = show_pages and (" " .. commit_state.current_page .. "/" .. pages .. " ") or ""

  if not commit then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { page_str })
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_height(win, 1)
    return
  end

  local msg = commit.message or ""

  -- Split message into lines
  local msg_lines = vim.split(msg, "\n", { trimempty = true })
  if #msg_lines == 0 then msg_lines = { "" } end

  -- Build display: page indicator (if >1 page) then commit message
  local lines = {}
  table.insert(lines, page_str .. " " .. msg_lines[1])

  for i = 2, #msg_lines do
    table.insert(lines, " " .. msg_lines[i])
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Highlight page indicator
  local hl_ns = vim.api.nvim_create_namespace("raccoon_header_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  if show_pages then
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, "Comment", 0, 0, #page_str)
  end

  vim.api.nvim_win_set_height(win, math.max(1, #lines))
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

    local win = commit_state.grid_wins[i]
    if hunk_data then
      render_hunk_to_buffer(buf, hunk_data.hunk, hunk_data.filename)
      -- Show filename and cell number in winbar
      if win and vim.api.nvim_win_is_valid(win) then
        vim.wo[win].winbar = " " .. hunk_data.filename .. "%=#" .. i
      end
    else
      -- Empty cell
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
      vim.bo[buf].modifiable = false
      vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
      if win and vim.api.nvim_win_is_valid(win) then
        vim.wo[win].winbar = "%=#" .. i
      end
    end

    ::continue::
  end

  update_header()
  render_filetree()
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

  local filename = hunk_data.filename
  if filename == "dev/null" then return end
  local commit = get_commit(commit_state.selected_index)
  local clone_path = state.get_clone_path()
  if not commit or not clone_path then return end

  local generation = commit_state.select_generation

  -- Fetch full-context diff for this file (shows entire file, not just hunks)
  git.show_commit_file(clone_path, commit.sha, filename, function(patch, err)
    if generation ~= commit_state.select_generation then return end

    if err or not patch or patch == "" then
      vim.notify("Failed to get full file diff", vim.log.levels.ERROR)
      return
    end

    local hunks = diff.parse_patch(patch)
    if #hunks == 0 then return end

    -- Build lines and track highlight info
    local lines = {}
    local hl_lines = {}
    for _, hunk in ipairs(hunks) do
      for _, line_data in ipairs(hunk.lines) do
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

    -- Set state immediately so the WinEnter autocmd recognizes this window
    commit_state.maximize_win = win
    commit_state.maximize_buf = buf

    -- Apply diff highlights and gutter signs
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    for idx, hl in ipairs(hl_lines) do
      if hl.type == "add" then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, idx - 1, 0, {
          line_hl_group = "RaccoonAdd",
          sign_text = "+",
          sign_hl_group = "RaccoonAddSign",
        })
      elseif hl.type == "del" then
        pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, idx - 1, 0, {
          line_hl_group = "RaccoonDelete",
          sign_text = "-",
          sign_hl_group = "RaccoonDeleteSign",
        })
      end
    end

    local shortcuts = config.load_shortcuts()
    local close_hint = config.is_enabled(shortcuts.close) and (shortcuts.close .. " or q") or "q"
    vim.wo[win].winbar = " " .. filename .. "%=%#Comment# " .. close_hint .. " to exit %*"
    vim.wo[win].signcolumn = "yes:1"
    vim.wo[win].wrap = true

    lock_maximize_buf(buf)

    -- Buffer-local keymaps to close (set after lock so these override nop)
    local buf_opts = { buffer = buf, noremap = true, silent = true }
    if config.is_enabled(shortcuts.close) then
      vim.keymap.set(NORMAL_MODE, shortcuts.close, close_maximize, buf_opts)
    end
    vim.keymap.set(NORMAL_MODE, "q", close_maximize, buf_opts)
  end)
end

--- Select a commit and load its hunks into the grid
---@param index number Index into the combined commit list (1-based)
local function select_commit(index)
  if index < 1 or index > total_commits() then
    return
  end

  commit_state.selected_index = index
  commit_state.current_page = 1
  commit_state.select_generation = commit_state.select_generation + 1
  local generation = commit_state.select_generation

  local commit = get_commit(index)
  local clone_path = state.get_clone_path()
  if not clone_path then return end

  git.show_commit(clone_path, commit.sha, function(files, err)
    if generation ~= commit_state.select_generation then return end

    if err then
      vim.notify("Failed to get commit diff", vim.log.levels.ERROR)
      vim.notify("[raccoon debug] show_commit: " .. err, vim.log.levels.DEBUG)
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
      -- No diff hunks — clear grid and reset winbars
      for i, buf in ipairs(commit_state.grid_bufs) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  No changes in this commit" })
          vim.bo[buf].modifiable = false
        end
        local win = commit_state.grid_wins[i]
        if win and vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winbar = "%=#" .. i
        end
      end
      update_header()
      return
    end

    render_grid_page()
  end)
end

--- Update sidebar selection highlight
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
  local line_idx = idx
  if idx > pr_count then
    line_idx = idx + 2 -- skip blank separator + base header
  end
  pcall(vim.api.nvim_buf_add_highlight, buf, sel_ns, "Visual", line_idx, 0, -1)

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

--- Close the file tree panel
local function close_filetree()
  if commit_state.filetree_win and vim.api.nvim_win_is_valid(commit_state.filetree_win) then
    pcall(vim.api.nvim_win_close, commit_state.filetree_win, true)
  end
  commit_state.filetree_win = nil
  commit_state.filetree_buf = nil
end

--- Render the file tree panel with three-tier highlighting
render_filetree = function()
  local buf = commit_state.filetree_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  -- Collect all PR file paths
  local pr_files = state.get_files()
  local all_paths = {}
  for _, file in ipairs(pr_files) do
    table.insert(all_paths, file.filename)
  end
  table.sort(all_paths)

  -- Build lookup: files in current commit (all hunks)
  local commit_files = {}
  for _, hunk_data in ipairs(commit_state.all_hunks) do
    commit_files[hunk_data.filename] = true
  end

  -- Build lookup: files visible on current grid page
  local visible_files = {}
  local cells = commit_state.grid_rows * commit_state.grid_cols
  local start_idx = (commit_state.current_page - 1) * cells + 1
  for i = start_idx, math.min(start_idx + cells - 1, #commit_state.all_hunks) do
    local hunk_data = commit_state.all_hunks[i]
    if hunk_data then
      visible_files[hunk_data.filename] = true
    end
  end

  -- Render lines and determine highlights
  local lines = {}
  local highlights = {}
  for _, path in ipairs(all_paths) do
    table.insert(lines, "  " .. path)
    local hl_group
    if visible_files[path] then
      hl_group = "RaccoonFileVisible"
    elseif commit_files[path] then
      hl_group = "RaccoonFileInCommit"
    else
      hl_group = "RaccoonFileNormal"
    end
    table.insert(highlights, { line = #lines - 1, hl = hl_group })
  end

  if #lines == 0 then
    lines = { "  No files" }
    highlights = { { line = 0, hl = "Comment" } }
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  -- Apply highlights
  local hl_ns = vim.api.nvim_create_namespace("raccoon_filetree_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, hl.hl, hl.line, 0, -1)
  end

  -- Update winbar with file count
  local win = commit_state.filetree_win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = " Files (" .. #all_paths .. ")"
  end
end

--- Create the grid layout (grid cells + sidebar + file tree)
---@param rows number Grid rows
---@param cols number Grid columns
local function create_grid_layout(rows, cols)
  commit_state.grid_rows = rows
  commit_state.grid_cols = cols

  -- Start with single window
  vim.cmd("only")

  -- Create file tree panel on the LEFT
  vim.cmd("vsplit")
  vim.cmd("wincmd H")
  commit_state.filetree_win = vim.api.nvim_get_current_win()
  commit_state.filetree_buf = create_scratch_buf()
  vim.api.nvim_win_set_buf(commit_state.filetree_win, commit_state.filetree_buf)
  vim.api.nvim_win_set_width(commit_state.filetree_win, SIDEBAR_WIDTH)
  vim.wo[commit_state.filetree_win].wrap = false
  vim.wo[commit_state.filetree_win].number = false
  vim.wo[commit_state.filetree_win].relativenumber = false
  vim.wo[commit_state.filetree_win].signcolumn = "no"
  lock_buf(commit_state.filetree_buf)

  -- Go to main area (right of file tree)
  vim.cmd("wincmd l")

  -- Create commit sidebar on the RIGHT
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

  -- Go to main area (between both panels)
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
      lock_buf(buf)
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
      vim.wo[win].winbar = "%=#" .. i
      vim.wo[win].winhl = "WinBar:Normal,WinBarNC:Normal"
    end
  end

  -- Blend sidebar and filetree winbar backgrounds
  if vim.api.nvim_win_is_valid(commit_state.sidebar_win) then
    vim.wo[commit_state.sidebar_win].winhl = "WinBar:Normal,WinBarNC:Normal"
  end
  if vim.api.nvim_win_is_valid(commit_state.filetree_win) then
    vim.wo[commit_state.filetree_win].winhl = "WinBar:Normal,WinBarNC:Normal"
  end

  -- Create header window at the top (full width)
  vim.api.nvim_set_current_win(grid_wins[1])
  vim.cmd("split")
  commit_state.header_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd K")
  commit_state.header_buf = create_scratch_buf()
  vim.api.nvim_win_set_buf(commit_state.header_win, commit_state.header_buf)
  vim.wo[commit_state.header_win].number = false
  vim.wo[commit_state.header_win].relativenumber = false
  vim.wo[commit_state.header_win].signcolumn = "no"
  vim.wo[commit_state.header_win].wrap = false
  vim.wo[commit_state.header_win].winhl = "Normal:Normal"
  lock_buf(commit_state.header_buf)

  -- Equalize grid windows, then fix dimensions
  vim.cmd("wincmd =")
  if vim.api.nvim_win_is_valid(commit_state.sidebar_win) then
    vim.api.nvim_win_set_width(commit_state.sidebar_win, SIDEBAR_WIDTH)
  end
  if vim.api.nvim_win_is_valid(commit_state.filetree_win) then
    vim.api.nvim_win_set_width(commit_state.filetree_win, SIDEBAR_WIDTH)
  end
  vim.api.nvim_win_set_height(commit_state.header_win, 1)
  local total_height = vim.o.lines - vim.o.cmdheight - 2
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

--- Setup commit mode keymaps (buffer-local to all commit-mode buffers)
local function setup_keymaps()
  local shortcuts = config.load_shortcuts()
  local nop = function() end

  local all = {
    {
      mode = NORMAL_MODE, lhs = shortcuts.commit_mode.exit,
      rhs = function() M.toggle() end, desc = "Exit commit viewer",
    },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_mode.next_page, rhs = next_page, desc = "Next page of hunks" },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_mode.prev_page, rhs = prev_page, desc = "Previous page of hunks" },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_mode.next_page_alt, rhs = next_page, desc = "Next page of hunks" },
  }

  -- Filter out disabled commit-mode shortcuts, keep hardcoded blocks unconditional
  commit_mode_keymaps = {}
  for _, km in ipairs(all) do
    if config.is_enabled(km.lhs) then
      table.insert(commit_mode_keymaps, km)
    end
  end

  -- Block window-switching keys (always, not user-configurable)
  local window_blocks = {
    { mode = NORMAL_MODE, lhs = "<C-w>h", rhs = nop, desc = "Blocked in commit mode" },
    { mode = NORMAL_MODE, lhs = "<C-w>j", rhs = nop, desc = "Blocked in commit mode" },
    { mode = NORMAL_MODE, lhs = "<C-w>k", rhs = nop, desc = "Blocked in commit mode" },
    { mode = NORMAL_MODE, lhs = "<C-w>l", rhs = nop, desc = "Blocked in commit mode" },
    { mode = NORMAL_MODE, lhs = "<C-w>w", rhs = nop, desc = "Blocked in commit mode" },
    { mode = NORMAL_MODE, lhs = "<C-w><C-w>", rhs = nop, desc = "Blocked in commit mode" },
    { mode = NORMAL_MODE, lhs = "<C-w>H", rhs = nop, desc = "Blocked in commit mode" },
    { mode = NORMAL_MODE, lhs = "<C-w>J", rhs = nop, desc = "Blocked in commit mode" },
    { mode = NORMAL_MODE, lhs = "<C-w>K", rhs = nop, desc = "Blocked in commit mode" },
    { mode = NORMAL_MODE, lhs = "<C-w>L", rhs = nop, desc = "Blocked in commit mode" },
  }
  for _, km in ipairs(window_blocks) do
    table.insert(commit_mode_keymaps, km)
  end

  -- Add maximize keymaps for each grid cell (only if maximize_prefix is enabled)
  if config.is_enabled(shortcuts.commit_mode.maximize_prefix) then
    local cells = commit_state.grid_rows * commit_state.grid_cols
    for i = 1, cells do
      table.insert(commit_mode_keymaps, {
        mode = NORMAL_MODE,
        lhs = shortcuts.commit_mode.maximize_prefix .. i,
        rhs = function() maximize_cell(i) end,
        desc = "Maximize grid cell " .. i,
      })
    end
  end

  -- Collect all commit-mode buffers
  local commit_bufs = {}
  for _, buf in ipairs(commit_state.grid_bufs or {}) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      table.insert(commit_bufs, buf)
    end
  end
  if commit_state.sidebar_buf and vim.api.nvim_buf_is_valid(commit_state.sidebar_buf) then
    table.insert(commit_bufs, commit_state.sidebar_buf)
  end
  if commit_state.header_buf and vim.api.nvim_buf_is_valid(commit_state.header_buf) then
    table.insert(commit_bufs, commit_state.header_buf)
  end
  if commit_state.filetree_buf and vim.api.nvim_buf_is_valid(commit_state.filetree_buf) then
    table.insert(commit_bufs, commit_state.filetree_buf)
  end

  -- Apply keymaps buffer-locally (no global side effects)
  for _, buf in ipairs(commit_bufs) do
    for _, km in ipairs(commit_mode_keymaps) do
      vim.keymap.set(km.mode, km.lhs, km.rhs,
        { buffer = buf, noremap = true, silent = true, desc = km.desc })
    end
  end

  -- Sidebar-local keymaps
  if commit_state.sidebar_buf and vim.api.nvim_buf_is_valid(commit_state.sidebar_buf) then
    local buf_opts = { buffer = commit_state.sidebar_buf, noremap = true, silent = true }
    vim.keymap.set(NORMAL_MODE, "j", move_down, buf_opts)
    vim.keymap.set(NORMAL_MODE, "k", move_up, buf_opts)
    vim.keymap.set(NORMAL_MODE, "<Down>", move_down, buf_opts)
    vim.keymap.set(NORMAL_MODE, "<Up>", move_up, buf_opts)
    vim.keymap.set(NORMAL_MODE, "<CR>", function() select_commit(commit_state.selected_index) end, buf_opts)
    lock_buf(commit_state.sidebar_buf)
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
      -- If maximize is open, always snap back to it
      if commit_state.maximize_win and vim.api.nvim_win_is_valid(commit_state.maximize_win) then
        vim.schedule(function()
          if commit_state.maximize_win and vim.api.nvim_win_is_valid(commit_state.maximize_win) then
            vim.api.nvim_set_current_win(commit_state.maximize_win)
          end
        end)
        return
      end
      if cur_win ~= commit_state.sidebar_win then
        vim.schedule(lock_to_sidebar)
      end
    end,
  })
end

--- Clear commit mode keymaps
--- Buffer-local keymaps are automatically cleaned up when buffers are wiped
local function clear_keymaps()
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

  -- Validate inputs before modifying any state
  local clone_path = state.get_clone_path()
  if not clone_path or clone_path == "" then
    vim.notify("No clone path available", vim.log.levels.WARN)
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
      rows = clamp_int(cfg.commit_viewer.grid.rows, 2, 1, 10)
      cols = clamp_int(cfg.commit_viewer.grid.cols, 2, 1, 10)
    end
    base_count = clamp_int(cfg.commit_viewer.base_commits_count, 20, 1, 200)
  end

  local base_branch = pr.base.ref

  vim.notify("Entering commit viewer mode...", vim.log.levels.INFO)

  -- Unshallow if needed, then fetch base branch, then fetch commits
  git.unshallow_if_needed(clone_path, function(_, unshallow_err)
    if unshallow_err then
      vim.notify("Warning: repository unshallow failed", vim.log.levels.WARN)
      vim.notify("[raccoon debug] unshallow: " .. unshallow_err, vim.log.levels.DEBUG)
    end

    -- Fetch base branch to ensure origin/<base_branch> ref exists
    -- (shallow single-branch clones only track the PR branch)
    git.fetch_branch(clone_path, base_branch, function(_, fetch_err)
      if fetch_err then
        vim.notify("Failed to fetch base branch", vim.log.levels.ERROR)
        vim.notify("[raccoon debug] fetch_branch: " .. fetch_err, vim.log.levels.DEBUG)
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
          vim.notify("Failed to get PR commits", vim.log.levels.ERROR)
          vim.notify("[raccoon debug] log_commits: " .. err, vim.log.levels.DEBUG)
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
  close_filetree()

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

-- Exposed for testing
M._lock_buf = lock_buf
M._lock_maximize_buf = lock_maximize_buf
M._clamp_int = clamp_int
M._get_state = function() return commit_state end
M._select_commit = select_commit
M._setup_keymaps = setup_keymaps
M._render_filetree = render_filetree

return M
