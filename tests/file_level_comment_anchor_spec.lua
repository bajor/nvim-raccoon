local api = require("raccoon.api")
local comment_metadata = require("raccoon.comment_metadata")
local comments = require("raccoon.comments")
local config = require("raccoon.config")
local state = require("raccoon.state")
local thread_index = require("raccoon.thread_index")

local CLONE_PATH = "/tmp/raccoon-file-level-comment-anchor"

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

describe("file-level review comments", function()
  before_each(function()
    state.reset()
    state.start({
      owner = "owner",
      repo = "repo",
      number = 1,
      url = "https://github.com/owner/repo/pull/1",
      clone_path = CLONE_PATH,
    })
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
    })
  end)

  after_each(function()
    if comments.close_overlays then
      comments.close_overlays(true)
    end
    state.reset()
  end)

  it("sends plain bodies for file-level fallback comments", function()
    local original_config_load = config.load
    local original_get_token_entry = config.get_token_entry
    local original_api_init = api.init
    local original_create_comment = api.create_comment
    local original_sync = require("raccoon.open").sync

    local captured_body
    local sync_called = false

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
      captured_body = opts.body
      assert.equals("file", opts.subject_type)
      callback({ id = 700 }, nil)
    end
    require("raccoon.open").sync = function()
      sync_called = true
    end

    make_file_buffer("lua/a.lua", 12)
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    comments.show_comment_thread()

    local editor_buf = vim.api.nvim_get_current_buf()
    local line_count = vim.api.nvim_buf_line_count(editor_buf)
    vim.api.nvim_buf_set_lines(editor_buf, line_count - 1, line_count, false, { "persist me here" })
    vim.cmd("stopinsert")
    trigger_buffer_mapping(editor_buf, "n", " s")
    vim.wait(1000, function()
      return sync_called
    end, 10)

    config.load = original_config_load
    config.get_token_entry = original_get_token_entry
    api.init = original_api_init
    api.create_comment = original_create_comment
    require("raccoon.open").sync = original_sync

    assert.equals("persist me here", captured_body)
  end)

  it("keeps file-level review comments at GitHub's file placement while stripping legacy anchors", function()
    local comment = {
      id = 41,
      body = "<!-- raccoon:file-line 10 -->\npersisted body",
      path = "lua/a.lua",
      subject_type = "file",
      line = 1,
      original_line = 1,
      position = 1,
      thread_id = "thread-file-1",
      resolved = false,
      in_reply_to_id = vim.NIL,
      created_at = "2026-01-01T00:00:00Z",
      user = { login = "reviewer" },
    }

    comment_metadata.normalize_file_level_comment(comment)
    state.set_comments("lua/a.lua", { comment })

    local index, err = thread_index.build()

    assert.is_nil(err)
    assert.equals("persisted body", comment.body)
    assert.equals(1, comment.line)
    assert.is_nil(comment.position)
    assert.equals(1, index.thread_by_id["thread-file-1"].line)
    assert.equals("FILE", index.thread_by_id["thread-file-1"].line_label)
  end)
end)
