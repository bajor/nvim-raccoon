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
      assert.is_table(config.defaults.tokens)
      assert.is_table(config.defaults.repos)
      assert.is_string(config.defaults.clone_root)
      assert.is_number(config.defaults.pull_changes_interval)
      assert.equals(300, config.defaults.pull_changes_interval)
    end)

    it("repos defaults to empty table", function()
      assert.same({}, config.defaults.repos)
    end)

    it("does not contain dead config fields", function()
      assert.is_nil(config.defaults.ghostty_path)
      assert.is_nil(config.defaults.nvim_path)
      assert.is_nil(config.defaults.notifications)
      assert.is_nil(config.defaults.poll_interval_seconds)
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

    it("returns error when tokens are missing", function()
      local tmpfile = test_tmp_dir .. "/no_token.json"
      local f = io.open(tmpfile, "w")
      f:write('{}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.matches("tokens is required", err)

      os.remove(tmpfile)
    end)

    it("returns error when tokens is missing", function()
      local tmpfile = test_tmp_dir .. "/no_tokens.json"
      local f = io.open(tmpfile, "w")
      f:write('{}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.matches("tokens is required", err)

      os.remove(tmpfile)
    end)

    it("loads config without github_username", function()
      local tmpfile = test_tmp_dir .. "/no_username.json"
      local f = io.open(tmpfile, "w")
      f:write('{"tokens": {"owner": "ghp_xxx"}}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_not_nil(cfg)
      assert.is_nil(err)

      os.remove(tmpfile)
    end)

    it("silently ignores github_username in config (backward compat)", function()
      local tmpfile = test_tmp_dir .. "/legacy_username.json"
      local f = io.open(tmpfile, "w")
      f:write('{"github_username": "old-user", "tokens": {"owner": "ghp_xxx"}}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_not_nil(cfg)
      assert.is_nil(err)

      os.remove(tmpfile)
    end)

    it("normalizes github_host with protocol prefix", function()
      local tmpfile = test_tmp_dir .. "/host_proto.json"
      local f = io.open(tmpfile, "w")
      f:write('{"github_host": "https://github.mycompany.com", "tokens": {"owner": "ghp_xxx"}}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.equals("github.mycompany.com", cfg.github_host)

      os.remove(tmpfile)
    end)

    it("normalizes github_host with uppercase and whitespace", function()
      local tmpfile = test_tmp_dir .. "/host_case.json"
      local f = io.open(tmpfile, "w")
      f:write('{"github_host": "  GitHub.COM  ", "tokens": {"owner": "ghp_xxx"}}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.equals("github.com", cfg.github_host)

      os.remove(tmpfile)
    end)

    it("normalizes github_host with trailing slashes", function()
      local tmpfile = test_tmp_dir .. "/host_slash.json"
      local f = io.open(tmpfile, "w")
      f:write('{"github_host": "github.mycompany.com/", "tokens": {"owner": "ghp_xxx"}}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.equals("github.mycompany.com", cfg.github_host)

      os.remove(tmpfile)
    end)

    it("loads valid config successfully", function()
      local tmpfile = test_tmp_dir .. "/valid_config.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"owner": "ghp_test123"},
        "clone_root": "~/test/repos"
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      assert.equals("ghp_test123", cfg.tokens["owner"])
      -- Check tilde expansion
      assert.is_not_nil(cfg.clone_root:match("^/"))

      os.remove(tmpfile)
    end)

    it("loads config with repos filter", function()
      local tmpfile = test_tmp_dir .. "/repos_filter.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"acme": "ghp_xxx"},
        "repos": ["acme/backend", "acme/frontend"]
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      assert.same({"acme/backend", "acme/frontend"}, cfg.repos)

      os.remove(tmpfile)
    end)

    it("defaults repos to empty table when not specified", function()
      local tmpfile = test_tmp_dir .. "/no_repos.json"
      local f = io.open(tmpfile, "w")
      f:write('{"tokens": {"owner": "ghp_xxx"}}')
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.same({}, cfg.repos)

      os.remove(tmpfile)
    end)

    it("merges with defaults for missing optional fields", function()
      local tmpfile = test_tmp_dir .. "/partial_config.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"owner": "ghp_test123"}
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      -- Should have default values
      assert.is_not_nil(cfg.clone_root)

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
    it("returns nil when no owner-specific token exists", function()
      local cfg = {
        tokens = {},
      }
      local token = config.get_token_for_owner(cfg, "some-owner")
      assert.is_nil(token)
    end)

    it("returns owner-specific token when available", function()
      local cfg = {
        tokens = {
          ["my-org"] = "org_specific_token",
        },
      }
      local token = config.get_token_for_owner(cfg, "my-org")
      assert.equals("org_specific_token", token)
    end)

    it("returns nil for non-matching owner", function()
      local cfg = {
        tokens = {
          ["other-org"] = "other_token",
        },
      }
      local token = config.get_token_for_owner(cfg, "my-org")
      assert.is_nil(token)
    end)

    it("handles nil tokens table", function()
      local cfg = {
        tokens = nil,
      }
      local token = config.get_token_for_owner(cfg, "any-owner")
      assert.is_nil(token)
    end)

    it("handles empty tokens table", function()
      local cfg = {
        tokens = {},
      }
      local token = config.get_token_for_owner(cfg, "any-owner")
      assert.is_nil(token)
    end)
  end)

  describe("get_token_for_repo", function()
    it("extracts owner from repo string and returns token", function()
      local cfg = {
        tokens = {
          ["my-org"] = "org_token",
        },
      }
      local token = config.get_token_for_repo(cfg, "my-org/my-repo")
      assert.equals("org_token", token)
    end)

    it("returns nil for unrecognized owner", function()
      local cfg = {
        tokens = {
          ["other-org"] = "other_token",
        },
      }
      local token = config.get_token_for_repo(cfg, "my-org/my-repo")
      assert.is_nil(token)
    end)

    it("returns nil for invalid repo format", function()
      local cfg = {
        tokens = {},
      }
      local token = config.get_token_for_repo(cfg, "invalid-format")
      assert.is_nil(token)
    end)

    it("returns nil for empty string", function()
      local cfg = {
        tokens = {},
      }
      local token = config.get_token_for_repo(cfg, "")
      assert.is_nil(token)
    end)

    it("handles repo with multiple slashes", function()
      local cfg = {
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
    it("accepts config with tokens map", function()
      local tmpfile = test_tmp_dir .. "/tokens_only.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {
          "org1": "token1",
          "org2": "token2"
        }
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

    it("ignores unknown fields in config", function()
      local tmpfile = test_tmp_dir .. "/extra_fields.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "some_unknown_field": "value",
        "tokens": {
          "special-org": "special_token"
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)
      assert.equals("special_token", cfg.tokens["special-org"])

      os.remove(tmpfile)
    end)
  end)

  describe("load edge cases", function()
    it("passes through unknown fields from config file", function()
      local tmpfile = test_tmp_dir .. "/extra_fields.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"owner": "ghp_xxx"},
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
        "next_thread", "prev_thread",
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

  describe("is_enabled", function()
    it("returns true for normal shortcut strings", function()
      assert.is_true(config.is_enabled("<leader>j"))
      assert.is_true(config.is_enabled("<leader>pr"))
    end)

    it("returns false for false", function()
      assert.is_false(config.is_enabled(false))
    end)

    it("returns false for vim.NIL (JSON null)", function()
      assert.is_false(config.is_enabled(vim.NIL))
    end)

    it("returns false for nil", function()
      assert.is_false(config.is_enabled(nil))
    end)

    it("returns false for empty string", function()
      assert.is_false(config.is_enabled(""))
    end)

    it("returns false for non-string types", function()
      assert.is_false(config.is_enabled(42))
      assert.is_false(config.is_enabled({}))
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
        "tokens": {"user": "ghp_xxx"},
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
        "tokens": {"user": "ghp_xxx"}
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

    it("preserves false values for disabled shortcuts", function()
      local tmpfile = test_tmp_dir .. "/disabled_shortcuts.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"user": "ghp_xxx"},
        "shortcuts": {
          "pr_list": false,
          "commit_mode": {
            "exit": false
          }
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local shortcuts = config.load_shortcuts()
      assert.is_false(shortcuts.pr_list)
      assert.is_false(config.is_enabled(shortcuts.pr_list))
      -- Non-overridden keys keep defaults
      assert.equals(config.defaults.shortcuts.close, shortcuts.close)
      -- Nested: overridden
      assert.is_false(shortcuts.commit_mode.exit)
      -- Nested: non-overridden keep defaults
      assert.equals(config.defaults.shortcuts.commit_mode.next_page, shortcuts.commit_mode.next_page)

      os.remove(tmpfile)
    end)

    it("sanitizes null values to defaults", function()
      local tmpfile = test_tmp_dir .. "/null_shortcuts.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"user": "ghp_xxx"},
        "shortcuts": {
          "pr_list": null,
          "close": null,
          "commit_mode": {
            "exit": null
          }
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local shortcuts = config.load_shortcuts()
      -- null should fall back to defaults, not vim.NIL
      assert.equals(config.defaults.shortcuts.pr_list, shortcuts.pr_list)
      assert.equals(config.defaults.shortcuts.close, shortcuts.close)
      assert.equals(config.defaults.shortcuts.commit_mode.exit, shortcuts.commit_mode.exit)

      os.remove(tmpfile)
    end)

    it("sanitizes numeric values to defaults", function()
      local tmpfile = test_tmp_dir .. "/numeric_shortcuts.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"user": "ghp_xxx"},
        "shortcuts": {
          "pr_list": 42,
          "commit_mode": {
            "next_page": 99
          }
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local shortcuts = config.load_shortcuts()
      assert.equals(config.defaults.shortcuts.pr_list, shortcuts.pr_list)
      assert.equals(config.defaults.shortcuts.commit_mode.next_page, shortcuts.commit_mode.next_page)

      os.remove(tmpfile)
    end)

    it("sanitizes empty string values to defaults", function()
      local tmpfile = test_tmp_dir .. "/empty_str_shortcuts.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"user": "ghp_xxx"},
        "shortcuts": {
          "close": ""
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local shortcuts = config.load_shortcuts()
      assert.equals(config.defaults.shortcuts.close, shortcuts.close)

      os.remove(tmpfile)
    end)

    it("recovers when commit_mode is replaced with a scalar", function()
      local tmpfile = test_tmp_dir .. "/scalar_commit_mode.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"user": "ghp_xxx"},
        "shortcuts": {
          "commit_mode": "oops"
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local shortcuts = config.load_shortcuts()
      -- commit_mode should be restored to defaults
      assert.is_table(shortcuts.commit_mode)
      assert.equals(config.defaults.shortcuts.commit_mode.next_page, shortcuts.commit_mode.next_page)
      assert.equals(config.defaults.shortcuts.commit_mode.exit, shortcuts.commit_mode.exit)

      os.remove(tmpfile)
    end)

    it("drops unknown shortcut keys", function()
      local tmpfile = test_tmp_dir .. "/unknown_keys.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {"user": "ghp_xxx"},
        "shortcuts": {
          "nonexistent_key": "<leader>z",
          "pr_list": "<leader>pp"
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local shortcuts = config.load_shortcuts()
      assert.is_nil(shortcuts.nonexistent_key)
      assert.equals("<leader>pp", shortcuts.pr_list)

      os.remove(tmpfile)
    end)
  end)

  describe("multi-host tokens", function()
    it("get_token_for_owner returns token and default host for string token", function()
      local cfg = {
        github_host = "github.com",
        tokens = { ["my-user"] = "ghp_xxx" },
      }
      local token, host = config.get_token_for_owner(cfg, "my-user")
      assert.equals("ghp_xxx", token)
      assert.equals("github.com", host)
    end)

    it("get_token_for_owner returns token and custom host for table token", function()
      local cfg = {
        github_host = "github.com",
        tokens = { ["work-org"] = { token = "ghp_yyy", host = "github.acme.com" } },
      }
      local token, host = config.get_token_for_owner(cfg, "work-org")
      assert.equals("ghp_yyy", token)
      assert.equals("github.acme.com", host)
    end)

    it("get_token_for_owner uses default host when table token has no host", function()
      local cfg = {
        github_host = "github.mycompany.com",
        tokens = { ["org"] = { token = "ghp_zzz" } },
      }
      local token, host = config.get_token_for_owner(cfg, "org")
      assert.equals("ghp_zzz", token)
      assert.equals("github.mycompany.com", host)
    end)

    it("get_token_for_owner returns nil, nil for missing owner", function()
      local cfg = {
        github_host = "github.com",
        tokens = { ["other"] = "ghp_xxx" },
      }
      local token, host = config.get_token_for_owner(cfg, "missing")
      assert.is_nil(token)
      assert.is_nil(host)
    end)

    it("get_token_for_repo returns token and host for table token", function()
      local cfg = {
        github_host = "github.com",
        tokens = { ["work-org"] = { token = "ghp_yyy", host = "github.acme.com" } },
      }
      local token, host = config.get_token_for_repo(cfg, "work-org/backend")
      assert.equals("ghp_yyy", token)
      assert.equals("github.acme.com", host)
    end)

    it("get_all_tokens normalizes mixed string and table tokens", function()
      local cfg = {
        github_host = "github.com",
        tokens = {
          ["personal"] = "ghp_aaa",
          ["work"] = { token = "ghp_bbb", host = "github.acme.com" },
        },
      }
      local entries = config.get_all_tokens(cfg)
      assert.equals(2, #entries)

      -- Sort by key for deterministic assertion
      table.sort(entries, function(a, b) return a.key < b.key end)
      assert.equals("personal", entries[1].key)
      assert.equals("ghp_aaa", entries[1].token)
      assert.equals("github.com", entries[1].host)
      assert.equals("work", entries[2].key)
      assert.equals("ghp_bbb", entries[2].token)
      assert.equals("github.acme.com", entries[2].host)
    end)

    it("loads config with table token and normalizes host", function()
      local tmpfile = test_tmp_dir .. "/multi_host.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {
          "personal": "ghp_aaa",
          "work": {"token": "ghp_bbb", "host": "https://GitHub.Acme.COM/"}
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(err)
      assert.is_not_nil(cfg)

      local token, host = config.get_token_for_owner(cfg, "work")
      assert.equals("ghp_bbb", token)
      assert.equals("github.acme.com", host)

      os.remove(tmpfile)
    end)

    it("rejects table token with empty host", function()
      local tmpfile = test_tmp_dir .. "/empty_host.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {
          "org": {"token": "ghp_xxx", "host": ""}
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.truthy(err:find("host"))

      os.remove(tmpfile)
    end)

    it("rejects table token with whitespace-only host", function()
      local tmpfile = test_tmp_dir .. "/whitespace_host.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {
          "org": {"token": "ghp_xxx", "host": "   "}
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.truthy(err:find("host"))

      os.remove(tmpfile)
    end)

    it("rejects table token with protocol-only host", function()
      local tmpfile = test_tmp_dir .. "/proto_only_host.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {
          "org": {"token": "ghp_xxx", "host": "https://"}
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.truthy(err:find("host"))

      os.remove(tmpfile)
    end)

    it("rejects table token with missing token field", function()
      local tmpfile = test_tmp_dir .. "/bad_table_token.json"
      local f = io.open(tmpfile, "w")
      f:write([[{
        "tokens": {
          "bad": {"host": "github.acme.com"}
        }
      }]])
      f:close()

      config.config_path = tmpfile
      local cfg, err = config.load()
      assert.is_nil(cfg)
      assert.is_not_nil(err)
      assert.truthy(err:find("token"))

      os.remove(tmpfile)
    end)
  end)
end)
