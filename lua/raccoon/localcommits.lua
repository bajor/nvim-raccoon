---@class RaccoonLocalCommits
---Local commit viewer: browse commits in any git repository
local M = {}

local commits_mod = require("raccoon.commits")
local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local diff = require("raccoon.diff")
local git = require("raccoon.git")
local keymaps = require("raccoon.keymaps")
local open = require("raccoon.open")
local state = require("raccoon.state")

local ns_id = vim.api.nvim_create_namespace("raccoon_local_commits")

local SIDEBAR_WIDTH = 40
local BATCH_SIZE = 100
local POLL_INTERVAL_MS = 10000

--- Module-local state (in-memory only, no disk persistence)
local local_state = {
  active = false,
  repo_path = nil,
  commits = {},
  total_loaded = 0,
  loading_more = false,
  poll_timer = nil,
  last_head_sha = nil,
  sidebar_win = nil,
  sidebar_buf = nil,
  selected_index = 1,
  grid_wins = {},
  grid_bufs = {},
  all_hunks = {},
  commit_files = {},
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
  cached_sha = nil,
  cached_tree_lines = nil,
  cached_line_paths = nil,
  cached_file_count = nil,
  pr_was_active = false,
}

local local_mode_keymaps = {}

-- Forward declarations
local render_filetree
local load_more_commits

local function reset_state()
  local_state = {
    active = false,
    repo_path = nil,
    commits = {},
    total_loaded = 0,
    loading_more = false,
    poll_timer = nil,
    last_head_sha = nil,
    sidebar_win = nil,
    sidebar_buf = nil,
    selected_index = 1,
    grid_wins = {},
    grid_bufs = {},
    all_hunks = {},
    commit_files = {},
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
    cached_sha = nil,
    cached_tree_lines = nil,
    cached_line_paths = nil,
    cached_file_count = nil,
    pr_was_active = false,
  }
end

local function create_scratch_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  return buf
end

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

