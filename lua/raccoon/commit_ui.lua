---@class RaccoonCommitUI
---Shared UI utilities for commit viewer modes (PR and local)
local M = {}

local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local diff = require("raccoon.diff")
local state = require("raccoon.state")

M.SIDEBAR_WIDTH = 50
M.STAT_BAR_MAX_WIDTH = 20

local GRID_CHROME_LINES = 2 -- global statusline (laststatus=3) + header window (1-line split)
local MIN_DIFF_CONTEXT = 3 -- git's default context line count

--- Safely stop and close a libuv timer handle (idempotent).
--- Logs failures at DEBUG level to avoid silently swallowing errors.
---@param handle userdata|nil Timer handle from vim.uv.new_timer()
function M.safe_close_timer(handle)
  if not handle then return end
  local ok1, err1 = pcall(handle.stop, handle)
  if not ok1 then
    vim.notify("Timer stop failed: " .. tostring(err1), vim.log.levels.DEBUG)
  end
  local ok2, err2 = pcall(handle.close, handle)
  if not ok2 then
    vim.notify("Timer close failed: " .. tostring(err2), vim.log.levels.DEBUG)
  end
end

--- Create the base state table shared by both commit viewer modules.
--- Callers extend the returned table with module-specific fields.
---@return table Base state with shared UI fields
function M.make_base_state()
  return {
    active = false,
    sidebar_win = nil,
    sidebar_buf = nil,
    selected_index = 1,
    grid_wins = {},
    grid_bufs = {},
    all_hunks = {},
    commit_files = {},
    file_stats = {},
    current_page = 1,
    saved_buf = nil,
    saved_laststatus = nil,
    grid_rows = 2,
    grid_cols = 2,
    maximize_win = nil,
    maximize_buf = nil,
    maximize_debounce_timer = nil,
    focus_augroup = nil,
    focus_redirect_timer = nil,
    header_win = nil,
    header_buf = nil,
    filetree_win = nil,
    filetree_buf = nil,
    select_generation = 0,
    cached_sha = nil,
    cached_tree_lines = nil,
    cached_line_paths = nil,
    cached_stat_lines = nil,
    cached_file_count = nil,
    focus_target = "sidebar",
  }
end

--- Parse and clamp commit viewer config values from user config.
---@return table {rows: number, cols: number, base_count: number, sidebar_width: number, sync_interval: number}
function M.parse_viewer_config()
  local cfg, cfg_err = config.load()
  if cfg_err then
    vim.notify("Commit viewer: using defaults (config error: " .. cfg_err .. ")", vim.log.levels.DEBUG)
  end
  local rows = 2
  local cols = 2
  local base_count = 20
  local sidebar_width = 50
  local sync_interval = 60
  if cfg and cfg.commit_viewer then
    if cfg.commit_viewer.grid then
      rows = M.clamp_int(cfg.commit_viewer.grid.rows, 2, 1, 10)
      cols = M.clamp_int(cfg.commit_viewer.grid.cols, 2, 1, 10)
    end
    base_count = M.clamp_int(cfg.commit_viewer.base_commits_count, 20, 1, 200)
    sidebar_width = M.clamp_int(cfg.commit_viewer.sidebar_width, 50, 20, 120)
    sync_interval = M.clamp_int(cfg.commit_viewer.sync_interval, 60, 10, 3600)
  end
  return {
    rows = rows,
    cols = cols,
    base_count = base_count,
    sidebar_width = sidebar_width,
    sync_interval = sync_interval,
  }
end

--- Approximate usable editor height for grid layout.
--- Subtracts cmdheight and global chrome (statusline + header window); intentionally omits
--- header content height and inter-row separators since this feeds a heuristic, not exact layout.
---@return number
function M.grid_total_height()
  return math.max(1, vim.o.lines - vim.o.cmdheight - GRID_CHROME_LINES)
end

