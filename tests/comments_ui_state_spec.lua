local comments = require("raccoon.comments")
local state = require("raccoon.state")
local api = require("raccoon.api")
local config = require("raccoon.config")
local diff = require("raccoon.diff")
local open = require("raccoon.open")

local CLONE_PATH = "/tmp/raccoon-ui-state"

local function review_comment(fields)
  return vim.tbl_extend("force", {
    id = 1,
    body = "review comment",
    thread_id = "thread-1",
    line = 1,
    resolved = false,
    in_reply_to_id = vim.NIL,
    created_at = "2026-01-01T00:00:00Z",
    user = { login = "reviewer" },
  }, fields or {})
end

local function issue_comment(fields)
  return vim.tbl_extend("force", {
    id = 100,
    body = "issue comment",
    line = 1,
    issue_comment = true,
    created_at = "2026-01-01T00:00:00Z",
    user = { login = "issue-author" },
  }, fields or {})
end

local function make_file_buffer(path, line_count)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, CLONE_PATH .. "/" .. path)
  local lines = {}
  for idx = 1, line_count do
    lines[idx] = "line " .. idx
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

local function write_checkout_file(path, lines)
  local full_path = vim.fs.joinpath(CLONE_PATH, path)
  vim.fn.mkdir(vim.fs.dirname(full_path), "p")
  vim.fn.writefile(lines, full_path)
end

local function make_split_buffer(opts)
  local rendered = diff.render_split_file({
    path = opts.path or "lua/a.lua",
    old_lines = opts.old_lines,
    new_lines = opts.new_lines,
    patch = opts.patch,
    width = opts.width or 100,
  })
  local buf = vim.api.nvim_create_buf(false, true)
  diff.apply_split_render(buf, rendered)
  vim.api.nvim_set_current_buf(buf)
  return buf, rendered
end

local function current_win_title()
  local title = vim.api.nvim_win_get_config(0).title
  if type(title) == "string" then
    return title
  end
  if type(title) == "table" then
    local parts = {}
    for _, chunk in ipairs(title) do
      if type(chunk) == "table" then
        table.insert(parts, chunk[1] or "")
      else
        table.insert(parts, tostring(chunk))
      end
    end
    return table.concat(parts, "")
  end
  return ""
end

local function trigger_buffer_mapping(buf, mode, lhs)
  local expected = vim.api.nvim_replace_termcodes(lhs, true, false, true)
  local expected_suffix = lhs:sub(-1)
  for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
    local actual = map.lhsraw or map.lhs or ""
    local expanded = vim.api.nvim_replace_termcodes(actual, true, false, true)
    if type(map.callback) == "function" and (expanded == expected or actual:sub(-1) == expected_suffix) then
      map.callback()
      return
    end
  end
  error(string.format("mapping %q not found for mode %s", lhs, mode))
end

