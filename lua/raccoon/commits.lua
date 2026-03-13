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

local COMBINED_DIFF_SHA = git.COMBINED_DIFF_SHA

--- Compute the base ref for combined diff operations.
--- Returns nil when no PR is active; callers should handle nil (diff_combined already guards it).
---@return string|nil base_ref
local function get_base_ref()
  local pr = state.get_pr()
  if not pr then return nil end
  return "origin/" .. pr.base.ref
end

--- Namespace for commit viewer highlights
local ns_id = vim.api.nvim_create_namespace("raccoon_commits")

local function make_initial_state()
  return {
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
    file_stats = {},
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
    cached_stat_lines = nil,
    cached_file_count = nil,
    focus_target = "sidebar",
    last_head_sha = nil,
    last_base_sha = nil,
    base_branch = nil,
    base_count = 20,
    sync_interval_ms = 60000,
  }
end

--- Module-local state
local commit_state = make_initial_state()

--- Commit mode keymaps (global)
local commit_mode_keymaps = {}

--- Module-level timer handle. Stored outside commit_state so it survives
--- state table reassignment in reset_state() and can always be stopped.
local poll_timer_handle = nil

--- In-flight guard: prevents overlapping sync ticks from running concurrent git operations.
local sync_in_flight = false

--- Stop the background sync timer
local function stop_poll_timer()
  if poll_timer_handle then
    local handle = poll_timer_handle
    poll_timer_handle = nil
    pcall(handle.stop, handle)
    pcall(handle.close, handle)
  end
  sync_in_flight = false
end

--- Reset module state
local function reset_state()
  stop_poll_timer()
  commit_state = make_initial_state()
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
    commit_message = commit.message or "",
    generation = commit_state.select_generation,
    get_generation = function() return commit_state.select_generation end,
    state = commit_state,
    is_combined_diff = commit.sha == COMBINED_DIFF_SHA,
    base_ref = get_base_ref(),
  })
