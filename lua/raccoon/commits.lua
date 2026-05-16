---@class RaccoonCommits
---Commit viewer mode: sidebar with commits, grid of diff hunks
local M = {}

local get_commit
local comments = require("raccoon.comments")
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

--- Preserved state while switching between flat diff and commit mode.
local mode_restore_state = {
  review = nil,
  commit_view = nil,
}

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
  popup_win = nil,
  select_generation = 0,
  cached_sha = nil,
  cached_tree_lines = nil,
  cached_line_paths = nil,
  cached_stat_lines = nil,
  cached_file_count = nil,
  focus_target = "sidebar",
  orig_grid_rows = nil,
  orig_grid_cols = nil,
  preview_generation = 0,
  sidebar_width = nil,
  pending_view_restore = nil,
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
    popup_win = nil,
    select_generation = 0,
    cached_sha = nil,
    cached_tree_lines = nil,
    cached_line_paths = nil,
    cached_stat_lines = nil,
    cached_file_count = nil,
    focus_target = "sidebar",
    orig_grid_rows = nil,
    orig_grid_cols = nil,
    preview_generation = 0,
    sidebar_width = nil,
    pending_view_restore = nil,
  }
end

---@return string|nil
local function current_review_session_key()
  local url = state.get_url()
  if url and url ~= "" then
    return url
  end

  local owner = state.get_owner()
  local repo = state.get_repo()
  local number = state.get_number()
  if owner and repo and number then
    return string.format("%s/%s#%s", owner, repo, tostring(number))
  end

  return nil
end

---@param snapshot table|nil
---@return boolean
local function snapshot_has_unsent_text(snapshot)
  if not snapshot or snapshot.kind ~= "editor" then
    return false
  end
  return table.concat(snapshot.input_lines or {}, "\n"):match("%S") ~= nil
end

