---@class RaccoonCommitUI
---Shared UI utilities for commit viewer modes (PR and local)
local M = {}

local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local diff = require("raccoon.diff")

M.SIDEBAR_WIDTH = 50
M.STAT_BAR_MAX_WIDTH = 20
M.COMMIT_MESSAGE_MAX_LINES = 2 -- max visual lines for the header commit message (controls truncation and window height)
M.PASSTHROUGH_KEYS = {} -- keys that bypass lock_buf blocking (loaded from config)
M.MIN_SIDEBAR_WIDTH = 10
M.MAX_SIDEBAR_WIDTH = 120

local GRID_CHROME_LINES = 2 -- global statusline (laststatus=3) + header separator (tabline not accounted for)
local MIN_DIFF_CONTEXT = 3 -- git's default context line count
local MIN_GRID_COL_WIDTH = 1

--- Set header window height, clamped to COMMIT_MESSAGE_MAX_LINES and 1/3 of terminal height.
--- Falls back to height 1 on non-trivial errors.
---@param win number Window handle
local function set_header_height(win)
  if not win or not vim.api.nvim_win_is_valid(win) then return end
  local max_lines = math.max(1, M.COMMIT_MESSAGE_MAX_LINES)
  local max_safe = math.max(1, math.floor(vim.o.lines / 3))
  local ok, err = pcall(vim.api.nvim_win_set_height, win, math.min(max_lines, max_safe))
  if not ok then
    if err and not tostring(err):match("Invalid window") then
      vim.notify("Header height error: " .. tostring(err), vim.log.levels.DEBUG)
    end
    pcall(vim.api.nvim_win_set_height, win, 1)
  end
end

--- Truncate a string to fit within a given number of display columns.
--- Walks codepoints accumulating strdisplaywidth so wide characters (CJK, emoji) are measured correctly.
---@param text string
---@param max_width number Maximum display columns
---@return string
function M.truncate_to_display_width(text, max_width)
  local width = 0
  local chars = 0
  local len = vim.fn.strchars(text)
  while chars < len do
    local ch = vim.fn.strcharpart(text, chars, 1)
    local ch_width = vim.fn.strdisplaywidth(ch)
    if width + ch_width > max_width then break end
    width = width + ch_width
    chars = chars + 1
  end
  return vim.fn.strcharpart(text, 0, chars)
end

--- Split the available grid width across columns, distributing remainder columns deterministically.
---@param total_width number
---@param cols number
---@return number[]
local function compute_grid_column_widths(total_width, cols)
  cols = math.max(1, cols or 1)
  total_width = math.max(cols * MIN_GRID_COL_WIDTH, total_width or cols * MIN_GRID_COL_WIDTH)

  local base_width = math.floor(total_width / cols)
  local remainder = total_width - (base_width * cols)
  local widths = {}
  for col = 1, cols do
    widths[col] = math.max(MIN_GRID_COL_WIDTH, base_width + (col <= remainder and 1 or 0))
  end
  return widths
end

--- Truncate sidebar text to fit inside the rendered sidebar width.
---@param text string|nil
---@param sidebar_width? number
---@return string
function M.truncate_sidebar_text(text, sidebar_width)
  text = text or ""
  sidebar_width = math.max(1, sidebar_width or M.SIDEBAR_WIDTH)

  local content_width = math.max(1, sidebar_width - 2)
  local ellipsis = "..."
  local ellipsis_width = vim.fn.strdisplaywidth(ellipsis)
  if vim.fn.strdisplaywidth(text) <= content_width then
    return text
  end

  local keep_width = math.max(1, content_width - ellipsis_width)
  return M.truncate_to_display_width(text, keep_width) .. ellipsis
end

--- Approximate usable editor height for grid layout.
--- Subtracts cmdheight and global chrome (statusline + header separator); intentionally omits
--- header content height (up to COMMIT_MESSAGE_MAX_LINES) and inter-row separators since this
--- feeds a heuristic, not exact layout.
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

--- Load commit viewer config values into module globals and return grid/count settings.
--- Single source of truth for config parsing shared by PR and local commit modes.
---@return number rows, number cols, number base_count
function M.load_viewer_config()
  local cfg = config.load()
  local rows = 2
  local cols = 2
  local base_count = 20
  if cfg and cfg.commit_viewer then
    if cfg.commit_viewer.grid then
      rows = M.clamp_int(cfg.commit_viewer.grid.rows, 2, 1, 10)
      cols = M.clamp_int(cfg.commit_viewer.grid.cols, 2, 1, 10)
    end
    base_count = M.clamp_int(cfg.commit_viewer.base_commits_count, 20, 1, 200)
    M.SIDEBAR_WIDTH = M.clamp_int(
      cfg.commit_viewer.sidebar_width,
      50,
      M.MIN_SIDEBAR_WIDTH,
      M.MAX_SIDEBAR_WIDTH
    )
    M.COMMIT_MESSAGE_MAX_LINES = M.clamp_int(cfg.commit_viewer.commit_message_max_lines, 2, 1, 20)
    if type(cfg.commit_viewer.passthrough_keys) == "table" then
      M.PASSTHROUGH_KEYS = cfg.commit_viewer.passthrough_keys
    end
  end
  return rows, cols, base_count
