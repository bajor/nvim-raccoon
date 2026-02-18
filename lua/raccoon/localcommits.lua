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
local WORKDIR_POLL_FAST_MS = 3000
local WORKDIR_POLL_SLOW_MS = 30000
local WORKDIR_IDLE_THRESHOLD_MS = 180000

local function make_initial_state()
  return {
    active = false,
    repo_path = nil,
    branch_commits = {},
    base_commits = {},
    current_branch = nil,
    base_branch = nil,
    merge_base_sha = nil,
    total_base_loaded = 0,
    loading_more = false,
    poll_timer = nil,
    last_head_sha = nil,
    workdir_poll_timer = nil,
    last_status_output = "",
    last_change_time = 0,
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
    pr_was_active = false,
  }
end

local local_state = make_initial_state()
local local_mode_keymaps = {}

-- Forward declarations
local load_more_commits
local build_filetree_cache

--- Total navigable commits (branch + base)
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
    generation = local_state.select_generation,
    get_generation = function() return local_state.select_generation end,
    state = local_state,
    is_working_dir = commit.sha == nil,
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

  local fetch_diff = commit.sha
    and function(cb) git.show_commit(local_state.repo_path, commit.sha, cb) end
    or function(cb) git.diff_working_dir(local_state.repo_path, cb) end

  fetch_diff(function(files, err)
    if generation ~= local_state.select_generation then return end

    if err then
      vim.notify("Failed to get commit diff", vim.log.levels.ERROR)
      return
    end

    local_state.commit_files = {}
    for _, file in ipairs(files or {}) do
      local_state.commit_files[file.filename] = true
    end
    local_state.file_stats = ui.compute_file_stats(files)

    local_state.all_hunks = {}
    local_state.cached_sha = nil
    build_filetree_cache()
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
      ui.update_header(local_state, get_commit(local_state.selected_index), total_pages())
      ui.render_filetree(local_state)
      return
    end

    render_grid_page()
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
        if commit.sha == nil then return "DiagnosticInfo" end
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
  })

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

--- Stop the working directory poll timer
local function stop_workdir_poll_timer()
  if local_state.workdir_poll_timer then
    local_state.workdir_poll_timer:stop()
    local_state.workdir_poll_timer:close()
    local_state.workdir_poll_timer = nil
  end
end

-- Forward declaration
local start_workdir_poll_timer