--- Compute the diff context line count for grid cells based on available row height.
--- Uses floor(row_height / 2) as a heuristic: with N context lines a single hunk produces
--- roughly 2N+1 output lines plus the hunk header, so halving is a reasonable approximation.
---@param rows number Number of grid rows
---@return number context Lines of context to pass to git diff (-U<N>, always >= 3)
function M.compute_grid_context(rows)
  rows = rows or 1
  local row_height = math.floor(M.grid_total_height() / math.max(1, rows))
  return math.max(MIN_DIFF_CONTEXT, math.floor(row_height / 2))
end

--- Preserve selected commit across a refresh by searching for a matching SHA.
--- Falls back to clamping the index when the SHA is not found (e.g., after force-push).
---@param s table State table (must have selected_index field)
---@param selected_sha string|nil SHA to search for
---@param total_fn fun(): number Returns total navigable commits
---@param get_fn fun(i: number): table|nil Returns commit at index i
function M.restore_selection_by_sha(s, selected_sha, total_fn, get_fn)
  if selected_sha then
    for i = 1, total_fn() do
      local c = get_fn(i)
      if c and c.sha == selected_sha then
        s.selected_index = i
        return
      end
    end
  end
  if s.selected_index > total_fn() then
    s.selected_index = math.max(1, total_fn())
  end
end

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

--- Set up the parallel agent dispatch keymap on a maximize buffer.
---@param buf number Buffer to bind the keymap on
---@param opts table {repo_path, sha, commit_message, filename, state}
---@param pa_cfg? table Pre-loaded parallel_agents config (avoids re-reading disk)
local function setup_parallel_agent_keymap(buf, opts, pa_cfg)
  pa_cfg = pa_cfg or config.load_parallel_agents()
  if not pa_cfg.enabled or not config.is_enabled(pa_cfg.shortcut) then return end
  local pa = require("raccoon.parallel_agents")
  local buf_opts = { buffer = buf, noremap = true, silent = true }
  local function dispatch_fn()
    local visual_lines, line_start, line_end
    local mode = vim.fn.mode()
    if mode == "v" or mode == "V" or mode == "\22" then
      vim.api.nvim_feedkeys(
        vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false
      )
      line_start = vim.fn.line("'<")
      line_end = vim.fn.line("'>")
      visual_lines = vim.api.nvim_buf_get_lines(buf, line_start - 1, line_end, false)
    end
    pa.dispatch({
      repo_path = opts.repo_path,
      commit_sha = opts.sha,
      commit_message = opts.commit_message or "",
      filename = opts.filename,
      visual_lines = visual_lines,
      line_start = line_start,
      line_end = line_end,
      view_state = opts.state,
    })
  end
  vim.keymap.set({ "n", "v" }, pa_cfg.shortcut, dispatch_fn, buf_opts)
end