local function lock_maximize_buf(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local shortcuts = config.load_shortcuts()
  local opts = { buffer = buf, noremap = true, silent = true }
  local nop = function() end
  local blocked = {
    "i", "I", "a", "A", "o", "O", "s", "S", "c", "C", "R",
    "d", "x", "p", "P", "u", "<C-r>",
    "Q", "gQ",
    "ZZ", "ZQ",
    "<C-z>",
  }
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
  if config.is_enabled(shortcuts.commit_mode.maximize_prefix) then
    local cells = local_state.grid_rows * local_state.grid_cols
    for i = 1, cells do
      vim.keymap.set(NORMAL_MODE, shortcuts.commit_mode.maximize_prefix .. i, nop, opts)
    end
  end
end

--- Render a diff hunk into a buffer with highlights
local function render_hunk_to_buffer(buf, hunk, filename)
  local lines = {}
  for _, line_data in ipairs(hunk.lines) do
    table.insert(lines, line_data.content or "")
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local ft = vim.filetype.match({ filename = filename })
  if ft then
    vim.bo[buf].filetype = ft
  end

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

local function total_pages()
  local cells = local_state.grid_rows * local_state.grid_cols
  if cells == 0 then return 1 end
  return math.max(1, math.ceil(#local_state.all_hunks / cells))
end

--- Update the header bar with commit message and page indicator
local function update_header()
  local buf = local_state.header_buf
  local win = local_state.header_win
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  local commit = local_state.commits[local_state.selected_index]
  local pages = total_pages()
  local show_pages = pages > 1
  local page_str = show_pages and (" " .. local_state.current_page .. "/" .. pages .. " ") or ""

  if not commit then
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { page_str })
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_height(win, 1)
    return
  end

  local msg = commit.message or ""
  local msg_lines = vim.split(msg, "\n", { trimempty = true })
  if #msg_lines == 0 then msg_lines = { "" } end

  local lines = {}
  table.insert(lines, page_str .. " " .. msg_lines[1])
  for i = 2, #msg_lines do
    table.insert(lines, " " .. msg_lines[i])
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local hl_ns = vim.api.nvim_create_namespace("raccoon_local_header_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  if show_pages then
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, "Comment", 0, 0, #page_str)
  end

  vim.api.nvim_win_set_height(win, math.max(1, #lines))
end

--- Render the current page of hunks into the grid
local function render_grid_page()
  local cells = local_state.grid_rows * local_state.grid_cols
  local start_idx = (local_state.current_page - 1) * cells + 1

  for i, buf in ipairs(local_state.grid_bufs) do
    if not vim.api.nvim_buf_is_valid(buf) then
      goto continue
    end

    local hunk_idx = start_idx + i - 1
    local hunk_data = local_state.all_hunks[hunk_idx]

    local win = local_state.grid_wins[i]
    if hunk_data then
      render_hunk_to_buffer(buf, hunk_data.hunk, hunk_data.filename)
      if win and vim.api.nvim_win_is_valid(win) then
        vim.wo[win].winbar = " " .. hunk_data.filename .. "%=#" .. i
      end
    else
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

local function next_page()
  if local_state.current_page < total_pages() then
    local_state.current_page = local_state.current_page + 1
    render_grid_page()
  end
end

local function prev_page()
  if local_state.current_page > 1 then
    local_state.current_page = local_state.current_page - 1
    render_grid_page()
  end
end

local function close_maximize()
  if local_state.maximize_win and vim.api.nvim_win_is_valid(local_state.maximize_win) then
    pcall(vim.api.nvim_win_close, local_state.maximize_win, true)
  end
  local_state.maximize_win = nil
  local_state.maximize_buf = nil
end

--- Maximize a grid cell: show the full file diff in a floating window
local function maximize_cell(cell_num)
  local cells = local_state.grid_rows * local_state.grid_cols
  local start_idx = (local_state.current_page - 1) * cells + 1
  local hunk_idx = start_idx + cell_num - 1
  local hunk_data = local_state.all_hunks[hunk_idx]
  if not hunk_data then return end

  local filename = hunk_data.filename
  if filename == "dev/null" then return end
  local commit = local_state.commits[local_state.selected_index]
  local repo_path = local_state.repo_path
  if not commit or not repo_path then return end

  local generation = local_state.select_generation

  git.show_commit_file(repo_path, commit.sha, filename, function(patch, err)
    if generation ~= local_state.select_generation then return end

    if err or not patch or patch == "" then
      vim.notify("Failed to get full file diff", vim.log.levels.ERROR)
      return
    end

    local hunks = diff.parse_patch(patch)
    if #hunks == 0 then return end

    local lines = {}
    local hl_lines = {}
    for _, hunk in ipairs(hunks) do
      for _, line_data in ipairs(hunk.lines) do
        table.insert(lines, line_data.content or "")
        table.insert(hl_lines, { type = line_data.type })
      end
    end

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

    local_state.maximize_win = win
    local_state.maximize_buf = buf

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

    local buf_opts = { buffer = buf, noremap = true, silent = true }
    if config.is_enabled(shortcuts.close) then
      vim.keymap.set(NORMAL_MODE, shortcuts.close, close_maximize, buf_opts)
    end
    vim.keymap.set(NORMAL_MODE, "q", close_maximize, buf_opts)
  end)
end

--- Select a commit and load its hunks into the grid
local function select_commit(index)
  if index < 1 or index > #local_state.commits then
    return
  end

  local_state.selected_index = index
  local_state.current_page = 1
  local_state.select_generation = local_state.select_generation + 1
  local generation = local_state.select_generation

  local commit = local_state.commits[index]
  local repo_path = local_state.repo_path
  if not repo_path then return end

  git.show_commit(repo_path, commit.sha, function(files, err)
    if generation ~= local_state.select_generation then return end

    if err then
      vim.notify("Failed to get commit diff", vim.log.levels.ERROR)
      return
    end

    local_state.commit_files = {}
    for _, file in ipairs(files or {}) do
      local_state.commit_files[file.filename] = true
    end

    local_state.all_hunks = {}
    local_state.cached_sha = nil
    for _, file in ipairs(files or {}) do
      local hunks = diff.parse_patch(file.patch)
      for _, hunk in ipairs(hunks) do
        table.insert(local_state.all_hunks, { hunk = hunk, filename = file.filename })
      end
    end

    if #local_state.all_hunks == 0 then
      for i, buf in ipairs(local_state.grid_bufs) do
        if vim.api.nvim_buf_is_valid(buf) then
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  No changes in this commit" })
          vim.bo[buf].modifiable = false
        end
        local win = local_state.grid_wins[i]
        if win and vim.api.nvim_win_is_valid(win) then
          vim.wo[win].winbar = "%=#" .. i
        end
      end
      update_header()
      render_filetree()
      return
    end

    render_grid_page()
  end)
end

--- Update sidebar selection highlight
local function update_sidebar_selection()
  local buf = local_state.sidebar_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local sel_ns = vim.api.nvim_create_namespace("raccoon_local_commit_sel")
  vim.api.nvim_buf_clear_namespace(buf, sel_ns, 0, -1)

  local idx = local_state.selected_index
  if idx < 1 or idx > #local_state.commits then return end

  -- Line 0 = header, commits start at line 1
  local line_idx = idx
  pcall(vim.api.nvim_buf_add_highlight, buf, sel_ns, "Visual", line_idx, 0, -1)

  if local_state.sidebar_win and vim.api.nvim_win_is_valid(local_state.sidebar_win) then
    pcall(vim.api.nvim_win_set_cursor, local_state.sidebar_win, { line_idx + 1, 0 })
  end
end

--- Render the sidebar with commit list
local function render_sidebar()
  local buf = local_state.sidebar_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = {}
  local highlights = {}

  table.insert(lines, "── Commits (" .. #local_state.commits .. ") ──")
  table.insert(highlights, { line = #lines - 1, hl = "Title" })

  for _, commit in ipairs(local_state.commits) do
    local msg = commit.message
    if #msg > SIDEBAR_WIDTH - 2 then
      msg = msg:sub(1, SIDEBAR_WIDTH - 5) .. "..."
    end
    table.insert(lines, "  " .. msg)
  end

  if local_state.loading_more then
    table.insert(lines, "")
    table.insert(lines, "  Loading...")
    table.insert(highlights, { line = #lines - 1, hl = "Comment" })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local hl_ns = vim.api.nvim_create_namespace("raccoon_local_commit_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, hl.hl, hl.line, 0, -1)
  end

  update_sidebar_selection()
end

local function move_up()
  if local_state.selected_index > 1 then
    local_state.selected_index = local_state.selected_index - 1
    update_sidebar_selection()
    select_commit(local_state.selected_index)
  end
end

local function move_down()
  if local_state.selected_index < #local_state.commits then
    local_state.selected_index = local_state.selected_index + 1
    update_sidebar_selection()
    select_commit(local_state.selected_index)

    -- Trigger loading more when within 10 commits of the end
    if #local_state.commits - local_state.selected_index < 10 then
      load_more_commits()
    end
  end
end

local function close_grid()
  for _, win in ipairs(local_state.grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  local_state.grid_wins = {}
  local_state.grid_bufs = {}
end

local function close_sidebar()
  if local_state.sidebar_win and vim.api.nvim_win_is_valid(local_state.sidebar_win) then
    pcall(vim.api.nvim_win_close, local_state.sidebar_win, true)
  end
  local_state.sidebar_win = nil
  local_state.sidebar_buf = nil
end

local function close_filetree()
  if local_state.filetree_win and vim.api.nvim_win_is_valid(local_state.filetree_win) then
    pcall(vim.api.nvim_win_close, local_state.filetree_win, true)
  end
  local_state.filetree_win = nil
  local_state.filetree_buf = nil
end

--- Build and cache the file tree for the selected commit
local function build_filetree_cache()
  local repo_path = local_state.repo_path
  if not repo_path then return end
  local commit = local_state.commits[local_state.selected_index]
  local sha = commit and commit.sha or "HEAD"

  if local_state.cached_sha == sha then return end

  local raw = vim.fn.systemlist(
    "git -C " .. vim.fn.shellescape(repo_path) .. " ls-tree -r --name-only " .. sha
  )
  if vim.v.shell_error ~= 0 then raw = {} end
  table.sort(raw)

  local tree = commits_mod._build_file_tree(raw)
  local lines = {}
  local line_paths = {}
  commits_mod._render_tree_node(tree, "", lines, line_paths)
  if #lines == 0 then
    lines = { "  No files" }
  end

  local_state.cached_sha = sha
  local_state.cached_tree_lines = lines
  local_state.cached_line_paths = line_paths
  local_state.cached_file_count = #raw
end

--- Render the file tree panel with three-tier highlighting
render_filetree = function()
  local buf = local_state.filetree_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  build_filetree_cache()

  local lines = local_state.cached_tree_lines
  local line_paths = local_state.cached_line_paths
  local commit_files = local_state.commit_files
  if not lines then return end

  local visible_files = {}
  local cells = local_state.grid_rows * local_state.grid_cols
  local start_idx = (local_state.current_page - 1) * cells + 1
  for i = start_idx, math.min(start_idx + cells - 1, #local_state.all_hunks) do
    local hunk_data = local_state.all_hunks[i]
    if hunk_data then
      visible_files[hunk_data.filename] = true
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local hl_ns = vim.api.nvim_create_namespace("raccoon_local_filetree_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  for line_idx = 0, #lines - 1 do
    local path = line_paths[line_idx]
    local hl_group
    if path and visible_files[path] then
      hl_group = "RaccoonFileVisible"
    elseif path and commit_files[path] then
      hl_group = "RaccoonFileInCommit"
    else
      hl_group = "RaccoonFileNormal"
    end
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, hl_group, line_idx, 0, -1)
  end

  local win = local_state.filetree_win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = " Files (" .. (local_state.cached_file_count or 0) .. ")"
  end
end

--- Create the grid layout (file tree + grid cells + sidebar)
local function create_grid_layout(rows, cols)
  local_state.grid_rows = rows
  local_state.grid_cols = cols

  vim.cmd("only")

  -- File tree on left
  vim.cmd("vsplit")
  vim.cmd("wincmd H")
  local_state.filetree_win = vim.api.nvim_get_current_win()
  local_state.filetree_buf = create_scratch_buf()
  vim.api.nvim_win_set_buf(local_state.filetree_win, local_state.filetree_buf)
  vim.api.nvim_win_set_width(local_state.filetree_win, SIDEBAR_WIDTH)
  vim.wo[local_state.filetree_win].wrap = false
  vim.wo[local_state.filetree_win].number = false
  vim.wo[local_state.filetree_win].relativenumber = false
  vim.wo[local_state.filetree_win].signcolumn = "no"
  lock_buf(local_state.filetree_buf)

  -- Go to main area
  vim.cmd("wincmd l")

  -- Commit sidebar on right
  vim.cmd("vsplit")
  vim.cmd("wincmd L")
  local_state.sidebar_win = vim.api.nvim_get_current_win()
  local_state.sidebar_buf = create_scratch_buf()
  vim.api.nvim_win_set_buf(local_state.sidebar_win, local_state.sidebar_buf)
  vim.api.nvim_win_set_width(local_state.sidebar_win, SIDEBAR_WIDTH)
  vim.wo[local_state.sidebar_win].cursorline = true
  vim.wo[local_state.sidebar_win].wrap = false
  vim.wo[local_state.sidebar_win].number = false
  vim.wo[local_state.sidebar_win].relativenumber = false
  vim.wo[local_state.sidebar_win].signcolumn = "no"

  -- Go to main area (between panels)
  vim.cmd("wincmd h")
  local main_win = vim.api.nvim_get_current_win()

  -- Create grid rows
  local row_wins = { main_win }
  for _ = 2, rows do
    vim.api.nvim_set_current_win(row_wins[#row_wins])
    vim.cmd("split")
    table.insert(row_wins, vim.api.nvim_get_current_win())
  end

  -- Create grid columns per row
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

  -- Reverse to reading order
  local n = #grid_wins
  for i = 1, math.floor(n / 2) do
    grid_wins[i], grid_wins[n - i + 1] = grid_wins[n - i + 1], grid_wins[i]
    grid_bufs[i], grid_bufs[n - i + 1] = grid_bufs[n - i + 1], grid_bufs[i]
  end

  local_state.grid_wins = grid_wins
  local_state.grid_bufs = grid_bufs

  for i, win in ipairs(grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winbar = "%=#" .. i
      vim.wo[win].winhl = "WinBar:Normal,WinBarNC:Normal"
    end
  end

  if vim.api.nvim_win_is_valid(local_state.sidebar_win) then
    vim.wo[local_state.sidebar_win].winhl = "WinBar:Normal,WinBarNC:Normal"
  end
  if vim.api.nvim_win_is_valid(local_state.filetree_win) then
    vim.wo[local_state.filetree_win].winhl = "WinBar:Normal,WinBarNC:Normal"
  end

  -- Header at top
  vim.api.nvim_set_current_win(grid_wins[1])
  vim.cmd("split")
  local_state.header_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd K")
  local_state.header_buf = create_scratch_buf()
  vim.api.nvim_win_set_buf(local_state.header_win, local_state.header_buf)
  vim.wo[local_state.header_win].number = false
  vim.wo[local_state.header_win].relativenumber = false
  vim.wo[local_state.header_win].signcolumn = "no"
  vim.wo[local_state.header_win].wrap = false
  vim.wo[local_state.header_win].winhl = "Normal:Normal"
  lock_buf(local_state.header_buf)

  -- Fix dimensions
  vim.cmd("wincmd =")
  if vim.api.nvim_win_is_valid(local_state.sidebar_win) then
    vim.api.nvim_win_set_width(local_state.sidebar_win, SIDEBAR_WIDTH)
  end
  if vim.api.nvim_win_is_valid(local_state.filetree_win) then
    vim.api.nvim_win_set_width(local_state.filetree_win, SIDEBAR_WIDTH)
  end
  vim.api.nvim_win_set_height(local_state.header_win, 1)
  local total_height = vim.o.lines - vim.o.cmdheight - 2
  local row_height = math.floor(total_height / rows)
  for _, win in ipairs(grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_height(win, row_height)
    end
  end

  -- Focus sidebar
  if vim.api.nvim_win_is_valid(local_state.sidebar_win) then
    vim.api.nvim_set_current_win(local_state.sidebar_win)
  end
end

local function lock_to_sidebar()
  local win = local_state.sidebar_win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.api.nvim_set_current_win(win)
  end
end

--- Setup keymaps for local commit mode
local function setup_keymaps()
  local shortcuts = config.load_shortcuts()
  local nop = function() end

  local all = {
    {
      mode = NORMAL_MODE, lhs = shortcuts.commit_mode.exit,
      rhs = function() M.toggle() end, desc = "Exit local commit viewer",
    },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_mode.next_page, rhs = next_page, desc = "Next page" },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_mode.prev_page, rhs = prev_page, desc = "Previous page" },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_mode.next_page_alt, rhs = next_page, desc = "Next page" },
  }

  local_mode_keymaps = {}
  for _, km in ipairs(all) do
    if config.is_enabled(km.lhs) then
      table.insert(local_mode_keymaps, km)
    end
  end

  -- Block window-switching keys
  local window_blocks = {
    { mode = NORMAL_MODE, lhs = "<C-w>h", rhs = nop, desc = "Blocked" },
    { mode = NORMAL_MODE, lhs = "<C-w>j", rhs = nop, desc = "Blocked" },
    { mode = NORMAL_MODE, lhs = "<C-w>k", rhs = nop, desc = "Blocked" },
    { mode = NORMAL_MODE, lhs = "<C-w>l", rhs = nop, desc = "Blocked" },
    { mode = NORMAL_MODE, lhs = "<C-w>w", rhs = nop, desc = "Blocked" },
    { mode = NORMAL_MODE, lhs = "<C-w><C-w>", rhs = nop, desc = "Blocked" },
    { mode = NORMAL_MODE, lhs = "<C-w>H", rhs = nop, desc = "Blocked" },
    { mode = NORMAL_MODE, lhs = "<C-w>J", rhs = nop, desc = "Blocked" },
    { mode = NORMAL_MODE, lhs = "<C-w>K", rhs = nop, desc = "Blocked" },
    { mode = NORMAL_MODE, lhs = "<C-w>L", rhs = nop, desc = "Blocked" },
  }
  for _, km in ipairs(window_blocks) do
    table.insert(local_mode_keymaps, km)
  end

  -- Maximize keymaps
  if config.is_enabled(shortcuts.commit_mode.maximize_prefix) then
    local cells = local_state.grid_rows * local_state.grid_cols
    for i = 1, cells do
      table.insert(local_mode_keymaps, {
        mode = NORMAL_MODE,
        lhs = shortcuts.commit_mode.maximize_prefix .. i,
        rhs = function() maximize_cell(i) end,
        desc = "Maximize grid cell " .. i,
      })
    end
  end

  -- Collect all buffers
  local commit_bufs = {}
  for _, buf in ipairs(local_state.grid_bufs or {}) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      table.insert(commit_bufs, buf)
    end
  end
  if local_state.sidebar_buf and vim.api.nvim_buf_is_valid(local_state.sidebar_buf) then
    table.insert(commit_bufs, local_state.sidebar_buf)
  end
  if local_state.header_buf and vim.api.nvim_buf_is_valid(local_state.header_buf) then
    table.insert(commit_bufs, local_state.header_buf)
  end
  if local_state.filetree_buf and vim.api.nvim_buf_is_valid(local_state.filetree_buf) then
    table.insert(commit_bufs, local_state.filetree_buf)
  end

  -- Apply keymaps buffer-locally
  for _, buf in ipairs(commit_bufs) do
    for _, km in ipairs(local_mode_keymaps) do
      vim.keymap.set(km.mode, km.lhs, km.rhs,
        { buffer = buf, noremap = true, silent = true, desc = km.desc })
    end
  end

  -- Sidebar-local keymaps
  if local_state.sidebar_buf and vim.api.nvim_buf_is_valid(local_state.sidebar_buf) then
    local buf_opts = { buffer = local_state.sidebar_buf, noremap = true, silent = true }
    vim.keymap.set(NORMAL_MODE, "j", move_down, buf_opts)
    vim.keymap.set(NORMAL_MODE, "k", move_up, buf_opts)
    vim.keymap.set(NORMAL_MODE, "<Down>", move_down, buf_opts)
    vim.keymap.set(NORMAL_MODE, "<Up>", move_up, buf_opts)
    vim.keymap.set(NORMAL_MODE, "<CR>", function() select_commit(local_state.selected_index) end, buf_opts)
    lock_buf(local_state.sidebar_buf)
  end

  -- Focus lock autocmd
  local_state.focus_augroup = vim.api.nvim_create_augroup("RaccoonLocalCommitFocus", { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = local_state.focus_augroup,
    callback = function()
      if not local_state.active then return end
      local cur_win = vim.api.nvim_get_current_win()
      if cur_win == local_state.maximize_win then return end
      if local_state.maximize_win and vim.api.nvim_win_is_valid(local_state.maximize_win) then
        vim.schedule(function()
          if local_state.maximize_win and vim.api.nvim_win_is_valid(local_state.maximize_win) then
            vim.api.nvim_set_current_win(local_state.maximize_win)
          end
        end)
        return
      end
      if cur_win ~= local_state.sidebar_win then
        vim.schedule(lock_to_sidebar)
      end
    end,
  })
end

--- Stop the poll timer
local function stop_poll_timer()
  if local_state.poll_timer then
    local_state.poll_timer:stop()
    local_state.poll_timer:close()
    local_state.poll_timer = nil
  end
end

--- Refresh commits from git (called when HEAD changes)
local function refresh_commits()
  local count = math.max(local_state.total_loaded, BATCH_SIZE)
  git.log_all_commits(local_state.repo_path, count, 0, function(new_commits, err)
    if err or not new_commits then return end

    local_state.commits = new_commits
    local_state.total_loaded = #new_commits

    if local_state.selected_index > #new_commits then
      local_state.selected_index = math.max(1, #new_commits)
    end

    render_sidebar()
    update_sidebar_selection()
    if #new_commits > 0 then
      select_commit(local_state.selected_index)
    end
  end)
end

--- Start the 10-second HEAD polling timer
local function start_poll_timer()
  stop_poll_timer()

  git.get_current_sha(local_state.repo_path, function(sha, _)
    if sha then
      local_state.last_head_sha = sha
    end
  end)

  local_state.poll_timer = vim.uv.new_timer()
  local_state.poll_timer:start(POLL_INTERVAL_MS, POLL_INTERVAL_MS, vim.schedule_wrap(function()
    if not local_state.active then return end

    git.get_current_sha(local_state.repo_path, function(sha, err)
      if err or not sha then return end
      if sha == local_state.last_head_sha then return end

      local_state.last_head_sha = sha
      refresh_commits()
    end)
  end))
end

--- Load more commits (triggered by approaching end of list)
load_more_commits = function()
  if local_state.loading_more then return end
  local_state.loading_more = true

  git.log_all_commits(local_state.repo_path, BATCH_SIZE, local_state.total_loaded, function(new_commits, err)
    local_state.loading_more = false
    if err or not new_commits or #new_commits == 0 then
      return
    end

    for _, commit in ipairs(new_commits) do
      table.insert(local_state.commits, commit)
    end
    local_state.total_loaded = local_state.total_loaded + #new_commits

    render_sidebar()
    update_sidebar_selection()
  end)
end

--- Enter local commit viewer mode
local function enter_local_mode()
  local_state.saved_buf = vim.api.nvim_get_current_buf()
  local_state.saved_laststatus = vim.o.laststatus

  -- If PR session is active, pause it
  local_state.pr_was_active = state.is_active()
  if local_state.pr_was_active then
    keymaps.clear()
    open.pause_sync()
  end

  vim.o.laststatus = 3
  local_state.active = true

  local cfg = config.load()
  local rows = 2
  local cols = 2
  if cfg and cfg.commit_viewer then
    if cfg.commit_viewer.grid then
      rows = commits_mod._clamp_int(cfg.commit_viewer.grid.rows, 2, 1, 10)
      cols = commits_mod._clamp_int(cfg.commit_viewer.grid.cols, 2, 1, 10)
    end
  end

  vim.notify("Loading commits...", vim.log.levels.INFO)

  git.find_repo_root(vim.fn.getcwd(), function(repo_root, root_err)
    if root_err or not repo_root then
      vim.notify("Not a git repository", vim.log.levels.ERROR)
      local_state.active = false
      return
    end

    local_state.repo_path = repo_root

    git.log_all_commits(repo_root, BATCH_SIZE, 0, function(initial_commits, err)
      if err or not initial_commits then
        vim.notify("Failed to load commits: " .. (err or "unknown error"), vim.log.levels.ERROR)
        local_state.active = false
        return
      end

      if #initial_commits == 0 then
        vim.notify("No commits found in repository", vim.log.levels.WARN)
        local_state.active = false
        return
      end

      local_state.commits = initial_commits
      local_state.total_loaded = #initial_commits

      vim.schedule(function()
        create_grid_layout(rows, cols)
        render_sidebar()
        setup_keymaps()
        select_commit(1)
        start_poll_timer()
        vim.notify(string.format("Local commit viewer: %d commits loaded", #initial_commits))
      end)
    end)
  end)
end

--- Exit local commit viewer mode
local function exit_local_mode()
  stop_poll_timer()

  if local_state.focus_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, local_state.focus_augroup)
  end

  close_maximize()
  local_mode_keymaps = {}
  close_grid()
  close_sidebar()
  close_filetree()

  if local_state.saved_laststatus then
    vim.o.laststatus = local_state.saved_laststatus
  end

  vim.cmd("only")
  if local_state.saved_buf and vim.api.nvim_buf_is_valid(local_state.saved_buf) then
    vim.api.nvim_set_current_buf(local_state.saved_buf)
  end

  -- Restore PR session if it was active
  if local_state.pr_was_active and state.is_active() then
    keymaps.setup()
    open.resume_sync()
  end

  reset_state()
  vim.notify("Exited local commit viewer", vim.log.levels.INFO)
end

--- Toggle local commit viewer mode
function M.toggle()
  if local_state.active then
    exit_local_mode()
  else
    enter_local_mode()
  end
end

-- Exposed for testing
M._get_state = function() return local_state end

return M