--- Start the adaptive working directory poll timer
--- Fast (3s) when changes are recent, slow (30s) after 3 minutes idle
start_workdir_poll_timer = function()
  stop_workdir_poll_timer()
  if not local_state.active then return end

  local now = vim.uv.now()
  local idle = local_state.last_change_time == 0
    or (now - local_state.last_change_time) >= WORKDIR_IDLE_THRESHOLD_MS
  local interval = idle and WORKDIR_POLL_SLOW_MS or WORKDIR_POLL_FAST_MS

  local_state.workdir_poll_timer = vim.uv.new_timer()
  local_state.workdir_poll_timer:start(interval, 0, vim.schedule_wrap(function()
    if not local_state.active then return end

    git.status_porcelain(local_state.repo_path, function(output, err)
      if err or not local_state.active then
        start_workdir_poll_timer()
        return
      end

      if output == local_state.last_status_output then
        start_workdir_poll_timer()
        return
      end

      local_state.last_status_output = output
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
  if selected_sha then
    for i = 1, total_commits() do
      local c = get_commit(i)
      if c and c.sha == selected_sha then
        local_state.selected_index = i
        return
      end
    end
  end
  if local_state.selected_index > total_commits() then
    local_state.selected_index = math.max(1, total_commits())
  end
end

--- Refresh commits from git (called when HEAD changes)
local function refresh_commits()
  local selected_sha = get_commit(local_state.selected_index)
    and get_commit(local_state.selected_index).sha

  if local_state.base_branch and local_state.merge_base_sha then
    -- Branch mode: refresh branch commits only (base stays static)
    git.log_branch_commits(local_state.repo_path, local_state.merge_base_sha, function(new_branch, err)
      if err or not new_branch then return end
      table.insert(new_branch, 1, { sha = nil, message = "Current changes" })
      local_state.branch_commits = new_branch
      local_state.last_status_output = ""
      restore_selection_by_sha(selected_sha)
      render_sidebar()
    end)
  else
    -- Flat mode: refresh all commits
    local count = math.max(total_commits() - 1, BATCH_SIZE)
    git.log_all_commits(local_state.repo_path, count, 0, function(new_commits, err)
      if err or not new_commits then return end
      table.insert(new_commits, 1, { sha = nil, message = "Current changes" })
      local_state.branch_commits = new_commits
      local_state.last_status_output = ""
      restore_selection_by_sha(selected_sha)
      render_sidebar()
    end)
  end
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

  if local_state.base_branch and local_state.merge_base_sha then
    -- Branch mode: load more base commits
    local_state.loading_more = true
    git.log_from_ref(local_state.repo_path, local_state.merge_base_sha,
      BATCH_SIZE, local_state.total_base_loaded,
      function(new_commits, err)
        local_state.loading_more = false
        if err or not new_commits or #new_commits == 0 then return end
        for _, commit in ipairs(new_commits) do
          table.insert(local_state.base_commits, commit)
        end
        local_state.total_base_loaded = local_state.total_base_loaded + #new_commits
        render_sidebar()
      end)
  else
    -- Flat mode: load more into branch_commits
    local_state.loading_more = true
    local skip = #local_state.branch_commits - 1 -- -1 for "Current changes"
    git.log_all_commits(local_state.repo_path, BATCH_SIZE, skip, function(new_commits, err)
      local_state.loading_more = false
      if err or not new_commits or #new_commits == 0 then return end
      for _, commit in ipairs(new_commits) do
        table.insert(local_state.branch_commits, commit)
      end
      render_sidebar()
    end)
  end
end

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
  local_state.last_change_time = vim.uv.now()

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

--- Enter local commit viewer mode
local function enter_local_mode()
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

  vim.notify("Loading commits...", vim.log.levels.INFO)

  git.find_repo_root(vim.fn.getcwd(), function(repo_root, root_err)
    if root_err or not repo_root then
      vim.notify("Not a git repository", vim.log.levels.ERROR)
      return
    end

    -- Detect current branch
    git.get_current_branch(repo_root, function(current_branch, _)
      if not current_branch or current_branch == "HEAD" then
        -- Detached HEAD or error: flat mode
        git.log_all_commits(repo_root, BATCH_SIZE, 0, function(commits, err)
          if err or not commits or #commits == 0 then
            vim.notify("No commits found", vim.log.levels.WARN)
            return
          end
          table.insert(commits, 1, { sha = nil, message = "Current changes" })
          local_state.branch_commits = commits
          activate_mode(repo_root, rows, cols,
            string.format("Local commit viewer: %d commits loaded", #commits - 1))
        end)
        return
      end

      -- Detect default branch
      git.find_default_branch(repo_root, function(default_branch, _)
        if not default_branch or current_branch == default_branch then
          -- On default branch or detection failed: flat mode
          git.log_all_commits(repo_root, BATCH_SIZE, 0, function(commits, err)
            if err or not commits or #commits == 0 then
              vim.notify("No commits found", vim.log.levels.WARN)
              return
            end
            local_state.current_branch = current_branch
            table.insert(commits, 1, { sha = nil, message = "Current changes" })
            local_state.branch_commits = commits
            activate_mode(repo_root, rows, cols,
              string.format("Local commit viewer: %d commits loaded", #commits - 1))
          end)
          return
        end

        -- Feature branch: find merge-base and split
        git.merge_base(repo_root, "HEAD", default_branch, function(merge_sha, merge_err)
          if merge_err or not merge_sha then
            -- Merge-base failed: flat mode fallback
            git.log_all_commits(repo_root, BATCH_SIZE, 0, function(commits, err)
              if err or not commits or #commits == 0 then
                vim.notify("No commits found", vim.log.levels.WARN)
                return
              end
              local_state.current_branch = current_branch
              table.insert(commits, 1, { sha = nil, message = "Current changes" })
              local_state.branch_commits = commits
              activate_mode(repo_root, rows, cols,
                string.format("Local commit viewer: %d commits loaded", #commits - 1))
            end)
            return
          end

          -- Branch mode: load branch commits and base commits in parallel
          local pending = 2
          local branch_result, base_result

          local function on_both_ready()
            local branch_commits = branch_result or {}
            local base_commits = base_result or {}
            table.insert(branch_commits, 1, { sha = nil, message = "Current changes" })
            local_state.current_branch = current_branch
            local_state.base_branch = default_branch
            local_state.merge_base_sha = merge_sha
            local_state.branch_commits = branch_commits
            local_state.base_commits = base_commits
            local_state.total_base_loaded = #base_commits
            activate_mode(repo_root, rows, cols,
              string.format("Local commit viewer: %d branch + %d base commits",
                #branch_commits - 1, #base_commits))
          end

          local function check_done()
            pending = pending - 1
            if pending == 0 then on_both_ready() end
          end

          git.log_branch_commits(repo_root, merge_sha, function(commits, _)
            branch_result = commits
            check_done()
          end)

          git.log_from_ref(repo_root, merge_sha, base_count, 0, function(commits, _)
            base_result = commits
            check_done()
          end)
        end)
      end)
    end)
  end)
end

--- Exit local commit viewer mode
local function exit_local_mode()
  stop_poll_timer()
  stop_workdir_poll_timer()

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
  if local_state.pr_was_active then
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
