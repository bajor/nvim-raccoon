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
local ui = require("raccoon.commit_ui")

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
}

--- Commit mode keymaps (global)
local commit_mode_keymaps = {}

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
  }
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

--- Render the current page of hunks into the grid
local function render_grid_page()
  ui.render_grid_page(commit_state, ns_id, function()
    return get_commit(commit_state.selected_index)
  end, total_pages())
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

  ui.open_maximize({
    ns_id = ns_id,
    repo_path = clone_path,
    sha = commit.sha,
    filename = filename,
    generation = commit_state.select_generation,
    get_generation = function() return commit_state.select_generation end,
    state = commit_state,
  })
end

-- Forward declaration
local build_filetree_cache

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
      return
    end

    -- Track all files in commit
    commit_state.commit_files = {}
    for _, file in ipairs(files or {}) do
      commit_state.commit_files[file.filename] = true
    end

    -- Parse all files into flat hunk list
    commit_state.all_hunks = {}
    commit_state.cached_sha = nil
    build_filetree_cache()
    for _, file in ipairs(files or {}) do
      local hunks = diff.parse_patch(file.patch)
      for _, hunk in ipairs(hunks) do
        table.insert(commit_state.all_hunks, { hunk = hunk, filename = file.filename })
      end
    end

    if #commit_state.all_hunks == 0 then
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
      ui.update_header(commit_state, get_commit(commit_state.selected_index), total_pages())
      ui.render_filetree(commit_state)
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
    if #msg > ui.SIDEBAR_WIDTH - 2 then
      msg = msg:sub(1, ui.SIDEBAR_WIDTH - 5) .. "..."
    end
    table.insert(lines, "  " .. msg)
  end

  -- Separator
  table.insert(lines, "")
  table.insert(lines, "── Base Branch ──")
  table.insert(highlights, { line = #lines - 1, hl = "Title" })

  for _, commit in ipairs(commit_state.base_commits) do
    local msg = commit.message
    if #msg > ui.SIDEBAR_WIDTH - 2 then
      msg = msg:sub(1, ui.SIDEBAR_WIDTH - 5) .. "..."
    end
    table.insert(lines, "  " .. msg)
    table.insert(highlights, { line = #lines - 1, hl = "Comment" })
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local hl_ns = vim.api.nvim_create_namespace("raccoon_commit_hl")
  vim.api.nvim_buf_clear_namespace(buf, hl_ns, 0, -1)
  for _, hl in ipairs(highlights) do
    pcall(vim.api.nvim_buf_add_highlight, buf, hl_ns, hl.hl, hl.line, 0, -1)
  end

  ui.update_sidebar_winbar(commit_state, total_commits())
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

local function move_to_top()
  if total_commits() > 0 then
    commit_state.selected_index = 1
    update_sidebar_selection()
    select_commit(1)
  end
end

local function move_to_bottom()
  if total_commits() > 0 then
    commit_state.selected_index = total_commits()
    update_sidebar_selection()
    select_commit(commit_state.selected_index)
  end
end

local function select_at_cursor()
  if not commit_state.sidebar_win or not vim.api.nvim_win_is_valid(commit_state.sidebar_win) then return end
  local cursor_line = vim.api.nvim_win_get_cursor(commit_state.sidebar_win)[1]
  local index = cursor_line - 1
  if index >= 1 and index <= total_commits() then
    commit_state.selected_index = index
    update_sidebar_selection()
    select_commit(index)
  end
end

--- Build and cache the file tree structure for the selected commit.
build_filetree_cache = function()
  local clone_path = state.get_clone_path()
  if not clone_path then return end
  local commit = get_commit(commit_state.selected_index)
  local sha = commit and commit.sha or "HEAD"
  ui.build_filetree_cache(commit_state, clone_path, sha)
end

--- Setup commit mode keymaps (buffer-local to all commit-mode buffers)
local function setup_keymaps()
  local shortcuts = config.load_shortcuts()

  local all = {
    {
      mode = NORMAL_MODE, lhs = shortcuts.commit_mode.exit,
      rhs = function() M.toggle() end, desc = "Exit commit viewer",
    },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_mode.next_page, rhs = next_page, desc = "Next page of hunks" },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_mode.prev_page, rhs = prev_page, desc = "Previous page of hunks" },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_mode.next_page_alt, rhs = next_page, desc = "Next page of hunks" },
  }

  commit_mode_keymaps = {}
  for _, km in ipairs(all) do
    if config.is_enabled(km.lhs) then
      table.insert(commit_mode_keymaps, km)
    end
  end

  -- Block window-switching keys
  for _, km in ipairs(ui.window_block_keymaps()) do
    table.insert(commit_mode_keymaps, km)
  end

  -- Maximize keymaps
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

  -- Apply keymaps buffer-locally
  local commit_bufs = ui.collect_bufs(commit_state)
  for _, buf in ipairs(commit_bufs) do
    for _, km in ipairs(commit_mode_keymaps) do
      vim.keymap.set(km.mode, km.lhs, km.rhs,
        { buffer = buf, noremap = true, silent = true, desc = km.desc })
    end
  end

  -- Sidebar-local keymaps
  ui.setup_sidebar_nav(commit_state.sidebar_buf, {
    move_down = move_down,
    move_up = move_up,
    move_to_top = move_to_top,
    move_to_bottom = move_to_bottom,
    select_at_cursor = select_at_cursor,
  })

  -- Focus lock autocmd
  commit_state.focus_augroup = ui.setup_focus_lock(commit_state, "RaccoonCommitFocus")
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

  local clone_path = state.get_clone_path()
  if not clone_path or clone_path == "" then
    vim.notify("No clone path available", vim.log.levels.WARN)
    return
  end

  commit_state.saved_buf = vim.api.nvim_get_current_buf()
  commit_state.saved_laststatus = vim.o.laststatus
  vim.o.laststatus = 3

  keymaps.clear()
  open.pause_sync()
  state.set_commit_mode(true)
  commit_state.active = true

  local cfg = config.load()
  local rows = 2
  local cols = 2
  local base_count = 20
  if cfg and cfg.commit_viewer then
    if cfg.commit_viewer.grid then
      rows = ui.clamp_int(cfg.commit_viewer.grid.rows, 2, 1, 10)
      cols = ui.clamp_int(cfg.commit_viewer.grid.cols, 2, 1, 10)
    end
    base_count = ui.clamp_int(cfg.commit_viewer.base_commits_count, 20, 1, 200)
  end

  local base_branch = pr.base.ref

  vim.notify("Entering commit viewer mode...", vim.log.levels.INFO)

  git.unshallow_if_needed(clone_path, function(_, unshallow_err)
    if unshallow_err then
      vim.notify("Warning: repository unshallow failed", vim.log.levels.WARN)
    end

    git.fetch_branch(clone_path, base_branch, function(_, fetch_err)
      if fetch_err then
        vim.notify("Failed to fetch base branch", vim.log.levels.ERROR)
        M.toggle()
        return
      end

      local pending = 2

      local function on_both_ready()
        if #commit_state.pr_commits == 0 then
          vim.notify("No commits found on PR branch", vim.log.levels.WARN)
          M.toggle()
          return
        end

        ui.create_grid_layout(commit_state, rows, cols)
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
  if commit_state.focus_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, commit_state.focus_augroup)
  end

  ui.close_win_pair(commit_state, "maximize_win", "maximize_buf")
  commit_mode_keymaps = {}
  ui.close_grid(commit_state)
  ui.close_win_pair(commit_state, "sidebar_win", "sidebar_buf")
  ui.close_win_pair(commit_state, "filetree_win", "filetree_buf")

  state.set_commit_mode(false)

  if commit_state.saved_laststatus then
    vim.o.laststatus = commit_state.saved_laststatus
  end

  vim.cmd("only")
  if commit_state.saved_buf and vim.api.nvim_buf_is_valid(commit_state.saved_buf) then
    vim.api.nvim_set_current_buf(commit_state.saved_buf)
  end

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
M._lock_buf = ui.lock_buf
M._lock_maximize_buf = function(buf) ui.lock_maximize_buf(buf, commit_state.grid_rows, commit_state.grid_cols) end
M._clamp_int = ui.clamp_int
M._get_state = function() return commit_state end
M._select_commit = select_commit
M._setup_keymaps = setup_keymaps
M._render_filetree = function() ui.render_filetree(commit_state) end
M._build_file_tree = ui.build_file_tree
M._render_tree_node = ui.render_tree_node
M._close_filetree = function() ui.close_win_pair(commit_state, "filetree_win", "filetree_buf") end

return M
