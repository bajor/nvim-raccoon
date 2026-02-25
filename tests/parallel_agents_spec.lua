local pa = require("raccoon.parallel_agents")
local config = require("raccoon.config")

local test_tmp_dir = "/tmp/claude/raccoon-tests"

describe("raccoon.parallel_agents", function()
  local original_config_path

  before_each(function()
    original_config_path = config.config_path
    pa._reset_agents()
    vim.fn.mkdir(test_tmp_dir, "p")
  end)

  after_each(function()
    config.config_path = original_config_path
    pa._reset_agents()
  end)

  describe("get_running_count", function()
    it("starts at 0", function()
      assert.equals(0, pa.get_running_count())
    end)
  end)

  describe("build_prompt", function()
    it("builds prompt with task text only in normal mode", function()
      local result = pa.build_prompt({
        commit_sha = "abc12345def",
        commit_message = "fix: handle nil input",
        filename = "src/main.lua",
      }, "refactor this function")

      assert.truthy(result:find("refactor this function"))
      assert.truthy(result:find("abc12345"))
      assert.truthy(result:find("fix: handle nil input"))
      -- No visual context
      assert.falsy(result:find("Selected code"))
    end)

    it("includes visual selection context", function()
      local result = pa.build_prompt({
        commit_sha = "abc12345def",
        commit_message = "feat: add validation",
        filename = "src/utils.lua",
        visual_lines = { "local x = 1", "local y = 2" },
        line_start = 10,
        line_end = 11,
      }, "explain this code")

      assert.truthy(result:find("explain this code"))
      assert.truthy(result:find("Selected code from src/utils.lua, lines 10%-11"))
      assert.truthy(result:find("local x = 1"))
      assert.truthy(result:find("local y = 2"))
    end)

    it("omits commit info when sha and message are empty", function()
      local result = pa.build_prompt({
        filename = "test.lua",
      }, "do something")

      assert.falsy(result:find("Commit:"))
    end)

    it("includes suffix_prompt when provided", function()
      local result = pa.build_prompt({
        commit_sha = "abc12345",
        commit_message = "test",
        filename = "test.lua",
        suffix_prompt = "Always commit and push when done.",
      }, "task")

      assert.truthy(result:find("Always commit and push when done."))
    end)

    it("omits suffix_prompt when empty", function()
      local result = pa.build_prompt({
        commit_sha = "abc12345",
        commit_message = "test",
        filename = "test.lua",
        suffix_prompt = "",
      }, "task")

      -- Should not have trailing empty section
      local lines = vim.split(result, "\n")
      local last_non_empty
      for i = #lines, 1, -1 do
        if lines[i] ~= "" then
          last_non_empty = lines[i]
          break
        end
      end
      assert.truthy(last_non_empty:find("test"))
    end)

    it("handles special characters in task text", function()
      local result = pa.build_prompt({
        commit_sha = "abc12345",
        commit_message = "test",
        filename = "test.lua",
      }, "fix the 100% CPU usage & memory leak")

      assert.truthy(result:find("100%% CPU"))
    end)
  end)

  describe("build_command", function()
    it("replaces placeholder with shell-escaped prompt", function()
      local cmd = pa.build_command('claude -p "your task"', "hello world")
      assert.truthy(cmd:find("claude %-p "))
      -- Should not contain the placeholder anymore
      assert.falsy(cmd:find('"your task"'))
    end)

    it("returns template unchanged when placeholder is missing", function()
      local cmd = pa.build_command("echo hello", "task")
      assert.equals("echo hello", cmd)
    end)

    it("handles special characters in prompt via shellescape", function()
      local cmd = pa.build_command('claude -p "your task"', "it's a test with $VAR and `backticks`")
      -- shellescape wraps in single quotes, so the original quotes should be escaped
      assert.falsy(cmd:find('"your task"'))
    end)

    it("only replaces the first occurrence", function()
      local cmd = pa.build_command('echo "your task" && echo "your task"', "hello")
      -- First placeholder replaced, second remains
      local _, count = cmd:gsub('"your task"', "")
      assert.equals(1, count)
    end)
  end)

  describe("dispatch guards", function()
    it("notifies when not enabled", function()
      local tmpfile = test_tmp_dir .. "/pa_disabled.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": false}}')
      f:close()
      config.config_path = tmpfile

      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:find("not enabled") then notified = true end
      end

      pa.dispatch({ repo_path = "/tmp" })

      vim.notify = orig_notify
      assert.is_true(notified)
      os.remove(tmpfile)
    end)

    it("notifies when command is empty", function()
      local tmpfile = test_tmp_dir .. "/pa_no_cmd.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": ""}}')
      f:close()
      config.config_path = tmpfile

      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:find("configure") then notified = true end
      end

      pa.dispatch({ repo_path = "/tmp" })

      vim.notify = orig_notify
      assert.is_true(notified)
      os.remove(tmpfile)
    end)

    it("notifies when command lacks placeholder", function()
      local tmpfile = test_tmp_dir .. "/pa_no_placeholder.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": "echo hello"}}')
      f:close()
      config.config_path = tmpfile

      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:find("placeholder") then notified = true end
      end

      pa.dispatch({ repo_path = "/tmp" })

      vim.notify = orig_notify
      assert.is_true(notified)
      os.remove(tmpfile)
    end)
  end)
end)
