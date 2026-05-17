local comments = require("raccoon.comments")
local state = require("raccoon.state")

describe("raccoon.comments", function()
  before_each(function()
    state.reset()
  end)

  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local config = vim.api.nvim_win_get_config(win)
      if config.relative ~= "" then
        vim.api.nvim_win_close(win, true)
      end
    end
  end)

  describe("get_namespace", function()
    it("returns a namespace ID", function()
      local ns = comments.get_namespace()
      assert.is_number(ns)
      assert.is_true(ns > 0)
    end)
  end)

  describe("basic guards", function()
    it("returns empty buffer comments without an active session", function()
      assert.same({}, comments.get_buffer_comments())
    end)

    it("has no unsent text when no editor is open", function()
      assert.is_false(comments.has_unsent_text())
    end)
  end)

  describe("flat diff mode helpers", function()
    it("reports flat diff mode only for an active non-commit review session", function()
      assert.is_false(comments.is_flat_diff_mode())

      state.start({
        owner = "test",
        repo = "repo",
        number = 1,
        url = "https://github.com/test/repo/pull/1",
        clone_path = "/tmp/repo",
      })
      assert.is_true(comments.is_flat_diff_mode())

      state.set_commit_mode(true)
      assert.is_false(comments.is_flat_diff_mode())
    end)
  end)

  describe("buffer safety", function()
    it("ignores invalid buffers when showing comments", function()
      comments.show_comments(-1, {})
    end)

    it("ignores invalid buffers when clearing comments", function()
      comments.clear_comments(-1)
    end)
  end)

  describe("readonly thread popup", function()
    it("uses the editor background highlights", function()
      require("raccoon").setup()

      comments.show_readonly_thread({
        title = "Thread",
        comments = {
          {
            user = { login = "octocat" },
            body = "Looks good to me.",
          },
        },
      })

      local win
      for _, candidate in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(candidate)
        if config.relative ~= "" then
          win = candidate
          break
        end
      end

      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.matches("Normal:Normal", vim.wo[win].winhl)
      assert.matches("FloatBorder:Normal", vim.wo[win].winhl)
    end)
  end)
end)