end

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

  local context = ui.compute_grid_context(commit_state.grid_rows)

  local fetch_diff
  if commit.sha == COMBINED_DIFF_SHA then
    local base_ref = get_base_ref()
    fetch_diff = function(cb) git.diff_combined(clone_path, base_ref, context, cb) end
  else
    fetch_diff = function(cb) git.show_commit(clone_path, commit.sha, context, cb) end
  end

  fetch_diff(function(files, err)
    if generation ~= commit_state.select_generation then return end

    if err then
      vim.notify("Failed to get commit diff: " .. err, vim.log.levels.ERROR)
      return
    end

    -- Track files, compute stats, and build flat hunk list in a single pass
    commit_state.commit_files = {}
    commit_state.file_stats = {}
    commit_state.all_hunks = {}
    commit_state.cached_sha = nil
    commit_state.cached_stat_lines = nil
    for _, file in ipairs(files or {}) do
      commit_state.commit_files[file.filename] = true
      local additions = 0
      local deletions = 0
      local hunks = diff.parse_patch(file.patch)
      for _, hunk in ipairs(hunks) do
        table.insert(commit_state.all_hunks, { hunk = hunk, filename = file.filename })
        for _, line_data in ipairs(hunk.lines) do
          if line_data.type == "add" then
            additions = additions + 1
          elseif line_data.type == "del" then
            deletions = deletions + 1
          end
        end
      end
      commit_state.file_stats[file.filename] = { additions = additions, deletions = deletions }
    end
    build_filetree_cache()

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
  local idx = commit_state.selected_index
  if idx < 1 or idx > total_commits() then return end
  ui.update_split_selection(
    commit_state.sidebar_buf, commit_state.sidebar_win,
    idx, #commit_state.pr_commits
  )
end

--- Render the sidebar with commit lists
local function render_sidebar()
  ui.render_split_sidebar(commit_state.sidebar_buf, {
    section1_header = "── PR Branch ──",
    section1_commits = commit_state.pr_commits,
    section2_header = "── Base Branch ──",
    section2_commits = commit_state.base_commits,
    commit_hl_fn = function(commit)
      if commit.sha == COMBINED_DIFF_SHA then return "DiagnosticInfo" end
    end,
  })
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
  local index = ui.split_sidebar_cursor_to_index(cursor_line, #commit_state.pr_commits)
  if index and index >= 1 and index <= total_commits() then
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

--- Preserve selected commit across a refresh
local function restore_selection_by_sha(selected_sha)
  ui.restore_selection_by_sha(commit_state, selected_sha, total_commits, get_commit)
end

--- Refresh commits after detecting remote changes.
--- Fetches updated commit lists and rebuilds the sidebar, preserving selection.
local function refresh_commits()
  local clone_path = state.get_clone_path()
  local base_branch = commit_state.base_branch
  if not clone_path or not base_branch then return end

  local sel = get_commit(commit_state.selected_index)
  local selected_sha = sel and sel.sha

  local pending = 2
  local new_pr, new_base

  local function on_both_ready()
    commit_state.pr_commits = new_pr or commit_state.pr_commits
    commit_state.base_commits = new_base or commit_state.base_commits

    if #commit_state.pr_commits > 1
      and commit_state.pr_commits[1].sha ~= COMBINED_DIFF_SHA then
      table.insert(commit_state.pr_commits, 1, git.make_combined_diff_entry())
    end

    restore_selection_by_sha(selected_sha)
    render_sidebar()

    if total_commits() > 0 then
      select_commit(commit_state.selected_index)
    end
  end

  local function check_done()
    pending = pending - 1
    if pending == 0 then on_both_ready() end
  end

  git.log_commits(clone_path, base_branch, function(commits, err)
    if err then
      vim.notify("Sync: failed to refresh PR commits", vim.log.levels.DEBUG)
    end
    new_pr = (not err) and commits or nil
    check_done()
  end)

  git.log_base_commits(clone_path, base_branch, commit_state.base_count, function(commits, err)
    if err then
      vim.notify("Sync: failed to refresh base commits", vim.log.levels.DEBUG)
    end
    new_base = (not err) and commits or nil
    check_done()
  end)
end

--- Single sync tick: fetch branches, check for new commits, reset and refresh if needed.
--- Guarded by sync_in_flight to prevent overlapping git operations.
---@param clone_path string
---@param pr_branch string
---@param base_branch string
local function sync_tick(clone_path, pr_branch, base_branch)
  if sync_in_flight then return end
  if not commit_state.active then return end
  sync_in_flight = true

  local function done()
    sync_in_flight = false
  end

  git.fetch_branch(clone_path, pr_branch, function(_, fetch_err)
    if not commit_state.active then done(); return end
    if fetch_err then
      vim.notify("Sync: failed to fetch PR branch", vim.log.levels.DEBUG)
      done(); return
    end

    git.fetch_branch(clone_path, base_branch, function(_, base_fetch_err)
      if not commit_state.active then done(); return end
      if base_fetch_err then
        vim.notify("Sync: failed to fetch base branch", vim.log.levels.DEBUG)
      end

      -- Check both PR and base branch SHAs in parallel
      local pending = 2
      local pr_sha, base_sha
      local function check_both()
        pending = pending - 1
        if pending > 0 then return end
        if not commit_state.active then done(); return end

        -- Seed SHAs on first tick
        if not commit_state.last_head_sha then
          commit_state.last_head_sha = pr_sha
        end
        if not commit_state.last_base_sha then
          commit_state.last_base_sha = base_sha
        end

        local pr_changed = pr_sha and pr_sha ~= commit_state.last_head_sha
        local base_changed = base_sha and base_sha ~= commit_state.last_base_sha

        if not pr_changed and not base_changed then
          done(); return
        end

        -- Update tracked base SHA
        if base_sha then commit_state.last_base_sha = base_sha end

        if pr_changed then
          -- PR branch advanced — reset local clone to match origin
          git.reset_hard(clone_path, "origin/" .. pr_branch, function(ok, reset_err)
            if not commit_state.active then done(); return end
            if not ok then
              vim.notify("Sync: failed to reset to remote: " .. (reset_err or ""), vim.log.levels.DEBUG)
              done(); return
            end
            commit_state.last_head_sha = pr_sha
            refresh_commits()
            done()
          end)
        else
          -- Only base branch changed — refresh commit lists without reset
          refresh_commits()
          done()
        end
      end

      git.ref_sha(clone_path, "origin/" .. pr_branch, function(sha, ref_err)
        if ref_err then
          vim.notify("Sync: could not resolve PR branch SHA", vim.log.levels.DEBUG)
        end
        pr_sha = sha
        check_both()
      end)

      git.ref_sha(clone_path, "origin/" .. base_branch, function(sha, ref_err)
        if ref_err then
          vim.notify("Sync: could not resolve base branch SHA", vim.log.levels.DEBUG)
        end
        base_sha = sha
        check_both()
      end)
    end)
  end)
end

--- Start the background sync timer.
--- On each tick: fetch PR branch from origin, check for new commits, reset and refresh if needed.
local function start_poll_timer()
  stop_poll_timer()
  if not commit_state.active then return end
  if commit_state.sync_interval_ms <= 0 then return end

  local clone_path = state.get_clone_path()
  local pr = state.get_pr()
  if not clone_path or not pr then return end

  local pr_branch = pr.head.ref
  local base_branch = commit_state.base_branch

  -- Seed last_head_sha and last_base_sha before starting the timer to avoid spurious refresh on first tick
  sync_in_flight = false
  git.get_current_sha(clone_path, function(sha, seed_err)
    if not commit_state.active then return end
    if seed_err then
      vim.notify("Sync: failed to seed HEAD SHA", vim.log.levels.DEBUG)
    end
    if sha then commit_state.last_head_sha = sha end

    git.ref_sha(clone_path, "origin/" .. base_branch, function(base_sha, base_seed_err)
      if not commit_state.active then return end
      if base_seed_err then
        vim.notify("Sync: failed to seed base SHA", vim.log.levels.DEBUG)
      end
      if base_sha then commit_state.last_base_sha = base_sha end

      -- Guard against concurrent timer creation from rapid toggle
      stop_poll_timer()
      if not commit_state.active then return end

      local timer = vim.uv.new_timer()
      if not timer then
        vim.notify("Failed to create sync timer", vim.log.levels.WARN)
        return
      end
      poll_timer_handle = timer
      timer:start(commit_state.sync_interval_ms, commit_state.sync_interval_ms,
        vim.schedule_wrap(function()
          sync_tick(clone_path, pr_branch, base_branch)
        end))
    end)
  end)
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

  -- Browse files toggle
  if config.is_enabled(shortcuts.commit_mode.browse_files) then
    table.insert(commit_mode_keymaps, {
      mode = NORMAL_MODE,
      lhs = shortcuts.commit_mode.browse_files,
      rhs = function() ui.toggle_filetree_focus(commit_state) end,
      desc = "Toggle file tree browsing",
    })
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

  -- Filetree navigation keymaps
  ui.setup_filetree_nav(commit_state, {
    ns_id = ns_id,
    get_repo_path = function() return state.get_clone_path() end,
    get_sha = function()
      local c = get_commit(commit_state.selected_index)
      return c and c.sha
    end,
    get_commit_message = function()
      local c = get_commit(commit_state.selected_index)
      return c and c.message or ""
    end,
    get_base_ref = get_base_ref,
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
  local sync_interval = 60
  if cfg and cfg.commit_viewer then
    if cfg.commit_viewer.grid then
      rows = ui.clamp_int(cfg.commit_viewer.grid.rows, 2, 1, 10)
      cols = ui.clamp_int(cfg.commit_viewer.grid.cols, 2, 1, 10)
    end
    base_count = ui.clamp_int(cfg.commit_viewer.base_commits_count, 20, 1, 200)
    ui.SIDEBAR_WIDTH = ui.clamp_int(cfg.commit_viewer.sidebar_width, 50, 20, 120)
    sync_interval = ui.clamp_int(cfg.commit_viewer.sync_interval, 60, 10, 3600)
  end

  local base_branch = pr.base.ref
  commit_state.base_branch = base_branch
  commit_state.base_count = base_count
  commit_state.sync_interval_ms = sync_interval * 1000

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

        local real_pr_count = #commit_state.pr_commits
        if real_pr_count > 1 then
          table.insert(commit_state.pr_commits, 1, git.make_combined_diff_entry())
        end

        ui.create_grid_layout(commit_state, rows, cols)
        render_sidebar()
        setup_keymaps()
        select_commit(1)
        start_poll_timer()
        vim.notify(string.format("Commit viewer: %d PR commits, %d base commits",
          real_pr_count, #commit_state.base_commits))
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
  stop_poll_timer()

  if commit_state.focus_augroup then
    pcall(vim.api.nvim_del_augroup_by_id, commit_state.focus_augroup)
  end

  -- Close floating maximize window (not affected by :only)
  ui.close_win_pair(commit_state, "maximize_win", "maximize_buf")
  commit_mode_keymaps = {}

  state.set_commit_mode(false)

  -- Close all splits in one shot; scratch buffers auto-wipe (bufhidden=wipe)
  vim.cmd("only")

  if commit_state.saved_buf and vim.api.nvim_buf_is_valid(commit_state.saved_buf) then
    vim.api.nvim_set_current_buf(commit_state.saved_buf)
  end

  if commit_state.saved_laststatus then
    vim.o.laststatus = commit_state.saved_laststatus
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
M._compute_file_stats = ui.compute_file_stats
M._format_stat_bar = ui.format_stat_bar
M._close_filetree = function() ui.close_win_pair(commit_state, "filetree_win", "filetree_buf") end

return M
