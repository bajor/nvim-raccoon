---@class RaccoonCommitUI
---Shared UI utilities for commit viewer modes (PR and local)
local M = {}

local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local diff = require("raccoon.diff")

M.SIDEBAR_WIDTH = 50
M.STAT_BAR_MAX_WIDTH = 20

--- Compute per-file addition/deletion counts from diff patches
---@param files table[] Array of {filename, patch}
---@return table<string, {additions: number, deletions: number}>
function M.compute_file_stats(files)
  local stats = {}
  for _, file in ipairs(files or {}) do
    local additions = 0
    local deletions = 0
    local hunks = diff.parse_patch(file.patch)
    for _, hunk in ipairs(hunks) do
      for _, line_data in ipairs(hunk.lines) do
        if line_data.type == "add" then
          additions = additions + 1
        elseif line_data.type == "del" then
          deletions = deletions + 1
        end
      end
    end
    stats[file.filename] = { additions = additions, deletions = deletions }
  end
  return stats
end

--- Format a diff size bar. Bar length scales with total change count (more changes = longer bar,
--- capped at STAT_BAR_MAX_WIDTH). Within the bar, + and - are split proportionally.
---@param additions number
---@param deletions number
---@return string bar The bar string (e.g. "+++----")
---@return number add_chars Count of + characters
---@return number del_chars Count of - characters
function M.format_stat_bar(additions, deletions)
  local changes = additions + deletions
  if changes == 0 then return "", 0, 0 end
  local max_width = M.STAT_BAR_MAX_WIDTH
  local bar_len = math.min(changes, max_width)
  -- Ensure both types visible when both exist
  if additions > 0 and deletions > 0 then
    bar_len = math.max(2, bar_len)
  end
  -- Split bar into + and - proportionally
  local add_chars = math.floor(additions / changes * bar_len + 0.5)
  local del_chars = bar_len - add_chars
  -- Guarantee at least 1 char for each non-zero type
  if additions > 0 and add_chars == 0 then
    add_chars = 1
    del_chars = bar_len - 1
  elseif deletions > 0 and del_chars == 0 then
    del_chars = 1
    add_chars = bar_len - 1
  end
  return string.rep("+", add_chars) .. string.rep("-", del_chars), add_chars, del_chars
