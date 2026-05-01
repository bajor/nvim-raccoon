local pa = require("raccoon.parallel_agents")
local config = require("raccoon.config")
local mocks = require("tests.helpers.mocks")

local test_tmp_dir = vim.fn.tempname() .. "-raccoon-tests"

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
      local cmd = pa.build_command('claude -p <PROMPT>', "hello world")
      assert.truthy(cmd:find("claude %-p "))
      -- Should not contain the placeholder anymore
      assert.falsy(cmd:find('<PROMPT>'))
    end)

    it("returns template unchanged when placeholder is missing", function()
      local cmd = pa.build_command("echo hello", "task")
      assert.equals("echo hello", cmd)
    end)

    it("handles special characters in prompt via shellescape", function()
      local cmd = pa.build_command('claude -p <PROMPT>', "it's a test with $VAR and `backticks`")
      -- shellescape wraps in single quotes, so the original quotes should be escaped
      assert.falsy(cmd:find('<PROMPT>'))
    end)

    it("only replaces the first occurrence", function()
      local cmd = pa.build_command('echo <PROMPT> && echo <PROMPT>', "hello")
      -- First placeholder replaced, second remains
      local _, count = cmd:gsub('<PROMPT>', "")
      assert.equals(1, count)
    end)
  end)

  describe("statusline and is_active integration", function()
    local original_open

    before_each(function()
      original_open = package.loaded["raccoon.open"]
      package.loaded["raccoon.open"] = {
        statusline = function() return "PR #42: Open" end,
        is_active = function() return false end,
      }
      -- Force raccoon.init to pick up the fresh mock
      package.loaded["raccoon.init"] = nil
    end)

    after_each(function()
      package.loaded["raccoon.open"] = original_open
      package.loaded["raccoon.init"] = nil
    end)

    it("statusline returns base string with 0 agents", function()
      local init = require("raccoon.init")
      assert.equals("PR #42: Open", init.statusline())
    end)

    it("statusline appends singular agent count", function()
      table.insert(pa._get_agents(), { job_id = 1, task_name = "t1" })
      local init = require("raccoon.init")
      assert.equals("PR #42: Open [1 agent]", init.statusline())
    end)

    it("statusline appends plural agent count", function()
      local agents = pa._get_agents()
      table.insert(agents, { job_id = 1, task_name = "t1" })
      table.insert(agents, { job_id = 2, task_name = "t2" })
      table.insert(agents, { job_id = 3, task_name = "t3" })
      local init = require("raccoon.init")
      assert.equals("PR #42: Open [3 agents]", init.statusline())
    end)

    it("is_active returns false with 0 agents and open inactive", function()
      local init = require("raccoon.init")
      assert.is_false(init.is_active())
    end)

    it("is_active returns true when agents are running", function()
      table.insert(pa._get_agents(), { job_id = 1, task_name = "t1" })
      local init = require("raccoon.init")
      assert.is_true(init.is_active())
    end)
  end)

  describe("dispatch success path", function()
    after_each(function()
      pa._open_task_input = nil
      mocks.restore()
    end)

    it("increments count and tracks agent after dispatch", function()
      -- Write enabled config with valid command
      local tmpfile = test_tmp_dir .. "/pa_dispatch.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": "echo <PROMPT>"}}')
      f:close()
      config.config_path = tmpfile

      -- Mock task input to provide task text immediately
      pa._open_task_input = function(on_submit) on_submit("my test task") end

      -- Mock jobstart to capture the job
      mocks.mock_jobstart({ [".*"] = { exit_code = 0 } })

      pa.dispatch({ repo_path = "/tmp" })

      -- Agent should be tracked
      assert.equals(1, pa.get_running_count())
      local agents = pa._get_agents()
      assert.equals("my test task", agents[1].task_name)

      -- Flush vim.schedule so on_exit fires
      vim.wait(100, function() return pa.get_running_count() == 0 end)
      assert.equals(0, pa.get_running_count())

      os.remove(tmpfile)
    end)
  end)

  describe("dispatch failure paths", function()
    after_each(function()
      pa._open_task_input = nil
      mocks.restore()
    end)

    it("reports error when jobstart returns 0 (invalid arguments)", function()
      local tmpfile = test_tmp_dir .. "/pa_jobfail_0.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": "echo <PROMPT>"}}')
      f:close()
      config.config_path = tmpfile

      pa._open_task_input = function(on_submit) on_submit("test task") end

      local orig_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return 0 end

      local notifications = mocks.mock_notify()

      pa.dispatch({ repo_path = "/tmp" })

      vim.fn.jobstart = orig_jobstart
      assert.equals(0, pa.get_running_count())

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("invalid command arguments") and n.level == vim.log.levels.ERROR then
          found = true
        end
      end
      assert.is_true(found)
      os.remove(tmpfile)
    end)

    it("reports error when jobstart returns -1 (not executable)", function()
      local tmpfile = test_tmp_dir .. "/pa_jobfail_neg.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": "echo <PROMPT>"}}')
      f:close()
      config.config_path = tmpfile

      pa._open_task_input = function(on_submit) on_submit("test task") end

      local orig_jobstart = vim.fn.jobstart
      vim.fn.jobstart = function() return -1 end

      local notifications = mocks.mock_notify()

      pa.dispatch({ repo_path = "/tmp" })

      vim.fn.jobstart = orig_jobstart
      assert.equals(0, pa.get_running_count())

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("command not executable") and n.level == vim.log.levels.ERROR then
          found = true
        end
      end
      assert.is_true(found)
      os.remove(tmpfile)
    end)

    it("reports non-zero exit code with stderr in notification", function()
      local tmpfile = test_tmp_dir .. "/pa_exit_fail.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": "echo <PROMPT>"}}')
      f:close()
      config.config_path = tmpfile

      pa._open_task_input = function(on_submit) on_submit("failing task") end

      mocks.mock_jobstart({ [".*"] = {
        exit_code = 1,
        stderr = { "error: something went wrong", "fatal: cannot continue" },
      }})

      local notifications = mocks.mock_notify()

      pa.dispatch({ repo_path = "/tmp" })

      -- Wait for on_exit to fire via vim.schedule
      vim.wait(100, function()
        for _, n in ipairs(notifications) do
          if n.msg:find("exit 1") then return true end
        end
        return false
      end)

      local found = false
      for _, n in ipairs(notifications) do
        if n.msg:find("exit 1") and n.msg:find("something went wrong") and n.level == vim.log.levels.WARN then
          found = true
        end
      end
      assert.is_true(found)
      os.remove(tmpfile)
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

    it("blocks dispatch when claude command lacks permission flags", function()
      local tmpfile = test_tmp_dir .. "/pa_no_perms.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": "claude -p <PROMPT>"}}')
      f:close()
      config.config_path = tmpfile

      local input_opened = false
      pa._open_task_input = function() input_opened = true end

      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:find("permission flags") and level == vim.log.levels.WARN then
          warned = true
        end
      end

      pa.dispatch({ repo_path = "/tmp" })

      vim.notify = orig_notify
      pa._open_task_input = nil
      assert.is_true(warned)
      assert.is_false(input_opened)
      os.remove(tmpfile)
    end)

    it("does not warn when --dangerously-skip-permissions is present", function()
      local tmpfile = test_tmp_dir .. "/pa_with_perms.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": "claude --dangerously-skip-permissions -p <PROMPT>"}}')
      f:close()
      config.config_path = tmpfile

      pa._open_task_input = function() end

      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:find("permission flags") then warned = true end
      end

      pa.dispatch({ repo_path = "/tmp" })

      vim.notify = orig_notify
      pa._open_task_input = nil
      assert.is_false(warned)
      os.remove(tmpfile)
    end)

    it("does not warn when --allowedTools is present", function()
      local tmpfile = test_tmp_dir .. "/pa_allowed_tools.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": "claude --allowedTools Edit,Write -p <PROMPT>"}}')
      f:close()
      config.config_path = tmpfile

      pa._open_task_input = function() end

      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:find("permission flags") then warned = true end
      end

      pa.dispatch({ repo_path = "/tmp" })

      vim.notify = orig_notify
      pa._open_task_input = nil
      assert.is_false(warned)
      os.remove(tmpfile)
    end)

    it("does not warn for non-claude commands", function()
      local tmpfile = test_tmp_dir .. "/pa_non_claude.json"
      local f = io.open(tmpfile, "w")
      f:write('{"parallel_agents": {"enabled": true, "command": "amp -x <PROMPT>"}}')
      f:close()
      config.config_path = tmpfile

      pa._open_task_input = function() end

      local warned = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg:find("permission flags") then warned = true end
      end

      pa.dispatch({ repo_path = "/tmp" })

      vim.notify = orig_notify
      pa._open_task_input = nil
      assert.is_false(warned)
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

  describe("kill_all", function()
    it("stops running jobs and clears tracking", function()
      local agents = pa._get_agents()
      table.insert(agents, { job_id = 101, task_name = "a" })
      table.insert(agents, { job_id = 202, task_name = "b" })

      local stopped_ids = {}
      local original_jobstop = vim.fn.jobstop
      vim.fn.jobstop = function(id)
        table.insert(stopped_ids, id)
        return 1
      end

      local result = pa.kill_all()
      vim.fn.jobstop = original_jobstop

      assert.equals(2, result.requested)
      assert.equals(2, result.stopped)
      assert.equals(0, #result.errors)
      assert.equals(0, pa.get_running_count())
      assert.same({ 101, 202 }, stopped_ids)
    end)

    it("ignores already-gone jobs", function()
      local agents = pa._get_agents()
      table.insert(agents, { job_id = 303, task_name = "a" })
      table.insert(agents, { job_id = 404, task_name = "b" })

      local original_jobstop = vim.fn.jobstop
      vim.fn.jobstop = function(id)
        if id == 303 then return 0 end
        return -1
      end

      local result = pa.kill_all()
      vim.fn.jobstop = original_jobstop

      assert.equals(2, result.requested)
      assert.equals(0, result.stopped)
      assert.equals(0, #result.errors)
      assert.equals(0, pa.get_running_count())
    end)

    it("collects hard errors from jobstop", function()
      local agents = pa._get_agents()
      table.insert(agents, { job_id = 505, task_name = "a" })

      local original_jobstop = vim.fn.jobstop
      vim.fn.jobstop = function()
        error("boom")
      end

      local result = pa.kill_all()
      vim.fn.jobstop = original_jobstop

      assert.equals(1, result.requested)
      assert.equals(0, result.stopped)
      assert.equals(1, #result.errors)
      assert.truthy(result.errors[1]:find("job 505", 1, true))
      assert.equals(0, pa.get_running_count())
    end)

    it("always clears in-progress lock when unexpected errors occur", function()
      local agents = pa._get_agents()
      table.insert(agents, { job_id = 606, task_name = "a" })

      local original_ipairs = ipairs
      _G.ipairs = function()
        error("unexpected ipairs failure")
      end

      local ok, result = pcall(pa.kill_all)
      _G.ipairs = original_ipairs

      assert.is_true(ok)
      assert.equals(1, result.requested)
      assert.equals(0, result.stopped)
      assert.equals(1, #result.errors)
      assert.truthy(result.errors[1]:find("kill_all failed", 1, true))

      local second = pa.kill_all()
      assert.equals(0, second.requested)
      assert.is_nil(second.in_progress)
    end)
  end)
end)
