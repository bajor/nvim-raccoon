---@class RaccoonCommitUI
---Shared UI utilities for commit viewer modes (PR and local)
local M = {}

local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local diff = require("raccoon.diff")

M.SIDEBAR_WIDTH = 40

--- Create a scratch buffer (nofile, wipe on hide)
---@return number buf
function M.create_scratch_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  return buf
end

--- Block editing keys on a buffer (allows navigation and scrolling)
---@param buf number Buffer ID
function M.lock_buf(buf)
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

--- Block editing and commit-mode navigation keys in a maximize floating window
---@param buf number Buffer ID
---@param grid_rows number Grid row count (for maximize prefix blocking)
---@param grid_cols number Grid column count
function M.lock_maximize_buf(buf, grid_rows, grid_cols)
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
    local cells = grid_rows * grid_cols
    for i = 1, cells do
      vim.keymap.set(NORMAL_MODE, shortcuts.commit_mode.maximize_prefix .. i, nop, opts)
    end
  end
end

--- Render a diff hunk into a buffer with syntax highlighting and diff signs
---@param ns_id number Namespace ID for extmarks
---@param buf number Buffer ID
---@param hunk table Parsed hunk from diff.parse_patch
---@param filename string File name (for filetype detection)
function M.render_hunk_to_buffer(ns_id, buf, hunk, filename)
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

  M.apply_diff_highlights(ns_id, buf, hunk.lines)
end

--- Apply add/del diff highlights to buffer lines
---@param ns_id number Namespace ID for extmarks
---@param buf number Buffer ID
---@param line_list table[] Array of {type, content} entries
function M.apply_diff_highlights(ns_id, buf, line_list)
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  for idx, line_data in ipairs(line_list) do
    if line_data.type == "add" then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, idx - 1, 0, {
        line_hl_group = "RaccoonAdd",
        sign_text = "+",
        sign_hl_group = "RaccoonAddSign",
      })
    elseif line_data.type == "del" then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, idx - 1, 0, {
        line_hl_group = "RaccoonDelete",
        sign_text = "-",
        sign_hl_group = "RaccoonDeleteSign",
      })
    end
  end
end

--- Clamp a config value to an integer within [min_val, max_val], or return default
---@param val any
---@param default number
---@param min_val number
---@param max_val number
---@return number
function M.clamp_int(val, default, min_val, max_val)
  if type(val) ~= "number" then return default end
  val = math.floor(val)
  if val < min_val then return min_val end
  if val > max_val then return max_val end
  return val
end

--- Build a nested tree structure from a sorted list of file paths
---@param paths string[] Sorted file paths
---@return table root Tree root with .children array
function M.build_file_tree(paths)
  local root = { children = {} }
  for _, path in ipairs(paths) do
    local parts = vim.split(path, "/", { plain = true })
    local node = root
    for i, part in ipairs(parts) do
      if i == #parts then
        table.insert(node.children, { name = part, path = path })
      else
        local found
        for _, child in ipairs(node.children) do
          if child.children and child.name == part then
            found = child
            break
          end
        end
        if not found then
          found = { name = part, children = {} }
          table.insert(node.children, found)
        end
        node = found
      end
    end
  end
  return root
end