---@return string|nil
local function current_review_path()
  local clone_path = state.get_clone_path()
  if not clone_path or clone_path == "" then
    return nil
  end
  local name = vim.api.nvim_buf_get_name(0)
  if name:sub(1, #clone_path) ~= clone_path then
    return nil
  end
  return name:sub(#clone_path + 2):gsub("\\", "/")
end

---@param path string|nil
---@return number|nil, table|nil
local function find_review_file(path)
  if not path then
    return nil, nil
  end
  for idx, file in ipairs(state.get_files()) do
    if file.filename == path then
      return idx, file
    end
  end
  return nil, nil
end

---@param path string|nil
---@return number|nil
local function find_review_buffer(path)
  if not path then
    return nil
  end
  local clone_path = state.get_clone_path()
  if not clone_path or clone_path == "" then
    return nil
  end
  local full_path = vim.fs.joinpath(clone_path, path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == full_path then
      return buf
    end
  end
  return nil
end

---@return table
local function capture_review_snapshot()
  local overlay = comments.capture_ui_state()
  local current_file = state.get_current_file()
  local path = current_review_path() or (current_file and current_file.filename or nil)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = cursor and cursor[1] or 1
  local col = cursor and cursor[2] or 0

  if overlay and overlay.path then
    path = overlay.path
    line = overlay.line or line
    col = 0
  end

  return {
    session_key = current_review_session_key(),
    path = path,
    line = line,
    col = col,
    selected_thread_id = state.get_selected_thread_id(),
    overlay = overlay,
    saved_buf = find_review_buffer(path) or vim.api.nvim_get_current_buf(),
  }
end

---@param snapshot table|nil
---@return boolean
local function restore_review_buffer(snapshot)
  if not snapshot then
    return false
  end

  local _, file = find_review_file(snapshot.path)
  if file then
    local buf = diff.open_file(file)
    if buf then
      comments.show_comments(buf, state.get_comments(file.filename))
      local line_count = vim.api.nvim_buf_line_count(buf)
      local target_line = math.max(1, math.min(snapshot.line or 1, line_count))
      local line_text = vim.api.nvim_buf_get_lines(buf, target_line - 1, target_line, false)[1] or ""
      local target_col = math.max(0, math.min(snapshot.col or 0, #line_text))
      vim.api.nvim_win_set_cursor(0, { target_line, target_col })
      vim.cmd("normal! zz")
      return true
    end
  end

  if snapshot.saved_buf and vim.api.nvim_buf_is_valid(snapshot.saved_buf) then
    vim.api.nvim_set_current_buf(snapshot.saved_buf)
    return true
  end

  return false
end

---@param snapshot table|nil
local function restore_review_snapshot(snapshot)
  if not snapshot or snapshot.session_key ~= current_review_session_key() then
    return
  end

  if snapshot.selected_thread_id then
    state.set_selected_thread_id(snapshot.selected_thread_id)
  end
  restore_review_buffer(snapshot)
  if snapshot.overlay then
    comments.restore_ui_state(snapshot.overlay)
  end
end

---@param selected_sha string|nil
---@param prefer_pr_section boolean
---@param preferred_section_index number|nil
---@param pr_commits table[]
---@param base_commits table[]
---@return number|nil
local function choose_commit_index(selected_sha, prefer_pr_section, preferred_section_index, pr_commits, base_commits)
  if selected_sha then
    for idx, commit in ipairs(pr_commits or {}) do
      if commit.sha == selected_sha then
        return idx
      end
    end
    for idx, commit in ipairs(base_commits or {}) do
      if commit.sha == selected_sha then
        return #pr_commits + idx
      end
    end
  end

  local section = prefer_pr_section and pr_commits or base_commits
  if section and #section > 0 then
    local section_index = math.max(1, math.min(preferred_section_index or 1, #section))
    return prefer_pr_section and section_index or (#pr_commits + section_index)
  end

  if pr_commits and #pr_commits > 0 then
    return 1
  end
  if base_commits and #base_commits > 0 then
    return #pr_commits + 1
  end
  return nil
end

---@return table
local function capture_commit_view_snapshot()
  local selected_commit = get_commit(commit_state.selected_index)
  local filetree_cursor = nil
  if commit_state.filetree_win and vim.api.nvim_win_is_valid(commit_state.filetree_win) then
    filetree_cursor = vim.api.nvim_win_get_cursor(commit_state.filetree_win)[1]
  end

  local prefer_pr_section = commit_state.selected_index <= #commit_state.pr_commits
  local section_index = prefer_pr_section
    and commit_state.selected_index
    or (commit_state.selected_index - #commit_state.pr_commits)

  return {
    session_key = current_review_session_key(),
    selected_sha = selected_commit and selected_commit.sha or nil,
    prefer_pr_section = prefer_pr_section,
    preferred_section_index = section_index,
    current_page = commit_state.current_page,
    focus_target = commit_state.focus_target,
    filetree_cursor = filetree_cursor,
  }
end

---@return table|nil
local function active_commit_view_snapshot()
  local snapshot = mode_restore_state.commit_view
  if snapshot and snapshot.session_key == current_review_session_key() then
    return snapshot
  end
  return nil
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
get_commit = function(index)
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

local function commit_filetree_opts()
  return {
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
    get_is_working_dir = function() return false end,
    apply_keymaps = function(bufs) ui.apply_keymaps_to_bufs(commit_mode_keymaps, bufs) end,
    render_page = render_grid_page,
  }
end

local function apply_pending_view_restore(generation)
  local pending = commit_state.pending_view_restore
  if not pending or pending.generation ~= generation then
    return
  end

  commit_state.pending_view_restore = nil

  if #commit_state.all_hunks > 0 then
    commit_state.current_page = math.max(1, math.min(pending.current_page or 1, total_pages()))
    render_grid_page()
  end

  if pending.focus_target == "filetree" then
    local filetree_opts = commit_filetree_opts()
    if commit_state.focus_target ~= "filetree" then
      ui.toggle_filetree_focus(commit_state, filetree_opts)
    end
    if commit_state.filetree_win and vim.api.nvim_win_is_valid(commit_state.filetree_win) then
      local max_line = vim.api.nvim_buf_line_count(commit_state.filetree_buf)
      local target_line = math.max(1, math.min(pending.filetree_cursor or 1, max_line))
      pcall(vim.api.nvim_win_set_cursor, commit_state.filetree_win, { target_line, 0 })
      ui._preview_file_at_cursor(commit_state, filetree_opts)
      vim.api.nvim_set_current_win(commit_state.filetree_win)
    end
  elseif commit_state.sidebar_win and vim.api.nvim_win_is_valid(commit_state.sidebar_win) then
    vim.api.nvim_set_current_win(commit_state.sidebar_win)
  end
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
  if not commit then return end
  local clone_path = state.get_clone_path()
  if not clone_path then return end

  ui.fetch_full_message(commit_state, commit, clone_path, generation, total_pages)

  local context = ui.compute_grid_context(commit_state.grid_rows)
  git.show_commit(clone_path, commit.sha, context, function(files, err)
    if generation ~= commit_state.select_generation then return end

    if err then
      vim.notify("Failed to get commit diff", vim.log.levels.ERROR)
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
      apply_pending_view_restore(generation)
      return
    end

    render_grid_page()
    apply_pending_view_restore(generation)
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
    sidebar_width = commit_state.sidebar_width,
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

--- Setup commit mode keymaps (buffer-local to all commit-mode buffers)
local function setup_keymaps()
  local shortcuts = config.load_shortcuts()

  local all = {
    {
      mode = NORMAL_MODE, lhs = shortcuts.commit_viewer.exit,
      rhs = function() M.toggle() end, desc = "Exit commit viewer",
    },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_viewer.next_page, rhs = next_page, desc = "Next page of hunks" },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_viewer.prev_page, rhs = prev_page, desc = "Previous page of hunks" },
    { mode = NORMAL_MODE, lhs = shortcuts.commit_viewer.next_page_alt, rhs = next_page, desc = "Next page of hunks" },
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
  if config.is_enabled(shortcuts.commit_viewer.maximize_prefix) then
    local cells = commit_state.grid_rows * commit_state.grid_cols
    for i = 1, cells do
      table.insert(commit_mode_keymaps, {
        mode = NORMAL_MODE,
        lhs = shortcuts.commit_viewer.maximize_prefix .. i,
        rhs = function() maximize_cell(i) end,
        desc = "Maximize grid cell " .. i,
      })
    end
  end

  local filetree_opts = commit_filetree_opts()

  -- Browse files toggle
  if config.is_enabled(shortcuts.commit_viewer.browse_files) then
    table.insert(commit_mode_keymaps, {
      mode = NORMAL_MODE,
      lhs = shortcuts.commit_viewer.browse_files,
      rhs = function() ui.toggle_filetree_focus(commit_state, filetree_opts) end,
      desc = "Toggle file tree browsing",
    })
  end

  -- Apply keymaps buffer-locally
  local commit_bufs = ui.collect_bufs(commit_state)
  ui.apply_keymaps_to_bufs(commit_mode_keymaps, commit_bufs)
  for _, buf in ipairs(commit_bufs) do
    keymaps.setup_buffer(buf)
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
  ui.setup_filetree_nav(commit_state, filetree_opts)

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

  mode_restore_state.review = capture_review_snapshot()
  comments.close_overlays(true)
  local ok_ui, ui_mod = pcall(require, "raccoon.ui")
  if ok_ui and ui_mod.close_description then
    ui_mod.close_description()
  end
  if ok_ui and ui_mod.close_pr_list then
    ui_mod.close_pr_list()
  end

  commit_state.saved_buf = mode_restore_state.review.saved_buf or vim.api.nvim_get_current_buf()
  ui.save_vim_options(commit_state)

  keymaps.clear()
  open.pause_sync()
  state.set_commit_mode(true)
  commit_state.active = true

  local rows, cols, base_count = ui.load_viewer_config()

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
        local resume = active_commit_view_snapshot()
        local initial_index = 1
        if resume then
          initial_index = choose_commit_index(
            resume.selected_sha,
            resume.prefer_pr_section,
            resume.preferred_section_index,
            commit_state.pr_commits,
            commit_state.base_commits
          ) or 1
        end
        select_commit(initial_index)
        if resume then
          commit_state.pending_view_restore = {
            generation = commit_state.select_generation,
            current_page = resume.current_page or 1,
            focus_target = resume.focus_target or "sidebar",
            filetree_cursor = resume.filetree_cursor,
          }
        end
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
          vim.notify("Failed to load base commits: " .. tostring(err), vim.log.levels.WARN)
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
---@param opts table|nil { resume_sync?: boolean }
local function exit_commit_mode(opts)
  opts = opts or {}
  if not commit_state.active then
    commit_mode_keymaps = {}
    state.set_commit_mode(false)
    if opts.resume_sync ~= false then
      open.resume_sync()
    end
    reset_state()
    return
  end

  mode_restore_state.commit_view = capture_commit_view_snapshot()

  if commit_state.focus_augroup then
    local ok, err = pcall(vim.api.nvim_del_augroup_by_id, commit_state.focus_augroup)
    if not ok then
      vim.notify("Failed to delete focus lock augroup: " .. tostring(err), vim.log.levels.DEBUG)
    end
  end

  ui.close_win_pair(commit_state, "maximize_win", "maximize_buf")
  commit_mode_keymaps = {}
  ui.close_grid(commit_state)
  ui.close_win_pair(commit_state, "sidebar_win", "sidebar_buf")
  ui.close_win_pair(commit_state, "filetree_win", "filetree_buf")

  state.set_commit_mode(false)

  ui.restore_vim_options(commit_state)

  vim.cmd("only")
  restore_review_snapshot(mode_restore_state.review)
  mode_restore_state.review = nil

  keymaps.setup()
  if opts.resume_sync ~= false then
    open.resume_sync()
  end

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

--- Exit commit viewer mode (safe to call when not active)
---@param opts table|nil { resume_sync?: boolean }
function M.exit_commit_mode(opts)
  exit_commit_mode(opts)
end

--- Allow a popup window while commit mode focus lock is active
---@param win number|nil
function M.set_popup_win(win)
  commit_state.popup_win = win
end

--- Clear the commit mode popup window exception
function M.clear_popup_win()
  commit_state.popup_win = nil
end

function M.refresh_after_sync()
  if not commit_state.active then
    return
  end

  local pr = state.get_pr()
  local clone_path = state.get_clone_path()
  if not pr or not clone_path then
    return
  end

  local selected_commit = get_commit(commit_state.selected_index)
  local selected_sha = selected_commit and selected_commit.sha or nil
  local was_in_pr_section = commit_state.selected_index <= #commit_state.pr_commits
  local section_index = was_in_pr_section
    and commit_state.selected_index
    or (commit_state.selected_index - #commit_state.pr_commits)
  local _, _, base_count = ui.load_viewer_config()
  local base_branch = pr.base.ref
  local pending = 2
  local next_pr_commits = commit_state.pr_commits
  local next_base_commits = commit_state.base_commits

  local function apply_refresh()
    commit_state.pr_commits = next_pr_commits or {}
    commit_state.base_commits = next_base_commits or {}
    render_sidebar()
    local next_index = choose_commit_index(
      selected_sha,
      was_in_pr_section,
      section_index,
      next_pr_commits,
      next_base_commits
    )
    if next_index then
      commit_state.selected_index = next_index
      update_sidebar_selection()
      select_commit(next_index)
    else
      ui.update_header(commit_state, nil, total_pages())
    end
  end

  local function on_done()
    pending = pending - 1
    if pending == 0 then
      vim.schedule(apply_refresh)
    end
  end

  git.log_commits(clone_path, base_branch, function(commits, err)
    if err then
      vim.notify("Failed to refresh PR commits: " .. tostring(err), vim.log.levels.WARN)
    else
      next_pr_commits = commits or {}
    end
    on_done()
  end)

  git.log_base_commits(clone_path, base_branch, base_count, function(commits, err)
    if err then
      vim.notify("Failed to refresh base commits: " .. tostring(err), vim.log.levels.WARN)
    else
      next_base_commits = commits or {}
    end
    on_done()
  end)
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
M.has_hidden_review_draft = function()
  local snapshot = mode_restore_state.review
  return snapshot
    and snapshot.session_key == current_review_session_key()
    and snapshot_has_unsent_text(snapshot.overlay)
    or false
end
M.clear_mode_restore_state = function()
  mode_restore_state.review = nil
  mode_restore_state.commit_view = nil
end
M._capture_review_snapshot = capture_review_snapshot
M._restore_review_snapshot = restore_review_snapshot
M._capture_commit_view_snapshot = capture_commit_view_snapshot
M._choose_commit_index = choose_commit_index
M._set_mode_restore_state = function(review_snapshot, commit_snapshot)
  mode_restore_state.review = review_snapshot
  mode_restore_state.commit_view = commit_snapshot
end
M._get_mode_restore_state = function()
  return mode_restore_state
end

return M
