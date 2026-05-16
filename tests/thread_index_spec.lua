local state = require("raccoon.state")
local thread_index = require("raccoon.thread_index")

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

describe("raccoon.thread_index", function()
  before_each(function()
    state.reset()
    state.start({
      owner = "owner",
      repo = "repo",
      number = 1,
      url = "https://github.com/owner/repo/pull/1",
      clone_path = "/tmp/repo",
    })
    state.set_files({
      { filename = "lua/a.lua" },
      { filename = "lua/b.lua" },
    })
  end)

  it("indexes exact threads, hides resolved flat-diff rows, and marks needs-reply threads", function()
    state.set_viewer_login("me")
    state.set_comments("_reviews", {
      {
        id = 901,
        body = "second review body",
        submitted_at = "2026-01-02T00:00:00Z",
        user = { login = "reviewer-b" },
      },
      {
        id = 900,
        body = "first review body",
        submitted_at = "2026-01-01T00:00:00Z",
        user = { login = "reviewer-a" },
      },
    })
    state.set_comments("lua/a.lua", {
      review_comment({
        id = 1,
        thread_id = "thread-a",
        line = 10,
        body = "initial thread",
        created_at = "2026-01-01T00:00:00Z",
        user = { login = "me" },
      }),
      review_comment({
        id = 2,
        thread_id = "thread-a",
        line = 10,
        body = "reply after me",
        created_at = "2026-01-02T00:00:00Z",
        in_reply_to_id = 1,
        user = { login = "reviewer-1" },
      }),
      review_comment({
        id = 3,
        thread_id = "thread-b",
        line = 10,
        body = "parallel unresolved thread",
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
        line = 10,
        body = "broad PR note on this line",
        user = { login = "issue-author" },
      }),
    })

    local index, err = thread_index.build()

    assert.is_nil(err)
    assert.equals(3, #index.threads)
    assert.equals(2, #index.unresolved_threads)
    assert.equals("first review body", index.review_bodies[1].body)
    assert.equals("second review body", index.review_bodies[2].body)

    local thread_a = index.thread_by_id["thread-a"]
    assert.is_true(thread_a.has_my_comment)
    assert.is_true(thread_a.needs_reply)
    assert.equals(1, thread_a.root_comment_id)
    assert.equals("reviewer-1", thread_a.latest_author)
    assert.equals("L10", thread_a.line_label)

    local thread_b = index.thread_by_id["thread-b"]
    assert.is_false(thread_b.has_my_comment)
    assert.is_false(thread_b.needs_reply)

    local thread_c = index.thread_by_id["thread-c"]
    assert.is_true(thread_c.resolved)

    local line_state = thread_index.get_line_state(index, "lua/a.lua", 10)
    assert.is_not_nil(line_state)
    assert.equals(2, #line_state.threads)
    assert.equals(1, #line_state.issue_comments)
    assert.same({ nr = 1, u = 1, i = 1 }, line_state.counts)

    assert.is_nil(thread_index.get_line_state(index, "lua/a.lua", 8))
  end)

  it("uses original_line and position when line is missing", function()
    local original_line_comment = review_comment({
      id = 11,
      line = vim.NIL,
      original_line = 14,
    })
    local position_comment = review_comment({
      id = 12,
      line = vim.NIL,
      original_line = vim.NIL,
      position = 22,
    })

    assert.equals(14, thread_index.get_comment_line(original_line_comment))
    assert.equals(22, thread_index.get_comment_line(position_comment))
  end)

  it("fails when a review comment is missing a thread id", function()
    local comment = review_comment({
      id = 21,
    })
    comment.thread_id = nil

    state.set_comments("lua/a.lua", {
      comment,
    })

    local index, err = thread_index.build()

    assert.is_nil(index)
    assert.matches("missing thread id on review comment 21", err)
  end)

  it("fails when an unresolved thread has no root review comment", function()
    state.set_comments("lua/a.lua", {
      review_comment({
        id = 31,
        thread_id = "thread-no-root",
        in_reply_to_id = 30,
      }),
    })

    local index, err = thread_index.build()

    assert.is_nil(index)
    assert.matches("missing root review comment for thread thread%-no%-root", err)
  end)
end)
