---@class RaccoonCommits
---Commit viewer mode: sidebar with commits, grid of diff hunks
local M = {}

local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local git = require("raccoon.git")
local keymaps = require("raccoon.keymaps")
local open = require("raccoon.open")
local state = require("raccoon.state")
local ui = require("raccoon.commit_ui")


--- Compute the base ref for combined diff operations.
--- Returns nil when no PR is active; callers should handle nil (diff_combined already guards it).
---@return string|nil base_ref
local function get_base_ref()
  local pr = state.get_pr()
  if not pr or not pr.base or not pr.base.ref then return nil end
  return "origin/" .. pr.base.ref
end

--- Namespace for commit viewer highlights
local ns_id = vim.api.nvim_create_namespace("raccoon_commits")

local function make_initial_state()
  local s = ui.make_base_state()
  s.pr_commits = {}
  s.base_commits = {}
  s.last_head_sha = nil
  s.last_base_sha = nil
  s.base_branch = nil
  s.base_count = nil
  s.sync_interval_ms = nil
  return s
end

local commit_state = make_initial_state()
local commit_mode_keymaps = {}

-- Forward declaration to allow enter_commit_mode to register the exit hook.
local exit_commit_mode

--- Module-level timer handle. Stored outside commit_state so stop_poll_timer()
--- can always reach it, even when reset_state() replaces the state table.
local poll_timer_handle = nil

--- In-flight guard: prevents overlapping sync ticks from running concurrent git operations.
local sync_in_flight = false

--- Session generation counter. Incremented in reset_state() so that async callbacks
--- from a previous viewer session can detect they are stale and bail out.
local session_gen = 0

--- Consecutive sync failure counter. After SYNC_FAIL_ESCALATION_THRESHOLD,
--- notifications escalate from DEBUG to WARN so the user knows sync is broken.
local sync_fail_count = 0
local SYNC_FAIL_ESCALATION_THRESHOLD = 3

--- Stop the background sync timer
local function stop_poll_timer()
  if poll_timer_handle then
    local handle = poll_timer_handle
    poll_timer_handle = nil
    ui.safe_close_timer(handle)
  end
  sync_in_flight = false
end

local function reset_state()
  stop_poll_timer()
  session_gen = session_gen + 1
  sync_fail_count = 0
  commit_state = make_initial_state()
end