local function setup_session()
  state.reset()
  state.start({
    owner = "owner",
    repo = "repo",
    number = 1,
    url = "https://github.com/owner/repo/pull/1",
    clone_path = CLONE_PATH,
  })
  state.set_viewer_login("me")
  state.set_pr({
    number = 1,
    title = "Test PR",
    head = { sha = "abc123", ref = "feature" },
    base = { ref = "main" },
  })
  state.set_files({
    {
      filename = "lua/a.lua",
      patch = "@@ -1,2 +1,3 @@\n line 1\n+line 2\n line 3",
    },
    {
      filename = "lua/b.lua",
      patch = "@@ -1,2 +1,3 @@\n line 1\n+line 2\n line 3",
    },
  })
  state.set_comments("_reviews", {
    {
      id = 900,
      body = "broad review body",
      submitted_at = "2026-01-01T00:00:00Z",
      user = { login = "reviewer-a" },
    },
  })
  state.set_comments("lua/a.lua", {
    review_comment({
      id = 1,
      thread_id = "thread-a",
      line = 4,
      body = "my initial comment",
      created_at = "2026-01-01T00:00:00Z",
      user = { login = "me" },
    }),
    review_comment({
      id = 2,
      thread_id = "thread-a",
      line = 4,
      body = "reply after me",
      created_at = "2026-01-02T00:00:00Z",
      in_reply_to_id = 1,
      user = { login = "reviewer-1" },
    }),
    review_comment({
      id = 3,
      thread_id = "thread-b",
      line = 6,
      body = "other unresolved thread",
      created_at = "2026-01-03T00:00:00Z",
      user = { login = "reviewer-2" },
    }),
    review_comment({
      id = 4,
      thread_id = "thread-c",
      line = 8,
      body = "resolved thread",
      resolved = true,
      created_at = "2026-01-04T00:00:00Z",
      user = { login = "reviewer-3" },
    }),
    issue_comment({
      id = 5,
      line = 2,
      body = "broad PR note on this line",
      html_url = "https://github.com/owner/repo/pull/1#issuecomment-5",
      user = { login = "issue-author" },
    }),
  })
  state.set_comments("lua/b.lua", {
    review_comment({
      id = 6,
      thread_id = "thread-d",
      line = 3,
      body = "file b unresolved thread",
      created_at = "2026-01-05T00:00:00Z",
      user = { login = "reviewer-4" },
    }),
  })
end