--- Render a tree node into lines with tree-drawing characters
---@param node table Tree node with .children
---@param prefix string Indentation prefix for current depth
---@param lines string[] Output lines array (mutated)
---@param line_paths table<number, string> Output map: line index -> file path (mutated)
function M.render_tree_node(node, prefix, lines, line_paths)
  local dirs = {}
  local files = {}
  for _, child in ipairs(node.children) do
    if child.children then
      table.insert(dirs, child)
    else
      table.insert(files, child)
    end
  end
  table.sort(dirs, function(a, b) return a.name < b.name end)
  table.sort(files, function(a, b) return a.name < b.name end)

  local sorted = {}
  for _, d in ipairs(dirs) do table.insert(sorted, d) end
  for _, f in ipairs(files) do table.insert(sorted, f) end

  for i, child in ipairs(sorted) do
    local is_last = (i == #sorted)
    local connector = is_last and "└── " or "├── "
    local display = child.children and (child.name .. "/") or child.name
    table.insert(lines, prefix .. connector .. display)
    if child.path then
      line_paths[#lines - 1] = child.path
    end
    if child.children then
      local next_prefix = prefix .. (is_last and "    " or "│   ")
      M.render_tree_node(child, next_prefix, lines, line_paths)
    end
  end
end

--- Return window-blocking keymaps (blocks <C-w> combos)
---@return table[] Array of {mode, lhs, rhs, desc} keymap entries
function M.window_block_keymaps()
  local nop = function() end
  return {
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
end

--- Create the full grid layout: file tree (left), diff grid (center), commit sidebar (right), header (top).
--- Writes window/buffer handles into the provided state table.
---@param s table State table to populate (must have grid_wins, grid_bufs, etc. fields)
---@param rows number Grid rows
---@param cols number Grid columns
function M.create_grid_layout(s, rows, cols)
  s.grid_rows = rows
  s.grid_cols = cols

  vim.cmd("only")

  -- File tree on left
  vim.cmd("vsplit")
  vim.cmd("wincmd H")
  s.filetree_win = vim.api.nvim_get_current_win()
  s.filetree_buf = M.create_scratch_buf()
  vim.api.nvim_win_set_buf(s.filetree_win, s.filetree_buf)
  vim.api.nvim_win_set_width(s.filetree_win, M.SIDEBAR_WIDTH)
  vim.wo[s.filetree_win].wrap = false
  vim.wo[s.filetree_win].number = false
  vim.wo[s.filetree_win].relativenumber = false
  vim.wo[s.filetree_win].signcolumn = "no"
  M.lock_buf(s.filetree_buf)

  -- Main area
  vim.cmd("wincmd l")

  -- Sidebar on right
  vim.cmd("vsplit")
  vim.cmd("wincmd L")
  s.sidebar_win = vim.api.nvim_get_current_win()
  s.sidebar_buf = M.create_scratch_buf()
  vim.api.nvim_win_set_buf(s.sidebar_win, s.sidebar_buf)
  vim.api.nvim_win_set_width(s.sidebar_win, M.SIDEBAR_WIDTH)
  vim.wo[s.sidebar_win].cursorline = true
  vim.wo[s.sidebar_win].wrap = false
  vim.wo[s.sidebar_win].number = false
  vim.wo[s.sidebar_win].relativenumber = false
  vim.wo[s.sidebar_win].signcolumn = "no"

  -- Grid area (between file tree and sidebar)
  vim.cmd("wincmd h")
  local main_win = vim.api.nvim_get_current_win()

  local row_wins = { main_win }
  for _ = 2, rows do
    vim.api.nvim_set_current_win(row_wins[#row_wins])
    vim.cmd("split")
    table.insert(row_wins, vim.api.nvim_get_current_win())
  end

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
      local buf = M.create_scratch_buf()
      vim.api.nvim_win_set_buf(win, buf)
      vim.wo[win].wrap = true
      vim.wo[win].number = false
      vim.wo[win].relativenumber = false
      vim.wo[win].signcolumn = "yes:1"
      M.lock_buf(buf)
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

  s.grid_wins = grid_wins
  s.grid_bufs = grid_bufs

  for i, win in ipairs(grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.wo[win].winbar = "%=#" .. i
      vim.wo[win].winhl = "WinBar:Normal,WinBarNC:Normal"
    end
  end

  if vim.api.nvim_win_is_valid(s.sidebar_win) then
    vim.wo[s.sidebar_win].winhl = "WinBar:Normal,WinBarNC:Normal"
  end
  if vim.api.nvim_win_is_valid(s.filetree_win) then
    vim.wo[s.filetree_win].winhl = "WinBar:Normal,WinBarNC:Normal"
  end

  -- Header at top (full width)
  vim.api.nvim_set_current_win(grid_wins[1])
  vim.cmd("split")
  s.header_win = vim.api.nvim_get_current_win()
  vim.cmd("wincmd K")
  s.header_buf = M.create_scratch_buf()
  vim.api.nvim_win_set_buf(s.header_win, s.header_buf)
  vim.wo[s.header_win].number = false
  vim.wo[s.header_win].relativenumber = false
  vim.wo[s.header_win].signcolumn = "no"
  vim.wo[s.header_win].wrap = false
  vim.wo[s.header_win].winhl = "Normal:Normal"
  M.lock_buf(s.header_buf)

  -- Fix dimensions
  vim.cmd("wincmd =")
  if vim.api.nvim_win_is_valid(s.sidebar_win) then
    vim.api.nvim_win_set_width(s.sidebar_win, M.SIDEBAR_WIDTH)
  end
  if vim.api.nvim_win_is_valid(s.filetree_win) then
    vim.api.nvim_win_set_width(s.filetree_win, M.SIDEBAR_WIDTH)
  end
  vim.api.nvim_win_set_height(s.header_win, 1)
  local total_height = vim.o.lines - vim.o.cmdheight - 2
  local row_height = math.floor(total_height / rows)
  for _, win in ipairs(grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_height(win, row_height)
    end
  end

  -- Focus sidebar
  if vim.api.nvim_win_is_valid(s.sidebar_win) then
    vim.api.nvim_set_current_win(s.sidebar_win)
  end
end

--- Close a win/buf pair in a state table and nil out the keys
---@param s table State table
---@param win_key string Key for the window handle
---@param buf_key string|nil Key for the buffer handle (optional)
function M.close_win_pair(s, win_key, buf_key)
  if s[win_key] and vim.api.nvim_win_is_valid(s[win_key]) then
    pcall(vim.api.nvim_win_close, s[win_key], true)
  end
  s[win_key] = nil
  if buf_key then s[buf_key] = nil end
end

--- Close all grid windows
---@param s table State table with grid_wins and grid_bufs
function M.close_grid(s)
  for _, win in ipairs(s.grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  s.grid_wins = {}
  s.grid_bufs = {}
end

--- Open a maximize floating window for a full-file diff
---@param opts table {ns_id, repo_path, sha, filename, generation, get_generation, state}
function M.open_maximize(opts)
  local git = require("raccoon.git")

  git.show_commit_file(opts.repo_path, opts.sha, opts.filename, function(patch, err)
    if opts.get_generation() ~= opts.generation then return end

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

    local buf = M.create_scratch_buf()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    local ft = vim.filetype.match({ filename = opts.filename })
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

    opts.state.maximize_win = win
    opts.state.maximize_buf = buf

    M.apply_diff_highlights(opts.ns_id, buf, hl_lines)

    local shortcuts = config.load_shortcuts()
    local close_hint = config.is_enabled(shortcuts.close) and (shortcuts.close .. " or q") or "q"
    vim.wo[win].winbar = " " .. opts.filename .. "%=%#Comment# " .. close_hint .. " to exit %*"
    vim.wo[win].signcolumn = "yes:1"
    vim.wo[win].wrap = true

    M.lock_maximize_buf(buf, opts.state.grid_rows, opts.state.grid_cols)

    local buf_opts = { buffer = buf, noremap = true, silent = true }
    local function close_fn()
      M.close_win_pair(opts.state, "maximize_win", "maximize_buf")
    end
    if config.is_enabled(shortcuts.close) then
      vim.keymap.set(NORMAL_MODE, shortcuts.close, close_fn, buf_opts)
    end
    vim.keymap.set(NORMAL_MODE, "q", close_fn, buf_opts)
  end)
end

--- Build and cache a file tree for a commit.
--- Only runs git ls-tree when the commit SHA changes.
---@param s table State table (needs cached_sha, cached_tree_lines, cached_line_paths, cached_file_count)
---@param repo_path string Path to git repository
---@param sha string Commit SHA
function M.build_filetree_cache(s, repo_path, sha)
  if s.cached_sha == sha then return end

  local raw = vim.fn.systemlist(
    "git -C " .. vim.fn.shellescape(repo_path) .. " ls-tree -r --name-only " .. sha
  )
  if vim.v.shell_error ~= 0 then raw = {} end
  table.sort(raw)

  local tree = M.build_file_tree(raw)
  local lines = {}
  local line_paths = {}
  M.render_tree_node(tree, "", lines, line_paths)
  if #lines == 0 then
    lines = { "  No files" }
  end

  s.cached_sha = sha
  s.cached_tree_lines = lines
  s.cached_line_paths = line_paths
  s.cached_file_count = #raw
end

--- Render the file tree panel with three-tier highlighting
---@param s table State table
function M.render_filetree(s)
  local buf = s.filetree_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = s.cached_tree_lines
  local line_paths = s.cached_line_paths
  local commit_files = s.commit_files
  if not lines then return end

  -- Build lookup: files visible on current grid page
  local visible_files = {}
  local cells = s.grid_rows * s.grid_cols
  local start_idx = (s.current_page - 1) * cells + 1
  for i = start_idx, math.min(start_idx + cells - 1, #s.all_hunks) do
    local hunk_data = s.all_hunks[i]
    if hunk_data then
      visible_files[hunk_data.filename] = true
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local hl_ns = vim.api.nvim_create_namespace("raccoon_filetree_hl")
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

  local win = s.filetree_win
  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = " Files (" .. (s.cached_file_count or 0) .. ")"
  end
end

--- Update the header bar with commit message and page indicator
---@param s table State table
---@param commit table|nil Current commit {message}
---@param pages number Total page count
function M.update_header(s, commit, pages)
  local buf = s.header_buf
  local win = s.header_win
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  if not win or not vim.api.nvim_win_is_valid(win) then return end

  local show_pages = pages > 1
  local page_str = show_pages and (" " .. s.current_page .. "/" .. pages .. " ") or ""

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

  local hl_ns = vim.api.nvim_create_namespace("raccoon_header_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  if show_pages then
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, "Comment", 0, 0, #page_str)
  end

  vim.api.nvim_win_set_height(win, math.max(1, #lines))
end

--- Render the current page of hunks into the grid
---@param s table State table
---@param ns_id number Namespace ID for extmarks
---@param get_commit fun(): table|nil Function returning current commit
---@param pages number Total page count
function M.render_grid_page(s, ns_id, get_commit, pages)
  local cells = s.grid_rows * s.grid_cols
  local start_idx = (s.current_page - 1) * cells + 1

  for i, buf in ipairs(s.grid_bufs) do
    if not vim.api.nvim_buf_is_valid(buf) then
      goto continue
    end

    local hunk_idx = start_idx + i - 1
    local hunk_data = s.all_hunks[hunk_idx]

    local win = s.grid_wins[i]
    if hunk_data then
      M.render_hunk_to_buffer(ns_id, buf, hunk_data.hunk, hunk_data.filename)
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

  M.update_header(s, get_commit(), pages)
  M.render_filetree(s)
end

--- Collect all buffers from a state table (grid + sidebar + header + filetree)
---@param s table State table
---@return number[] bufs Valid buffer IDs
function M.collect_bufs(s)
  local bufs = {}
  for _, buf in ipairs(s.grid_bufs or {}) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      table.insert(bufs, buf)
    end
  end
  if s.sidebar_buf and vim.api.nvim_buf_is_valid(s.sidebar_buf) then
    table.insert(bufs, s.sidebar_buf)
  end
  if s.header_buf and vim.api.nvim_buf_is_valid(s.header_buf) then
    table.insert(bufs, s.header_buf)
  end
  if s.filetree_buf and vim.api.nvim_buf_is_valid(s.filetree_buf) then
    table.insert(bufs, s.filetree_buf)
  end
  return bufs
end

--- Setup the focus-lock autocmd that keeps cursor in sidebar (or maximize window)
---@param s table State table (needs active, maximize_win, sidebar_win)
---@param augroup_name string Name for the augroup
---@return number augroup_id
function M.setup_focus_lock(s, augroup_name)
  local augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })
  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    callback = function()
      if not s.active then return end
      local cur_win = vim.api.nvim_get_current_win()
      if cur_win == s.maximize_win then return end
      if s.maximize_win and vim.api.nvim_win_is_valid(s.maximize_win) then
        vim.schedule(function()
          if s.maximize_win and vim.api.nvim_win_is_valid(s.maximize_win) then
            vim.api.nvim_set_current_win(s.maximize_win)
          end
        end)
        return
      end
      if cur_win ~= s.sidebar_win then
        vim.schedule(function()
          if s.sidebar_win and vim.api.nvim_win_is_valid(s.sidebar_win) then
            vim.api.nvim_set_current_win(s.sidebar_win)
          end
        end)
      end
    end,
  })
  return augroup
end

return M
