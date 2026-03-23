local commit_ui = require("raccoon.commit_ui")

describe("raccoon.commit_ui", function()
  -- Shared header window helper
  local function make_header(width)
    width = width or 80
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].modifiable = true
    local win = vim.api.nvim_open_win(buf, false, {
      relative = "editor", row = 0, col = 0, width = width, height = 1,
    })
    vim.wo[win].wrap = true
    return buf, win
  end

  local function teardown_header(buf, win)
    pcall(vim.api.nvim_win_close, win, true)
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  it("header shows subject then updates to full multiline body", function()
    local buf, win = make_header(80)

    local state = { header_buf = buf, header_win = win, current_page = 1 }
    local commit = { message = "feat: add login" }

    -- Initially only subject is available
    commit_ui.update_header(state, commit, 1)
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals("feat: add login", lines[1])

    -- Async fetch completes — full_message now available
    commit.full_message = "feat: add login\n\nAdds OAuth2 flow\nwith refresh tokens"
    commit_ui.update_header(state, commit, 1)
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    assert.equals(1, #lines)
    assert.truthy(lines[1]:find("feat: add login"))
    assert.truthy(lines[1]:find("Adds OAuth2 flow"))
    assert.truthy(lines[1]:find("with refresh tokens"))

    teardown_header(buf, win)
  end)

  it("stale async callback is ignored when select_generation has changed", function()
    local buf, win = make_header(80)
    local git = require("raccoon.git")
    local orig = git.get_commit_message

    local captured_cb
    git.get_commit_message = function(_, _, cb) captured_cb = cb end

    local state = {
      header_buf = buf, header_win = win, current_page = 1,
      select_generation = 1,
    }
    local commit = { sha = "abc123", message = "subject" }

    commit_ui.fetch_and_display_commit_message(state, commit, "/tmp", 1, function() return 1 end)

    -- User navigated away before the callback fires
    state.select_generation = 2
    captured_cb("subject\nfull body text", nil)

    assert.is_nil(commit.full_message)

    git.get_commit_message = orig
    teardown_header(buf, win)
  end)

  it("sidebar widths stay symmetric when requested width is too large", function()
    local cols = 2
    local huge_width = 9999
    local result = commit_ui.compute_effective_sidebar_width(cols, huge_width)

    -- Must not exceed the symmetric maximum
    local separators = cols + 1
    local max_width = math.floor((vim.o.columns - cols - separators) / 2)
    assert.equals(max_width, result)

    -- Both sides would get the same value (function is deterministic)
    assert.equals(result, commit_ui.compute_effective_sidebar_width(cols, huge_width))

    -- A small width that fits should pass through unchanged
    assert.equals(10, commit_ui.compute_effective_sidebar_width(cols, 10))
  end)
end)