---@return number
local function total_pages()
  local cells = commit_state.grid_rows * commit_state.grid_cols
  if cells == 0 then return 1 end
  return math.max(1, math.ceil(#commit_state.all_hunks / cells))
end

--- Total navigable sidebar entries (PR section + base section, including synthetic entries)
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
    is_combined_diff = git.is_combined_diff(commit),
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
  if git.is_combined_diff(commit) then
    local base_ref = get_base_ref()
    if not base_ref then
      vim.notify("Combined diff requires a base branch", vim.log.levels.WARN)
      return
    end
    fetch_diff = function(cb) git.diff_combined(clone_path, base_ref, context, cb) end
  else
    fetch_diff = function(cb) git.show_commit(clone_path, commit.sha, context, cb) end
  end

  fetch_diff(function(files, err)
    ui.apply_diff_result(commit_state, {
      files = files,
      err = err,
      generation = generation,
      get_generation = function() return commit_state.select_generation end,
      build_cache_fn = build_filetree_cache,
      get_commit_fn = function() return get_commit(commit_state.selected_index) end,
      total_pages_fn = total_pages,
      ns_id = ns_id,
      render_grid_fn = render_grid_page,
    })
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
      if git.is_combined_diff(commit) then return "DiagnosticInfo" end
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
---@param on_complete fun()|nil Called after both git log calls finish and the UI is updated
local function refresh_commits(on_complete)
  local clone_path = state.get_clone_path()
  local base_branch = commit_state.base_branch
  if not clone_path or not base_branch then
    if on_complete then on_complete() end
    return
  end

  local my_gen = session_gen
  local sel = get_commit(commit_state.selected_index)
  local selected_sha = sel and sel.sha

  local pending = 2
  local new_pr, new_base

  local function on_both_ready()
    if my_gen ~= session_gen then
      if on_complete then on_complete() end
      return
    end
    -- When both calls failed, skip re-render to avoid clobbering valid state
    if not new_pr and not new_base then
      vim.notify("Sync: failed to refresh commits", vim.log.levels.WARN)
      if on_complete then on_complete() end
      return
    end

    if not new_pr then
      vim.notify("Sync: PR commits are stale (refresh failed)", vim.log.levels.WARN)
    end
    if not new_base then
      vim.notify("Sync: base commits are stale (refresh failed)", vim.log.levels.WARN)
    end
    commit_state.pr_commits = new_pr or commit_state.pr_commits
    commit_state.base_commits = new_base or commit_state.base_commits

    git.maybe_prepend_combined_diff(commit_state.pr_commits)

    restore_selection_by_sha(selected_sha)
    render_sidebar()

    if total_commits() > 0 then
      select_commit(commit_state.selected_index)
    end
    if on_complete then on_complete() end
  end

  local function check_done()
    pending = pending - 1
    if pending == 0 then on_both_ready() end
  end

  git.log_commits(clone_path, base_branch, function(commits, err)
    if err then
      vim.notify("Sync: failed to refresh PR commits: " .. tostring(err), vim.log.levels.DEBUG)
    end
    new_pr = (not err) and commits or nil
    check_done()
  end)

  git.log_base_commits(clone_path, base_branch, commit_state.base_count, function(commits, err)
    if err then
      vim.notify("Sync: failed to refresh base commits: " .. tostring(err), vim.log.levels.DEBUG)
    end
    new_base = (not err) and commits or nil
    check_done()
  end)
end

--- Single sync tick: fetch branches, compare SHAs, and refresh commit lists.
--- Hard-resets the local clone only when the PR branch has advanced.
--- Guarded by sync_in_flight to prevent overlapping git operations.
---@param clone_path string
---@param pr_branch string
---@param base_branch string
local function sync_tick(clone_path, pr_branch, base_branch)
  if sync_in_flight then return end
  if not commit_state.active then return end
  sync_in_flight = true
  local my_gen = session_gen

  --- Escalate from DEBUG to WARN after repeated failures so the user is informed.
  local function sync_log(msg)
    local level = sync_fail_count >= SYNC_FAIL_ESCALATION_THRESHOLD
      and vim.log.levels.WARN or vim.log.levels.DEBUG
    vim.notify(msg, level)
  end

  local function done_fail()
    sync_in_flight = false
    sync_fail_count = sync_fail_count + 1
  end

  local function done_ok()
    sync_in_flight = false
    sync_fail_count = 0
  end

  local function stale()
    return my_gen ~= session_gen
  end

  git.fetch_branch(clone_path, pr_branch, function(_, fetch_err)
    if stale() then sync_in_flight = false; return end
    if fetch_err then
      sync_log("Sync: failed to fetch PR branch: " .. tostring(fetch_err))
      done_fail(); return
    end

    git.fetch_branch(clone_path, base_branch, function(_, base_fetch_err)
      if stale() then sync_in_flight = false; return end
      -- Base fetch is non-fatal: we still check PR branch SHAs.
      -- Use stale base SHA to avoid false "changed" detection.
      local base_fetch_failed = false
      if base_fetch_err then
        sync_log("Sync: failed to fetch base branch: " .. tostring(base_fetch_err))
        base_fetch_failed = true
      end

      -- Check both PR and base branch SHAs in parallel
      local pending = 2
      local pr_sha, base_sha
      local function check_both()
        pending = pending - 1
        if pending > 0 then return end
        if stale() then sync_in_flight = false; return end

        -- Defensive fallback: seed SHAs if start_poll_timer's seeding was incomplete
        if not commit_state.last_head_sha then
          commit_state.last_head_sha = pr_sha
        end
        if not commit_state.last_base_sha then
          commit_state.last_base_sha = base_sha
        end

        -- If both SHA resolutions failed, treat as sync failure
        if not pr_sha and not base_sha then
          sync_log("Sync: could not resolve any branch SHAs")
          done_fail(); return
        end

        local pr_changed = pr_sha and pr_sha ~= commit_state.last_head_sha
        local base_changed = base_sha and base_sha ~= commit_state.last_base_sha

        if not pr_changed and not base_changed then
          done_ok(); return
        end

        -- Update tracked base SHA
        if base_sha then commit_state.last_base_sha = base_sha end

        if pr_changed then
          -- PR branch advanced — reset local clone to match origin
          git.reset_hard(clone_path, "origin/" .. pr_branch, function(ok, reset_err)
            if stale() then sync_in_flight = false; return end
            if not ok then
              sync_log("Sync: failed to reset to remote: " .. (reset_err or ""))
              done_fail(); return
            end
            commit_state.last_head_sha = pr_sha
            refresh_commits(done_ok)
          end)
        else
          -- Only base branch changed — refresh commit lists without reset
          refresh_commits(done_ok)
        end
      end

      git.ref_sha(clone_path, "origin/" .. pr_branch, function(sha, ref_err)
        if ref_err then
          sync_log("Sync: could not resolve PR branch SHA: " .. tostring(ref_err))
        end
        pr_sha = sha
        check_both()
      end)

      if base_fetch_failed then
        -- Skip base SHA check since fetch failed; use stale value to prevent false "changed"
        base_sha = commit_state.last_base_sha
        check_both()
      else
        git.ref_sha(clone_path, "origin/" .. base_branch, function(sha, ref_err)
          if ref_err then
            sync_log("Sync: could not resolve base branch SHA: " .. tostring(ref_err))
          end
          base_sha = sha
          check_both()
        end)
      end
    end)
  end)
end

--- Start the background sync timer.
--- On each tick: fetch PR and base branches from origin, check for new commits, reset and refresh if needed.
local function start_poll_timer()
  stop_poll_timer()
  if not commit_state.active then return end
  if commit_state.sync_interval_ms <= 0 then return end

  local clone_path = state.get_clone_path()
  local pr = state.get_pr()
  if not clone_path or not pr then return end

  local pr_branch = pr.head.ref
  local base_branch = commit_state.base_branch
  local my_gen = session_gen

  -- Seed last_head_sha and last_base_sha before starting the timer to avoid spurious refresh on first tick
  sync_in_flight = false
  git.get_current_sha(clone_path, function(sha, seed_err)
    if my_gen ~= session_gen then return end
    if seed_err then
      vim.notify("Sync: failed to seed HEAD SHA", vim.log.levels.DEBUG)
    end
    if sha then commit_state.last_head_sha = sha end

    git.ref_sha(clone_path, "origin/" .. base_branch, function(base_sha, base_seed_err)
      if my_gen ~= session_gen then return end
      if base_seed_err then
        vim.notify("Sync: failed to seed base SHA", vim.log.levels.DEBUG)
      end
      if base_sha then commit_state.last_base_sha = base_sha end

      -- Guard against concurrent timer creation from rapid toggle
      stop_poll_timer()
      if my_gen ~= session_gen then return end

      local timer = vim.uv.new_timer()
      if not timer then
        vim.notify("Failed to create sync timer", vim.log.levels.WARN)
        return
      end
      poll_timer_handle = timer
      timer:start(commit_state.sync_interval_ms, commit_state.sync_interval_ms,
        vim.schedule_wrap(function()
          if my_gen ~= session_gen then return end
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
  state.set_mode_exit(function() exit_commit_mode() end)

  local vcfg = ui.parse_viewer_config()
  ui.SIDEBAR_WIDTH = vcfg.sidebar_width

  local rows = vcfg.rows
  local cols = vcfg.cols
  local base_branch = pr.base.ref
  commit_state.base_branch = base_branch
  commit_state.base_count = vcfg.base_count
  commit_state.sync_interval_ms = vcfg.sync_interval * 1000

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
        git.maybe_prepend_combined_diff(commit_state.pr_commits)

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

      git.log_base_commits(clone_path, base_branch, commit_state.base_count, function(commits, err)
        if err then
          vim.notify("Failed to get base commits", vim.log.levels.WARN)
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

  ui.teardown_viewer(commit_state, {
    on_before_only = function()
      commit_mode_keymaps = {}
      state.set_commit_mode(false)
      state.set_mode_exit(nil)
    end,
    on_after = function()
      keymaps.setup()
      open.resume_sync()
      reset_state()
      vim.notify("Exited commit viewer mode", vim.log.levels.INFO)
    end,
  })
end

--- Toggle commit viewer mode
function M.toggle()
  if commit_state.active then
    exit_commit_mode()
  else
    enter_commit_mode()
  end
end

function M.is_active()
  return commit_state.active
end

function M.close()
  if commit_state.active then
    exit_commit_mode()
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
M._get_session_gen = function() return session_gen end
M._reset_state = reset_state

return M