--- Block editing and commit-mode navigation keys in a maximize floating window
---@param buf number Buffer ID
---@param grid_rows number Grid row count (for maximize prefix blocking)
---@param grid_cols number Grid column count
---@param skip_keys? table<string, boolean> Keys to exclude from blocking
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
    if not (skip_keys and skip_keys[key]) then
      vim.keymap.set(NORMAL_MODE, key, nop, opts)
    end
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
  local row_height = math.floor(M.grid_total_height() / math.max(1, rows))
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
  if win_key == "maximize_win" then
    M.stop_maximize_watcher(s)
    s.maximize_workdir_opts = nil
  end
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
---@param opts table {ns_id, repo_path, sha, filename, commit_message, generation, get_generation, state, is_working_dir?, is_combined_diff?, base_ref (required if is_combined_diff)}
function M.open_maximize(opts)
  local git = require("raccoon.git")

  local fetch_patch
  if opts.is_working_dir then
    fetch_patch = function(cb) git.diff_working_dir_file(opts.repo_path, opts.filename, cb) end
  elseif opts.is_combined_diff then
    fetch_patch = function(cb) git.diff_combined_file(opts.repo_path, opts.base_ref, opts.filename, cb) end
  else
    fetch_patch = function(cb) git.show_commit_file(opts.repo_path, opts.sha, opts.filename, cb) end
  end

  fetch_patch(function(patch, err)
    if opts.get_generation() ~= opts.generation then return end

    if err then
      vim.notify("Failed to get full file diff: " .. err, vim.log.levels.ERROR)
      return
    end
    if not patch or patch == "" then
      vim.notify("No diff content for " .. opts.filename, vim.log.levels.INFO)
      return
    end

    local hunks = diff.parse_patch(patch)
    if #hunks == 0 then
      vim.notify("No diff hunks to display for " .. opts.filename, vim.log.levels.INFO)
      return
    end

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
      zindex = 50,
    })

    opts.state.maximize_win = win
    opts.state.maximize_buf = buf
    M.stop_maximize_watcher(opts.state)
    if opts.is_working_dir then
      opts.state.maximize_workdir_opts = {
        ns_id = opts.ns_id,
        repo_path = opts.repo_path,
        filename = opts.filename,
      }
      M.start_maximize_watcher(opts.state)
    else
      opts.state.maximize_workdir_opts = nil
    end

    M.apply_diff_highlights(opts.ns_id, buf, hl_lines)

    local shortcuts = config.load_shortcuts()
    local close_hint = config.is_enabled(shortcuts.close) and (shortcuts.close .. " or q") or "q"
    vim.wo[win].winbar = " " .. opts.filename .. "%=%#Comment# " .. close_hint .. " to exit %*"
    vim.wo[win].signcolumn = "yes:1"
    vim.wo[win].wrap = true

    local pa_cfg = config.load_parallel_agents()
    local skip_keys
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

    setup_parallel_agent_keymap(buf, opts, pa_cfg)
  end)
end

--- Stop the file watcher (and its debounce timer) for the maximize window
---@param s table State table
function M.stop_maximize_watcher(s)
  M.safe_close_timer(s.maximize_debounce_timer)
  s.maximize_debounce_timer = nil
  if s.maximize_fs_event then
    local handle = s.maximize_fs_event
    s.maximize_fs_event = nil
    local ok1, err1 = pcall(handle.stop, handle)
    if not ok1 then
      vim.notify("fs_event stop failed: " .. tostring(err1), vim.log.levels.DEBUG)
    end
    local ok2, err2 = pcall(function()
      if not handle:is_closing() then
        handle:close()
      end
    end)
    if not ok2 then
      vim.notify("fs_event close failed: " .. tostring(err2), vim.log.levels.DEBUG)
    end
  end
end

local FS_EVENT_DEBOUNCE_MS = 150

--- Start a file watcher that refreshes the maximize window on file changes.
--- Debounced: rapid fs_event fires (common on macOS FSEvents) collapse into
--- a single refresh after FS_EVENT_DEBOUNCE_MS of quiet.
---@param s table State table (must have maximize_workdir_opts set)
function M.start_maximize_watcher(s)
  local mopts = s.maximize_workdir_opts
  if not mopts then return end

  local filepath = vim.fs.joinpath(mopts.repo_path, mopts.filename)
  local handle = vim.uv.new_fs_event()
  if not handle then
    vim.notify("Failed to create file watcher for " .. mopts.filename, vim.log.levels.DEBUG)
    return
  end

  s.maximize_fs_event = handle
  s.maximize_debounce_timer = nil

  local start_ok, start_err = pcall(handle.start, handle, filepath, {}, vim.schedule_wrap(function(err)
    if err then
      vim.notify("File watcher error: " .. tostring(err), vim.log.levels.DEBUG)
      return
    end
    if not s.maximize_workdir_opts then return end

    -- Cancel any pending debounce and restart the delay
    if s.maximize_debounce_timer then
      s.maximize_debounce_timer:stop()
    else
      s.maximize_debounce_timer = vim.uv.new_timer()
      if not s.maximize_debounce_timer then
        M.refresh_maximize(s) -- fallback: refresh immediately
        return
      end
    end
    s.maximize_debounce_timer:start(FS_EVENT_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
      if not s.maximize_workdir_opts then return end
      M.refresh_maximize(s)
    end))
  end))
  if not start_ok then
    vim.notify("File watcher start failed: " .. tostring(start_err), vim.log.levels.DEBUG)
    pcall(handle.close, handle)
    s.maximize_fs_event = nil
    return
  end