end

--- Clamp sidebar width so both side panels fit symmetrically in the current editor width.
--- Leaves at least one column for each grid column plus the vertical separators.
---@param cols number Number of grid columns
---@param requested_width? number Preferred sidebar width
---@return number
function M.compute_effective_sidebar_width(cols, requested_width)
  cols = math.max(1, cols or 1)
  requested_width = requested_width or M.SIDEBAR_WIDTH

  local separators = cols + 1
  local remaining = vim.o.columns - cols * MIN_GRID_COL_WIDTH - separators
  local max_width = math.floor(remaining / 2)
  return math.max(1, math.min(requested_width, max_width))
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

--- Shadow global keymaps buffer-locally so commit mode can own the input surface.
--- Skips <Plug> mappings, raccoon global mappings, and configured passthrough keys.
---@param buf number Buffer ID
---@param mode string Vim mode passed to nvim_get_keymap / keymap.set
---@param passthrough_keys? string[] Keys to skip shadowing
local function shadow_global_keymaps(buf, mode, passthrough_keys)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local shortcuts = config.load_shortcuts()
  local function normalize_lhs(lhs)
    if type(lhs) ~= "string" or lhs == "" then return nil end
    return vim.fn.keytrans(vim.api.nvim_replace_termcodes(lhs, true, true, true))
  end

  local pr_list_lhs = normalize_lhs(shortcuts.pr_list)
  local show_shortcuts_lhs = normalize_lhs(shortcuts.show_shortcuts)
  local passthrough = {}
  local viewer_cfg = config.load_commit_viewer()
  local merged_passthrough = {}
  for _, lhs in ipairs(viewer_cfg.passthrough_keys or {}) do
    table.insert(merged_passthrough, lhs)
  end
  for _, lhs in ipairs(M.PASSTHROUGH_KEYS or {}) do
    table.insert(merged_passthrough, lhs)
  end
  for _, lhs in ipairs(passthrough_keys or {}) do
    table.insert(merged_passthrough, lhs)
  end
  for _, lhs in ipairs(merged_passthrough) do
    local normalized_lhs = normalize_lhs(lhs)
    if normalized_lhs then
      passthrough[normalized_lhs] = true
    end
  end

  local function is_raccoon_global_map(map, normalized_lhs)
    if normalized_lhs == pr_list_lhs or normalized_lhs == show_shortcuts_lhs then
      return true
    end

    if type(map.desc) == "string" and map.desc:match("^Raccoon:") then
      return true
    end

    return type(map.rhs) == "string" and map.rhs:match("[<:]Raccoon%s")
  end

  local opts = { buffer = buf, noremap = true, silent = true }
  local nop = function() end
  for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
    local lhs = map.lhs
    local normalized_lhs = normalize_lhs(lhs)
    if type(lhs) == "string"
        and lhs ~= ""
        and not passthrough[normalized_lhs]
        and not is_raccoon_global_map(map, normalized_lhs)
        and not lhs:match("^<Plug>")
    then
      pcall(vim.keymap.set, mode, lhs, nop, opts)
    end
  end
end

