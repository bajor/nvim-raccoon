---@class RaccoonLocalCommits
---Local commit viewer: browse commits in any git repository
local M = {}

local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local diff = require("raccoon.diff")
local git = require("raccoon.git")
local keymaps = require("raccoon.keymaps")
local open = require("raccoon.open")
local state = require("raccoon.state")
local ui = require("raccoon.commit_ui")

local ns_id = vim.api.nvim_create_namespace("raccoon_local_commits")

local BATCH_SIZE = 100
local POLL_INTERVAL_MS = 10000

local function make_initial_state()
  return {
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

local local_state = make_initial_state()
local local_mode_keymaps = {}

-- Forward declaration
local load_more_commits

local function total_pages()
  local cells = local_state.grid_rows * local_state.grid_cols
  if cells == 0 then return 1 end
  return math.max(1, math.ceil(#local_state.all_hunks / cells))
end

local function render_grid_page()
  ui.render_grid_page(local_state, ns_id, function()
    return local_state.commits[local_state.selected_index]
  end, total_pages())
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

--- Maximize a grid cell
local function maximize_cell(cell_num)
  local cells = local_state.grid_rows * local_state.grid_cols
  local start_idx = (local_state.current_page - 1) * cells + 1
  local hunk_idx = start_idx + cell_num - 1
  local hunk_data = local_state.all_hunks[hunk_idx]
  if not hunk_data then return end

  local filename = hunk_data.filename
  if filename == "dev/null" then return end
  local commit = local_state.commits[local_state.selected_index]
  if not commit or not local_state.repo_path then return end

  ui.open_maximize({
    ns_id = ns_id,
    repo_path = local_state.repo_path,
    sha = commit.sha,
    filename = filename,
    generation = local_state.select_generation,
    get_generation = function() return local_state.select_generation end,
    state = local_state,
  })
end

--- Select a commit and load its hunks into the grid
local function select_commit(index)
  if index < 1 or index > #local_state.commits then return end

  local_state.selected_index = index
  local_state.current_page = 1
  local_state.select_generation = local_state.select_generation + 1
  local generation = local_state.select_generation

  local commit = local_state.commits[index]
  if not local_state.repo_path then return end

  git.show_commit(local_state.repo_path, commit.sha, function(files, err)
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
      ui.update_header(local_state, local_state.commits[local_state.selected_index], total_pages())
      ui.render_filetree(local_state)
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
  pcall(vim.api.nvim_buf_add_highlight, buf, sel_ns, "Visual", idx, 0, -1)

  if local_state.sidebar_win and vim.api.nvim_win_is_valid(local_state.sidebar_win) then
    pcall(vim.api.nvim_win_set_cursor, local_state.sidebar_win, { idx + 1, 0 })
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
    if #msg > ui.SIDEBAR_WIDTH - 2 then
      msg = msg:sub(1, ui.SIDEBAR_WIDTH - 5) .. "..."
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

--- Build and cache the file tree for the selected commit
local function build_filetree_cache()
  if not local_state.repo_path then return end
  local commit = local_state.commits[local_state.selected_index]
  local sha = commit and commit.sha or "HEAD"
  ui.build_filetree_cache(local_state, local_state.repo_path, sha)
end

--- Setup keymaps for local commit mode
local function setup_keymaps()
  local shortcuts = config.load_shortcuts()

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
  for _, km in ipairs(ui.window_block_keymaps()) do
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

  -- Apply keymaps buffer-locally
  local commit_bufs = ui.collect_bufs(local_state)
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
    ui.lock_buf(local_state.sidebar_buf)
  end

  -- Focus lock autocmd
  local_state.focus_augroup = ui.setup_focus_lock(local_state, "RaccoonLocalCommitFocus")
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
    if err or not new_commits or #new_commits == 0 then return end

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
      rows = ui.clamp_int(cfg.commit_viewer.grid.rows, 2, 1, 10)
      cols = ui.clamp_int(cfg.commit_viewer.grid.cols, 2, 1, 10)
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
        ui.create_grid_layout(local_state, rows, cols)
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

  ui.close_win_pair(local_state, "maximize_win", "maximize_buf")
  local_mode_keymaps = {}
  ui.close_grid(local_state)
  ui.close_win_pair(local_state, "sidebar_win", "sidebar_buf")
  ui.close_win_pair(local_state, "filetree_win", "filetree_buf")

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

  local_state = make_initial_state()
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
