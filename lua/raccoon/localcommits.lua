---@class RaccoonLocalCommits
---Local commit viewer: browse commits in any git repository
local M = {}

local config = require("raccoon.config")
local NORMAL_MODE = config.NORMAL
local git = require("raccoon.git")
local keymaps = require("raccoon.keymaps")
local open = require("raccoon.open")
local state = require("raccoon.state")
local ui = require("raccoon.commit_ui")

local CURRENT_CHANGES_MSG = "UNCOMMITTED CHANGES"

local ns_id = vim.api.nvim_create_namespace("raccoon_local_commits")

local BATCH_SIZE = 100
local POLL_INTERVAL_MS = 10000
local WORKDIR_POLL_FAST_MS = 3000
local WORKDIR_POLL_SLOW_MS = 30000
local WORKDIR_IDLE_THRESHOLD_MS = 180000
local MAX_WORKDIR_FAILURES = 5

local function make_initial_state()
  local s = ui.make_base_state()
  s.repo_path = nil
  s.branch_commits = {}
  s.base_commits = {}
  s.current_branch = nil
  s.base_branch = nil
  s.merge_base_sha = nil
  s.total_base_loaded = 0
  s.loading_more = false
  s.poll_timer = nil
  s.last_head_sha = nil
  s.workdir_poll_timer = nil
  s.last_status_output = ""
  s.last_change_time = 0
  s.pr_was_active = false
  return s
end

local local_state = make_initial_state()
local local_mode_keymaps = {}

--- Compute the local base ref for combined diff operations.
--- Differs from commits.get_base_ref() which returns "origin/" + pr.base.ref.
--- Prefers merge-base SHA (exact ancestor) when available; falls back to branch name.
---@return string|nil base_ref
local function get_local_base_ref()
  return local_state.merge_base_sha or local_state.base_branch
end

--- Prepend synthetic entries (COMBINED DIFF + UNCOMMITTED CHANGES) to a branch commit list.
--- Always inserts UNCOMMITTED CHANGES regardless of commit count.
--- Inserts COMBINED DIFF only when there are multiple real commits.
---@param commits table[] Commit list to modify in place
local function prepend_synthetic_entries(commits)
  git.maybe_prepend_combined_diff(commits)
  -- Insert UNCOMMITTED CHANGES after COMBINED DIFF (or at position 1 if no combined diff)
  local insert_pos = git.is_combined_diff(commits[1]) and 2 or 1
  table.insert(commits, insert_pos, { sha = nil, message = CURRENT_CHANGES_MSG })
end

local load_more_commits
local build_filetree_cache

--- Total navigable sidebar entries (branch section + base section, including synthetic entries)
local function total_commits()
  return #local_state.branch_commits + #local_state.base_commits
end

--- Get commit by combined index (branch first, then base)
local function get_commit(index)
  local branch_count = #local_state.branch_commits
  if index <= branch_count then
    return local_state.branch_commits[index]
  else
    return local_state.base_commits[index - branch_count]
  end
end