end

--- Refresh the maximize window in-place for working directory changes
--- Only works when maximize_workdir_opts is set (i.e. viewing "Current changes")
---@param s table State table
function M.refresh_maximize(s)
  local mopts = s.maximize_workdir_opts
  if not mopts then return end
  if not s.maximize_buf or not vim.api.nvim_buf_is_valid(s.maximize_buf) then return end
  if not s.maximize_win or not vim.api.nvim_win_is_valid(s.maximize_win) then return end

  local git = require("raccoon.git")
  local buf = s.maximize_buf
  local win = s.maximize_win

  git.diff_working_dir_file(mopts.repo_path, mopts.filename, function(patch, err)
    if not s.maximize_workdir_opts then return end
    if not vim.api.nvim_buf_is_valid(buf) then return end

    if err then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  Error refreshing diff: " .. tostring(err) })
      vim.bo[buf].modifiable = false
      return
    end
    if not patch or patch == "" then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  No diff content (file may be unchanged)" })
      vim.bo[buf].modifiable = false
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

    local cursor = vim.api.nvim_win_get_cursor(win)

    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    M.apply_diff_highlights(mopts.ns_id, buf, hl_lines)

    -- Restore cursor, clamped to new line count
    local max_line = vim.api.nvim_buf_line_count(buf)
    if cursor[1] > max_line then cursor[1] = max_line end
    pcall(vim.api.nvim_win_set_cursor, win, cursor)
  end)
end


--- Open a maximize floating window showing raw file content at a commit state
---@param opts table {repo_path, sha, filename, generation, get_generation, state}
function M.open_file_content(opts)
  local git = require("raccoon.git")

  git.show_file_content(opts.repo_path, opts.sha, opts.filename, function(lines, err)
    if opts.get_generation() ~= opts.generation then return end
    if err or not lines then
      vim.notify("Failed to get file content: " .. (err or opts.filename), vim.log.levels.ERROR)
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
      zindex = 50,
    })

    opts.state.maximize_win = win
    opts.state.maximize_buf = buf

    local shortcuts = config.load_shortcuts()
    local close_hint = config.is_enabled(shortcuts.close) and (shortcuts.close .. " or q") or "q"
    vim.wo[win].winbar = " " .. opts.filename .. "%=%#Comment# " .. close_hint .. " to exit %*"
    vim.wo[win].wrap = true

    local pa_cfg = config.load_parallel_agents()
    M.lock_maximize_buf(buf, opts.state.grid_rows, opts.state.grid_cols)

    local buf_opts = { buffer = buf, noremap = true, silent = true }
    local function close_fn()
      M.close_win_pair(opts.state, "maximize_win", "maximize_buf")
    end
    if config.is_enabled(shortcuts.close) then
      vim.keymap.set(NORMAL_MODE, shortcuts.close, close_fn, buf_opts)
    end
    vim.keymap.set(NORMAL_MODE, "q", close_fn, buf_opts)

    setup_parallel_agent_keymap(buf, opts, pa_cfg)
  end)
end

