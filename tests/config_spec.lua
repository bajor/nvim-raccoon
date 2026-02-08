local config = require("raccoon.config")

-- Use /tmp/claude/ for temp files (sandbox-safe)
local test_tmp_dir = "/tmp/claude/raccoon-tests"

describe("raccoon.config", function()
  local original_config_path

  before_each(function()
    -- Save original config path
    original_config_path = config.config_path
    -- Ensure test tmp dir exists
    vim.fn.mkdir(test_tmp_dir, "p")
  end)

  after_each(function()
    -- Restore original config path
    config.config_path = original_config_path
  end)

  describe("defaults", function()
    it("has all required default fields", function()
      assert.is_string(config.defaults.github_token)
      assert.is_string(config.defaults.github_username)
      assert.is_table(config.defaults.repos)
      assert.is_string(config.defaults.clone_root)
      assert.is_number(config.defaults.poll_interval_seconds)
    end)

    it("does not contain dead config fields", function()
      assert.is_nil(config.defaults.ghostty_path)
      assert.is_nil(config.defaults.nvim_path)
      assert.is_nil(config.defaults.notifications)
    end)
  end)

  describe("load", function()
    it("returns error when config file does not exist", function()
      config.config_path = "/nonexistent/path/config.json"
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.matches("Config file not found", err)
    end)

    it("returns error for invalid JSON", function()
      local tmpfile = test_tmp_dir .. "/invalid_json.json"
      local f = io.open(tmpfile, "w")
      f:write("{ invalid json }")
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.matches("Invalid JSON", err)

      os.remove(tmpfile)
    end)

    it("returns error when github_token and tokens are missing", function()
      local tmpfile = test_tmp_dir .. "/no_token.json"
      local f = io.open(tmpfile, "w")
      f:write('{"github_username": "user", "repos": ["owner/repo"]}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.matches("github_token or tokens is required", err)

      os.remove(tmpfile)
    end)

    it("returns error when github_username is missing", function()
      local tmpfile = test_tmp_dir .. "/no_username.json"
      local f = io.open(tmpfile, "w")
      f:write('{"github_token": "ghp_xxx", "repos": ["owner/repo"]}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.matches("github_username is required", err)

      os.remove(tmpfile)
    end)

    it("accepts empty repos for auto-discovery", function()
      local tmpfile = test_tmp_dir .. "/empty_repos.json"
      local f = io.open(tmpfile, "w")
      f:write('{"github_token": "ghp_xxx", "github_username": "user", "repos": []}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      -- Empty repos is now valid - enables auto-discovery
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      assert.equals(0, #cfg.repos)

      os.remove(tmpfile)
    end)

    it("returns error for invalid repo format", function()
      local tmpfile = test_tmp_dir .. "/invalid_repo.json"
      local f = io.open(tmpfile, "w")
      f:write('{"github_token": "ghp_xxx", "github_username": "user", "repos": ["invalid"]}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.matches("Invalid repo format", err)

      os.remove(tmpfile)
    end)

    it("loads valid config successfully", function()
      local tmpfile = test_tmp_dir .. "/valid_config.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "github_token": "ghp_test123",
        "github_username": "testuser",
        "repos": ["owner/repo1", "owner/repo2"],
        "clone_root": "~/test/repos"
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      assert.equals("ghp_test123", cfg.github_token)
      assert.equals("testuser", cfg.github_username)
      assert.equals(2, #cfg.repos)
      -- Check tilde expansion
      assert.is_not_nil(cfg.clone_root:match("^/"))

      os.remove(tmpfile)
    end)

    it("merges with defaults for missing optional fields", function()
      local tmpfile = test_tmp_dir .. "/partial_config.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "github_token": "ghp_test123",
        "github_username": "testuser",
        "repos": ["owner/repo"]
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      -- Should have default values
      assert.equals(300, cfg.poll_interval_seconds)

      os.remove(tmpfile)
    end)
  end)

  describe("create_default", function()
    it("creates default config file", function()
      local tmpdir = test_tmp_dir .. "/create_default_test"
      vim.fn.mkdir(tmpdir, "p")

      config.config_path = tmpdir .. "/config.json"
      local ok, err = config.create_default()
      assert.is_true(ok)
      assert.is_nil(err)
      assert.equals(1, vim.fn.filereadable(config.config_path))

      -- Cleanup
      os.remove(config.config_path)
      vim.fn.delete(tmpdir, "d")
    end)

    it("returns error if config already exists", function()
      local tmpfile = test_tmp_dir .. "/existing_config.json"
      local f = io.open(tmpfile, "w")
      f:write("{}")
      f:close()

      config.config_path = tmpfile
      local ok, err = config.create_default()
      assert.is_false(ok)
      assert.is_not_nil(err)
      assert.matches("already exists", err)

      os.remove(tmpfile)
    end)
  end)

  describe("get_token_for_owner", function()
    it("returns default token when no owner-specific token exists", function()
      local cfg = {
        github_token = "default_token",
        tokens = {},
      }
      local token = config.get_token_for_owner(cfg, "some-owner")
      assert.equals("default_token", token)
    end)

    it("returns owner-specific token when available", function()
      local cfg = {
        github_token = "default_token",
        tokens = {
          ["my-org"] = "org_specific_token",
        },
      }
      local token = config.get_token_for_owner(cfg, "my-org")
      assert.equals("org_specific_token", token)
    end)

    it("returns default token for non-matching owner", function()
      local cfg = {
        github_token = "default_token",
        tokens = {
          ["other-org"] = "other_token",
        },
      }
      local token = config.get_token_for_owner(cfg, "my-org")
      assert.equals("default_token", token)
    end)

    it("handles nil tokens table", function()
      local cfg = {
        github_token = "default_token",
        tokens = nil,
      }
      local token = config.get_token_for_owner(cfg, "any-owner")
      assert.equals("default_token", token)
    end)

    it("handles empty tokens table", function()
      local cfg = {
        github_token = "default_token",
        tokens = {},
      }
      local token = config.get_token_for_owner(cfg, "any-owner")
      assert.equals("default_token", token)
    end)
  end)

  describe("get_token_for_repo", function()
    it("extracts owner from repo string and returns token", function()
      local cfg = {
        github_token = "default_token",
        tokens = {
          ["my-org"] = "org_token",
        },
      }
      local token = config.get_token_for_repo(cfg, "my-org/my-repo")
      assert.equals("org_token", token)
    end)

    it("returns default token for unrecognized owner", function()
      local cfg = {
        github_token = "default_token",
        tokens = {
          ["other-org"] = "other_token",
        },
      }
      local token = config.get_token_for_repo(cfg, "my-org/my-repo")
      assert.equals("default_token", token)
    end)

    it("returns default token for invalid repo format", function()
      local cfg = {
        github_token = "default_token",
        tokens = {},
      }
      local token = config.get_token_for_repo(cfg, "invalid-format")
      assert.equals("default_token", token)
    end)

    it("returns default token for empty string", function()
      local cfg = {
        github_token = "default_token",
        tokens = {},
      }
      local token = config.get_token_for_repo(cfg, "")
      assert.equals("default_token", token)
    end)

    it("handles repo with multiple slashes", function()
      local cfg = {
        github_token = "default_token",
        tokens = {
          ["my-org"] = "org_token",
        },
      }
      -- Should extract "my-org" as owner
      local token = config.get_token_for_repo(cfg, "my-org/my-repo/extra")
      assert.equals("org_token", token)
    end)
  end)

  describe("load with tokens", function()
    it("accepts config with tokens map instead of github_token", function()
      local tmpfile = test_tmp_dir .. "/tokens_only.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "github_username": "testuser",
        "tokens": {
          "org1": "token1",
          "org2": "token2"
        },
        "repos": ["org1/repo1"]
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      assert.is_table(cfg.tokens)
      assert.equals("token1", cfg.tokens["org1"])

      os.remove(tmpfile)
    end)

    it("accepts config with both github_token and tokens", function()
      local tmpfile = test_tmp_dir .. "/both_tokens.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "github_token": "default_token",
        "github_username": "testuser",
        "tokens": {
          "special-org": "special_token"
        },
        "repos": ["owner/repo"]
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      assert.equals("default_token", cfg.github_token)
      assert.equals("special_token", cfg.tokens["special-org"])

      os.remove(tmpfile)
    end)
  end)

  describe("load edge cases", function()
    it("handles repos with dots in name", function()
      local tmpfile = test_tmp_dir .. "/dotted_repo.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "github_token": "ghp_xxx",
        "github_username": "user",
        "repos": ["owner/repo.nvim", "owner/my-plugin.lua"]
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      assert.equals(2, #cfg.repos)

      os.remove(tmpfile)
    end)

    it("handles repos with underscores and hyphens", function()
      local tmpfile = test_tmp_dir .. "/special_chars_repo.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "github_token": "ghp_xxx",
        "github_username": "user",
        "repos": ["my_org/my-repo_name", "org-name/repo_name"]
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      assert.equals(2, #cfg.repos)

      os.remove(tmpfile)
    end)

    it("passes through unknown fields from config file", function()
      local tmpfile = test_tmp_dir .. "/extra_fields.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "github_token": "ghp_xxx",
        "github_username": "user",
        "repos": ["owner/repo"],
        "some_extra_field": "value"
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      -- Extra fields from JSON should be preserved via tbl_deep_extend
      assert.equals("value", cfg.some_extra_field)

      os.remove(tmpfile)
    end)
  end)

  describe("shortcuts defaults", function()
    it("has shortcuts in defaults", function()
      assert.is_table(config.defaults.shortcuts)
    end)

    it("has all expected shortcut keys", function()
      local expected = {
        "pr_list", "show_shortcuts",
        "next_point", "prev_point", "next_file", "prev_file",
        "next_thread", "prev_thread", "next_file_alt", "prev_file_alt",
        "comment", "description", "list_comments", "merge", "commit_viewer",
        "comment_save", "comment_resolve", "comment_unresolve",
        "close",
      }
      for _, key in ipairs(expected) do
        assert.is_string(config.defaults.shortcuts[key],
          "Missing shortcut default: " .. key)
      end
    end)

    it("has commit_mode subsection with expected keys", function()
      assert.is_table(config.defaults.shortcuts.commit_mode)
      local expected = { "next_page", "prev_page", "next_page_alt", "exit", "maximize_prefix" }
      for _, key in ipairs(expected) do
        assert.is_string(config.defaults.shortcuts.commit_mode[key],
          "Missing commit_mode shortcut default: " .. key)
      end
    end)

    it("default shortcuts are non-empty strings", function()
      for key, val in pairs(config.defaults.shortcuts) do
        if key ~= "commit_mode" then
          assert.is_string(val, "Shortcut " .. key .. " should be a string")
          assert.is_true(#val > 0, "Shortcut " .. key .. " should not be empty")
        end
      end
      for key, val in pairs(config.defaults.shortcuts.commit_mode) do
        assert.is_string(val, "commit_mode." .. key .. " should be a string")
        assert.is_true(#val > 0, "commit_mode." .. key .. " should not be empty")
      end
    end)
  end)

  describe("load_shortcuts", function()
    it("returns defaults when config file does not exist", function()
      config.config_path = "/nonexistent/path/config.json"
      local shortcuts = config.load_shortcuts()
      assert.is_table(shortcuts)
      assert.equals(config.defaults.shortcuts.pr_list, shortcuts.pr_list)
      assert.equals(config.defaults.shortcuts.close, shortcuts.close)
    end)

    it("returns defaults for invalid JSON", function()
      local tmpfile = test_tmp_dir .. "/invalid_shortcuts.json"
      local f = io.open(tmpfile, "w")
      f:write("{ invalid json }")
      f:close()

      config.config_path = tmpfile
      local shortcuts = config.load_shortcuts()
      assert.is_table(shortcuts)
      assert.equals(config.defaults.shortcuts.pr_list, shortcuts.pr_list)

      os.remove(tmpfile)
    end)

    it("merges user shortcut overrides with defaults", function()
      local tmpfile = test_tmp_dir .. "/custom_shortcuts.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "github_token": "ghp_xxx",
        "github_username": "user",
        "shortcuts": {
          "pr_list": "<leader>pp",
          "close": "<leader>x",
          "commit_mode": {
            "exit": "<leader>xx"
          }
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local shortcuts = config.load_shortcuts()
      -- Overridden values
      assert.equals("<leader>pp", shortcuts.pr_list)
      assert.equals("<leader>x", shortcuts.close)
      -- Non-overridden values get defaults
      assert.equals(config.defaults.shortcuts.next_point, shortcuts.next_point)
      assert.equals(config.defaults.shortcuts.description, shortcuts.description)
      -- Nested commit_mode: overridden key
      assert.equals("<leader>xx", shortcuts.commit_mode.exit)
      -- Nested commit_mode: non-overridden keys keep defaults
      assert.equals(config.defaults.shortcuts.commit_mode.next_page, shortcuts.commit_mode.next_page)

      os.remove(tmpfile)
    end)

    it("works when config has no shortcuts key", function()
      local tmpfile = test_tmp_dir .. "/no_shortcuts.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "github_token": "ghp_xxx",
        "github_username": "user"
      }]])
      f:close()

      config.config_path = tmpfile
      local shortcuts = config.load_shortcuts()
      assert.is_table(shortcuts)
      -- All defaults should be present
      assert.equals(config.defaults.shortcuts.pr_list, shortcuts.pr_list)
      assert.equals(config.defaults.shortcuts.close, shortcuts.close)

      os.remove(tmpfile)
    end)

    it("returns independent copies (no mutation)", function()
      config.config_path = "/nonexistent/path/config.json"
      local s1 = config.load_shortcuts()
      local s2 = config.load_shortcuts()
      s1.pr_list = "MUTATED"
      assert.is_not_equal("MUTATED", s2.pr_list)
    end)
  end)
end)
