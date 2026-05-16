local compat = require("raccoon.config_compat")

describe("raccoon.config_compat", function()
  describe("normalize", function()
    it("leaves a clean config (no deprecated keys) untouched", function()
      local input = {
        github_host = "github.com",
        tokens = { ["me"] = "ghp_xxx" },
        sync_interval = 120,
        commit_viewer = {
          grid = { rows = 3, cols = 2 },
          passthrough_keys = { "<leader>x" },
        },
        shortcuts = {
          pr_list = "<leader>pr",
          commit_viewer_toggle = "<leader>cm",
          commit_viewer = { next_page = "<leader>j" },
        },
      }
      local before = vim.deepcopy(input)
      local result = compat.normalize(input)

      assert.same(before, result)
      assert.is_nil(result.pull_changes_interval)
      assert.is_nil(result.passthrough_keymaps)
      assert.is_nil(result.shortcuts.commit_mode)
    end)

    it("migrates every deprecated key to its new name", function()
      local input = {
        pull_changes_interval = 200,
        passthrough_keymaps = {
          "<leader>x",
          { key = "<leader>y" },
          { not_a_key = true },
          42,
        },
        shortcuts = {
          commit_viewer = "<leader>cm",
          commit_mode = {
            next_page = "<leader>j",
            exit = "<leader>cm",
          },
        },
      }

      local result = compat.normalize(input)

      assert.equals(200, result.sync_interval)
      assert.is_nil(result.pull_changes_interval)

      assert.same({ "<leader>x", "<leader>y" }, result.commit_viewer.passthrough_keys)
      assert.is_nil(result.passthrough_keymaps)

      assert.equals("<leader>cm", result.shortcuts.commit_viewer_toggle)

      assert.same(
        { next_page = "<leader>j", exit = "<leader>cm" },
        result.shortcuts.commit_viewer
      )
      assert.is_nil(result.shortcuts.commit_mode)
    end)

    it("migrates legacy comment_save to comment_send", function()
      local input = {
        shortcuts = {
          comment_save = "<leader>x",
        },
      }

      local result = compat.normalize(input)

      assert.equals("<leader>x", result.shortcuts.comment_send)
      assert.is_nil(result.shortcuts.comment_save)
    end)

    it("migrates disabled legacy commit_viewer toggle before migrating commit_mode", function()
      local input = {
        shortcuts = {
          commit_viewer = false,
          commit_mode = {
            next_page = "<leader>j",
            exit = "<leader>x",
          },
        },
      }

      local result = compat.normalize(input)

      assert.is_false(result.shortcuts.commit_viewer_toggle)
      assert.same(
        { next_page = "<leader>j", exit = "<leader>x" },
        result.shortcuts.commit_viewer
      )
      assert.is_nil(result.shortcuts.commit_mode)
    end)

    it("coerces invalid commit_viewer values before migrating passthrough_keymaps", function()
      local input = {
        commit_viewer = 42,
        passthrough_keymaps = {
          "<leader>x",
          { key = "<leader>y" },
        },
      }

      local result = compat.normalize(input)

      assert.same({ "<leader>x", "<leader>y" }, result.commit_viewer.passthrough_keys)
      assert.is_nil(result.passthrough_keymaps)
    end)

    it("new key wins on conflict; old key is dropped", function()
      local input = {
        pull_changes_interval = 999,
        sync_interval = 120,
        passthrough_keymaps = { "<leader>legacy" },
        commit_viewer = {
          passthrough_keys = { "<leader>kept" },
        },
        shortcuts = {
          commit_viewer = "<leader>old_toggle",
          commit_viewer_toggle = "<leader>new_toggle",
          commit_mode = { next_page = "<leader>old_j" },
        },
      }
      -- shortcuts.commit_mode should NOT migrate because shortcuts.commit_viewer
      -- still exists as a string at the start; once that string leaf moves to
      -- _toggle, commit_viewer is freed and commit_mode tries to claim it. But
      -- since commit_viewer_toggle is already set (new wins), and commit_viewer
      -- is freed, commit_mode WILL move into commit_viewer. We test that the
      -- conflict between commit_viewer_toggle (old string-leaf) and the
      -- explicit commit_viewer_toggle resolves to the explicit value.
      local result = compat.normalize(input)

      assert.equals(120, result.sync_interval)
      assert.is_nil(result.pull_changes_interval)

      assert.same({ "<leader>kept" }, result.commit_viewer.passthrough_keys)
      assert.is_nil(result.passthrough_keymaps)

      assert.equals("<leader>new_toggle", result.shortcuts.commit_viewer_toggle)
      assert.same({ next_page = "<leader>old_j" }, result.shortcuts.commit_viewer)
      assert.is_nil(result.shortcuts.commit_mode)
    end)

    it("returns non-tables unchanged", function()
      assert.is_nil(compat.normalize(nil))
      assert.equals(42, compat.normalize(42))
      assert.equals("hello", compat.normalize("hello"))
    end)
  end)
end)