--- Block all keys on a buffer. Raccoon keymaps set AFTER this call override specific keys.
---@param buf number Buffer ID
---@param passthrough_keys? string[] Keys to skip blocking
function M.lock_buf(buf, passthrough_keys)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local opts = { buffer = buf, noremap = true, silent = true }
  local nop = function() end
  shadow_global_keymaps(buf, NORMAL_MODE, passthrough_keys)

  local skip = {}
  for _, key in ipairs(M.PASSTHROUGH_KEYS or {}) do
    skip[key] = true
  end
  for _, key in ipairs(passthrough_keys or {}) do
    skip[key] = true
  end

  local blocked = {}

  -- All lowercase and uppercase letters
  for c = string.byte("a"), string.byte("z") do
    table.insert(blocked, string.char(c))
    table.insert(blocked, string.char(c - 32))
  end
  -- Digits
  for c = string.byte("0"), string.byte("9") do
    table.insert(blocked, string.char(c))
  end
  -- Punctuation and symbols
  for _, key in ipairs({
    "`", "~", "!", "@", "#", "$", "%", "^", "&", "*", "(", ")",
    "-", "_", "=", "+", "[", "]", "{", "}", "\\", "|",
    ";", ":", "'", '"', ",", ".", "<", ">", "/", "?", " ",
  }) do
    table.insert(blocked, key)
  end
  -- Ctrl combos
  for c = string.byte("a"), string.byte("z") do
    table.insert(blocked, "<C-" .. string.char(c) .. ">")
  end
  -- Special keys
  for _, key in ipairs({
    "<Tab>", "<S-Tab>", "<Insert>", "<Del>", "<Home>", "<End>",
    "<PageUp>", "<PageDown>", "<Up>", "<Down>", "<Left>", "<Right>",
    "<F1>", "<F2>", "<F3>", "<F4>", "<F5>", "<F6>",
    "<F7>", "<F8>", "<F9>", "<F10>", "<F11>", "<F12>",
  }) do
    table.insert(blocked, key)
  end
  -- Multi-key sequences
  for _, key in ipairs({ "ZZ", "ZQ", "gQ", "gg", "gq" }) do
    table.insert(blocked, key)
  end
  for _, key in ipairs(blocked) do
    if not skip[key] then
      vim.keymap.set(NORMAL_MODE, key, nop, opts)
    end
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

--- Block editing and commit-mode navigation keys in a maximize floating window.
--- Global normal-mode mappings are shadowed so only explicit maximize bindings remain active.
---@param buf number Buffer ID
---@param grid_rows number Grid row count (for maximize prefix blocking)
---@param grid_cols number Grid column count
---@param skip_keys? table<string, boolean> Keys to exclude from blocking
function M.lock_maximize_buf(buf, grid_rows, grid_cols, skip_keys)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local shortcuts = config.load_shortcuts()
  local opts = { buffer = buf, noremap = true, silent = true }
  local nop = function() end
  shadow_global_keymaps(buf, NORMAL_MODE)
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

