local commits = require("raccoon.commits")
local config = require("raccoon.config")
local git = require("raccoon.git")
local state = require("raccoon.state")

describe("raccoon.commits", function()
  before_each(function()
    state.reset()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(commits)
    end)

    it("has toggle function", function()
      assert.is_function(commits.toggle)
    end)
  end)

  describe("toggle without active session", function()
    it("does nothing when no PR session", function()
      local original_notify = vim.notify
      vim.notify = function() end
      commits.toggle()
      vim.notify = original_notify
    end)
  end)
end)

describe("raccoon.git commit operations", function()
  -- Detect whether origin/main is reachable (may be absent in CI shallow clones,
  -- repos with master default branch, or repos without an origin remote)
  local has_origin_main = vim.fn.system("git rev-parse --verify origin/main 2>/dev/null"):match("^%x+") ~= nil
  local is_shallow = vim.fn.system("git rev-parse --is-shallow-repository"):match("true") ~= nil
  local can_diff = has_origin_main and not is_shallow

  describe("new functions exist", function()
    it("has unshallow_if_needed function", function()
      assert.is_function(git.unshallow_if_needed)
    end)

    it("has fetch_branch function", function()
      assert.is_function(git.fetch_branch)
    end)

    it("has log_commits function", function()
      assert.is_function(git.log_commits)
    end)

    it("has log_base_commits function", function()
      assert.is_function(git.log_base_commits)
    end)

    it("has show_commit function", function()
      assert.is_function(git.show_commit)
    end)

    it("has show_commit_file function", function()
      assert.is_function(git.show_commit_file)
    end)
  end)

  describe("log_commits on current repo", function()
    it("returns commits or error depending on origin/main availability", function()
      local done = false
      local result_commits = nil
      local result_err = nil

      git.log_commits(vim.fn.getcwd(), "main", function(commits_list, err)
        result_commits = commits_list
        result_err = err
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)

      if has_origin_main then
        assert.is_table(result_commits)
      else
        -- origin/main missing: git returns (nil, err_string)
        assert.is_nil(result_commits)
        assert.is_string(result_err)
      end
    end)
  end)

  describe("log_base_commits on current repo", function()
    it("returns recent commits from base branch", function()
      if not has_origin_main then return end

      local done = false
      local result_commits = nil

      git.log_base_commits(vim.fn.getcwd(), "main", 5, function(commits_list, err)
        result_commits = commits_list
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_table(result_commits)
      assert.is_true(#result_commits > 0)
    end)

    it("each commit has sha and message", function()
      if not has_origin_main then return end

      local done = false
      local result_commits = nil

      git.log_base_commits(vim.fn.getcwd(), "main", 3, function(commits_list, err)
        result_commits = commits_list
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)

      for _, commit in ipairs(result_commits) do
        assert.is_string(commit.sha)
        assert.equals(40, #commit.sha)
        assert.is_string(commit.message)
      end
    end)
  end)

  describe("show_commit on current repo", function()
    it("returns file diffs for a commit", function()
      if not can_diff then return end

      local done = false
      local sha = nil

      git.log_base_commits(vim.fn.getcwd(), "main", 1, function(commits_list, err)
        if commits_list and #commits_list > 0 then
          sha = commits_list[1].sha
        end
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_not_nil(sha)

      done = false
      local result_files = nil

      git.show_commit(vim.fn.getcwd(), sha, function(files, err)
        result_files = files
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_table(result_files)

      for _, file in ipairs(result_files) do
        assert.is_string(file.filename)
        assert.is_string(file.patch)
      end
    end)

    it("never returns dev/null as filename", function()
      if not can_diff then return end

      local done = false
      local sha = nil

      git.log_base_commits(vim.fn.getcwd(), "main", 10, function(commits_list, err)
        if commits_list and #commits_list > 0 then
          sha = commits_list[1].sha
        end
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_not_nil(sha)

      done = false
      local result_files = nil

      git.show_commit(vim.fn.getcwd(), sha, function(files, err)
        result_files = files
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_table(result_files)

      for _, file in ipairs(result_files) do
        assert.is_not_equal("dev/null", file.filename)
      end
    end)
  end)

  describe("show_commit_file on current repo", function()
    it("returns full-context patch for a file", function()
      if not can_diff then return end

      local done = false
      local sha = nil
      local first_filename = nil

      git.log_base_commits(vim.fn.getcwd(), "main", 1, function(commits_list, err)
        if commits_list and #commits_list > 0 then
          sha = commits_list[1].sha
        end
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_not_nil(sha)

      done = false
      git.show_commit(vim.fn.getcwd(), sha, function(files, err)
        if files and #files > 0 then
          first_filename = files[1].filename
        end
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_not_nil(first_filename)

      done = false
      local result_patch = nil

      git.show_commit_file(vim.fn.getcwd(), sha, first_filename, function(patch, err)
        result_patch = patch
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_string(result_patch)
      assert.is_truthy(result_patch:match("^@@"))
    end)
  end)

  describe("unshallow_if_needed", function()
    it("succeeds on non-shallow repo", function()
      local done = false
      local result_success = nil

      git.unshallow_if_needed(vim.fn.getcwd(), function(success, err)
        result_success = success
        done = true
      end)

      vim.wait(5000, function() return done end)
      assert.is_true(done)
      assert.is_true(result_success)
    end)
  end)
end)

describe("raccoon.state commit mode", function()
  before_each(function()
    state.reset()
  end)

  it("is_commit_mode returns false by default", function()
    assert.is_false(state.is_commit_mode())
  end)

  it("set_commit_mode changes state", function()
    state.set_commit_mode(true)
    assert.is_true(state.is_commit_mode())
  end)

  it("reset clears commit mode", function()
    state.set_commit_mode(true)
    state.reset()
    assert.is_false(state.is_commit_mode())
  end)
end)

describe("raccoon.commits keybinding lockdown", function()
  local function create_scratch_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    return buf
  end

  local function has_buf_keymap(buf, mode, lhs)
    local maps = vim.api.nvim_buf_get_keymap(buf, mode)
    for _, map in ipairs(maps) do
      if map.lhs == lhs then
        return true
      end
    end
    return false
  end

  describe("_lock_buf", function()
    it("is exposed for testing", function()
      assert.is_function(commits._lock_buf)
    end)

    it("blocks colon on buffer", function()
      local buf = create_scratch_buf()
      commits._lock_buf(buf)
      assert.is_true(has_buf_keymap(buf, "n", ":"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("blocks insert mode keys", function()
      local buf = create_scratch_buf()
      commits._lock_buf(buf)
      for _, key in ipairs({ "i", "I", "a", "A", "o", "O" }) do
        assert.is_true(has_buf_keymap(buf, "n", key), "expected " .. key .. " to be blocked")
      end
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("blocks editing keys", function()
      local buf = create_scratch_buf()
      commits._lock_buf(buf)
      for _, key in ipairs({ "d", "x", "p", "P" }) do
        assert.is_true(has_buf_keymap(buf, "n", key), "expected " .. key .. " to be blocked")
      end
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("blocks quit shortcuts", function()
      local buf = create_scratch_buf()
      commits._lock_buf(buf)
      assert.is_true(has_buf_keymap(buf, "n", "ZZ"))
      assert.is_true(has_buf_keymap(buf, "n", "ZQ"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("blocks macro recording", function()
      local buf = create_scratch_buf()
      commits._lock_buf(buf)
      assert.is_true(has_buf_keymap(buf, "n", "q"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("does not block j or k", function()
      local buf = create_scratch_buf()
      commits._lock_buf(buf)
      assert.is_false(has_buf_keymap(buf, "n", "j"))
      assert.is_false(has_buf_keymap(buf, "n", "k"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles invalid buffer gracefully", function()
      -- Should not error
      commits._lock_buf(nil)
      commits._lock_buf(99999)
    end)
  end)

  describe("_lock_maximize_buf", function()
    it("is exposed for testing", function()
      assert.is_function(commits._lock_maximize_buf)
    end)

    it("does not block colon (allows ex commands)", function()
      local buf = create_scratch_buf()
      commits._lock_maximize_buf(buf)
      assert.is_false(has_buf_keymap(buf, "n", ":"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("does not block q (used for close)", function()
      local buf = create_scratch_buf()
      commits._lock_maximize_buf(buf)
      assert.is_false(has_buf_keymap(buf, "n", "q"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("blocks insert mode keys", function()
      local buf = create_scratch_buf()
      commits._lock_maximize_buf(buf)
      for _, key in ipairs({ "i", "I", "a", "A", "o", "O" }) do
        assert.is_true(has_buf_keymap(buf, "n", key), "expected " .. key .. " to be blocked")
      end
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("blocks page navigation keys", function()
      local buf = create_scratch_buf()
      commits._lock_maximize_buf(buf)
      assert.is_true(has_buf_keymap(buf, "n", " j"))
      assert.is_true(has_buf_keymap(buf, "n", " k"))
      assert.is_true(has_buf_keymap(buf, "n", " l"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("blocks commit viewer exit key", function()
      local buf = create_scratch_buf()
      commits._lock_maximize_buf(buf)
      assert.is_true(has_buf_keymap(buf, "n", " cm"))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("blocks cell maximize keys", function()
      local buf = create_scratch_buf()
      commits._lock_maximize_buf(buf)
      -- Default 2x2 grid = 4 cells
      for i = 1, 4 do
        assert.is_true(has_buf_keymap(buf, "n", " m" .. i), "expected <leader>m" .. i .. " to be blocked")
      end
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("handles invalid buffer gracefully", function()
      -- Should not error
      commits._lock_maximize_buf(nil)
      commits._lock_maximize_buf(99999)
    end)
  end)
end)

describe("raccoon.commits select_generation guard", function()
  it("exposes _get_state for testing", function()
    assert.is_function(commits._get_state)
  end)

  it("exposes _select_commit for testing", function()
    assert.is_function(commits._select_commit)
  end)

  it("has select_generation starting at 0", function()
    local cs = commits._get_state()
    assert.is_number(cs.select_generation)
    assert.equals(0, cs.select_generation)
  end)

  describe("stale callback handling", function()
    local original_show_commit
    local captured_callback

    before_each(function()
      original_show_commit = git.show_commit
      git.show_commit = function(_, _, cb)
        captured_callback = cb
      end
      local cs = commits._get_state()
      cs.pr_commits = {
        { sha = "aaaa", message = "commit 1" },
        { sha = "bbbb", message = "commit 2" },
      }
      cs.active = true
      cs.grid_bufs = {}
      cs.grid_wins = {}
      cs.all_hunks = {}
      cs.select_generation = 0
      state.session = state.session or {}
      state.session.clone_path = "/tmp/fake"
    end)

    after_each(function()
      git.show_commit = original_show_commit
      state.reset()
    end)

    it("discards stale callback when generation has advanced", function()
      local cs = commits._get_state()

      commits._select_commit(1)
      local stale_cb = captured_callback
      assert.equals(1, cs.select_generation)

      commits._select_commit(2)
      assert.equals(2, cs.select_generation)

      -- Fire the stale callback — should be silently discarded
      stale_cb({ { filename = "stale.lua", patch = "@@ -1,1 +1,1 @@\n-old\n+new" } }, nil)
      assert.equals(0, #cs.all_hunks)
    end)

    it("accepts callback when generation matches", function()
      local cs = commits._get_state()

      commits._select_commit(1)
      local cb = captured_callback
      assert.equals(1, cs.select_generation)

      -- Fire the current callback — should be accepted
      cb({ { filename = "fresh.lua", patch = "@@ -1,1 +1,1 @@\n-old\n+new" } }, nil)
      assert.is_true(#cs.all_hunks > 0)
    end)
  end)
end)

describe("raccoon.commits error message sanitization", function()
  local source

  before_each(function()
    if not source then
      local src_path = vim.fn.getcwd() .. "/lua/raccoon/commits.lua"
      local f = io.open(src_path, "r")
      assert.is_truthy(f, "could not open commits.lua")
      source = f:read("*a")
      f:close()
    end
  end)

  it("does not expose raw err in ERROR notifications", function()
    for line in source:gmatch("[^\n]+") do
      if line:match("vim%.notify%(") and line:match("levels%.ERROR") then
        assert.is_falsy(
          line:match('%.%.%s*err') or line:match('%.%.%s*fetch_err') or line:match('%.%.%s*unshallow_err'),
          "ERROR notify should not concatenate raw error: " .. line
        )
      end
    end
  end)

  it("does not expose raw err in WARN notifications", function()
    for line in source:gmatch("[^\n]+") do
      if line:match("vim%.notify%(") and line:match("levels%.WARN") then
        assert.is_falsy(
          line:match('%.%.%s*err') or line:match('%.%.%s*fetch_err') or line:match('%.%.%s*unshallow_err'),
          "WARN notify should not concatenate raw error: " .. line
        )
      end
    end
  end)

  it("logs raw errors at DEBUG level for diagnostics", function()
    local debug_lines = {}
    for line in source:gmatch("[^\n]+") do
      if line:match("vim%.notify%(") and line:match("levels%.DEBUG") then
        table.insert(debug_lines, line)
      end
    end
    assert.is_true(#debug_lines >= 4, "expected at least 4 DEBUG log lines, got " .. #debug_lines)
  end)
end)

describe("raccoon.config commit_viewer defaults", function()
  it("has commit_viewer in defaults", function()
    assert.is_table(config.defaults.commit_viewer)
  end)

  it("has grid config with rows and cols", function()
    assert.is_table(config.defaults.commit_viewer.grid)
    assert.equals(2, config.defaults.commit_viewer.grid.rows)
    assert.equals(2, config.defaults.commit_viewer.grid.cols)
  end)

  it("has base_commits_count default", function()
    assert.equals(20, config.defaults.commit_viewer.base_commits_count)
  end)
end)

describe("raccoon.commits buffer-local keymaps", function()
  local function create_scratch_buf()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    return buf
  end

  local function has_buf_keymap(buf, mode, lhs)
    local maps = vim.api.nvim_buf_get_keymap(buf, mode)
    for _, map in ipairs(maps) do
      if map.lhs == lhs then
        return true
      end
    end
    return false
  end

  local function has_global_keymap(mode, lhs)
    local maps = vim.api.nvim_get_keymap(mode)
    for _, map in ipairs(maps) do
      if map.lhs == lhs then
        return true
      end
    end
    return false
  end

  local cs
  local bufs_to_clean = {}

  before_each(function()
    cs = commits._get_state()
    cs.sidebar_buf = create_scratch_buf()
    cs.header_buf = create_scratch_buf()
    cs.grid_bufs = {
      create_scratch_buf(),
      create_scratch_buf(),
      create_scratch_buf(),
      create_scratch_buf(),
    }
    cs.grid_rows = 2
    cs.grid_cols = 2
    bufs_to_clean = { cs.sidebar_buf, cs.header_buf }
    for _, buf in ipairs(cs.grid_bufs) do
      table.insert(bufs_to_clean, buf)
    end
  end)

  after_each(function()
    for _, buf in ipairs(bufs_to_clean) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    bufs_to_clean = {}
  end)

  describe("_setup_keymaps", function()
    it("is exposed for testing", function()
      assert.is_function(commits._setup_keymaps)
    end)

    it("applies <leader>cm buffer-locally to all buffers", function()
      commits._setup_keymaps()
      assert.is_true(has_buf_keymap(cs.sidebar_buf, "n", " cm"))
      assert.is_true(has_buf_keymap(cs.header_buf, "n", " cm"))
      for _, buf in ipairs(cs.grid_bufs) do
        assert.is_true(has_buf_keymap(buf, "n", " cm"))
      end
    end)

    it("applies navigation keymaps buffer-locally", function()
      commits._setup_keymaps()
      for _, key in ipairs({ " j", " k", " l" }) do
        assert.is_true(has_buf_keymap(cs.sidebar_buf, "n", key),
          "expected " .. key .. " on sidebar")
        for _, buf in ipairs(cs.grid_bufs) do
          assert.is_true(has_buf_keymap(buf, "n", key),
            "expected " .. key .. " on grid buf")
        end
      end
    end)

    it("applies <C-w> blocks buffer-locally", function()
      commits._setup_keymaps()
      assert.is_true(has_buf_keymap(cs.sidebar_buf, "n", "<C-W>h"))
      assert.is_true(has_buf_keymap(cs.grid_bufs[1], "n", "<C-W>l"))
    end)

    it("applies <leader>m<N> keymaps buffer-locally", function()
      commits._setup_keymaps()
      for i = 1, 4 do
        assert.is_true(has_buf_keymap(cs.sidebar_buf, "n", " m" .. i),
          "expected <leader>m" .. i .. " on sidebar")
      end
    end)

    it("does NOT create global keymaps", function()
      -- Snapshot global keymaps for keys we care about
      local keys = { " cm", " j", " k", " l", " m1", " m2" }
      local before = {}
      for _, key in ipairs(keys) do
        before[key] = has_global_keymap("n", key)
      end

      commits._setup_keymaps()

      -- No new global keymaps should have been added
      for _, key in ipairs(keys) do
        assert.equals(before[key], has_global_keymap("n", key),
          "global keymap " .. key .. " was unexpectedly added")
      end
    end)

    it("handles invalid buffers gracefully", function()
      cs.sidebar_buf = 99999
      cs.header_buf = nil
      cs.grid_bufs = { 99998 }
      -- Should not error
      commits._setup_keymaps()
    end)
  end)
end)

describe("raccoon.commits input validation", function()
  describe("_clamp_int", function()
    it("is exposed for testing", function()
      assert.is_function(commits._clamp_int)
    end)

    it("returns default for nil", function()
      assert.equals(2, commits._clamp_int(nil, 2, 1, 10))
    end)

    it("returns default for string", function()
      assert.equals(2, commits._clamp_int("three", 2, 1, 10))
    end)

    it("returns default for boolean", function()
      assert.equals(2, commits._clamp_int(true, 2, 1, 10))
    end)

    it("returns default for table", function()
      assert.equals(2, commits._clamp_int({}, 2, 1, 10))
    end)

    it("returns value when within range", function()
      assert.equals(3, commits._clamp_int(3, 2, 1, 10))
    end)

    it("clamps to min when below range", function()
      assert.equals(1, commits._clamp_int(0, 2, 1, 10))
      assert.equals(1, commits._clamp_int(-5, 2, 1, 10))
    end)

    it("clamps to max when above range", function()
      assert.equals(10, commits._clamp_int(99, 2, 1, 10))
    end)

    it("floors fractional numbers", function()
      assert.equals(2, commits._clamp_int(2.9, 2, 1, 10))
      assert.equals(1, commits._clamp_int(1.5, 2, 1, 10))
    end)

    it("handles exact boundary values", function()
      assert.equals(1, commits._clamp_int(1, 2, 1, 10))
      assert.equals(10, commits._clamp_int(10, 2, 1, 10))
    end)
  end)
end)

describe("raccoon.commits file tree panel", function()
  before_each(function()
    state.reset()
  end)

  it("exposes _render_filetree for testing", function()
    assert.is_function(commits._render_filetree)
  end)

  it("has filetree_win and filetree_buf in state", function()
    local cs = commits._get_state()
    assert.is_nil(cs.filetree_win)
    assert.is_nil(cs.filetree_buf)
  end)

  it("render_filetree handles nil buffer gracefully", function()
    local cs = commits._get_state()
    cs.filetree_buf = nil
    -- Should not error
    commits._render_filetree()
  end)

  it("render_filetree handles invalid buffer gracefully", function()
    local cs = commits._get_state()
    cs.filetree_buf = 99999
    -- Should not error
    commits._render_filetree()
  end)

  describe("_build_file_tree", function()
    it("builds tree from flat paths", function()
      local tree = commits._build_file_tree({ "a/b.lua", "a/c.lua", "d.lua" })
      assert.equals(2, #tree.children) -- "a/" dir + "d.lua" file
    end)

    it("handles empty input", function()
      local tree = commits._build_file_tree({})
      assert.equals(0, #tree.children)
    end)

    it("nests deeply", function()
      local tree = commits._build_file_tree({ "a/b/c/d.lua" })
      assert.equals("a", tree.children[1].name)
      assert.equals("b", tree.children[1].children[1].name)
      assert.equals("c", tree.children[1].children[1].children[1].name)
      assert.equals("d.lua", tree.children[1].children[1].children[1].children[1].name)
    end)
  end)

  describe("_render_tree_node", function()
    it("renders with tree characters", function()
      local tree = commits._build_file_tree({ "a/b.lua", "c.lua" })
      local lines = {}
      local line_paths = {}
      commits._render_tree_node(tree, "", lines, line_paths)
      assert.is_true(#lines > 0)
      -- Should contain tree drawing characters
      local joined = table.concat(lines, "\n")
      assert.is_truthy(joined:match("[├└│]"))
    end)

    it("maps file lines to paths", function()
      local tree = commits._build_file_tree({ "x.lua", "y.lua" })
      local lines = {}
      local line_paths = {}
      commits._render_tree_node(tree, "", lines, line_paths)
      -- Both files should have path mappings
      local mapped = 0
      for _ in pairs(line_paths) do mapped = mapped + 1 end
      assert.equals(2, mapped)
    end)

    it("does not map directory lines to paths", function()
      local tree = commits._build_file_tree({ "dir/file.lua" })
      local lines = {}
      local line_paths = {}
      commits._render_tree_node(tree, "", lines, line_paths)
      -- 2 lines: dir/ and file.lua, only file.lua has path
      assert.equals(2, #lines)
      assert.is_nil(line_paths[0]) -- dir line
      assert.equals("dir/file.lua", line_paths[1]) -- file line
    end)
  end)
end)