local function total_pages()
  local cells = local_state.grid_rows * local_state.grid_cols
  if cells == 0 then return 1 end
  return math.max(1, math.ceil(#local_state.all_hunks / cells))
end

local function render_grid_page()
  ui.render_grid_page(local_state, ns_id, function()
    return get_commit(local_state.selected_index)
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
  local commit = get_commit(local_state.selected_index)
  if not commit or not local_state.repo_path then return end

  ui.open_maximize({
    ns_id = ns_id,
    repo_path = local_state.repo_path,
    sha = commit.sha,
    filename = filename,
    commit_message = commit.message or "",
    generation = local_state.select_generation,
    get_generation = function() return local_state.select_generation end,
    state = local_state,
    is_working_dir = commit.sha == nil,
    is_combined_diff = git.is_combined_diff(commit),
    base_ref = get_local_base_ref(),
  })
end

--- Select a commit and load its hunks into the grid
local function select_commit(index)
  if index < 1 or index > total_commits() then return end

  local_state.selected_index = index
  local_state.current_page = 1
  local_state.select_generation = local_state.select_generation + 1
  local generation = local_state.select_generation

  local commit = get_commit(index)
  if not local_state.repo_path then return end

  local context = ui.compute_grid_context(local_state.grid_rows)

  local fetch_diff
  if git.is_combined_diff(commit) then
    local base_ref = get_local_base_ref()
    if not base_ref then
      vim.notify("Combined diff requires a base branch", vim.log.levels.WARN)
      return
    end
    fetch_diff = function(cb) git.diff_combined(local_state.repo_path, base_ref, context, cb) end
  elseif commit.sha then
    fetch_diff = function(cb) git.show_commit(local_state.repo_path, commit.sha, context, cb) end
  else
    fetch_diff = function(cb) git.diff_working_dir(local_state.repo_path, context, cb) end
  end

  fetch_diff(function(files, err)
    ui.apply_diff_result(local_state, {
      files = files,
      err = err,
      generation = generation,
      get_generation = function() return local_state.select_generation end,
      build_cache_fn = build_filetree_cache,
      get_commit_fn = function() return get_commit(local_state.selected_index) end,
      total_pages_fn = total_pages,
      ns_id = ns_id,
      render_grid_fn = render_grid_page,
    })
  end)
end

--- Update sidebar selection highlight
local function update_sidebar_selection()
  local idx = local_state.selected_index
  if idx < 1 or idx > total_commits() then return end

  if local_state.base_branch then
    -- Branch mode: two-section sidebar
    ui.update_split_selection(
      local_state.sidebar_buf, local_state.sidebar_win,
      idx, #local_state.branch_commits
    )
  else
    -- Flat mode: simple offset (line 0 = header, commits start at line 1)
    local buf = local_state.sidebar_buf
    if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
    local sel_ns = vim.api.nvim_create_namespace("raccoon_local_commit_sel")
    vim.api.nvim_buf_clear_namespace(buf, sel_ns, 0, -1)
    pcall(vim.api.nvim_buf_add_highlight, buf, sel_ns, "Visual", idx, 0, -1)
    if local_state.sidebar_win and vim.api.nvim_win_is_valid(local_state.sidebar_win) then
      pcall(vim.api.nvim_win_set_cursor, local_state.sidebar_win, { idx + 1, 0 })
    end
  end
end

--- Render the sidebar with commit list
local function render_sidebar()
  local buf = local_state.sidebar_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end

  if local_state.base_branch then
    -- Branch mode: two-section sidebar using shared function
    local branch_label = local_state.current_branch or "branch"
    ui.render_split_sidebar(buf, {
      section1_header = "── " .. branch_label .. " ──",
      section1_commits = local_state.branch_commits,
      section2_header = "── " .. local_state.base_branch .. " ──",
      section2_commits = local_state.base_commits,
      commit_hl_fn = function(commit)
        if commit.sha == nil or git.is_combined_diff(commit) then return "DiagnosticInfo" end
      end,
      loading = local_state.loading_more,
    })
  else
    -- Flat mode: single section
    local lines = {}
    local highlights = {}

    local commit_count = math.max(0, total_commits() - 1)
    table.insert(lines, "── Commits (" .. commit_count .. ") ──")
    table.insert(highlights, { line = #lines - 1, hl = "Title" })

    for i, commit in ipairs(local_state.branch_commits) do
      local msg = commit.message
      if #msg > ui.SIDEBAR_WIDTH - 2 then
        msg = msg:sub(1, ui.SIDEBAR_WIDTH - 5) .. "..."
      end
      table.insert(lines, "  " .. msg)
      if commit.sha == nil then
        table.insert(highlights, { line = i, hl = "DiagnosticInfo" })
      end
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
  end

  ui.update_sidebar_winbar(local_state, total_commits())
  update_sidebar_selection()
end

local function move_up()
  if local_state.selected_index > 1 then
    local_state.selected_index = local_state.selected_index - 1
    update_sidebar_selection()
    select_commit(local_state.selected_index)
  end
end

local function move_to_top()
  if total_commits() > 0 then
    local_state.selected_index = 1
    update_sidebar_selection()
    select_commit(1)
  end
end

local function move_to_bottom()
  if total_commits() > 0 then
    local_state.selected_index = total_commits()
    update_sidebar_selection()
    select_commit(local_state.selected_index)
    load_more_commits()
  end
end

local function select_at_cursor()
  if not local_state.sidebar_win or not vim.api.nvim_win_is_valid(local_state.sidebar_win) then return end
  local cursor_line = vim.api.nvim_win_get_cursor(local_state.sidebar_win)[1]

  local index
  if local_state.base_branch then
    index = ui.split_sidebar_cursor_to_index(cursor_line, #local_state.branch_commits)
  else
    index = cursor_line - 1
  end

  if index and index >= 1 and index <= total_commits() then
    local_state.selected_index = index
    update_sidebar_selection()
    select_commit(index)
  end
end

local function move_down()
  if local_state.selected_index < total_commits() then
    local_state.selected_index = local_state.selected_index + 1
    update_sidebar_selection()
    select_commit(local_state.selected_index)

    -- Trigger loading more when within 10 commits of the end
    if total_commits() - local_state.selected_index < 10 then
      load_more_commits()
    end
  end
end

--- Build and cache the file tree for the selected commit
build_filetree_cache = function()
  if not local_state.repo_path then return end
  local commit = get_commit(local_state.selected_index)
  local sha = (commit and commit.sha) or nil
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

    -- Maximize file picker
    table.insert(local_mode_keymaps, {
      mode = NORMAL_MODE,
      lhs = shortcuts.commit_mode.maximize_prefix .. "f",
      rhs = function()
        local items = {}
        for path, _ in pairs(local_state.commit_files) do
          table.insert(items, { display = "  " .. path, value = path })
        end
        table.sort(items, function(a, b) return a.display < b.display end)
        ui.open_maximize_list({
          title = "Files (" .. #items .. ")",
          items = items,
          state = local_state,
          on_select = function(path)
            for i, hd in ipairs(local_state.all_hunks) do
              if hd.filename == path then
                local c = local_state.grid_rows * local_state.grid_cols
                local_state.current_page = math.ceil(i / c)
                render_grid_page()
                maximize_cell(((i - 1) % c) + 1)
                return
              end
            end
          end,
        })
      end,
      desc = "Maximize file picker",
    })

    -- Maximize commit picker
    table.insert(local_mode_keymaps, {
      mode = NORMAL_MODE,
      lhs = shortcuts.commit_mode.maximize_prefix .. "c",
      rhs = function()
        local items = {}
        for i = 1, total_commits() do
          local c = get_commit(i)
          if c then table.insert(items, { display = "  " .. c.message, value = i }) end
        end
        ui.open_maximize_list({
          title = "Commits (" .. #items .. ")",
          items = items,
          state = local_state,
          on_select = function(idx)
            local_state.selected_index = idx
            update_sidebar_selection()
            select_commit(idx)
          end,
        })
      end,
      desc = "Maximize commit picker",
    })
  end

  -- Browse files toggle
  if config.is_enabled(shortcuts.commit_mode.browse_files) then
    table.insert(local_mode_keymaps, {
      mode = NORMAL_MODE,
      lhs = shortcuts.commit_mode.browse_files,
      rhs = function() ui.toggle_filetree_focus(local_state) end,
      desc = "Toggle file tree browsing",
    })
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
  ui.setup_sidebar_nav(local_state.sidebar_buf, {
    move_down = move_down,
    move_up = move_up,
    move_to_top = move_to_top,
    move_to_bottom = move_to_bottom,
    select_at_cursor = select_at_cursor,
  })

  -- Filetree navigation keymaps
  ui.setup_filetree_nav(local_state, {
    ns_id = ns_id,
    get_repo_path = function() return local_state.repo_path end,
    get_sha = function()
      local c = get_commit(local_state.selected_index)
      return c and c.sha
    end,
    get_commit_message = function()
      local c = get_commit(local_state.selected_index)
      return c and c.message or ""
    end,
    get_base_ref = get_local_base_ref,
  })

  -- Focus lock autocmd
  local_state.focus_augroup = ui.setup_focus_lock(local_state, "RaccoonLocalCommitFocus")
end

local function stop_poll_timer()
  if local_state.poll_timer then
    local handle = local_state.poll_timer
    local_state.poll_timer = nil
    ui.safe_close_timer(handle)
  end
end

local function stop_workdir_poll_timer()
  if local_state.workdir_poll_timer then
    local handle = local_state.workdir_poll_timer
    local_state.workdir_poll_timer = nil
    ui.safe_close_timer(handle)
  end
end

local start_workdir_poll_timer
local workdir_fail_count = 0

--- Start the adaptive working directory poll timer.
--- Fast (WORKDIR_POLL_FAST_MS) when changes are recent,
--- slow (WORKDIR_POLL_SLOW_MS) after WORKDIR_IDLE_THRESHOLD_MS idle.
start_workdir_poll_timer = function()
  stop_workdir_poll_timer()
  if not local_state.active then return end

  local now = vim.uv.now()
  local idle = local_state.last_change_time == 0
    or (now - local_state.last_change_time) >= WORKDIR_IDLE_THRESHOLD_MS
  local interval = idle and WORKDIR_POLL_SLOW_MS or WORKDIR_POLL_FAST_MS

  local timer = vim.uv.new_timer()
  if not timer then
    vim.notify("Failed to create workdir poll timer", vim.log.levels.WARN)
    return
  end
  local_state.workdir_poll_timer = timer
  timer:start(interval, 0, vim.schedule_wrap(function()
    if not local_state.active then return end

    git.status_porcelain(local_state.repo_path, function(output, err)
      if not local_state.active then
        start_workdir_poll_timer()
        return
      end
      if err then
        workdir_fail_count = workdir_fail_count + 1
        if workdir_fail_count >= MAX_WORKDIR_FAILURES then
          vim.notify("Workdir poll: stopped after " .. workdir_fail_count .. " consecutive failures", vim.log.levels.WARN)
          return
        end
        vim.notify("Workdir poll: status_porcelain failed", vim.log.levels.DEBUG)
        start_workdir_poll_timer()
        return
      end
      workdir_fail_count = 0

      if (output or "") == local_state.last_status_output then
        start_workdir_poll_timer()
        return
      end

      local_state.last_status_output = output or ""
      local_state.last_change_time = vim.uv.now()
      render_sidebar()

      if local_state.selected_index == 1 then
        select_commit(1)
      end

      start_workdir_poll_timer()
    end)
  end))
end

--- Preserve selected commit across a refresh
local function restore_selection_by_sha(selected_sha)
  ui.restore_selection_by_sha(local_state, selected_sha, total_commits, get_commit)
end

--- Refresh commits from git (called when HEAD changes)
local function refresh_commits()
  local selected_sha = get_commit(local_state.selected_index)
    and get_commit(local_state.selected_index).sha

  if local_state.base_branch and local_state.merge_base_sha then
    -- Branch mode: refresh branch commits only (base stays static)
    git.log_branch_commits(local_state.repo_path, local_state.merge_base_sha, function(new_branch, err)
      if err or not new_branch then
        vim.notify("Local sync: failed to refresh branch commits", vim.log.levels.WARN)
        return
      end
      prepend_synthetic_entries(new_branch)
      local_state.branch_commits = new_branch
      local_state.last_status_output = ""
      restore_selection_by_sha(selected_sha)
      render_sidebar()
    end)
  else
    -- Flat mode: refresh all commits
    local count = math.max(total_commits() - 1, BATCH_SIZE)
    git.log_all_commits(local_state.repo_path, count, 0, function(new_commits, err)
      if err or not new_commits then
        vim.notify("Local sync: failed to refresh commits", vim.log.levels.WARN)
        return
      end
      table.insert(new_commits, 1, { sha = nil, message = CURRENT_CHANGES_MSG })
      local_state.branch_commits = new_commits
      local_state.last_status_output = ""
      restore_selection_by_sha(selected_sha)
      render_sidebar()
    end)
  end
end

--- Start the HEAD polling timer (interval: POLL_INTERVAL_MS).
--- Seeds last_head_sha before starting the timer to avoid spurious refresh on first tick.
local function start_poll_timer()
  stop_poll_timer()
  if not local_state.active then return end

  git.get_current_sha(local_state.repo_path, function(sha, seed_err)
    if not local_state.active then return end
    if seed_err then
      vim.notify("Local sync: failed to seed HEAD SHA", vim.log.levels.DEBUG)
    end
    if sha then
      local_state.last_head_sha = sha
    end

    -- Guard against concurrent timer creation from rapid toggle
    stop_poll_timer()
    if not local_state.active then return end

    local timer = vim.uv.new_timer()
    if not timer then
      vim.notify("Failed to create HEAD poll timer", vim.log.levels.WARN)
      return
    end
    local_state.poll_timer = timer
    timer:start(POLL_INTERVAL_MS, POLL_INTERVAL_MS, vim.schedule_wrap(function()
      if not local_state.active then return end

      git.get_current_sha(local_state.repo_path, function(new_sha, err)
        if err then
          vim.notify("Local sync: HEAD SHA check failed: " .. tostring(err), vim.log.levels.DEBUG)
          return
        end
        if not new_sha then return end
        if new_sha == local_state.last_head_sha then return end

        local_state.last_head_sha = new_sha
        refresh_commits()
      end)
    end))
  end)
end

--- Load more commits (triggered by approaching end of list)
load_more_commits = function()
  if local_state.loading_more then return end

  if local_state.base_branch and local_state.merge_base_sha then
    -- Branch mode: load more base commits
    local_state.loading_more = true
    git.log_from_ref(local_state.repo_path, local_state.merge_base_sha,
      BATCH_SIZE, local_state.total_base_loaded,
      function(new_commits, err)
        local_state.loading_more = false
        if err then
          vim.notify("Failed to load more base commits", vim.log.levels.DEBUG)
          return
        end
        if not new_commits or #new_commits == 0 then return end
        for _, commit in ipairs(new_commits) do
          table.insert(local_state.base_commits, commit)
        end
        local_state.total_base_loaded = local_state.total_base_loaded + #new_commits
        render_sidebar()
      end)
  else
    -- Flat mode: load more into branch_commits
    local_state.loading_more = true
    local skip = #local_state.branch_commits - 1 -- -1 for the single synthetic entry (UNCOMMITTED CHANGES); flat mode has no COMBINED DIFF
    git.log_all_commits(local_state.repo_path, BATCH_SIZE, skip, function(new_commits, err)
      local_state.loading_more = false
      if err then
        vim.notify("Failed to load more commits", vim.log.levels.DEBUG)
        return
      end
      if not new_commits or #new_commits == 0 then return end
      for _, commit in ipairs(new_commits) do
        table.insert(local_state.branch_commits, commit)
      end
      render_sidebar()
    end)
  end
end

local exit_local_mode -- forward declaration (defined below activate_mode)

--- Activate local mode with the given state
local function activate_mode(repo_root, rows, cols, notify_msg)
  local_state.saved_buf = vim.api.nvim_get_current_buf()
  local_state.saved_laststatus = vim.o.laststatus
  local_state.pr_was_active = state.is_active()
  if local_state.pr_was_active then
    keymaps.clear()
    open.pause_sync()
  end
  vim.o.laststatus = 3
  local_state.active = true
  local_state.repo_path = repo_root
  state.set_mode_exit(function() exit_local_mode() end)
  local_state.last_change_time = vim.uv.now()
  workdir_fail_count = 0

  vim.schedule(function()
    ui.create_grid_layout(local_state, rows, cols)
    render_sidebar()
    setup_keymaps()
    select_commit(1)
    start_poll_timer()
    start_workdir_poll_timer()
    vim.notify(notify_msg)
  end)
end

--- Flat-mode entry: prepend UNCOMMITTED CHANGES and activate.
--- Shared by all code paths that skip branch-mode (detached HEAD, default branch, merge-base failure).
---@param repo_root string
---@param rows number
---@param cols number
---@param commits table[] Commit list from git log
---@param current_branch string|nil
local function enter_flat_mode(repo_root, rows, cols, commits, current_branch)
  table.insert(commits, 1, { sha = nil, message = CURRENT_CHANGES_MSG })
  if current_branch then local_state.current_branch = current_branch end
  local_state.branch_commits = commits
  activate_mode(repo_root, rows, cols,
    string.format("Local commit viewer: %d commits loaded", #commits - 1))
end

--- Enter local commit viewer mode
local function enter_local_mode()
  local vcfg = ui.parse_viewer_config()
  ui.SIDEBAR_WIDTH = vcfg.sidebar_width
  local rows = vcfg.rows
  local cols = vcfg.cols
  local base_count = vcfg.base_count

  vim.notify("Loading commits...", vim.log.levels.INFO)

  git.find_repo_root(vim.fn.getcwd(), function(repo_root, root_err)
    if root_err or not repo_root then
      vim.notify("Not a git repository", vim.log.levels.ERROR)
      return
    end

    -- Detect current branch
    git.get_current_branch(repo_root, function(current_branch, _)
      if not current_branch or current_branch == "HEAD" then
        git.log_all_commits(repo_root, BATCH_SIZE, 0, function(commits, err)
          if err or not commits or #commits == 0 then
            vim.notify("No commits found", vim.log.levels.WARN)
            return
          end
          enter_flat_mode(repo_root, rows, cols, commits, nil)
        end)
        return
      end

      -- Detect default branch
      git.find_default_branch(repo_root, function(default_branch, _)
        if not default_branch or current_branch == default_branch then
          git.log_all_commits(repo_root, BATCH_SIZE, 0, function(commits, err)
            if err or not commits or #commits == 0 then
              vim.notify("No commits found", vim.log.levels.WARN)
              return
            end
            enter_flat_mode(repo_root, rows, cols, commits, current_branch)
          end)
          return
        end

        -- Feature branch: find merge-base and split
        git.merge_base(repo_root, "HEAD", default_branch, function(merge_sha, merge_err)
          if merge_err or not merge_sha then
            git.log_all_commits(repo_root, BATCH_SIZE, 0, function(commits, err)
              if err or not commits or #commits == 0 then
                vim.notify("No commits found", vim.log.levels.WARN)
                return
              end
              enter_flat_mode(repo_root, rows, cols, commits, current_branch)
            end)
            return
          end

          -- Branch mode: load branch commits and base commits in parallel
          local pending = 2
          local branch_result, base_result

          local function on_both_ready()
            local branch_commits = branch_result or {}
            local base_commits = base_result or {}
            local real_branch_count = #branch_commits
            prepend_synthetic_entries(branch_commits)
            local_state.current_branch = current_branch
            local_state.base_branch = default_branch
            local_state.merge_base_sha = merge_sha
            local_state.branch_commits = branch_commits
            local_state.base_commits = base_commits
            local_state.total_base_loaded = #base_commits
            activate_mode(repo_root, rows, cols,
              string.format("Local commit viewer: %d branch + %d base commits",
                real_branch_count, #base_commits))
          end

          local function check_done()
            pending = pending - 1
            if pending == 0 then on_both_ready() end
          end

          git.log_branch_commits(repo_root, merge_sha, function(commits, err)
            if err then
              vim.notify("Failed to load branch commits", vim.log.levels.WARN)
            end
            branch_result = commits
            check_done()
          end)

          git.log_from_ref(repo_root, merge_sha, base_count, 0, function(commits, err)
            if err then
              vim.notify("Failed to load base commits", vim.log.levels.WARN)
            end
            base_result = commits
            check_done()
          end)
        end)
      end)
    end)
  end)
end

--- Exit local commit viewer mode
exit_local_mode = function()
  stop_poll_timer()
  stop_workdir_poll_timer()

  local was_pr_active = local_state.pr_was_active
  ui.teardown_viewer(local_state, {
    on_before_only = function()
      local_mode_keymaps = {}
      state.set_mode_exit(nil)
    end,
    on_after = function()
      if was_pr_active then
        keymaps.setup()
        open.resume_sync()
      end
      local_state = make_initial_state()
      vim.notify("Exited local commit viewer", vim.log.levels.INFO)
    end,
  })
end

--- Toggle local commit viewer mode
function M.toggle()
  if local_state.active then
    exit_local_mode()
  else
    enter_local_mode()
  end
end

function M.is_active()
  return local_state.active
end

function M.close()
  if local_state.active then
    exit_local_mode()
  end
end

-- Exposed for testing
M._get_state = function() return local_state end
M._select_commit = select_commit

return M
