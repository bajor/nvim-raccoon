describe(":Raccoon command", function()
  local notifications
  local original_notify
  local original_open_module
  local original_ui_module
  local original_config_module

  before_each(function()
    if vim.fn.exists(":Raccoon") == 0 then
      vim.cmd("runtime plugin/raccoon.lua")
    end

    notifications = {}
    original_notify = vim.notify
    vim.notify = function(msg, level, opts)
      table.insert(notifications, { msg = msg, level = level, opts = opts })
    end
    original_open_module = package.loaded["raccoon.open"]
    original_ui_module = package.loaded["raccoon.ui"]
    original_config_module = package.loaded["raccoon.config"]
    package.loaded["raccoon.config"] = {
      validate_close_shortcut = function()
        return { valid = true }
      end,
      config_path = "/tmp/claude/raccoon-tests/command-spec-config.json",
      autofix_close_shortcut = function()
        return { changed = false, skipped = true, reason = "already_valid" }
      end,
    }
  end)

  after_each(function()
    vim.notify = original_notify
    package.loaded["raccoon.open"] = original_open_module
    package.loaded["raccoon.ui"] = original_ui_module
    package.loaded["raccoon.config"] = original_config_module
  end)

  it("registers the user command", function()
    assert.equals(2, vim.fn.exists(":Raccoon"))
  end)

  it("dispatches :Raccoon exit to raccoon.open.close_all_sessions", function()
    local close_calls = 0
    package.loaded["raccoon.open"] = {
      close_all_sessions = function()
        close_calls = close_calls + 1
      end,
    }

    vim.cmd("Raccoon exit")

    assert.equals(1, close_calls)
  end)

  it("does not block :Raccoon exit when shortcuts.close is invalid", function()
    local exit_calls = 0
    package.loaded["raccoon.config"] = {
      validate_close_shortcut = function()
        return { valid = false, reason = "shortcuts.close must be a non-empty shortcut string", value = false }
      end,
    }
    package.loaded["raccoon.open"] = {
      close_all_sessions = function()
        exit_calls = exit_calls + 1
      end,
    }

    vim.cmd("Raccoon exit")

    assert.equals(1, exit_calls)
  end)

  it("dispatches :Raccoon description to raccoon.ui.show_description", function()
    local show_calls = 0
    package.loaded["raccoon.ui"] = {
      show_description = function()
        show_calls = show_calls + 1
      end,
    }

    vim.cmd("Raccoon description")

    assert.equals(1, show_calls)
  end)

  it("blocks subcommands when shortcuts.close is invalid", function()
    local show_calls = 0
    package.loaded["raccoon.config"] = {
      validate_close_shortcut = function()
        return { valid = false, reason = "shortcuts.close must be a non-empty shortcut string", value = false }
      end,
    }
    package.loaded["raccoon.ui"] = {
      show_description = function()
        show_calls = show_calls + 1
      end,
    }

    vim.cmd("Raccoon description")

    assert.equals(0, show_calls)
    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.truthy(notifications[1].msg:find("Cannot run :Raccoon description", 1, true))
    assert.truthy(notifications[1].msg:find("Run :Raccoon config", 1, true))
  end)

  it("dispatches :Raccoon sync to raccoon.open.sync", function()
    local sync_calls = 0
    package.loaded["raccoon.open"] = {
      sync = function()
        sync_calls = sync_calls + 1
      end,
    }

    vim.cmd("Raccoon sync")

    assert.equals(1, sync_calls)
  end)

  it("rejects removed :Raccoon close subcommand", function()
    vim.cmd("Raccoon close")

    assert.equals(1, #notifications)
    assert.equals(vim.log.levels.ERROR, notifications[1].level)
    assert.equals("Unknown subcommand: close", notifications[1].msg)
  end)

  it("dispatches :Raccoon desc alias to raccoon.ui.show_description", function()
    local show_calls = 0
    package.loaded["raccoon.ui"] = {
      show_description = function()
        show_calls = show_calls + 1
      end,
    }

    vim.cmd("Raccoon desc")

    assert.equals(1, show_calls)
    assert.equals(0, #notifications)
  end)

  it("dispatches :Raccoon update alias to raccoon.open.sync", function()
    local sync_calls = 0
    package.loaded["raccoon.open"] = {
      sync = function()
        sync_calls = sync_calls + 1
      end,
    }

    vim.cmd("Raccoon update")

    assert.equals(1, sync_calls)
    assert.equals(0, #notifications)
  end)

  it("dispatches :Raccoon refresh alias to raccoon.open.sync", function()
    local sync_calls = 0
    package.loaded["raccoon.open"] = {
      sync = function()
        sync_calls = sync_calls + 1
      end,
    }

    vim.cmd("Raccoon refresh")

    assert.equals(1, sync_calls)
    assert.equals(0, #notifications)
  end)
end)