--- Resize a split window while it is focused so Neovim applies the width to that side.
--- Works best when equalalways is disabled (caller's responsibility). Focusing the target first
--- ensures the requested width is honored rather than absorbed by resize of the previously active window.
---@param win number|nil
---@param width number
---@return number? applied_width
local function set_focused_split_width(win, width)
  if not win or not vim.api.nvim_win_is_valid(win) then return nil end

  local current_win = vim.api.nvim_get_current_win()
  local restore_win = current_win ~= win and current_win or nil
  if restore_win then
    vim.api.nvim_set_current_win(win)
  end

  pcall(vim.api.nvim_win_set_width, win, width)
  local get_ok, applied_width = pcall(vim.api.nvim_win_get_width, win)
  if not get_ok then return nil end

  if restore_win and vim.api.nvim_win_is_valid(restore_win) then
    vim.api.nvim_set_current_win(restore_win)
  end

  return applied_width
end

--- Re-equalize sidebar widths, header height, and grid cell dimensions.
--- Called after initial layout creation and after any layout disruption (rogue window, terminal resize).
---@param s table State table (needs sidebar_win, filetree_win, header_win, grid_wins, grid_rows, grid_cols, requested_sidebar_width; writes sidebar_width)
function M.equalize_grid(s)
  local rows = s.grid_rows or 1
  local cols = s.grid_cols or 1
  local requested_sidebar_width = s.requested_sidebar_width or M.SIDEBAR_WIDTH
  local effective_sidebar_width = M.compute_effective_sidebar_width(cols, requested_sidebar_width)

  local filetree_width = set_focused_split_width(s.filetree_win, effective_sidebar_width) or effective_sidebar_width
  local sidebar_width = set_focused_split_width(s.sidebar_win, effective_sidebar_width) or effective_sidebar_width
  s.sidebar_width = sidebar_width

  set_header_height(s.header_win)
  local row_height = math.floor(M.grid_total_height() / math.max(1, rows))
  -- Layout: filetree | col1 | col2 | ... | colN | sidebar → (cols + 1) separators
  local grid_width = vim.o.columns - filetree_width - sidebar_width - (cols + 1)
  local col_widths = compute_grid_column_widths(grid_width, cols)
  for idx, win in ipairs(s.grid_wins or {}) do
    if vim.api.nvim_win_is_valid(win) then
      local col_idx = ((idx - 1) % cols) + 1
      local h_ok, h_err = pcall(vim.api.nvim_win_set_height, win, row_height)
      local w_ok, w_err = pcall(vim.api.nvim_win_set_width, win, col_widths[col_idx])
      if (not h_ok or not w_ok) then
        local msg = not h_ok and tostring(h_err) or tostring(w_err)
        if not msg:match("Invalid window") then
          vim.notify("Grid cell resize error: " .. msg, vim.log.levels.DEBUG)
        end
      end
    end
  end
end

--- Create the full grid layout: file tree (left), diff grid (center), commit sidebar (right), header (top).
--- Writes window/buffer handles into the provided state table.
---@param s table State table to populate (must have grid_wins, grid_bufs, etc. fields)
---@param rows number Grid rows
---@param cols number Grid columns
function M.create_grid_layout(s, rows, cols)
  s.grid_rows = rows
  s.grid_cols = cols
  s.requested_sidebar_width = M.SIDEBAR_WIDTH
  s.sidebar_width = M.compute_effective_sidebar_width(cols, s.requested_sidebar_width)

  vim.cmd("only")

  -- File tree on left
  vim.cmd("vsplit")
  vim.cmd("wincmd H")
  s.filetree_win = vim.api.nvim_get_current_win()
  s.filetree_buf = M.create_scratch_buf()
  vim.api.nvim_win_set_buf(s.filetree_win, s.filetree_buf)
  vim.api.nvim_win_set_width(s.filetree_win, s.sidebar_width)
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
  vim.api.nvim_win_set_width(s.sidebar_win, s.sidebar_width)
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
  vim.wo[s.header_win].wrap = true
  vim.wo[s.header_win].winhl = "Normal:Normal"
  M.lock_buf(s.header_buf)

  -- Fix dimensions
  vim.cmd("wincmd =")
  M.equalize_grid(s)

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

--- Rebuild the grid portion of the layout without touching sidebar/filetree/header.
--- Keeps one grid window as an anchor to preserve layout position, closes the rest,
--- then splits the anchor to create the new grid dimensions.
---@param s table State table
---@param rows number New grid rows
---@param cols number New grid cols
---@param apply_keymaps fun(bufs: number[]) Callback to apply keymaps to new grid buffers
function M.rebuild_grid(s, rows, cols, apply_keymaps)
  s.grid_rows = rows
  s.grid_cols = cols

  -- Keep the first valid grid window as anchor, close the rest
  local anchor_win = nil
  for _, win in ipairs(s.grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      if not anchor_win then
        anchor_win = win
      else
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end
  s.grid_wins = {}
  s.grid_bufs = {}

  if not anchor_win then
    -- Fallback: create a window to the left of sidebar
    if not s.sidebar_win or not vim.api.nvim_win_is_valid(s.sidebar_win) then return end
    vim.api.nvim_set_current_win(s.sidebar_win)
    vim.cmd("aboveleft vsplit")
    anchor_win = vim.api.nvim_get_current_win()
  end

  vim.api.nvim_set_current_win(anchor_win)

  -- Build row windows by splitting the anchor downward
  local row_wins = { anchor_win }
  for _ = 2, rows do
    vim.api.nvim_set_current_win(row_wins[#row_wins])
    vim.cmd("belowright split")
    table.insert(row_wins, vim.api.nvim_get_current_win())
  end

  -- Build grid cells by splitting each row rightward
  local grid_wins = {}
  local grid_bufs = {}
  for _, row_win in ipairs(row_wins) do
    vim.api.nvim_set_current_win(row_win)
    local col_wins = { row_win }
    for _ = 2, cols do
      vim.cmd("belowright vsplit")
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

  -- Fix dimensions: set sidebar/filetree widths first, then equalize grid cells
  if s.sidebar_win and vim.api.nvim_win_is_valid(s.sidebar_win) then
    vim.api.nvim_win_set_width(s.sidebar_win, M.SIDEBAR_WIDTH)
  end
  if s.filetree_win and vim.api.nvim_win_is_valid(s.filetree_win) then
    vim.api.nvim_win_set_width(s.filetree_win, M.SIDEBAR_WIDTH)
  end
  if s.header_win and vim.api.nvim_win_is_valid(s.header_win) then
    vim.api.nvim_win_set_height(s.header_win, math.max(1, #vim.api.nvim_buf_get_lines(s.header_buf, 0, -1, false)))
  end
  local row_height = math.floor(M.grid_total_height() / math.max(1, rows))
  local grid_width = vim.o.columns - 2 * M.SIDEBAR_WIDTH - (cols + 1)
  local col_width = math.max(1, math.floor(grid_width / math.max(1, cols)))
  for _, win in ipairs(grid_wins) do
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_set_height(win, row_height)
      vim.api.nvim_win_set_width(win, col_width)
    end
  end

  -- Apply keymaps to the new buffers
  apply_keymaps(grid_bufs)
end

--- Write lines to a preview buffer, set filetype, and update winbar.
---@param buf number Buffer ID
---@param win number|nil Window ID
---@param filename string File name for filetype detection and winbar
---@param lines string[] Lines to write
local function finalize_preview(buf, win, filename, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  local ft = vim.filetype.match({ filename = filename })
  if ft then vim.bo[buf].filetype = ft end
  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = " " .. filename .. "%=[Enter]"
    pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
  end
end

--- Render a file preview into the first grid buffer.
--- Shows diff if file is changed in the current commit, otherwise shows raw content.
---@param s table State table (needs grid_bufs[1])
---@param opts table {ns_id, repo_path, sha, filename, is_working_dir}
function M.render_file_preview(s, opts)
  local buf = s.grid_bufs and s.grid_bufs[1]
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local win = s.grid_wins and s.grid_wins[1]

  local git = require("raccoon.git")
  local is_changed = s.commit_files and s.commit_files[opts.filename]

  s.preview_generation = s.preview_generation + 1
  local gen = s.preview_generation

  if is_changed then
    local fetch_patch = opts.is_working_dir
        and function(cb) git.diff_working_dir_file(opts.repo_path, opts.filename, cb) end
      or function(cb) git.show_commit_file(opts.repo_path, opts.sha, opts.filename, cb) end

    fetch_patch(function(patch, err)
      if s.preview_generation ~= gen then return end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if err or not patch or patch == "" then
        M._set_preview_empty(buf, win, opts.filename, "  No diff available")
        return
      end
      local hunks = diff.parse_patch(patch)
      if #hunks == 0 then
        M._set_preview_empty(buf, win, opts.filename, "  No changes")
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
      finalize_preview(buf, win, opts.filename, lines)
      M.apply_diff_highlights(opts.ns_id, buf, hl_lines)
    end)
  else
    git.show_file_content(opts.repo_path, opts.sha, opts.filename, function(lines, err)
      if s.preview_generation ~= gen then return end
      if not vim.api.nvim_buf_is_valid(buf) then return end
      if err or not lines then
        M._set_preview_empty(buf, win, opts.filename, "  Cannot read file")
        return
      end
      finalize_preview(buf, win, opts.filename, lines)
      vim.api.nvim_buf_clear_namespace(buf, opts.ns_id, 0, -1)
    end)
  end
end

--- Apply a list of keymaps to a set of buffers.
---@param keymaps table[] Array of {mode, lhs, rhs, desc}
---@param bufs number[] Buffer IDs
function M.apply_keymaps_to_bufs(keymaps, bufs)
  for _, buf in ipairs(bufs) do
    for _, km in ipairs(keymaps) do
      vim.keymap.set(km.mode, km.lhs, km.rhs,
        { buffer = buf, noremap = true, silent = true, desc = km.desc })
    end
  end
end

--- Return sorted line indices that map to file paths in cached_line_paths.
---@param s table State table (needs cached_line_paths)
---@return number[]
function M._sorted_file_lines(s)
  local result = {}
  if not s.cached_line_paths then return result end
  for line_idx, _ in pairs(s.cached_line_paths) do
    table.insert(result, line_idx)
  end
  table.sort(result)
  return result
end

--- Helper to set empty preview content
---@param buf number Buffer ID
---@param win number|nil Window ID
---@param filename string File name for winbar
---@param msg string Message to display
function M._set_preview_empty(buf, win, filename, msg)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "", msg })
  vim.bo[buf].modifiable = false
  if win and vim.api.nvim_win_is_valid(win) then
    vim.wo[win].winbar = " " .. filename .. "%=[Enter]"
  end
end

--- Open a maximize floating window for a full-file diff
---@param opts table {ns_id, repo_path, sha, filename, commit_message, generation, ...}
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

--- Stop the file watcher for the maximize window
---@param s table State table
function M.stop_maximize_watcher(s)
  if s.maximize_fs_event then
    pcall(function()
      s.maximize_fs_event:stop()
      if not s.maximize_fs_event:is_closing() then
        s.maximize_fs_event:close()
      end
    end)
    s.maximize_fs_event = nil
  end
end

--- Start a file watcher that refreshes the maximize window on file changes
---@param s table State table (must have maximize_workdir_opts set)
function M.start_maximize_watcher(s)
  local mopts = s.maximize_workdir_opts
  if not mopts then return end

  local filepath = vim.fs.joinpath(mopts.repo_path, mopts.filename)
  local handle = vim.uv.new_fs_event()
  if not handle then return end

  s.maximize_fs_event = handle
  handle:start(filepath, {}, vim.schedule_wrap(function(err)
    if err then return end
    if not s.maximize_workdir_opts then return end
    M.refresh_maximize(s)
  end))
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

    if err or not patch or patch == "" then
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
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

--- Fetch the full commit message async and update the header.
--- Immediately shows whatever message is available, then re-renders with the full text.
---@param s table State table (needs header_buf, header_win, select_generation, current_page)
---@param commit table|nil Commit with {sha, message, full_message?}
---@param repo_path string|nil Repository path for git operations
---@param generation number select_generation at call time (for stale-callback guard)
---@param total_pages_fn fun(): number Function returning current total page count
function M.fetch_and_display_commit_message(s, commit, repo_path, generation, total_pages_fn)
  if not commit then
    M.update_header(s, nil, total_pages_fn())
    return
  end

  if not repo_path or repo_path == "" then
    M.update_header(s, commit, total_pages_fn())
    return
  end

  local git = require("raccoon.git")

  M.update_header(s, commit, total_pages_fn())

  if commit.sha and not commit.full_message then
    git.get_commit_message(repo_path, commit.sha, function(message, err)
      if generation ~= s.select_generation then return end
      if err then
        vim.notify("Failed to load full commit message: " .. err, vim.log.levels.WARN)
        return
      end
      if message and message ~= "" then
        commit.full_message = message
        M.update_header(s, commit, total_pages_fn())
      end
    end)
  end
end

--- Update the header bar with commit message and page indicator
---@param s table State table
---@param commit table|nil Current commit {message, full_message?}
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
    set_header_height(win)
    return
  end

  local msg = commit.full_message or commit.message or ""

  -- Join all lines with spaces so the message flows continuously with wrapping
  local msg_lines = vim.split(msg, "\n", { trimempty = true })
  local joined = table.concat(msg_lines, " ")

  local max_lines = math.max(1, M.COMMIT_MESSAGE_MAX_LINES)
  local win_width = math.max(1, vim.api.nvim_win_get_width(win))

  -- Truncate text to fit within max_lines of visual wrapping
  local prefix = show_pages and page_str or ""
  local ellipsis = "..."
  local ellipsis_width = vim.fn.strdisplaywidth(ellipsis)
  local max_display_width = max_lines * win_width - vim.fn.strdisplaywidth(prefix)
  if max_display_width <= ellipsis_width then
    joined = ""
  elseif vim.fn.strdisplaywidth(joined) > max_display_width then
    joined = M.truncate_to_display_width(joined, max_display_width - ellipsis_width) .. ellipsis
  end

  local lines = { prefix .. joined }

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local hl_ns = vim.api.nvim_create_namespace("raccoon_header_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  if #prefix > 0 then
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, "Comment", 0, 0, #prefix)
  end

  -- Always use max_lines so the header stays a fixed size (no jumping between commits)
  set_header_height(win)
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

--- Setup sidebar navigation keymaps (j/k/gg/G/Enter/arrows) and lock the buffer.
--- lock_buf is called first to block everything, then nav keymaps override specific keys.
---@param buf number Buffer ID
---@param callbacks table {move_down, move_up, move_to_top, move_to_bottom, select_at_cursor}
function M.setup_sidebar_nav(buf, callbacks)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  M.lock_buf(buf)
  local o = { buffer = buf, noremap = true, silent = true }
  vim.keymap.set(NORMAL_MODE, "j", callbacks.move_down, o)
  vim.keymap.set(NORMAL_MODE, "k", callbacks.move_up, o)
  vim.keymap.set(NORMAL_MODE, "<Down>", callbacks.move_down, o)
  vim.keymap.set(NORMAL_MODE, "<Up>", callbacks.move_up, o)
  vim.keymap.set(NORMAL_MODE, "gg", callbacks.move_to_top, o)
  vim.keymap.set(NORMAL_MODE, "G", callbacks.move_to_bottom, o)
  vim.keymap.set(NORMAL_MODE, "<CR>", callbacks.select_at_cursor, o)
end

--- Collect known commit-mode split window handles (floating windows like maximize and popup are checked separately).
---@param s table State table
---@return table<number, true> Set of known window IDs
local function collect_known_wins(s)
  local known = {}
  if s.sidebar_win then known[s.sidebar_win] = true end
  if s.filetree_win then known[s.filetree_win] = true end
  if s.header_win then known[s.header_win] = true end
  for _, w in ipairs(s.grid_wins or {}) do
    known[w] = true
  end
  return known
end

--- Setup the focus-lock autocmd that keeps cursor in the active panel (or maximize window).
--- Also guards layout by closing unexpected split windows (e.g. file explorer sidebars).
--- Respects s.focus_target: "sidebar" (default) or "filetree".
---@param s table State table (needs active, maximize_win, sidebar_win, filetree_win, focus_target)
---@param augroup_name string Name for the augroup
---@return number augroup_id
function M.setup_focus_lock(s, augroup_name)
  local augroup = vim.api.nvim_create_augroup(augroup_name, { clear = true })

  -- Guard layout: close unexpected split windows (floating windows are fine)
  vim.api.nvim_create_autocmd("WinNew", {
    group = augroup,
    callback = function()
      if not s.active then return end
      vim.schedule(function()
        local win = vim.api.nvim_get_current_win()
        if not vim.api.nvim_win_is_valid(win) then return end
        -- Floating windows don't disrupt layout — allow them
        local cfg = vim.api.nvim_win_get_config(win)
        if cfg.relative and cfg.relative ~= "" then return end
        -- Check if this split is one of our known layout windows
        local known = collect_known_wins(s)
        if not known[win] then
          local buf_name = ""
          pcall(function()
            buf_name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)), ":t")
          end)
          local close_ok = pcall(vim.api.nvim_win_close, win, true)
          if close_ok then
            vim.notify(
              "Commit viewer closed unexpected window" .. (buf_name ~= "" and ": " .. buf_name or ""),
              vim.log.levels.DEBUG
            )
            M.equalize_grid(s)
          else
            vim.notify(
              "Commit viewer could not close unexpected window" .. (buf_name ~= "" and ": " .. buf_name or ""),
              vim.log.levels.WARN
            )
          end
        end
      end)
    end,
  })

  -- Re-equalize grid after terminal resize
  vim.api.nvim_create_autocmd("VimResized", {
    group = augroup,
    callback = function()
      if not s.active then return end
      if s.maximize_win and vim.api.nvim_win_is_valid(s.maximize_win) then return end
      vim.schedule(function()
        if not s.active then return end
        M.equalize_grid(s)
      end)
    end,
  })

  vim.api.nvim_create_autocmd("WinEnter", {
    group = augroup,
    callback = function()
      if not s.active then return end
      if s.popup_win and not vim.api.nvim_win_is_valid(s.popup_win) then
        s.popup_win = nil
      end
      local cur_win = vim.api.nvim_get_current_win()
      if cur_win == s.maximize_win then return end
      if s.popup_win and cur_win == s.popup_win then return end
      if s.maximize_win and vim.api.nvim_win_is_valid(s.maximize_win) then
        vim.schedule(function()
          if s.popup_win and not vim.api.nvim_win_is_valid(s.popup_win) then
            s.popup_win = nil
          end
          if s.popup_win then return end
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
--- When in filetree focus (1x1 grid), navigation also updates the file preview.
---@param s table State table
---@param opts table {get_repo_path, get_sha, get_commit_message, get_is_working_dir, ns_id}
function M.setup_filetree_nav(s, opts)
  if not s.filetree_buf or not vim.api.nvim_buf_is_valid(s.filetree_buf) then return end

  local function all_file_lines()
    return M._sorted_file_lines(s)
  end

  local function go_to_line(line_idx)
    if s.filetree_win and vim.api.nvim_win_is_valid(s.filetree_win) then
      pcall(vim.api.nvim_win_set_cursor, s.filetree_win, { line_idx + 1, 0 })
    end
  end

  local function maybe_preview()
    if s.focus_target == "filetree" and s.orig_grid_rows then
      M._preview_file_at_cursor(s, opts)
    end
  end

  local function ft_move_down()
    if not s.filetree_win or not vim.api.nvim_win_is_valid(s.filetree_win) then return end
    local lines = all_file_lines()
    if #lines == 0 then return end
    local cur = vim.api.nvim_win_get_cursor(s.filetree_win)[1] - 1
    for _, idx in ipairs(lines) do
      if idx > cur then go_to_line(idx); maybe_preview(); return end
    end
  end

  local function ft_move_up()
    if not s.filetree_win or not vim.api.nvim_win_is_valid(s.filetree_win) then return end
    local lines = all_file_lines()
    if #lines == 0 then return end
    local cur = vim.api.nvim_win_get_cursor(s.filetree_win)[1] - 1
    for i = #lines, 1, -1 do
      if lines[i] < cur then go_to_line(lines[i]); maybe_preview(); return end
    end
  end

  local function ft_move_top()
    local lines = all_file_lines()
    if #lines > 0 then go_to_line(lines[1]); maybe_preview() end
  end

  local function ft_move_bottom()
    local lines = all_file_lines()
    if #lines > 0 then go_to_line(lines[#lines]); maybe_preview() end
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

--- Toggle focus between sidebar and filetree panels.
--- When switching to filetree, collapses the grid to 1x1 and shows a file preview.
--- When switching back to sidebar, restores the original NxM grid.
---@param s table State table
---@param opts table {apply_keymaps, render_page, ns_id, get_repo_path, get_sha, get_is_working_dir}
function M.toggle_filetree_focus(s, opts)
  if not opts or not opts.apply_keymaps then return end
  if s.focus_target == "filetree" then
    -- Switching back to sidebar: restore original grid
    s.focus_target = "sidebar"
    if s.filetree_win and vim.api.nvim_win_is_valid(s.filetree_win) then
      vim.wo[s.filetree_win].cursorline = false
    end
    if s.orig_grid_rows then
      s.preview_generation = s.preview_generation + 1
      M.rebuild_grid(s, s.orig_grid_rows, s.orig_grid_cols, opts.apply_keymaps)
      s.orig_grid_rows = nil
      s.orig_grid_cols = nil
      if opts.render_page then opts.render_page() end
    end
    if s.sidebar_win and vim.api.nvim_win_is_valid(s.sidebar_win) then
      vim.api.nvim_set_current_win(s.sidebar_win)
    end
  else
    -- Switching to filetree: collapse grid to 1x1 with file preview
    s.focus_target = "filetree"
    s.orig_grid_rows = s.grid_rows
    s.orig_grid_cols = s.grid_cols
    M.rebuild_grid(s, 1, 1, opts.apply_keymaps)
    M._preview_file_at_cursor(s, opts)
    if s.filetree_win and vim.api.nvim_win_is_valid(s.filetree_win) then
      vim.wo[s.filetree_win].cursorline = true
      vim.api.nvim_set_current_win(s.filetree_win)
    end
  end
end

--- Preview the file at the current filetree cursor position in the 1x1 grid.
--- If the cursor is not on a file line, moves to the nearest file line first.
---@param s table State table
---@param opts table {ns_id, get_repo_path, get_sha, get_is_working_dir}
function M._preview_file_at_cursor(s, opts)
  if not s.filetree_win or not vim.api.nvim_win_is_valid(s.filetree_win) then return end
  if not s.cached_line_paths then return end

  local cur = vim.api.nvim_win_get_cursor(s.filetree_win)[1] - 1
  local path = s.cached_line_paths[cur]

  -- If cursor is not on a file line, find the nearest one
  if not path then
    local file_lines = M._sorted_file_lines(s)
    -- Find first file line at or after cursor
    for _, idx in ipairs(file_lines) do
      if idx >= cur then
        path = s.cached_line_paths[idx]
        pcall(vim.api.nvim_win_set_cursor, s.filetree_win, { idx + 1, 0 })
        break
      end
    end
    -- Fall back to first file line
    if not path and #file_lines > 0 then
      path = s.cached_line_paths[file_lines[1]]
      pcall(vim.api.nvim_win_set_cursor, s.filetree_win, { file_lines[1] + 1, 0 })
    end
  end

  -- Clear stale preview content when no file is found
  if not path then
    local buf = s.grid_bufs and s.grid_bufs[1]
    if buf and vim.api.nvim_buf_is_valid(buf) then
      M._set_preview_empty(buf, s.grid_wins and s.grid_wins[1], "(no file)", "  No file at cursor")
    end
    return
  end
  local repo_path = opts.get_repo_path and opts.get_repo_path()
  if not repo_path then return end
  local sha = opts.get_sha and opts.get_sha()
  M.render_file_preview(s, {
    ns_id = opts.ns_id,
    repo_path = repo_path,
    sha = sha,
    filename = path,
    is_working_dir = opts.get_is_working_dir and opts.get_is_working_dir() or false,
  })
end

--- Render a two-section sidebar (section1 commits + separator + section2 commits dimmed).
--- Works for both PR viewer ("PR Branch"/"Base Branch") and local viewer ("feat-xyz"/"main").
---@param buf number Buffer ID
---@param opts table {section1_header, section1_commits, section2_header, section2_commits, commit_hl_fn?, loading?, sidebar_width?}
function M.render_split_sidebar(buf, opts)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  local lines = {}
  local highlights = {}
  local sidebar_width = opts.sidebar_width or M.SIDEBAR_WIDTH

  -- Section 1 header
  table.insert(lines, opts.section1_header)
  table.insert(highlights, { line = #lines - 1, hl = "Title" })

  -- Section 1 commits
  for _, commit in ipairs(opts.section1_commits) do
    local msg = M.truncate_sidebar_text(commit.message, sidebar_width)
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
    local msg = M.truncate_sidebar_text(commit.message, sidebar_width)
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
