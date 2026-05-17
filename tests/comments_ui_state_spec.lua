local comments = require("raccoon.comments")
local state = require("raccoon.state")

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

local function feed_keys(lhs)
  local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
  vim.api.nvim_feedkeys(keys, "xt", false)
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
  local baseline_buffers

  before_each(function()
    baseline_buffers = {}
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      baseline_buffers[buf] = true
    end
    original_notify = vim.notify
    setup_session()
  end)

  after_each(function()
    comments.close_overlays(true)
    vim.notify = original_notify
    state.reset()
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      if not baseline_buffers[buf] and vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
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
      { filename = "lua/a.lua", patch = "" },
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

  it("blocks new threads outside the diff context before send", function()
    local notifications = {}
    vim.notify = function(message)
      table.insert(notifications, message)
    end

    local file_buf = make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 10, 0 })

    comments.show_comment_thread()

    assert.is_nil(comments.capture_ui_state())
    assert.equals(file_buf, vim.api.nvim_get_current_buf())
    assert.matches(
      "This line is outside the PR diff context; GitHub only allows review threads on changed lines and unchanged lines shown for context",
      notifications[#notifications]
    )
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
    assert.is_false(picker_lines[2] and picker_lines[2]:match("^%[NEW%]") ~= nil)
  end)

  it("closes the same-line picker with the configured close shortcut", function()
    local file_buf = make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 8, 0 })

    comments.show_comment_thread()
    assert.equals("picker", comments.capture_ui_state().kind)

    feed_keys(" q")

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
