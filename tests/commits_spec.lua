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
    local original_list_files
    local captured_callback

    before_each(function()
      original_show_commit = git.show_commit
      original_list_files = git.list_files
      git.show_commit = function(_, _, cb)
        captured_callback = cb
      end
      git.list_files = function(_, _, cb) cb({}, nil) end
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
      git.list_files = original_list_files
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

  it("does not expose raw err in INFO notifications", function()
    for line in source:gmatch("[^\n]+") do
      if line:match("vim%.notify%(") and line:match("levels%.INFO") then
        assert.is_falsy(
          line:match('%.%.%s*err') or line:match('%.%.%s*fetch_err') or line:match('%.%.%s*unshallow_err'),
          "INFO notify should not concatenate raw error: " .. line
        )
      end
    end
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
    cs.filetree_buf = create_scratch_buf()
    cs.grid_bufs = {
      create_scratch_buf(),
      create_scratch_buf(),
      create_scratch_buf(),
      create_scratch_buf(),
    }
    cs.grid_rows = 2
    cs.grid_cols = 2
    bufs_to_clean = { cs.sidebar_buf, cs.header_buf, cs.filetree_buf }
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
    cs.sidebar_buf = nil
    cs.header_buf = nil
    cs.filetree_buf = nil
    cs.grid_bufs = {}
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

    it("applies keymaps to filetree_buf", function()
      commits._setup_keymaps()
      assert.is_true(has_buf_keymap(cs.filetree_buf, "n", " cm"),
        "expected <leader>cm on filetree_buf")
      for _, key in ipairs({ " j", " k", " l" }) do
        assert.is_true(has_buf_keymap(cs.filetree_buf, "n", key),
          "expected " .. key .. " on filetree_buf")
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

    it("handles a single root-level file", function()
      local tree = commits._build_file_tree({ "README.md" })
      assert.equals(1, #tree.children)
      assert.equals("README.md", tree.children[1].name)
      assert.equals("README.md", tree.children[1].path)
      assert.is_nil(tree.children[1].children)
    end)

    it("groups multiple files in the same directory", function()
      local tree = commits._build_file_tree({ "src/a.lua", "src/b.lua", "src/c.lua" })
      assert.equals(1, #tree.children)
      assert.equals("src", tree.children[1].name)
      assert.is_table(tree.children[1].children)
      assert.equals(3, #tree.children[1].children)
    end)

    it("handles sibling directories at the same level", function()
      local tree = commits._build_file_tree({ "alpha/x.lua", "beta/y.lua", "gamma/z.lua" })
      assert.equals(3, #tree.children)
      for _, child in ipairs(tree.children) do
        assert.is_table(child.children)
      end
    end)

    it("mixes root files and subdirectory files", function()
      local tree = commits._build_file_tree({ "init.lua", "lib/init.lua", "lib/utils.lua", "README.md" })
      -- root children: "lib" dir + "init.lua" file + "README.md" file = 3
      assert.equals(3, #tree.children)
    end)

    it("distinguishes similar-prefix directory names", function()
      local tree = commits._build_file_tree({ "a/file.lua", "ab/file.lua" })
      assert.equals(2, #tree.children)
      assert.equals("a", tree.children[1].name)
      assert.equals("ab", tree.children[2].name)
    end)

    it("files have path and no children, dirs have children and no path", function()
      local tree = commits._build_file_tree({ "src/lib/utils.lua", "src/main.lua" })
      local src = tree.children[1]
      assert.is_table(src.children)
      assert.is_nil(src.path)
      for _, child in ipairs(src.children) do
        if child.name == "main.lua" then
          assert.equals("src/main.lua", child.path)
          assert.is_nil(child.children)
        elseif child.name == "lib" then
          assert.is_table(child.children)
          assert.is_nil(child.path)
        end
      end
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

    it("renders directories before files", function()
      local tree = commits._build_file_tree({ "src/a.lua", "z_file.lua" })
      local lines = {}
      local line_paths = {}
      commits._render_tree_node(tree, "", lines, line_paths)
      assert.is_truthy(lines[1]:match("src/"))
      assert.is_truthy(lines[#lines]:match("z_file.lua"))
    end)

    it("uses correct connector for last vs non-last items", function()
      local tree = commits._build_file_tree({ "a.lua", "b.lua", "c.lua" })
      local lines = {}
      local line_paths = {}
      commits._render_tree_node(tree, "", lines, line_paths)
      assert.equals(3, #lines)
      assert.is_truthy(lines[1]:match("├ "))
      assert.is_truthy(lines[2]:match("├ "))
      assert.is_truthy(lines[3]:match("└ "))
    end)

    it("propagates prefix correctly for nested items", function()
      local tree = commits._build_file_tree({ "a/nested.lua", "b/nested.lua" })
      local lines = {}
      local line_paths = {}
      commits._render_tree_node(tree, "", lines, line_paths)
      -- a/ not last -> child gets "│  " prefix; b/ is last -> child gets "   " prefix
      assert.equals(4, #lines)
      assert.is_truthy(lines[2]:match("^│  └ nested.lua"))
      assert.is_truthy(lines[4]:match("^   └ nested.lua"))
    end)

    it("indents deeply nested items correctly", function()
      local tree = commits._build_file_tree({ "a/b/c/d.lua" })
      local lines = {}
      local line_paths = {}
      commits._render_tree_node(tree, "", lines, line_paths)
      assert.equals(4, #lines)
      assert.equals("└ a/", lines[1])
      assert.equals("   └ b/", lines[2])
      assert.equals("      └ c/", lines[3])
      assert.equals("         └ d.lua", lines[4])
    end)

    it("handles many siblings correctly", function()
      local paths = {}
      for i = 1, 20 do
        table.insert(paths, string.format("file_%02d.lua", i))
      end
      local tree = commits._build_file_tree(paths)
      local lines = {}
      local line_paths = {}
      commits._render_tree_node(tree, "", lines, line_paths)
      assert.equals(20, #lines)
      local mapped = 0
      for _ in pairs(line_paths) do mapped = mapped + 1 end
      assert.equals(20, mapped)
    end)

    it("sorts directories alphabetically among themselves", function()
      local tree = commits._build_file_tree({ "a_dir/b.lua", "m_file.lua", "z_dir/a.lua" })
      local lines = {}
      local line_paths = {}
      commits._render_tree_node(tree, "", lines, line_paths)
      -- Dirs first sorted: a_dir, z_dir, then file: m_file.lua
      assert.is_truthy(lines[1]:match("a_dir"))
      assert.is_truthy(lines[3]:match("z_dir"))
      assert.is_truthy(lines[#lines]:match("m_file.lua"))
    end)
  end)
end)

describe("raccoon.commits commit_files tracking", function()
  local original_show_commit
  local original_list_files
  local captured_callback

  before_each(function()
    state.reset()
    original_show_commit = git.show_commit
    original_list_files = git.list_files
    git.show_commit = function(_, _, cb)
      captured_callback = cb
    end
    git.list_files = function(_, _, cb) cb({}, nil) end
    local cs = commits._get_state()
    cs.pr_commits = {
      { sha = "aaaa", message = "commit with binary" },
    }
    cs.active = true
    cs.grid_bufs = {}
    cs.grid_wins = {}
    cs.all_hunks = {}
    cs.commit_files = {}
    cs.select_generation = 0
    state.session = state.session or {}
    state.session.clone_path = "/tmp/fake"
  end)

  after_each(function()
    git.show_commit = original_show_commit
    git.list_files = original_list_files
    state.reset()
  end)

  it("includes files with empty patches in commit_files", function()
    local cs = commits._get_state()
    commits._select_commit(1)

    captured_callback({
      { filename = "src/main.lua", patch = "@@ -1,1 +1,1 @@\n-old\n+new" },
      { filename = "image.png", patch = "" },
      { filename = "renamed.lua", patch = "" },
    }, nil)

    assert.is_true(cs.commit_files["src/main.lua"] == true)
    assert.is_true(cs.commit_files["image.png"] == true)
    assert.is_true(cs.commit_files["renamed.lua"] == true)
    -- Only main.lua contributes hunks
    assert.is_true(#cs.all_hunks > 0)
  end)

  it("populates commit_files when all patches are empty", function()
    local cs = commits._get_state()
    commits._select_commit(1)

    captured_callback({
      { filename = "binary1.bin", patch = "" },
      { filename = "binary2.bin", patch = "" },
    }, nil)

    assert.is_true(cs.commit_files["binary1.bin"] == true)
    assert.is_true(cs.commit_files["binary2.bin"] == true)
    assert.equals(0, #cs.all_hunks)
  end)
end)

describe("raccoon.commits render_filetree three-tier highlighting", function()
  local cs
  local filetree_buf

  --- Helper: read highlight groups applied to filetree buffer lines
  local function get_filetree_highlights(buf)
    local ns = vim.api.nvim_create_namespace("raccoon_filetree_hl")
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local result = {}
    for _, mark in ipairs(marks) do
      result[mark[2]] = mark[4].hl_group
    end
    return result
  end

  before_each(function()
    state.reset()
    require("raccoon").setup()
    cs = commits._get_state()
    filetree_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[filetree_buf].buftype = "nofile"
    cs.filetree_buf = filetree_buf
    cs.grid_rows = 2
    cs.grid_cols = 2
    cs.current_page = 1
  end)

  after_each(function()
    if filetree_buf and vim.api.nvim_buf_is_valid(filetree_buf) then
      vim.api.nvim_buf_delete(filetree_buf, { force = true })
    end
    state.reset()
  end)

  it("applies RaccoonFileVisible to files on current page", function()
    cs.cached_sha = "test1"
    cs.cached_tree_lines = { "├ visible.lua", "├ in_commit.lua", "└ normal.lua" }
    cs.cached_line_paths = { [0] = "visible.lua", [1] = "in_commit.lua", [2] = "normal.lua" }
    cs.cached_file_count = 3

    cs.all_hunks = { { filename = "visible.lua", hunk = {} } }
    cs.commit_files = { ["visible.lua"] = true, ["in_commit.lua"] = true }

    commits._render_filetree()

    local hl = get_filetree_highlights(filetree_buf)
    assert.equals("RaccoonFileVisible", hl[0])
    assert.equals("RaccoonFileInCommit", hl[1])
    assert.equals("RaccoonFileNormal", hl[2])
  end)

  it("applies RaccoonFileInCommit to commit files not on current page", function()
    cs.grid_rows = 1
    cs.grid_cols = 1

    cs.cached_sha = "test2"
    cs.cached_tree_lines = { "├ file1.lua", "├ file2.lua", "└ file3.lua" }
    cs.cached_line_paths = { [0] = "file1.lua", [1] = "file2.lua", [2] = "file3.lua" }
    cs.cached_file_count = 3

    cs.all_hunks = {
      { filename = "file1.lua", hunk = {} },
      { filename = "file2.lua", hunk = {} },
      { filename = "file3.lua", hunk = {} },
    }
    cs.commit_files = { ["file1.lua"] = true, ["file2.lua"] = true, ["file3.lua"] = true }

    commits._render_filetree()

    local hl = get_filetree_highlights(filetree_buf)
    assert.equals("RaccoonFileVisible", hl[0])
    assert.equals("RaccoonFileInCommit", hl[1])
    assert.equals("RaccoonFileInCommit", hl[2])
  end)

  it("applies RaccoonFileNormal to directory lines", function()
    cs.cached_sha = "test3"
    cs.cached_tree_lines = { "└ src/", "   └ main.lua" }
    cs.cached_line_paths = { [1] = "src/main.lua" }
    cs.cached_file_count = 1

    cs.all_hunks = { { filename = "src/main.lua", hunk = {} } }
    cs.commit_files = { ["src/main.lua"] = true }

    commits._render_filetree()

    local hl = get_filetree_highlights(filetree_buf)
    assert.equals("RaccoonFileNormal", hl[0])
    assert.equals("RaccoonFileVisible", hl[1])
  end)

  it("highlights empty-patch files as RaccoonFileInCommit", function()
    cs.cached_sha = "test4"
    cs.cached_tree_lines = { "├ changed.lua", "├ binary.bin", "└ renamed.txt" }
    cs.cached_line_paths = { [0] = "changed.lua", [1] = "binary.bin", [2] = "renamed.txt" }
    cs.cached_file_count = 3

    -- Only changed.lua has hunks; binary.bin and renamed.txt are empty-patch
    cs.all_hunks = { { filename = "changed.lua", hunk = {} } }
    cs.commit_files = { ["changed.lua"] = true, ["binary.bin"] = true, ["renamed.txt"] = true }

    commits._render_filetree()

    local hl = get_filetree_highlights(filetree_buf)
    assert.equals("RaccoonFileVisible", hl[0])
    assert.equals("RaccoonFileInCommit", hl[1])
    assert.equals("RaccoonFileInCommit", hl[2])
  end)
end)

describe("raccoon.commits render_filetree early return path", function()
  local original_show_commit
  local original_list_files
  local captured_callback
  local cs
  local filetree_buf
  local grid_bufs

  --- Helper: read highlight groups applied to filetree buffer lines
  local function get_filetree_highlights(buf)
    local ns = vim.api.nvim_create_namespace("raccoon_filetree_hl")
    local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
    local result = {}
    for _, mark in ipairs(marks) do
      result[mark[2]] = mark[4].hl_group
    end
    return result
  end

  before_each(function()
    state.reset()
    require("raccoon").setup()
    original_show_commit = git.show_commit
    original_list_files = git.list_files
    git.show_commit = function(_, _, cb)
      captured_callback = cb
    end
    git.list_files = function(_, _, cb) cb({}, nil) end

    cs = commits._get_state()
    cs.pr_commits = { { sha = "empty1", message = "binary-only commit" } }
    cs.active = true
    cs.select_generation = 0
    cs.all_hunks = {}
    cs.commit_files = {}
    state.session = state.session or {}
    state.session.clone_path = "/tmp/fake"

    -- Create filetree buffer
    filetree_buf = vim.api.nvim_create_buf(false, true)
    vim.bo[filetree_buf].buftype = "nofile"
    cs.filetree_buf = filetree_buf

    -- Create grid buffers (needed by early return path)
    grid_bufs = { vim.api.nvim_create_buf(false, true) }
    vim.bo[grid_bufs[1]].buftype = "nofile"
    cs.grid_bufs = grid_bufs
    cs.grid_wins = {}
    cs.grid_rows = 1
    cs.grid_cols = 1
    cs.current_page = 1
  end)

  after_each(function()
    git.show_commit = original_show_commit
    git.list_files = original_list_files
    if filetree_buf and vim.api.nvim_buf_is_valid(filetree_buf) then
      vim.api.nvim_buf_delete(filetree_buf, { force = true })
    end
    for _, buf in ipairs(grid_bufs or {}) do
      if vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
    state.reset()
  end)

  it("calls render_filetree in early return path (zero hunks)", function()
    -- Place sentinel in filetree buffer to detect overwrite
    vim.bo[filetree_buf].modifiable = true
    vim.api.nvim_buf_set_lines(filetree_buf, 0, -1, false, { "SENTINEL" })
    vim.bo[filetree_buf].modifiable = false

    commits._select_commit(1)
    captured_callback({
      { filename = "image.png", patch = "" },
      { filename = "mode_change.sh", patch = "" },
    }, nil)

    assert.equals(0, #cs.all_hunks)
    assert.equals(true, cs.commit_files["image.png"])
    assert.equals(true, cs.commit_files["mode_change.sh"])

    -- Sentinel was overwritten — proves render_filetree() was called
    local lines = vim.api.nvim_buf_get_lines(filetree_buf, 0, -1, false)
    assert.is_not.equals("SENTINEL", lines[1])

    -- Grid cell shows empty-commit message
    local grid_lines = vim.api.nvim_buf_get_lines(grid_bufs[1], 0, -1, false)
    assert.is_truthy(table.concat(grid_lines):match("No changes"))
  end)

  it("calls render_filetree via render_grid_page for mixed patches", function()
    cs.pr_commits = { { sha = "mixed1", message = "mixed commit" } }

    -- Place sentinel in filetree buffer to detect overwrite
    vim.bo[filetree_buf].modifiable = true
    vim.api.nvim_buf_set_lines(filetree_buf, 0, -1, false, { "SENTINEL" })
    vim.bo[filetree_buf].modifiable = false

    commits._select_commit(1)
    captured_callback({
      { filename = "changed.lua", patch = "@@ -1,1 +1,1 @@\n-old\n+new" },
      { filename = "binary.bin", patch = "" },
      { filename = "renamed.txt", patch = "" },
    }, nil)

    assert.is_true(#cs.all_hunks > 0)
    assert.equals(true, cs.commit_files["changed.lua"])
    assert.equals(true, cs.commit_files["binary.bin"])
    assert.equals(true, cs.commit_files["renamed.txt"])

    -- Sentinel was overwritten — proves render_filetree() was called
    local lines = vim.api.nvim_buf_get_lines(filetree_buf, 0, -1, false)
    assert.is_not.equals("SENTINEL", lines[1])
  end)
end)

describe("raccoon file tree highlight groups", function()
  it("defines RaccoonFileNormal highlight group", function()
    require("raccoon").setup()
    local hl = vim.api.nvim_get_hl(0, { name = "RaccoonFileNormal" })
    assert.is_not_nil(hl.fg)
  end)

  it("defines RaccoonFileInCommit highlight group", function()
    require("raccoon").setup()
    local hl = vim.api.nvim_get_hl(0, { name = "RaccoonFileInCommit" })
    assert.is_not_nil(hl.fg)
  end)

  it("defines RaccoonFileVisible highlight group", function()
    require("raccoon").setup()
    local hl = vim.api.nvim_get_hl(0, { name = "RaccoonFileVisible" })
    assert.is_not_nil(hl.fg)
  end)
end)

describe("raccoon.commits close_filetree", function()
  it("is exposed for testing", function()
    assert.is_function(commits._close_filetree)
  end)

  it("clears filetree_win and filetree_buf to nil", function()
    local cs = commits._get_state()
    cs.filetree_win = 99999
    cs.filetree_buf = 99998
    commits._close_filetree()
    assert.is_nil(cs.filetree_win)
    assert.is_nil(cs.filetree_buf)
  end)

  it("handles nil filetree state gracefully", function()
    local cs = commits._get_state()
    cs.filetree_win = nil
    cs.filetree_buf = nil
    -- Should not error
    commits._close_filetree()
    assert.is_nil(cs.filetree_win)
    assert.is_nil(cs.filetree_buf)
  end)
end)

describe("raccoon.commits compute_file_stats", function()
  it("returns empty table for nil input", function()
    local stats = commits._compute_file_stats(nil)
    assert.same({}, stats)
  end)

  it("returns empty table for empty input", function()
    local stats = commits._compute_file_stats({})
    assert.same({}, stats)
  end)

  it("counts additions and deletions from patch", function()
    local stats = commits._compute_file_stats({
      { filename = "a.lua", patch = "@@ -1,2 +1,3 @@\n-old\n+new\n+added" },
    })
    assert.equals(2, stats["a.lua"].additions)
    assert.equals(1, stats["a.lua"].deletions)
  end)

  it("aggregates across multiple hunks", function()
    local patch = "@@ -1,1 +1,2 @@\n-a\n+b\n+c\n@@ -10,1 +11,1 @@\n-x\n+y"
    local stats = commits._compute_file_stats({
      { filename = "multi.lua", patch = patch },
    })
    assert.equals(3, stats["multi.lua"].additions)
    assert.equals(2, stats["multi.lua"].deletions)
  end)

  it("handles files with no changes (empty patch)", function()
    local stats = commits._compute_file_stats({
      { filename = "binary.bin", patch = "" },
    })
    assert.equals(0, stats["binary.bin"].additions)
    assert.equals(0, stats["binary.bin"].deletions)
  end)

  it("handles multiple files", function()
    local stats = commits._compute_file_stats({
      { filename = "a.lua", patch = "@@ -1,1 +1,1 @@\n-old\n+new" },
      { filename = "b.lua", patch = "@@ -1,1 +1,2 @@\n context\n+added" },
    })
    assert.equals(1, stats["a.lua"].additions)
    assert.equals(1, stats["a.lua"].deletions)
    assert.equals(1, stats["b.lua"].additions)
    assert.equals(0, stats["b.lua"].deletions)
  end)
end)

describe("raccoon.commits format_stat_bar", function()
  it("returns empty for zero changes", function()
    local bar, add, del = commits._format_stat_bar(0, 0)
    assert.equals("", bar)
    assert.equals(0, add)
    assert.equals(0, del)
  end)

  it("returns all + for additions only", function()
    local bar, add, del = commits._format_stat_bar(10, 0)
    assert.equals(20, #bar)
    assert.equals(20, add)
    assert.equals(0, del)
    assert.is_truthy(bar:match("^%++$"))
  end)

  it("returns all - for deletions only", function()
    local bar, add, del = commits._format_stat_bar(0, 5)
    assert.equals(20, #bar)
    assert.equals(0, add)
    assert.equals(20, del)
    assert.is_truthy(bar:match("^%-+$"))
  end)

  it("returns proportional bar for mixed changes", function()
    local bar, add, del = commits._format_stat_bar(10, 10)
    assert.equals(20, #bar)
    assert.equals(10, add)
    assert.equals(10, del)
    assert.equals(string.rep("+", 10) .. string.rep("-", 10), bar)
  end)

  it("ensures at least 1 char for small non-zero counts", function()
    local bar, add, del = commits._format_stat_bar(1, 100)
    assert.is_true(add >= 1)
    assert.is_true(del >= 1)
    assert.equals(20, add + del)
  end)

  it("bar length is always STAT_BAR_MAX_WIDTH for non-zero totals", function()
    local bar1 = commits._format_stat_bar(3, 7)
    local bar2 = commits._format_stat_bar(99, 1)
    local bar3 = commits._format_stat_bar(1, 99)
    assert.equals(20, #bar1)
    assert.equals(20, #bar2)
    assert.equals(20, #bar3)
  end)
end)

describe("raccoon.commits render_tree_node with file_stats", function()
  it("inserts stat lines below changed files", function()
    local tree = commits._build_file_tree({ "a.lua", "b.lua" })
    local lines = {}
    local line_paths = {}
    local file_stats = { ["a.lua"] = { additions = 5, deletions = 3 } }
    local stat_lines = {}
    commits._render_tree_node(tree, "", lines, line_paths, file_stats, stat_lines)
    -- a.lua + stat bar + b.lua = 3 lines
    assert.equals(3, #lines)
    assert.is_truthy(lines[1]:match("a.lua"))
    assert.is_truthy(lines[2]:match("[%+%-]"))
    assert.is_truthy(lines[3]:match("b.lua"))
  end)

  it("does not add stat lines to line_paths", function()
    local tree = commits._build_file_tree({ "a.lua", "b.lua" })
    local lines = {}
    local line_paths = {}
    local file_stats = { ["a.lua"] = { additions = 5, deletions = 3 } }
    local stat_lines = {}
    commits._render_tree_node(tree, "", lines, line_paths, file_stats, stat_lines)
    -- Only 2 files mapped, not the stat line
    local mapped = 0
    for _ in pairs(line_paths) do mapped = mapped + 1 end
    assert.equals(2, mapped)
    -- Stat line index (1, 0-based) should NOT be in line_paths
    assert.is_nil(line_paths[1])
  end)

  it("records stat line metadata in stat_lines table", function()
    local tree = commits._build_file_tree({ "x.lua" })
    local lines = {}
    local line_paths = {}
    local file_stats = { ["x.lua"] = { additions = 3, deletions = 7 } }
    local stat_lines = {}
    commits._render_tree_node(tree, "", lines, line_paths, file_stats, stat_lines)
    assert.equals(2, #lines)
    -- stat_lines[1] (0-based) should have metadata
    local stat = stat_lines[1]
    assert.is_not_nil(stat)
    assert.is_true(stat.add_chars > 0)
    assert.is_true(stat.del_chars > 0)
    assert.is_true(stat.prefix_len > 0)
  end)

  it("does not insert stat lines for files without stats", function()
    local tree = commits._build_file_tree({ "a.lua", "b.lua" })
    local lines = {}
    local line_paths = {}
    local file_stats = {}
    local stat_lines = {}
    commits._render_tree_node(tree, "", lines, line_paths, file_stats, stat_lines)
    assert.equals(2, #lines)
  end)

  it("does not insert stat lines when file_stats is nil", function()
    local tree = commits._build_file_tree({ "a.lua", "b.lua" })
    local lines = {}
    local line_paths = {}
    commits._render_tree_node(tree, "", lines, line_paths, nil, nil)
    assert.equals(2, #lines)
  end)

  it("skips stat line for files with zero changes", function()
    local tree = commits._build_file_tree({ "a.lua" })
    local lines = {}
    local line_paths = {}
    local file_stats = { ["a.lua"] = { additions = 0, deletions = 0 } }
    local stat_lines = {}
    commits._render_tree_node(tree, "", lines, line_paths, file_stats, stat_lines)
    assert.equals(1, #lines)
  end)

  it("uses correct tree prefix for stat lines", function()
    local tree = commits._build_file_tree({ "a.lua", "b.lua" })
    local lines = {}
    local line_paths = {}
    local file_stats = {
      ["a.lua"] = { additions = 5, deletions = 5 },
      ["b.lua"] = { additions = 3, deletions = 0 },
    }
    local stat_lines = {}
    commits._render_tree_node(tree, "", lines, line_paths, file_stats, stat_lines)
    -- a.lua is not last -> stat bar prefix has "│  "
    assert.is_truthy(lines[2]:match("^│  "))
    -- b.lua is last -> stat bar prefix has "   "
    assert.is_truthy(lines[4]:match("^   "))
  end)
end)
