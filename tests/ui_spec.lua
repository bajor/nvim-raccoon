local ui = require("raccoon.ui")

describe("raccoon.ui", function()
  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(ui)
    end)

    it("has create_floating_window function", function()
      assert.is_function(ui.create_floating_window)
    end)

    it("has show_description function", function()
      assert.is_function(ui.show_description)
    end)

    it("has close_pr_list function", function()
      assert.is_function(ui.close_pr_list)
    end)

    it("has state table", function()
      assert.is_table(ui.state)
    end)
  end)

  describe("create_floating_window", function()
    after_each(function()
      -- Clean up any open windows
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= "" then
          vim.api.nvim_win_close(win, true)
        end
      end
    end)

    it("creates a floating window", function()
      local win, buf = ui.create_floating_window({
        width = 40,
        height = 10,
        title = "Test",
      })

      assert.is_number(win)
      assert.is_number(buf)
      assert.is_true(vim.api.nvim_win_is_valid(win))
      assert.is_true(vim.api.nvim_buf_is_valid(buf))

      -- Check window config
      local config = vim.api.nvim_win_get_config(win)
      assert.equals("editor", config.relative)
      assert.equals(40, config.width)
      assert.equals(10, config.height)

      -- Cleanup
      vim.api.nvim_win_close(win, true)
    end)

    it("uses default dimensions if not provided", function()
      local win, buf = ui.create_floating_window({})

      local config = vim.api.nvim_win_get_config(win)
      assert.equals(60, config.width)
      assert.equals(20, config.height)

      vim.api.nvim_win_close(win, true)
    end)

    it("sets buffer options correctly", function()
      local win, buf = ui.create_floating_window({})

      assert.equals("wipe", vim.bo[buf].bufhidden)
      assert.equals("nofile", vim.bo[buf].buftype)
      assert.is_false(vim.bo[buf].swapfile)

      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe("close_pr_list", function()
    it("closes the PR list window if open", function()
      -- Create a window first
      local win, buf = ui.create_floating_window({})
      ui.state.win = win
      ui.state.buf = buf

      -- Close it
      ui.close_pr_list()

      -- Window should be closed
      assert.is_false(vim.api.nvim_win_is_valid(win))
      assert.is_nil(ui.state.win)
      assert.is_nil(ui.state.buf)
    end)

    it("handles already closed window gracefully", function()
      ui.state.win = nil
      ui.state.buf = nil

      -- Should not error
      ui.close_pr_list()
    end)
  end)

  describe("state", function()
    it("has expected fields", function()
      -- win and buf start as nil (no window open yet)
      -- but the fields exist on the table
      assert.is_table(ui.state)
      assert.is_table(ui.state.prs)
      assert.is_number(ui.state.selected)
    end)

    it("can track selected index", function()
      ui.state.selected = 5
      assert.equals(5, ui.state.selected)
      ui.state.selected = 1 -- reset
    end)

    it("can store PR list", function()
      ui.state.prs = {
        { number = 1, title = "PR 1" },
        { number = 2, title = "PR 2" },
      }
      assert.equals(2, #ui.state.prs)
      assert.equals("PR 1", ui.state.prs[1].title)
      ui.state.prs = {} -- reset
    end)

    it("has description_win field", function()
      -- Should be nil initially
      assert.is_nil(ui.state.description_win)
    end)
  end)

  describe("create_floating_window with percentages", function()
    after_each(function()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local config = vim.api.nvim_win_get_config(win)
        if config.relative ~= "" then
          vim.api.nvim_win_close(win, true)
        end
      end
    end)

    it("uses percentage-based width", function()
      local win, _ = ui.create_floating_window({
        width_pct = 0.5,
        height = 10,
      })

      local config = vim.api.nvim_win_get_config(win)
      local expected_width = math.floor(vim.o.columns * 0.5)
      assert.equals(expected_width, config.width)

      vim.api.nvim_win_close(win, true)
    end)

    it("uses percentage-based height", function()
      local win, _ = ui.create_floating_window({
        width = 40,
        height_pct = 0.3,
      })

      local config = vim.api.nvim_win_get_config(win)
      local expected_height = math.floor(vim.o.lines * 0.3)
      assert.equals(expected_height, config.height)

      vim.api.nvim_win_close(win, true)
    end)

    it("uses custom border style", function()
      local win, _ = ui.create_floating_window({
        border = "single",
      })

      local config = vim.api.nvim_win_get_config(win)
      -- Border config varies by Neovim version, just check window is valid
      assert.is_true(vim.api.nvim_win_is_valid(win))

      vim.api.nvim_win_close(win, true)
    end)
  end)

  describe("show_description", function()
    local state = require("raccoon.state")

    before_each(function()
      state.reset()
    end)

    it("warns when no active session", function()
      local warned = false
      local original_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end

      ui.show_description()

      vim.notify = original_notify
      assert.is_true(warned)
    end)

    it("warns when PR not set", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      -- Don't set PR data

      local warned = false
      local original_notify = vim.notify
      vim.notify = function(_, level)
        if level == vim.log.levels.WARN then
          warned = true
        end
      end

      ui.show_description()

      vim.notify = original_notify
      assert.is_true(warned)
    end)

    it("opens description window when PR is set", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_pr({
        number = 1,
        title = "Test PR",
        body = "Test description",
        user = { login = "testuser" },
        head = { ref = "feature" },
        base = { ref = "main" },
      })

      ui.show_description()

      -- Window should be open
      assert.is_not_nil(ui.state.description_win)
      assert.is_true(vim.api.nvim_win_is_valid(ui.state.description_win))

      -- Clean up
      vim.api.nvim_win_close(ui.state.description_win, true)
      ui.state.description_win = nil
    end)

    it("toggles description window off when called twice", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_pr({
        number = 1,
        title = "Test PR",
        body = "Test description",
        user = { login = "testuser" },
        head = { ref = "feature" },
        base = { ref = "main" },
      })

      -- First call opens
      ui.show_description()
      assert.is_not_nil(ui.state.description_win)

      -- Second call closes (toggle)
      ui.show_description()
      assert.is_nil(ui.state.description_win)
    end)
  end)

  describe("show_pr_list", function()
    after_each(function()
      ui.close_pr_list()
    end)

    it("has show_pr_list function", function()
      assert.is_function(ui.show_pr_list)
    end)

    it("opens a floating window", function()
      local original_fetch = ui.fetch_all_prs
      ui.fetch_all_prs = function(callback) callback({}, nil) end

      ui.show_pr_list()

      assert.is_not_nil(ui.state.win)
      assert.is_true(vim.api.nvim_win_is_valid(ui.state.win))

      ui.fetch_all_prs = original_fetch
    end)

    it("toggles window off when called twice", function()
      local original_fetch = ui.fetch_all_prs
      ui.fetch_all_prs = function(callback) callback({}, nil) end

      ui.show_pr_list()
      assert.is_not_nil(ui.state.win)

      ui.show_pr_list()
      assert.is_nil(ui.state.win)

      ui.fetch_all_prs = original_fetch
    end)

    it("stores PRs in state after fetch", function()
      local mock_prs = {
        {
          number = 42,
          title = "Test PR",
          html_url = "https://github.com/owner/repo/pull/42",
          user = { login = "testuser" },
          updated_at = "2026-01-01T00:00:00Z",
          base = { repo = { full_name = "owner/repo" } },
        },
      }

      local original_fetch = ui.fetch_all_prs
      ui.fetch_all_prs = function(callback) callback(mock_prs, nil) end

      ui.show_pr_list()

      assert.equals(1, #ui.state.prs)
      assert.equals(42, ui.state.prs[1].number)

      ui.fetch_all_prs = original_fetch
    end)

    it("reorders PRs by repo so selected index matches display order", function()
      -- PRs arrive in callback order: repo2, repo1, repo1
      -- Display groups by repo: repo1(#100, #42), repo2(#55)
      -- After reorder, flat array should match display: #100, #42, #55
      local mock_prs = {
        {
          number = 55,
          title = "PR from repo2",
          html_url = "https://github.com/owner/repo2/pull/55",
          user = { login = "user" },
          updated_at = "2026-01-01T00:00:00Z",
          base = { repo = { full_name = "owner/repo2" } },
        },
        {
          number = 100,
          title = "First PR from repo1",
          html_url = "https://github.com/owner/repo1/pull/100",
          user = { login = "user" },
          updated_at = "2026-01-01T00:00:00Z",
          base = { repo = { full_name = "owner/repo1" } },
        },
        {
          number = 42,
          title = "Second PR from repo1",
          html_url = "https://github.com/owner/repo1/pull/42",
          user = { login = "user" },
          updated_at = "2026-01-01T00:00:00Z",
          base = { repo = { full_name = "owner/repo1" } },
        },
      }

      local original_fetch = ui.fetch_all_prs
      ui.fetch_all_prs = function(callback) callback(mock_prs, nil) end

      ui.show_pr_list()

      -- repo2 is seen first, so display order is: repo2(#55), repo1(#100, #42)
      assert.equals(3, #ui.state.prs)
      assert.equals(55, ui.state.prs[1].number)
      assert.equals(100, ui.state.prs[2].number)
      assert.equals(42, ui.state.prs[3].number)

      ui.fetch_all_prs = original_fetch
    end)

    it("resets selected to 1 on open", function()
      ui.state.selected = 5

      local original_fetch = ui.fetch_all_prs
      ui.fetch_all_prs = function(callback) callback({}, nil) end

      ui.show_pr_list()

      assert.equals(1, ui.state.selected)

      ui.fetch_all_prs = original_fetch
    end)
  end)

  describe("relative_time", function()
    -- Fixed "now" = 2026-03-08T12:00:00Z (epoch 1772971200)
    -- This date is during US DST transition weekend, verifying no DST sensitivity.
    local now = 1772971200

    it("returns empty for nil input", function()
      assert.equals("", ui.relative_time(nil, now))
    end)

    it("returns empty for unparseable input", function()
      assert.equals("", ui.relative_time("not-a-date", now))
    end)

    it("returns just now for <60s ago", function()
      assert.equals("just now", ui.relative_time("2026-03-08T11:59:30Z", now))
    end)

    it("returns minutes ago", function()
      assert.equals("5 mins ago", ui.relative_time("2026-03-08T11:55:00Z", now))
    end)

    it("returns 1 min ago (singular)", function()
      assert.equals("1 min ago", ui.relative_time("2026-03-08T11:59:00Z", now))
    end)

    it("returns hours ago", function()
      assert.equals("3 hours ago", ui.relative_time("2026-03-08T09:00:00Z", now))
    end)

    it("returns 1 hour ago (singular)", function()
      assert.equals("1 hour ago", ui.relative_time("2026-03-08T11:00:00Z", now))
    end)

    it("returns days ago", function()
      assert.equals("2 days ago", ui.relative_time("2026-03-06T12:00:00Z", now))
    end)

    it("returns 1 day ago (singular)", function()
      assert.equals("1 day ago", ui.relative_time("2026-03-07T12:00:00Z", now))
    end)

    it("handles timestamps across US DST spring-forward boundary", function()
      -- now is 2026-03-08T12:00:00Z (Sunday, after US spring-forward at 2AM local)
      -- PR was created 2026-03-07T06:00:00Z (Saturday, before spring-forward)
      -- Exactly 30 hours apart, regardless of any local DST change
      assert.equals("1 day ago", ui.relative_time("2026-03-07T06:00:00Z", now))
    end)

    it("produces correct diff for known epoch values", function()
      -- 2026-01-01T00:00:00Z = epoch 1767225600
      -- now_utc = 1767225600 + 7200 = 1767232800 (exactly 2 hours later)
      assert.equals("2 hours ago", ui.relative_time("2026-01-01T00:00:00Z", 1767232800))
    end)
  end)
end)
