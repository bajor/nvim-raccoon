local state = require("raccoon.state")

describe("plugin Raccoon command", function()
  local original_notify

  before_each(function()
    state.reset()
    original_notify = vim.notify
    pcall(vim.api.nvim_del_user_command, "Raccoon")
    vim.g.loaded_raccoon = nil
    dofile(vim.fn.getcwd() .. "/plugin/raccoon.lua")
  end)

  after_each(function()
    vim.notify = original_notify
    state.reset()
  end)

  it("registers the Raccoon command", function()
    local commands = vim.api.nvim_get_commands({})
    assert.is_table(commands.Raccoon)
  end)

  it("includes open in usage text and completion", function()
    local messages = {}
    vim.notify = function(message)
      table.insert(messages, message)
    end

    vim.cmd("Raccoon")

    assert.matches("open", messages[#messages])
    assert.is_true(vim.tbl_contains(vim.fn.getcompletion("Raccoon ", "cmdline"), "open"))
  end)

  it("blocks merge in commit mode", function()
    local messages = {}
    vim.notify = function(message)
      table.insert(messages, message)
    end

    state.start({ owner = "o", repo = "r", number = 1 })
    state.set_commit_mode(true)

    vim.cmd("Raccoon merge")

    assert.equals("Available only in flat diff review mode", messages[#messages])
  end)

  it("blocks unresolved-thread picker in commit mode", function()
    local messages = {}
    vim.notify = function(message)
      table.insert(messages, message)
    end

    state.start({ owner = "o", repo = "r", number = 1 })
    state.set_commit_mode(true)

    vim.cmd("Raccoon threads")

    assert.equals("Available only in flat diff review mode", messages[#messages])
  end)

  it("blocks merge in local mode", function()
    local localcommits = require("raccoon.localcommits")
    local original_is_active = localcommits.is_active
    local messages = {}
    vim.notify = function(message)
      table.insert(messages, message)
    end

    state.start({ owner = "o", repo = "r", number = 1 })
    localcommits.is_active = function()
      return true
    end

    local ok, err = pcall(vim.cmd, "Raccoon merge")
    localcommits.is_active = original_is_active

    assert.is_true(ok, err)
    assert.equals("Available only in flat diff review mode", messages[#messages])
  end)

  it("keeps PR list available in commit mode", function()
    local ui = require("raccoon.ui")
    local original_show_pr_list = ui.show_pr_list
    local called = false
    ui.show_pr_list = function()
      called = true
    end

    state.start({ owner = "o", repo = "r", number = 1 })
    state.set_commit_mode(true)

    local ok, err = pcall(vim.cmd, "Raccoon prs")

    ui.show_pr_list = original_show_pr_list

    assert.is_true(ok, err)
    assert.is_true(called)
  end)
end)
