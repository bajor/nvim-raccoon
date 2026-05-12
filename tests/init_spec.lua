local config = require("raccoon.config")

local function fresh_raccoon()
  package.loaded["raccoon"] = nil
  return require("raccoon")
end

describe("raccoon", function()
  local original_load_shortcuts
  local created_keymaps

  local function clear_created_keymaps()
    for _, lhs in ipairs(created_keymaps) do
      pcall(vim.keymap.del, "n", lhs)
    end
    created_keymaps = {}
  end

  before_each(function()
    original_load_shortcuts = config.load_shortcuts
    created_keymaps = {}
    pcall(vim.api.nvim_del_augroup_by_name, "RaccoonHighlights")
    package.loaded["raccoon"] = nil
  end)

  after_each(function()
    config.load_shortcuts = original_load_shortcuts
    clear_created_keymaps()
    pcall(vim.api.nvim_del_augroup_by_name, "RaccoonHighlights")
    package.loaded["raccoon"] = nil
  end)

  it("setup accepts empty options", function()
    config.load_shortcuts = function()
      return { pr_list = false, show_shortcuts = false }
    end

    local raccoon = fresh_raccoon()
    raccoon.setup({})

    assert.is_table(raccoon.config)
  end)

  it("setup merges user options", function()
    config.load_shortcuts = function()
      return { pr_list = false, show_shortcuts = false }
    end

    local raccoon = fresh_raccoon()
    raccoon.setup({ custom_option = "test" })

    assert.equals("test", raccoon.config.custom_option)
  end)

  it("defines highlight groups during setup", function()
    config.load_shortcuts = function()
      return { pr_list = false, show_shortcuts = false }
    end

    local raccoon = fresh_raccoon()
    raccoon.setup({})

    local add_hl = vim.api.nvim_get_hl(0, { name = "RaccoonAdd" })
    local delete_hl = vim.api.nvim_get_hl(0, { name = "RaccoonDelete" })
    local visible_hl = vim.api.nvim_get_hl(0, { name = "RaccoonFileVisible" })

    assert.equals(tonumber("2d5a2d", 16), add_hl.bg)
    assert.equals(tonumber("5a2020", 16), delete_hl.bg)
    assert.equals(tonumber("ffffff", 16), visible_hl.fg)
  end)

  it("registers a ColorScheme autocmd that reapplies highlights", function()
    config.load_shortcuts = function()
      return { pr_list = false, show_shortcuts = false }
    end

    local raccoon = fresh_raccoon()
    raccoon.setup({})

    local autocmds = vim.api.nvim_get_autocmds({
      event = "ColorScheme",
      group = "RaccoonHighlights",
    })

    assert.equals(1, #autocmds)
  end)

  it("installs enabled global keymaps from shortcuts", function()
    created_keymaps = { "<leader>pp", "<leader>ss" }
    config.load_shortcuts = function()
      return {
        pr_list = "<leader>pp",
        show_shortcuts = "<leader>ss",
      }
    end

    local raccoon = fresh_raccoon()
    raccoon.setup({})

    local pr_map = vim.fn.maparg("<leader>pp", "n", false, true)
    local shortcuts_map = vim.fn.maparg("<leader>ss", "n", false, true)

    assert.equals("Raccoon: PR list", pr_map.desc)
    assert.equals("Raccoon: Show shortcuts", shortcuts_map.desc)
  end)

  it("skips disabled global keymaps", function()
    created_keymaps = { "<leader>enabled" }
    config.load_shortcuts = function()
      return {
        pr_list = "<leader>enabled",
        show_shortcuts = false,
      }
    end

    local raccoon = fresh_raccoon()
    raccoon.setup({})

    assert.equals("Raccoon: PR list", vim.fn.maparg("<leader>enabled", "n", false, true).desc)
    assert.equals("", vim.fn.maparg(config.defaults.shortcuts.show_shortcuts, "n"))
  end)

  it("delegates statusline to raccoon.open", function()
    package.loaded["raccoon.open"] = {
      statusline = function()
        return "behind by 2"
      end,
      is_active = function()
        return true
      end,
    }
    config.load_shortcuts = function()
      return { pr_list = false, show_shortcuts = false }
    end

    local raccoon = fresh_raccoon()

    assert.equals("behind by 2", raccoon.statusline())
    assert.is_true(raccoon.is_active())

    package.loaded["raccoon.open"] = nil
  end)
end)