end

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
function M.lock_maximize_buf(buf, grid_rows, grid_cols, skip_keys)
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
    if config.is_enabled(key) and not (skip_keys and skip_keys[key]) then
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
---@param file_stats? table<string, {additions: number, deletions: number}> Per-file diff stats
---@param stat_lines? table<number, table> Output stat line metadata (mutated)
function M.render_tree_node(node, prefix, lines, line_paths, file_stats, stat_lines)
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
    local connector = is_last and "└ " or "├ "
    local display = child.children and (child.name .. "/") or child.name
    table.insert(lines, prefix .. connector .. display)
    if child.path then
      line_paths[#lines - 1] = child.path
      -- Insert stat bar below changed files
      if file_stats and stat_lines then
        local stat = file_stats[child.path]
        if stat and (stat.additions > 0 or stat.deletions > 0) then
          local bar_prefix = prefix .. (is_last and "   " or "│  ")
          local bar, add_chars, del_chars = M.format_stat_bar(stat.additions, stat.deletions)
          table.insert(lines, bar_prefix .. bar)
          stat_lines[#lines - 1] = { prefix_len = #bar_prefix, add_chars = add_chars, del_chars = del_chars }
        end
      end
    end
    if child.children then
      local next_prefix = prefix .. (is_last and "   " or "│  ")
      M.render_tree_node(child, next_prefix, lines, line_paths, file_stats, stat_lines)
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
---@param opts table {ns_id, repo_path, sha, filename, generation, get_generation, state, is_working_dir}
function M.open_maximize(opts)
  local git = require("raccoon.git")

  local fetch_patch = opts.is_working_dir
    and function(cb) git.diff_working_dir_file(opts.repo_path, opts.filename, cb) end
    or function(cb) git.show_commit_file(opts.repo_path, opts.sha, opts.filename, cb) end

  fetch_patch(function(patch, err)
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

    -- Find the start of each change group (consecutive add/del lines)
    local change_starts = {}
    for i, hl in ipairs(hl_lines) do
      local is_change = hl.type == "add" or hl.type == "del"
      local prev_is_change = i > 1 and (hl_lines[i - 1].type == "add" or hl_lines[i - 1].type == "del")
      if is_change and not prev_is_change then
        table.insert(change_starts, i)
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
    vim.wo[win].winhighlight = "Normal:Normal"

    local skip_keys = nil
    if #change_starts > 0 then
      skip_keys = {
        [shortcuts.commit_mode.next_page] = true,
        [shortcuts.commit_mode.prev_page] = true,
      }
    end
    M.lock_maximize_buf(buf, opts.state.grid_rows, opts.state.grid_cols, skip_keys)

    local buf_opts = { buffer = buf, noremap = true, silent = true }
    local function close_fn()
      M.close_win_pair(opts.state, "maximize_win", "maximize_buf")
    end
    if config.is_enabled(shortcuts.close) then
      vim.keymap.set(NORMAL_MODE, shortcuts.close, close_fn, buf_opts)
    end
    vim.keymap.set(NORMAL_MODE, "q", close_fn, buf_opts)

    if #change_starts > 0 and config.is_enabled(shortcuts.commit_mode.next_page) then
      vim.keymap.set(NORMAL_MODE, shortcuts.commit_mode.next_page, function()
        local cur = vim.api.nvim_win_get_cursor(0)[1]
        for _, start in ipairs(change_starts) do
          if start > cur then
            vim.api.nvim_win_set_cursor(0, { start, 0 })
            return
          end
        end
      end, buf_opts)
    end
    if #change_starts > 0 and config.is_enabled(shortcuts.commit_mode.prev_page) then
      vim.keymap.set(NORMAL_MODE, shortcuts.commit_mode.prev_page, function()
        local cur = vim.api.nvim_win_get_cursor(0)[1]
        for i = #change_starts, 1, -1 do
          if change_starts[i] < cur then
            vim.api.nvim_win_set_cursor(0, { change_starts[i], 0 })
            return
          end
        end
      end, buf_opts)
    end
  end)
end


--- Open a maximize floating window showing raw file content at a commit state
---@param opts table {repo_path, sha, filename, generation, get_generation, state}
function M.open_file_content(opts)
  local git = require("raccoon.git")

  git.show_file_content(opts.repo_path, opts.sha, opts.filename, function(lines, err)
    if opts.get_generation() ~= opts.generation then return end
    if err or not lines then
      vim.notify("Failed to get file content", vim.log.levels.ERROR)
      return
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
    if ft then vim.bo[buf].filetype = ft end

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

    local shortcuts = config.load_shortcuts()
    local close_hint = config.is_enabled(shortcuts.close) and (shortcuts.close .. " or q") or "q"
    vim.wo[win].winbar = " " .. opts.filename .. "%=%#Comment# " .. close_hint .. " to exit %*"
    vim.wo[win].wrap = true
    vim.wo[win].winhighlight = "Normal:Normal"

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

--- Build and cache a file tree for a commit (or working directory when sha is nil).
--- Async: fetches file list via git, populates cache, then re-renders filetree.
---@param s table State table (needs cached_sha, cached_tree_lines, cached_line_paths, cached_file_count)
---@param repo_path string Path to git repository
---@param sha string|nil Commit SHA, or nil for working directory
function M.build_filetree_cache(s, repo_path, sha)
  local git = require("raccoon.git")
  local cache_key = sha or "WORKDIR"
  if s.cached_sha == cache_key then return end

  s.cached_sha = cache_key

  git.list_files(repo_path, sha, function(raw, _)
    if s.cached_sha ~= cache_key then return end

    table.sort(raw)
    local tree = M.build_file_tree(raw)
    local lines = {}
    local line_paths = {}
    local stat_lines = {}
    M.render_tree_node(tree, "", lines, line_paths, s.file_stats, stat_lines)
    if #lines == 0 then
      lines = { "  No files" }
    end

    s.cached_tree_lines = lines
    s.cached_line_paths = line_paths
    s.cached_stat_lines = stat_lines
    s.cached_file_count = #raw
    M.render_filetree(s)
  end)
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

  -- Apply split highlighting for diff stat bars (green +, red -)
  local stat_lines = s.cached_stat_lines
  if stat_lines then
    for line_idx, stat in pairs(stat_lines) do
      local start = stat.prefix_len
      if stat.add_chars > 0 then
        pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, "RaccoonAddSign", line_idx, start, start + stat.add_chars)
      end
      if stat.del_chars > 0 then
        local del_start = start + stat.add_chars
        local del_end = del_start + stat.del_chars
        pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, "RaccoonDeleteSign", line_idx, del_start, del_end)
      end
    end
  end

  local win = s.filetree_win
  if win and vim.api.nvim_win_is_valid(win) then
    local shortcuts = config.load_shortcuts()
    local key = config.is_enabled(shortcuts.commit_mode.browse_files) and shortcuts.commit_mode.browse_files or nil
    vim.wo[win].winbar = key and (" Files%=%#Comment# " .. key .. " %*") or " Files"
  end
end

--- Update sidebar winbar with shortcut hint
---@param s table State table
---@param count number Total commit count
function M.update_sidebar_winbar(s, count)
  if s.sidebar_win and vim.api.nvim_win_is_valid(s.sidebar_win) then
    local shortcuts = config.load_shortcuts()
    local key = config.is_enabled(shortcuts.commit_mode.browse_files) and shortcuts.commit_mode.browse_files or nil
    local label = " Commits (" .. count .. ")"
    vim.wo[s.sidebar_win].winbar = key
        and (label .. "%=%#Comment# " .. key .. " %*")
      or label
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

--- Setup sidebar navigation keymaps (j/k/gg/G/Enter/arrows) and lock the buffer
---@param buf number Buffer ID
---@param callbacks table {move_down, move_up, move_to_top, move_to_bottom, select_at_cursor}
function M.setup_sidebar_nav(buf, callbacks)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local o = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set(NORMAL_MODE, "j", callbacks.move_down, o)
  vim.keymap.set(NORMAL_MODE, "k", callbacks.move_up, o)
  vim.keymap.set(NORMAL_MODE, "<Down>", callbacks.move_down, o)
  vim.keymap.set(NORMAL_MODE, "<Up>", callbacks.move_up, o)
  vim.keymap.set(NORMAL_MODE, "gg", callbacks.move_to_top, o)
  vim.keymap.set(NORMAL_MODE, "G", callbacks.move_to_bottom, o)
  vim.keymap.set(NORMAL_MODE, "<CR>", callbacks.select_at_cursor, o)
  M.lock_buf(buf)
end

--- Setup the focus-lock autocmd that keeps cursor in the active panel (or maximize window).
--- Respects s.focus_target: "sidebar" (default) or "filetree".
---@param s table State table (needs active, maximize_win, sidebar_win, filetree_win, focus_target)
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
      local target = (s.focus_target == "filetree" and s.filetree_win) or s.sidebar_win
      if cur_win ~= target then
        vim.schedule(function()
          if target and vim.api.nvim_win_is_valid(target) then
            vim.api.nvim_set_current_win(target)
          end
        end)
      end
    end,
  })
  return augroup