describe("raccoon.comments UI state restore", function()
  local original_notify
  local original_load_shortcuts
  local baseline_buffers

  before_each(function()
    vim.fn.delete(CLONE_PATH, "rf")
    baseline_buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      baseline_buffers[buf] = true
    end
    original_notify = vim.notify
    original_load_shortcuts = config.load_shortcuts
    config.load_shortcuts = function()
      return vim.deepcopy(config.defaults.shortcuts)
    end
    setup_session()
  end)

  after_each(function()
    comments.close_overlays(true)
    vim.notify = original_notify
    config.load_shortcuts = original_load_shortcuts
    state.reset()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if not baseline_buffers[buf] and vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    vim.fn.delete(CLONE_PATH, "rf")
  end)

  it("captures and restores unresolved-thread picker selection", function()
    local file_buf = make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    comments.list_threads()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local snapshot = comments.capture_ui_state()
    assert.same({
      kind = "picker",
      picker_kind = "list_threads",
      row_key = "thread:thread-b",
      row_index = 2,
    }, snapshot)

    comments.close_overlays(true)
    vim.api.nvim_set_current_buf(file_buf)
    comments.restore_ui_state(snapshot)

    local restored = comments.capture_ui_state()
    assert.same(snapshot, restored)
  end)

  it("captures and restores changed-file picker selection", function()
    local file_buf = make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    comments.list_files()
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    local snapshot = comments.capture_ui_state()
    assert.same({
      kind = "picker",
      picker_kind = "list_files",
      row_key = "file:lua/b.lua",
      row_index = 2,
    }, snapshot)

    comments.close_overlays(true)
    vim.api.nvim_set_current_buf(file_buf)
    comments.restore_ui_state(snapshot)

    local restored = comments.capture_ui_state()
    assert.same(snapshot, restored)
  end)

  it("captures and restores broad comment-list selection", function()
    local file_buf = make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    comments.list_comments()
    vim.api.nvim_win_set_cursor(0, { 4, 0 })

    local snapshot = comments.capture_ui_state()
    assert.same({
      kind = "picker",
      picker_kind = "list_comments",
      row_key = "thread:thread-b",
      row_index = 4,
    }, snapshot)

    comments.close_overlays(true)
    vim.api.nvim_set_current_buf(file_buf)
    comments.restore_ui_state(snapshot)

    local restored = comments.capture_ui_state()
    assert.same(snapshot, restored)
  end)

  it("restores a new-thread draft, preserves text, and disables send when the line is no longer commentable", function()
    local notifications = {}
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    comments.show_comment_thread()
    local editor_buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "draft new thread" })

    local snapshot = comments.capture_ui_state()
    assert.equals("editor", snapshot.kind)
    assert.equals("new_thread", snapshot.editor_kind)
    assert.same({ "draft new thread" }, snapshot.input_lines)

    state.set_files({
      { filename = "lua/b.lua", patch = "@@ -1,2 +1,3 @@\n line 1\n+line 2\n line 3" },
    })

    comments.close_overlays(true)
    comments.restore_ui_state(snapshot)

    local restored = comments.capture_ui_state()
    assert.equals("editor", restored.kind)
    assert.equals("new_thread", restored.editor_kind)
    assert.same({ "draft new thread" }, restored.input_lines)
    assert.is_true(comments.has_unsent_text())
    assert.is_false(current_win_title():match("=send") ~= nil)
    assert.matches(
      "Thread is no longer commentable on this line; clear the text or close it",
      notifications[#notifications]
    )
  end)

  it("restores a new-thread draft with send still available when sync cannot re-verify diff context", function()
    make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })

    comments.show_comment_thread()
    local editor_buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "draft new thread" })

    local snapshot = comments.capture_ui_state()
    assert.equals("editor", snapshot.kind)
    assert.equals("new_thread", snapshot.editor_kind)

    state.set_files({
      { filename = "lua/a.lua", patch = "@@ -20,1 +20,2 @@\n line 20\n+line 21" },
      { filename = "lua/b.lua", patch = "@@ -1,2 +1,3 @@\n line 1\n+line 2\n line 3" },
    })

    comments.close_overlays(true)
    comments.restore_ui_state(snapshot)

    local restored = comments.capture_ui_state()
    assert.equals("editor", restored.kind)
    assert.equals("new_thread", restored.editor_kind)
    assert.same({ "draft new thread" }, restored.input_lines)
    assert.is_true(current_win_title():match("=send") ~= nil)
  end)

  it("allows new threads on unchanged lines that are still inside diff context", function()
    local notifications = {}
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    comments.show_comment_thread()

    local snapshot = comments.capture_ui_state()
    assert.equals("editor", snapshot.kind)
    assert.equals("new_thread", snapshot.editor_kind)
    assert.is_true(current_win_title():match("=send") ~= nil)
    assert.equals(0, #notifications)
  end)

  it("allows composing new threads outside visible diff context for changed files", function()
    local notifications = {}
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 10, 0 })

    comments.show_comment_thread()

    local snapshot = comments.capture_ui_state()
    assert.equals("editor", snapshot.kind)
    assert.equals("new_thread", snapshot.editor_kind)
    assert.matches("File Comment", current_win_title())
    assert.equals(0, #notifications)
  end)

  it("sends out-of-hunk changed-file comments as file-level REST comments", function()
    local notifications = {}
    local original_notify = vim.notify
    local original_config_load = config.load
    local original_get_token_entry = config.get_token_entry
    local original_api_init = api.init
    local original_create_comment = api.create_comment
    local original_sync = open.sync

    local graphql_called = false
    local rest_called = false
    local sync_called = false

    vim.notify = function(message)
      table.insert(notifications, message)
    end
    config.load = function()
      return {
        github_host = "github.com",
        tokens = { owner = "ghp_fake" },
      }, nil
    end
    config.get_token_entry = function()
      return { token = "ghp_fake" }
    end
    api.init = function() end
    api.create_comment = function(_owner, _repo, _number, opts, _token, callback)
      rest_called = true
      assert.equals("lua/a.lua", opts.path)
      assert.equals("file", opts.subject_type)
      assert.is_nil(opts.line)
      assert.equals("graphQL send body", opts.body)
      callback({ id = 777 }, nil)
    end
    open.sync = function()
      sync_called = true
    end

    state.set_pr({
      number = 1,
      title = "Test PR",
      node_id = "PR_kwDOA1",
      head = { sha = "abc123", ref = "feature" },
      base = { ref = "main" },
    })

    local file_buf = make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    comments.show_comment_thread()

    local editor_buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "graphQL send body" })
    vim.cmd("stopinsert")
    trigger_buffer_mapping(editor_buf, "n", " s")
    vim.wait(1000, function()
      return sync_called
    end, 10)

    vim.notify = original_notify
    config.load = original_config_load
    config.get_token_entry = original_get_token_entry
    api.init = original_api_init
    api.create_comment = original_create_comment
    open.sync = original_sync

    assert.is_false(graphql_called)
    assert.is_true(rest_called)
    assert.is_true(sync_called)
    assert.is_nil(comments.capture_ui_state())
    assert.equals(file_buf, vim.api.nvim_get_current_buf())
    assert.matches("Thread sent", notifications[#notifications])
  end)

  it("sends in-diff line comments as persisted REST review comments", function()
    local original_notify = vim.notify
    local original_config_load = config.load
    local original_get_token_entry = config.get_token_entry
    local original_api_init = api.init
    local original_create_comment = api.create_comment
    local original_sync = open.sync

    local graphql_called = false
    local rest_called = false
    local sync_called = false

    vim.notify = function() end
    config.load = function()
      return {
        github_host = "github.com",
        tokens = { owner = "ghp_fake" },
      }, nil
    end
    config.get_token_entry = function()
      return { token = "ghp_fake" }
    end
    api.init = function() end
    api.create_comment = function(_owner, _repo, _number, opts, _token, callback)
      rest_called = true
      assert.equals("lua/a.lua", opts.path)
      assert.equals(2, opts.line)
      callback({ id = 55 }, nil)
    end
    open.sync = function()
      sync_called = true
    end

    state.set_pr({
      number = 1,
      title = "Test PR",
      node_id = "PR_kwDOA1",
      head = { sha = "abc123", ref = "feature" },
      base = { ref = "main" },
    })

    make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    comments.show_comment_thread()

    local editor_buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "fallback body" })
    vim.cmd("stopinsert")
    trigger_buffer_mapping(editor_buf, "n", " s")
    vim.wait(1000, function()
      return sync_called
    end, 10)

    vim.notify = original_notify
    config.load = original_config_load
    config.get_token_entry = original_get_token_entry
    api.init = original_api_init
    api.create_comment = original_create_comment
    open.sync = original_sync

    assert.is_false(graphql_called)
    assert.is_true(rest_called)
    assert.is_true(sync_called)
  end)

  it("sends split-buffer left-side comments with LEFT side and old line", function()
    local original_notify = vim.notify
    local original_config_load = config.load
    local original_get_token_entry = config.get_token_entry
    local original_api_init = api.init
    local original_create_comment = api.create_comment
    local original_sync = open.sync

    local captured_opts
    local sync_called = false

    vim.notify = function() end
    config.load = function()
      return {
        github_host = "github.com",
        tokens = { owner = "ghp_fake" },
      }, nil
    end
    config.get_token_entry = function()
      return { token = "ghp_fake" }
    end
    api.init = function() end
    api.create_comment = function(_owner, _repo, _number, opts, _token, callback)
      captured_opts = opts
      callback({ id = 56 }, nil)
    end
    open.sync = function()
      sync_called = true
    end

    state.set_files({
      {
        filename = "lua/a.lua",
        patch = "@@ -1,3 +1,3 @@\n line 1\n-old value\n+new value\n line 3",
      },
    })
    make_split_buffer({
      old_lines = { "line 1", "old value", "line 3" },
      new_lines = { "line 1", "new value", "line 3" },
      patch = "@@ -1,3 +1,3 @@\n line 1\n-old value\n+new value\n line 3",
    })
    local rendered = diff.get_split_metadata(vim.api.nvim_get_current_buf())
    vim.api.nvim_win_set_cursor(0, { 2, rendered.left_range.content_start_col })
    comments.show_comment_thread()

    local editor_buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "left body" })
    vim.cmd("stopinsert")
    trigger_buffer_mapping(editor_buf, "n", " s")
    vim.wait(1000, function()
      return sync_called
    end, 10)

    vim.notify = original_notify
    config.load = original_config_load
    config.get_token_entry = original_get_token_entry
    api.init = original_api_init
    api.create_comment = original_create_comment
    open.sync = original_sync

    assert.equals("lua/a.lua", captured_opts.path)
    assert.equals(2, captured_opts.line)
    assert.equals("LEFT", captured_opts.side)
    assert.is_true(sync_called)
  end)

  it("sends split left-side tail deletion comments with old line beyond checkout bounds", function()
    local original_notify = vim.notify
    local original_config_load = config.load
    local original_get_token_entry = config.get_token_entry
    local original_api_init = api.init
    local original_create_comment = api.create_comment
    local original_sync = open.sync

    local captured_opts
    local sync_called = false

    vim.notify = function() end
    config.load = function()
      return {
        github_host = "github.com",
        tokens = { owner = "ghp_fake" },
      }, nil
    end
    config.get_token_entry = function()
      return { token = "ghp_fake" }
    end
    api.init = function() end
    api.create_comment = function(_owner, _repo, _number, opts, _token, callback)
      captured_opts = opts
      callback({ id = 59 }, nil)
    end
    open.sync = function()
      sync_called = true
    end

    local patch = "@@ -1,5 +1,3 @@\n line 1\n line 2\n line 3\n-line 4\n-line 5"
    state.set_files({
      {
        filename = "lua/a.lua",
        patch = patch,
      },
    })
    write_checkout_file("lua/a.lua", { "line 1", "line 2", "line 3" })
    make_split_buffer({
      old_lines = { "line 1", "line 2", "line 3", "line 4", "line 5" },
      new_lines = { "line 1", "line 2", "line 3" },
      patch = patch,
    })
    local rendered = diff.get_split_metadata(vim.api.nvim_get_current_buf())
    vim.api.nvim_win_set_cursor(0, { 5, rendered.left_range.content_start_col })
    comments.show_comment_thread()

    local editor_buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "old tail body" })
    vim.cmd("stopinsert")
    trigger_buffer_mapping(editor_buf, "n", " s")
    vim.wait(1000, function()
      return sync_called
    end, 10)

    vim.notify = original_notify
    config.load = original_config_load
    config.get_token_entry = original_get_token_entry
    api.init = original_api_init
    api.create_comment = original_create_comment
    open.sync = original_sync

    assert.equals("lua/a.lua", captured_opts.path)
    assert.equals(5, captured_opts.line)
    assert.equals("LEFT", captured_opts.side)
    assert.is_true(sync_called)
  end)

  it("retries rejected split left-side line comments as file-level comments", function()
    local original_notify = vim.notify
    local original_config_load = config.load
    local original_get_token_entry = config.get_token_entry
    local original_api_init = api.init
    local original_create_comment = api.create_comment
    local original_sync = open.sync

    local calls = {}
    local sync_called = false

    vim.notify = function() end
    config.load = function()
      return {
        github_host = "github.com",
        tokens = { owner = "ghp_fake" },
      }, nil
    end
    config.get_token_entry = function()
      return { token = "ghp_fake" }
    end
    api.init = function() end
    api.create_comment = function(_owner, _repo, _number, opts, _token, callback)
      table.insert(calls, vim.deepcopy(opts))
      if #calls == 1 then
        callback(nil, "GitHub API error (422): Validation Failed")
      else
        callback({ id = 57 }, nil)
      end
    end
    open.sync = function()
      sync_called = true
    end

    state.set_files({
      {
        filename = "lua/a.lua",
        patch = "@@ -1,3 +1,3 @@\n line 1\n-old value\n+new value\n line 3",
      },
    })
    make_split_buffer({
      old_lines = { "line 1", "old value", "line 3" },
      new_lines = { "line 1", "new value", "line 3" },
      patch = "@@ -1,3 +1,3 @@\n line 1\n-old value\n+new value\n line 3",
    })
    local rendered = diff.get_split_metadata(vim.api.nvim_get_current_buf())
    vim.api.nvim_win_set_cursor(0, { 2, rendered.left_range.content_start_col })
    comments.show_comment_thread()

    local editor_buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "retry body" })
    vim.cmd("stopinsert")
    trigger_buffer_mapping(editor_buf, "n", " s")
    vim.wait(1000, function()
      return sync_called
    end, 10)

    vim.notify = original_notify
    config.load = original_config_load
    config.get_token_entry = original_get_token_entry
    api.init = original_api_init
    api.create_comment = original_create_comment
    open.sync = original_sync

    assert.equals(2, #calls)
    assert.equals("LEFT", calls[1].side)
    assert.equals("file", calls[2].subject_type)
    assert.is_nil(calls[2].line)
    assert.is_true(sync_called)
  end)

  it("sends split out-of-hunk rows as file-level comments", function()
    local original_notify = vim.notify
    local original_config_load = config.load
    local original_get_token_entry = config.get_token_entry
    local original_api_init = api.init
    local original_create_comment = api.create_comment
    local original_sync = open.sync

    local captured_opts
    local sync_called = false

    vim.notify = function() end
    config.load = function()
      return {
        github_host = "github.com",
        tokens = { owner = "ghp_fake" },
      }, nil
    end
    config.get_token_entry = function()
      return { token = "ghp_fake" }
    end
    api.init = function() end
    api.create_comment = function(_owner, _repo, _number, opts, _token, callback)
      captured_opts = opts
      callback({ id = 58 }, nil)
    end
    open.sync = function()
      sync_called = true
    end

    state.set_files({
      {
        filename = "lua/a.lua",
        patch = "@@ -2,1 +2,1 @@\n-old value\n+new value",
      },
    })
    state.set_comments("lua/a.lua", {})
    make_split_buffer({
      old_lines = { "line 1", "old value", "line 3", "line 4" },
      new_lines = { "line 1", "new value", "line 3", "line 4" },
      patch = "@@ -2,1 +2,1 @@\n-old value\n+new value",
    })
    local rendered = diff.get_split_metadata(vim.api.nvim_get_current_buf())
    vim.api.nvim_win_set_cursor(0, { 4, rendered.right_range.content_start_col })
    comments.show_comment_thread()

    local editor_buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "file body" })
    vim.cmd("stopinsert")
    trigger_buffer_mapping(editor_buf, "n", " s")
    vim.wait(1000, function()
      return sync_called
    end, 10)

    vim.notify = original_notify
    config.load = original_config_load
    config.get_token_entry = original_get_token_entry
    api.init = original_api_init
    api.create_comment = original_create_comment
    open.sync = original_sync

    assert.equals("file", captured_opts.subject_type)
    assert.is_nil(captured_opts.line)
    assert.is_true(sync_called)
  end)

  it("jumps to the left rendered row and column for LEFT threads", function()
    local patch = "@@ -1,5 +1,5 @@\n line 1\n+inserted\n line 2\n line 3\n-old deleted\n line 5"
    state.set_files({
      {
        filename = "lua/a.lua",
        patch = patch,
      },
    })
    state.set_comments("lua/a.lua", {
      review_comment({
        id = 60,
        thread_id = "thread-left",
        line = 4,
        side = "LEFT",
        body = "left deleted thread",
      }),
    })
    write_checkout_file("lua/a.lua", { "line 1", "inserted", "line 2", "line 3", "line 5" })

    assert.is_true(comments.jump_to_thread("thread-left", {}))

    local rendered = diff.get_split_metadata(vim.api.nvim_get_current_buf())
    local expected_row
    for idx, row in ipairs(rendered.rows or {}) do
      if row.path == "lua/a.lua" and row.old_line == 4 and not row.left_continuation then
        expected_row = idx
        break
      end
    end
    local cursor = vim.api.nvim_win_get_cursor(0)

    assert.equals(expected_row, cursor[1])
    assert.equals(rendered.left_range.content_start_col, cursor[2])
  end)

  it("renders split badges from side-specific line buckets", function()
    state.set_comments("lua/a.lua", {
      review_comment({
        id = 61,
        thread_id = "thread-left",
        line = 2,
        side = "LEFT",
        body = "left thread",
      }),
      review_comment({
        id = 62,
        thread_id = "thread-right",
        line = 2,
        side = "RIGHT",
        body = "right thread",
      }),
    })
    local buf, rendered = make_split_buffer({
      old_lines = { "before", "old value", "after" },
      new_lines = { "before", "new value", "after" },
      patch = "@@ -1,3 +1,3 @@\n before\n-old value\n+new value\n after",
    })

    comments.show_comments(buf, state.get_comments("lua/a.lua"))

    local badges_by_col = {}
    for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, comments.get_namespace(), 0, -1, { details = true })) do
      local details = mark[4] or {}
      if details.virt_text_win_col == rendered.left_range.start_col
          or details.virt_text_win_col == rendered.right_range.start_col
      then
        badges_by_col[details.virt_text_win_col] = details.virt_text[1][1]
      end
    end

    assert.equals("[U1]", badges_by_col[rendered.left_range.start_col])
    assert.equals("[U1]", badges_by_col[rendered.right_range.start_col])
  end)

  it("opens same-line picker with only the selected split side's threads", function()
    state.set_comments("lua/a.lua", {
      review_comment({
        id = 63,
        thread_id = "thread-left",
        line = 2,
        side = "LEFT",
        body = "left side only",
      }),
      review_comment({
        id = 64,
        thread_id = "thread-right",
        line = 2,
        side = "RIGHT",
        body = "right side only",
      }),
    })
    local _buf, rendered = make_split_buffer({
      old_lines = { "before", "old value", "after" },
      new_lines = { "before", "new value", "after" },
      patch = "@@ -1,3 +1,3 @@\n before\n-old value\n+new value\n after",
    })
    vim.api.nvim_win_set_cursor(0, { 2, rendered.right_range.content_start_col })

    comments.show_comment_thread()

    local snapshot = comments.capture_ui_state()
    assert.equals("picker", snapshot.kind)
    assert.equals("thread:thread-right", snapshot.row_key)
    local picker_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, -1, false)
    assert.truthy(table.concat(picker_lines, "\n"):match("right side only"))
    assert.is_nil(table.concat(picker_lines, "\n"):match("left side only"))
  end)

  it("opens file-level comments from split placeholder rows without a line", function()
    state.set_files({
      {
        filename = "assets/logo.png",
        patch = "",
      },
    })
    local rendered = diff.render_split_file({
      path = "assets/logo.png",
      binary = true,
      width = 100,
    })
    local buf = vim.api.nvim_create_buf(false, true)
    diff.apply_split_render(buf, rendered)
    vim.api.nvim_set_current_buf(buf)
    vim.api.nvim_win_set_cursor(0, { 1, rendered.left_range.content_start_col })

    comments.show_comment_thread()

    local snapshot = comments.capture_ui_state()
    assert.equals("editor", snapshot.kind)
    assert.equals("new_thread", snapshot.editor_kind)
    assert.equals("assets/logo.png", snapshot.path)
    assert.is_nil(snapshot.line)
    assert.is_false(snapshot.in_diff_context)
  end)

  it("restores a thread reply draft and disables send when the thread becomes resolved", function()
    local notifications = {}
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    state.set_comments("lua/a.lua", {
      review_comment({
        id = 1,
        thread_id = "thread-a",
        line = 4,
        body = "my initial comment",
        resolved = true,
        created_at = "2026-01-01T00:00:00Z",
        user = { login = "me" },
      }),
      review_comment({
        id = 2,
        thread_id = "thread-a",
        line = 4,
        body = "reply after me",
        resolved = true,
        created_at = "2026-01-02T00:00:00Z",
        in_reply_to_id = 1,
        user = { login = "reviewer-1" },
      }),
      review_comment({
        id = 3,
        thread_id = "thread-b",
        line = 6,
        body = "other unresolved thread",
        created_at = "2026-01-03T00:00:00Z",
        user = { login = "reviewer-2" },
      }),
      issue_comment({
        id = 5,
        line = 2,
        body = "broad PR note on this line",
        user = { login = "issue-author" },
      }),
    })

    comments.restore_ui_state({
      kind = "editor",
      editor_kind = "thread",
      thread_id = "thread-a",
      input_lines = { "draft reply" },
    })

    local restored = comments.capture_ui_state()
    assert.equals("editor", restored.kind)
    assert.equals("thread", restored.editor_kind)
    assert.equals("thread-a", restored.thread_id)
    assert.same({ "draft reply" }, restored.input_lines)
    assert.is_true(comments.has_unsent_text())
    assert.is_false(current_win_title():match("=send") ~= nil)
    assert.truthy(current_win_title():match("=unresolve"))
    assert.matches("Thread is now resolved; unresolve it or clear the text", notifications[#notifications])
  end)

  it("shows resolved same-line threads in the comment picker", function()
    local original_columns = vim.o.columns
    vim.o.columns = 220
    make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 8, 0 })

    comments.show_comment_thread()

    local snapshot = comments.capture_ui_state()
    assert.same({
      kind = "picker",
      picker_kind = "same_line",
      row_key = "thread:thread-c",
      row_index = 1,
    }, snapshot)

    local picker_lines = vim.api.nvim_buf_get_lines(vim.api.nvim_get_current_buf(), 0, 2, false)
    assert.matches("^%[R%]", picker_lines[1])
    assert.equals("[NEW] New file comment for this file", picker_lines[2])

    local width = vim.api.nvim_win_get_config(0).width
    vim.o.columns = original_columns
    assert.is_true(width < 140)
  end)

  it("closes the same-line picker with the configured close shortcut", function()
    local file_buf = make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 8, 0 })

    comments.show_comment_thread()
    assert.equals("picker", comments.capture_ui_state().kind)

    trigger_buffer_mapping(vim.api.nvim_get_current_buf(), "n", " q")

    assert.is_nil(comments.capture_ui_state())
    assert.equals(file_buf, vim.api.nvim_get_current_buf())
  end)

  it("keeps prior thread comments read-only while allowing navigation and editing only in the reply region", function()
    comments.restore_ui_state({
      kind = "editor",
      editor_kind = "thread",
      thread_id = "thread-a",
      input_lines = { "draft reply" },
    })

    local buf = vim.api.nvim_get_current_buf()
    local input_line = vim.api.nvim_win_get_cursor(0)[1]
    local first_line_before = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]

    assert.is_true(vim.bo[buf].modifiable)
    vim.cmd("stopinsert")

    vim.cmd("normal! gg")
    comments.refresh_editor_editability()
    assert.equals(1, vim.api.nvim_win_get_cursor(0)[1])
    assert.is_false(vim.bo[buf].modifiable)

    vim.cmd("normal! j")
    comments.refresh_editor_editability()
    assert.equals(2, vim.api.nvim_win_get_cursor(0)[1])
    assert.is_false(vim.bo[buf].modifiable)

    pcall(vim.cmd, "normal! x")
    assert.equals(first_line_before, vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])

    vim.cmd("normal! G")
    comments.refresh_editor_editability()
    assert.equals(input_line, vim.api.nvim_win_get_cursor(0)[1])
    assert.is_true(vim.bo[buf].modifiable)

    local ok_reply_edit = pcall(vim.cmd, "normal! AX")
    assert.is_true(ok_reply_edit)
    assert.equals("draft replyX", vim.api.nvim_buf_get_lines(buf, input_line - 1, input_line, false)[1])
  end)
end)
