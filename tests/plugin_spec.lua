local function load_plugin()
  vim.g.loaded_raccoon = nil
  pcall(vim.api.nvim_del_user_command, "Raccoon")
  dofile(vim.fn.getcwd() .. "/plugin/raccoon.lua")
end

local function remove_stubs(names)
  for _, name in ipairs(names) do
    package.loaded[name] = nil
  end
end

describe("plugin.raccoon", function()
  local stubbed_modules
  local original_notify

  before_each(function()
    stubbed_modules = {}
    original_notify = vim.notify
    pcall(vim.api.nvim_del_user_command, "Raccoon")
    vim.g.loaded_raccoon = nil
  end)

  after_each(function()
    vim.notify = original_notify
    remove_stubs(stubbed_modules)
    pcall(vim.api.nvim_del_user_command, "Raccoon")
    vim.g.loaded_raccoon = nil
  end)

  local function stub_module(name, module)
    package.loaded[name] = module
    table.insert(stubbed_modules, name)
  end

  local function capture_notifications()
    local notifications = {}
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end
    return notifications
  end

  it("creates the :Raccoon command on load", function()
    load_plugin()
    local commands = vim.api.nvim_get_commands({})
    assert.is_table(commands.Raccoon)
    assert.equals("Raccoon commands", commands.Raccoon.definition)
  end)

  it("warns when no subcommand is provided", function()
    local notifications = capture_notifications()
    load_plugin()

    vim.cmd("Raccoon")

    assert.truthy(notifications[1].message:find("Usage: :Raccoon"))
  end)

  it("routes UI and sync aliases to the correct handlers", function()
    local counts = {
      show_pr_list = 0,
      list_comments = 0,
      show_description = 0,
      show_shortcuts = 0,
      sync = 0,
      close_pr = 0,
      toggle_commits = 0,
      toggle_local = 0,
    }

    stub_module("raccoon.ui", {
      show_pr_list = function() counts.show_pr_list = counts.show_pr_list + 1 end,
      show_description = function() counts.show_description = counts.show_description + 1 end,
      show_shortcuts = function() counts.show_shortcuts = counts.show_shortcuts + 1 end,
    })
    stub_module("raccoon.comments", {
      list_comments = function() counts.list_comments = counts.list_comments + 1 end,
    })
    stub_module("raccoon.open", {
      sync = function() counts.sync = counts.sync + 1 end,
      close_pr = function() counts.close_pr = counts.close_pr + 1 end,
    })
    stub_module("raccoon.commits", {
      toggle = function() counts.toggle_commits = counts.toggle_commits + 1 end,
    })
    stub_module("raccoon.localcommits", {
      toggle = function() counts.toggle_local = counts.toggle_local + 1 end,
    })

    load_plugin()

    vim.cmd("Raccoon prs")
    vim.cmd("Raccoon list")
    vim.cmd("Raccoon description")
    vim.cmd("Raccoon desc")
    vim.cmd("Raccoon shortcuts")
    vim.cmd("Raccoon sync")
    vim.cmd("Raccoon update")
    vim.cmd("Raccoon refresh")
    vim.cmd("Raccoon close")
    vim.cmd("Raccoon commits")
    vim.cmd("Raccoon local")

    assert.equals(1, counts.show_pr_list)
    assert.equals(1, counts.list_comments)
    assert.equals(2, counts.show_description)
    assert.equals(1, counts.show_shortcuts)
    assert.equals(3, counts.sync)
    assert.equals(1, counts.close_pr)
    assert.equals(1, counts.toggle_commits)
    assert.equals(1, counts.toggle_local)
  end)

  it("reads the open URL from the temp file when no argument is given", function()
    local captured_url
    local url_file = vim.fs.joinpath(vim.fn.stdpath("data"), "raccoon-url.txt")
    local file = assert(io.open(url_file, "w"))
    file:write("https://github.com/acme/widgets/pull/42\n")
    file:close()

    stub_module("raccoon.open", {
      open_pr = function(url)
        captured_url = url
      end,
    })

    load_plugin()
    vim.cmd("Raccoon open")

    assert.equals("https://github.com/acme/widgets/pull/42", captured_url)
    assert.equals(0, vim.fn.filereadable(url_file))
  end)

  it("warns when open is invoked without a URL", function()
    local notifications = capture_notifications()
    stub_module("raccoon.open", {
      open_pr = function()
        error("should not be called")
      end,
    })

    load_plugin()
    vim.cmd("Raccoon open")

    assert.truthy(notifications[1].message:find("Usage: :Raccoon open"))
  end)

  it("rejects merge commands when no session is active", function()
    local notifications = capture_notifications()
    stub_module("raccoon.state", {
      is_active = function() return false end,
    })
    stub_module("raccoon.api", {})
    stub_module("raccoon.config", {})

    load_plugin()
    vim.cmd("Raccoon merge")

    assert.truthy(notifications[1].message:find("No active PR review session"))
  end)

  it("rejects merge commands when conflicts are present", function()
    local notifications = capture_notifications()
    stub_module("raccoon.state", {
      is_active = function() return true end,
      get_owner = function() return "acme" end,
      get_repo = function() return "widgets" end,
      get_number = function() return 42 end,
      get_pr = function() return { title = "Ship it" } end,
      get_sync_status = function() return { has_conflicts = true } end,
    })
    stub_module("raccoon.api", {})
    stub_module("raccoon.config", {})

    load_plugin()
    vim.cmd("Raccoon merge")

    assert.truthy(notifications[1].message:find("merge conflicts"))
  end)

  it("surfaces config load errors before merge", function()
    local notifications = capture_notifications()
    stub_module("raccoon.state", {
      is_active = function() return true end,
      get_owner = function() return "acme" end,
      get_repo = function() return "widgets" end,
      get_number = function() return 42 end,
      get_pr = function() return { title = "Ship it" } end,
      get_sync_status = function() return { has_conflicts = false } end,
    })
    stub_module("raccoon.api", {})
    stub_module("raccoon.config", {
      load = function() return nil, "broken config" end,
    })

    load_plugin()
    vim.cmd("Raccoon merge")

    assert.truthy(notifications[1].message:find("broken config"))
  end)

  it("surfaces missing token errors before merge", function()
    local notifications = capture_notifications()
    stub_module("raccoon.state", {
      is_active = function() return true end,
      get_owner = function() return "acme" end,
      get_repo = function() return "widgets" end,
      get_number = function() return 42 end,
      get_pr = function() return { title = "Ship it" } end,
      get_sync_status = function() return { has_conflicts = false } end,
      get_github_host = function() return nil end,
    })
    stub_module("raccoon.api", {
      init = function() end,
    })
    stub_module("raccoon.config", {
      load = function() return { github_host = "github.com" }, nil end,
      get_token_for_owner = function() return nil end,
    })

    load_plugin()
    vim.cmd("Raccoon merge")

    assert.truthy(notifications[1].message:find("No token configured"))
  end)

  it("passes squash merge options through to the API and closes the session on success", function()
    local merge_calls = {}
    local closed = 0
    local notifications = capture_notifications()

    stub_module("raccoon.state", {
      is_active = function() return true end,
      get_owner = function() return "acme" end,
      get_repo = function() return "widgets" end,
      get_number = function() return 42 end,
      get_pr = function() return { title = "Ship it" } end,
      get_sync_status = function() return { has_conflicts = false } end,
      get_github_host = function() return nil end,
    })
    stub_module("raccoon.api", {
      init = function(host)
        table.insert(merge_calls, { init_host = host })
      end,
      merge_pr = function(owner, repo, number, opts, token, callback)
        table.insert(merge_calls, {
          owner = owner,
          repo = repo,
          number = number,
          opts = opts,
          token = token,
        })
        callback({}, nil)
      end,
    })
    stub_module("raccoon.config", {
      load = function() return { github_host = "github.com" }, nil end,
      get_token_for_owner = function() return "ghp_test", "github.com" end,
    })
    stub_module("raccoon.open", {
      close_pr = function()
        closed = closed + 1
      end,
    })

    load_plugin()
    vim.cmd("Raccoon squash")
    vim.wait(50)

    assert.equals("github.com", merge_calls[1].init_host)
    assert.equals("squash", merge_calls[2].opts.merge_method)
    assert.equals("Ship it", merge_calls[2].opts.commit_title)
    assert.equals("ghp_test", merge_calls[2].token)
    assert.equals(1, closed)
    assert.truthy(notifications[1].message:find("Squash merging"))
  end)

  it("passes rebase merge options through to the API", function()
    local merge_method

    stub_module("raccoon.state", {
      is_active = function() return true end,
      get_owner = function() return "acme" end,
      get_repo = function() return "widgets" end,
      get_number = function() return 42 end,
      get_pr = function() return { title = "Ship it" } end,
      get_sync_status = function() return { has_conflicts = false } end,
      get_github_host = function() return nil end,
    })
    stub_module("raccoon.api", {
      init = function() end,
      merge_pr = function(_, _, _, opts, _, callback)
        merge_method = opts.merge_method
        callback({}, nil)
      end,
    })
    stub_module("raccoon.config", {
      load = function() return { github_host = "github.com" }, nil end,
      get_token_for_owner = function() return "ghp_test", "github.com" end,
    })
    stub_module("raccoon.open", {
      close_pr = function() end,
    })

    load_plugin()
    vim.cmd("Raccoon rebase")
    vim.wait(50)

    assert.equals("rebase", merge_method)
  end)

  it("creates the default config file when :Raccoon config is used", function()
    local tmpdir = vim.fn.tempname()
    local config_path = tmpdir .. "/config.json"

    stub_module("raccoon.config", {
      config_path = config_path,
    })

    load_plugin()
    vim.cmd("Raccoon config")

    assert.equals(1, vim.fn.filereadable(config_path))
    local current = vim.api.nvim_buf_get_name(0)
    assert.equals(config_path, current)
    vim.cmd("enew")
  end)

  it("shows an error for unknown subcommands", function()
    local notifications = capture_notifications()
    load_plugin()

    vim.cmd("Raccoon nope")

    assert.truthy(notifications[1].message:find("Unknown subcommand"))
  end)
end)