--- Build and cache a file tree for a commit (or working directory when sha is nil).
--- Async: fetches file list via git, populates cache, then re-renders filetree.
---@param s table State table (needs cached_sha, cached_tree_lines, cached_line_paths, cached_file_count)
---@param repo_path string Path to git repository
---@param sha string|nil Commit SHA, or nil for working directory
function M.build_filetree_cache(s, repo_path, sha)
  local git = require("raccoon.git")
  -- Combined diff sentinel is not a real git ref; use HEAD for file listing
  if sha == git.COMBINED_DIFF_SHA then sha = "HEAD" end
  local cache_key = sha or "WORKDIR"
  if s.cached_sha == cache_key then return end

  s.cached_sha = cache_key

  git.list_files(repo_path, sha, function(raw, list_err)
    if list_err then
      vim.notify("Failed to list files for tree: " .. tostring(list_err), vim.log.levels.DEBUG)
    end
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

local FOCUS_LOCK_DEBOUNCE_MS = 50

--- Setup the focus-lock autocmd that keeps cursor in the active panel (or maximize window).
--- Debounced to prevent rapid focus-fight with external plugins.
--- Respects s.focus_target: "sidebar" (default) or "filetree".
---@param s table State table (needs active, maximize_win, sidebar_win, filetree_win, focus_target)
---@param augroup_name string Name for the augroup
---@return number augroup_id
function M.setup_focus_lock(s, augroup_name)
  local augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })
  s.focus_redirect_timer = nil

  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    callback = function()
      if not s.active then return end
      local cur_win = vim.api.nvim_get_current_win()
      if cur_win == s.maximize_win then return end
      -- Allow focus on per-state or global popups (e.g. PR picker)
      if s.popup_win and cur_win == s.popup_win then return end
      if state.global_popup_win then
        if not vim.api.nvim_win_is_valid(state.global_popup_win) then
          state.global_popup_win = nil
        elseif cur_win == state.global_popup_win then
          return
        end
      end

      -- Determine where focus should go
      local target
      if s.maximize_win and vim.api.nvim_win_is_valid(s.maximize_win) then
        target = s.maximize_win
      else
        target = (s.focus_target == "filetree" and s.filetree_win) or s.sidebar_win
      end

      if not target or cur_win == target then return end

      -- Debounce: cancel any pending redirect, wait FOCUS_LOCK_DEBOUNCE_MS before acting.
      -- This prevents a rapid focus-fight with external plugins that also redirect on WinEnter.
      if s.focus_redirect_timer then
        s.focus_redirect_timer:stop()
      else
        s.focus_redirect_timer = vim.uv.new_timer()
        if not s.focus_redirect_timer then
          -- Fallback: redirect immediately (old behaviour)
          vim.schedule(function()
            if target and vim.api.nvim_win_is_valid(target) then
              vim.api.nvim_set_current_win(target)
            end
          end)
          return
        end
      end
      s.focus_redirect_timer:start(FOCUS_LOCK_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
        if not s.active then return end
        local has_popup = s.popup_win
          or (state.global_popup_win and vim.api.nvim_win_is_valid(state.global_popup_win))
        if has_popup then return end
        -- Re-check: focus may already be correct by the time the debounce fires
        if vim.api.nvim_get_current_win() == target then return end
        if target and vim.api.nvim_win_is_valid(target) then
          vim.api.nvim_set_current_win(target)
        end
      end))
    end,
  })
  return augroup
end