end

--- Setup filetree browsing keymaps. j/k navigate all files, Enter shows file diff.
--- The diff grid stays intact while browsing.
---@param s table State table
---@param opts table {get_repo_path, get_sha, ns_id}
function M.setup_filetree_nav(s, opts)
  if not s.filetree_buf or not vim.api.nvim_buf_is_valid(s.filetree_buf) then return end

  local function all_file_lines()
    local result = {}
    if not s.cached_line_paths then return result end
    for line_idx, _ in pairs(s.cached_line_paths) do
      table.insert(result, line_idx)
    end
    table.sort(result)
    return result
  end

  local function go_to_line(line_idx)
    if s.filetree_win and vim.api.nvim_win_is_valid(s.filetree_win) then
      pcall(vim.api.nvim_win_set_cursor, s.filetree_win, { line_idx + 1, 0 })
    end
  end

  local function ft_move_down()
    if not s.filetree_win or not vim.api.nvim_win_is_valid(s.filetree_win) then return end
    local lines = all_file_lines()
    if #lines == 0 then return end
    local cur = vim.api.nvim_win_get_cursor(s.filetree_win)[1] - 1
    for _, idx in ipairs(lines) do
      if idx > cur then go_to_line(idx); return end
    end
  end

  local function ft_move_up()
    if not s.filetree_win or not vim.api.nvim_win_is_valid(s.filetree_win) then return end
    local lines = all_file_lines()
    if #lines == 0 then return end
    local cur = vim.api.nvim_win_get_cursor(s.filetree_win)[1] - 1
    for i = #lines, 1, -1 do
      if lines[i] < cur then go_to_line(lines[i]); return end
    end
  end

  local function ft_move_top()
    local lines = all_file_lines()
    if #lines > 0 then go_to_line(lines[1]) end
  end

  local function ft_move_bottom()
    local lines = all_file_lines()
    if #lines > 0 then go_to_line(lines[#lines]) end
  end

  local function ft_select()
    if not s.filetree_win or not vim.api.nvim_win_is_valid(s.filetree_win) then return end
    local cur = vim.api.nvim_win_get_cursor(s.filetree_win)[1] - 1
    local path = s.cached_line_paths and s.cached_line_paths[cur]
    if not path then return end
    local repo_path = opts.get_repo_path()
    local sha = opts.get_sha()
    if not repo_path then return end
    local is_changed = s.commit_files and s.commit_files[path]
    if is_changed then
      M.open_maximize({
        ns_id = opts.ns_id,
        repo_path = repo_path,
        sha = sha,
        filename = path,
        generation = s.select_generation,
        get_generation = function() return s.select_generation end,
        state = s,
        is_working_dir = sha == nil,
      })
    else
      M.open_file_content({
        repo_path = repo_path,
        sha = sha,
        filename = path,
        generation = s.select_generation,
        get_generation = function() return s.select_generation end,
        state = s,
      })
    end
  end

  M.setup_sidebar_nav(s.filetree_buf, {
    move_down = ft_move_down,
    move_up = ft_move_up,
    move_to_top = ft_move_top,
    move_to_bottom = ft_move_bottom,
    select_at_cursor = ft_select,
  })