--- Setup filetree browsing keymaps. j/k navigate all files, Enter shows file diff.
--- The diff grid stays intact while browsing.
---@param s table State table
---@param opts table {ns_id, get_repo_path, get_sha, get_commit_message, get_base_ref}
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
    local commit_msg = opts.get_commit_message and opts.get_commit_message() or ""
    local git = require("raccoon.git")
    local is_combined = sha == git.COMBINED_DIFF_SHA
    local base_ref = opts.get_base_ref and opts.get_base_ref()
    if is_changed then
      M.open_maximize({
        ns_id = opts.ns_id,
        repo_path = repo_path,
        sha = sha,
        filename = path,
        commit_message = commit_msg,
        generation = s.select_generation,
        get_generation = function() return s.select_generation end,
        state = s,
        is_working_dir = sha == nil,
        is_combined_diff = is_combined,
        base_ref = base_ref,
      })
    else
      M.open_file_content({
        repo_path = repo_path,
        sha = is_combined and "HEAD" or sha,
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

--- Process a diff result and populate state (shared by both commit viewer modules).
--- Handles file tracking, stat computation, hunk list building, empty-diff fallback, and render.
---@param s table State table
---@param opts table {files, err, generation, get_generation, build_cache_fn, get_commit_fn, total_pages_fn, ns_id, render_grid_fn}
function M.apply_diff_result(s, opts)
  if opts.get_generation() ~= opts.generation then return end

  if opts.err then
    vim.notify("Failed to get commit diff: " .. opts.err, vim.log.levels.ERROR)
    return
  end

  s.commit_files = {}
  s.file_stats = {}
  s.all_hunks = {}
  s.cached_sha = nil
  s.cached_stat_lines = nil
  for _, file in ipairs(opts.files or {}) do
    s.commit_files[file.filename] = true
    local additions = 0
    local deletions = 0
    local hunks = diff.parse_patch(file.patch)
    for _, hunk in ipairs(hunks) do
      table.insert(s.all_hunks, { hunk = hunk, filename = file.filename })
      for _, line_data in ipairs(hunk.lines) do
        if line_data.type == "add" then
          additions = additions + 1
        elseif line_data.type == "del" then
          deletions = deletions + 1
        end
      end
    end
    s.file_stats[file.filename] = { additions = additions, deletions = deletions }
  end
  opts.build_cache_fn()

  if #s.all_hunks == 0 then
    for i, buf in ipairs(s.grid_bufs) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", "  No changes in this commit" })
        vim.bo[buf].modifiable = false
      end
      local win = s.grid_wins[i]
      if win and vim.api.nvim_win_is_valid(win) then
        vim.wo[win].winbar = "%=#" .. i
      end
    end
    M.update_header(s, opts.get_commit_fn(), opts.total_pages_fn())
    M.render_filetree(s)
    return
  end

  opts.render_grid_fn()
end

--- Shared exit teardown for commit viewer modes.
--- Closes timers, deletes augroup, closes maximize/grid/filetree windows, then runs :only to close remaining splits.
--- Calls on_before_only after closing viewer panels but before :only, and on_after after restoring editor state.
---@param s table State table
---@param opts table {on_before_only: fun()|nil, on_after: fun()|nil}
function M.teardown_viewer(s, opts)
  M.safe_close_timer(s.focus_redirect_timer)
  s.focus_redirect_timer = nil
  if s.focus_augroup then
    local ok, del_err = pcall(vim.api.nvim_del_augroup_by_id, s.focus_augroup)
    if not ok then
      vim.notify("Failed to delete focus augroup: " .. tostring(del_err), vim.log.levels.DEBUG)
    end
  end

  M.close_win_pair(s, "maximize_win", "maximize_buf")
  if s.grid_wins then M.close_grid(s) end
  M.close_win_pair(s, "filetree_win", "filetree_buf")

  if opts.on_before_only then opts.on_before_only() end

  -- Switch to sidebar before :only so the main content window survives
  -- (not the narrow filetree if it happened to have focus)
  if s.sidebar_win and vim.api.nvim_win_is_valid(s.sidebar_win) then
    vim.api.nvim_set_current_win(s.sidebar_win)
  end
  local ok_only, only_err = pcall(vim.cmd, "only")
  if not ok_only then
    vim.notify("Warning: could not close viewer windows: " .. tostring(only_err), vim.log.levels.WARN)
  end

  if s.saved_buf and vim.api.nvim_buf_is_valid(s.saved_buf) then
    vim.api.nvim_set_current_buf(s.saved_buf)
  end

  if s.saved_laststatus then
    vim.o.laststatus = s.saved_laststatus
  end

  if opts.on_after then opts.on_after() end
end

return M