end

--- Toggle focus between sidebar and filetree panels
---@param s table State table
function M.toggle_filetree_focus(s)
  if s.focus_target == "filetree" then
    s.focus_target = "sidebar"
    if s.filetree_win and vim.api.nvim_win_is_valid(s.filetree_win) then
      vim.wo[s.filetree_win].cursorline = false
    end
    if s.sidebar_win and vim.api.nvim_win_is_valid(s.sidebar_win) then
      vim.api.nvim_set_current_win(s.sidebar_win)
    end
  else
    s.focus_target = "filetree"
    if s.filetree_win and vim.api.nvim_win_is_valid(s.filetree_win) then
      vim.wo[s.filetree_win].cursorline = true
      vim.api.nvim_set_current_win(s.filetree_win)
    end
  end
end

--- Render a two-section sidebar (section1 commits + separator + section2 commits dimmed).
--- Works for both PR viewer ("PR Branch"/"Base Branch") and local viewer ("feat-xyz"/"main").
---@param buf number Buffer ID
---@param opts table {section1_header, section1_commits, section2_header, section2_commits, commit_hl_fn?, loading?}
---@return table highlights Array of {line, hl} used for highlight application
function M.render_split_sidebar(buf, opts)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = {}
  local highlights = {}

  -- Section 1 header
  table.insert(lines, opts.section1_header)
  table.insert(highlights, { line = #lines - 1, hl = "Title" })

  -- Section 1 commits
  for _, commit in ipairs(opts.section1_commits) do
    local msg = commit.message
    if #msg > M.SIDEBAR_WIDTH - 2 then
      msg = msg:sub(1, M.SIDEBAR_WIDTH - 5) .. "..."
    end
    table.insert(lines, "  " .. msg)
    if opts.commit_hl_fn then
      local hl = opts.commit_hl_fn(commit)
      if hl then
        table.insert(highlights, { line = #lines - 1, hl = hl })
      end
    end
  end

  -- Separator + section 2 header
  table.insert(lines, "")
  table.insert(lines, opts.section2_header)
  table.insert(highlights, { line = #lines - 1, hl = "Title" })

  -- Section 2 commits (dimmed)
  for _, commit in ipairs(opts.section2_commits) do
    local msg = commit.message
    if #msg > M.SIDEBAR_WIDTH - 2 then
      msg = msg:sub(1, M.SIDEBAR_WIDTH - 5) .. "..."
    end
    table.insert(lines, "  " .. msg)
    table.insert(highlights, { line = #lines - 1, hl = "Comment" })
  end

  if opts.loading then
    table.insert(lines, "")
    table.insert(lines, "  Loading...")
    table.insert(highlights, { line = #lines - 1, hl = "Comment" })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local hl_ns = vim.api.nvim_create_namespace("raccoon_split_sidebar_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, hl.hl, hl.line, 0, -1)
  end
end

--- Update selection highlight in a two-section sidebar.
--- Accounts for the blank separator + section2 header (+2 offset) when in section2.
---@param buf number Buffer ID
---@param win number Window ID
---@param index number 1-based combined index
---@param section1_count number Number of commits in section 1
function M.update_split_selection(buf, win, index, section1_count)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local sel_ns = vim.api.nvim_create_namespace("raccoon_split_sidebar_sel")
  vim.api.nvim_buf_clear_namespace(buf, sel_ns, 0, -1)

  -- Line layout: header(0), s1 commits(1..N), blank(N+1), s2 header(N+2), s2 commits(N+3..)
  local line_idx = index
  if index > section1_count then
    line_idx = index + 2 -- skip blank separator + section2 header
  end
  pcall(vim.api.nvim_buf_add_highlight, buf, sel_ns, "Visual", line_idx, 0, -1)

  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_set_cursor, win, { line_idx + 1, 0 })
  end
end

--- Map a cursor line in a two-section sidebar back to a combined commit index.
---@param cursor_line number 1-based cursor line from nvim_win_get_cursor
---@param section1_count number Number of commits in section 1
---@return number|nil index 1-based combined index, or nil if on a non-commit line
function M.split_sidebar_cursor_to_index(cursor_line, section1_count)
  local line_0 = cursor_line - 1 -- 0-based
  if line_0 == 0 then return nil end -- header

  local section1_end = section1_count -- last s1 commit at line section1_count
  if line_0 <= section1_end then
    return line_0 -- directly maps to s1 index
  end

  -- blank at section1_count+1, s2 header at section1_count+2
  if line_0 <= section1_end + 2 then return nil end -- on separator or header

  return line_0 - 2 -- subtract blank + header to get combined index
end

return M
