local config = require("raccoon.config")

local function fresh_raccoon()
  package.loaded["raccoon"] = nil
  return require("raccoon")
end

describe("raccoon", function()
  local original_load_shortcuts
  local original_keymap_set
  local created_keymaps

  local function clear_created_keymaps()
    for _, lhs in ipairs(created_keymaps) do
      pcall(vim.keymap.del, "n", lhs)
    end
    created_keymaps = {}
  end

  before_each(function()
    original_load_shortcuts = config.load_shortcuts
    original_keymap_set = vim.keymap.set
    created_keymaps = {}
    pcall(vim.api.nvim_del_augroup_by_name, "RaccoonHighlights")
    package.loaded["raccoon.ui"] = nil
    package.loaded["raccoon"] = nil
  end)

  after_each(function()
    config.load_shortcuts = original_load_shortcuts
    vim.keymap.set = original_keymap_set
    clear_created_keymaps()
    pcall(vim.api.nvim_del_augroup_by_name, "RaccoonHighlights")
    package.loaded["raccoon.ui"] = nil
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

  it("setup accepts nil options", function()
    config.load_shortcuts = function()
      return { pr_list = false, show_shortcuts = false }
    end

    local raccoon = fresh_raccoon()

    assert.has_no.errors(function()
      raccoon.setup()
    end)
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

  it("keeps existing highlight groups because setup uses default highlights", function()
    config.load_shortcuts = function()
      return { pr_list = false, show_shortcuts = false }
    end

    vim.api.nvim_set_hl(0, "RaccoonAdd", { bg = tonumber("111111", 16) })
    vim.api.nvim_set_hl(0, "RaccoonDelete", {
      bg = tonumber("222222", 16),
      fg = tonumber("eeeeee", 16),
    })
    vim.api.nvim_set_hl(0, "RaccoonAddSign", { fg = tonumber("333333", 16) })
    vim.api.nvim_set_hl(0, "RaccoonDeleteSign", { fg = tonumber("444444", 16) })
    vim.api.nvim_set_hl(0, "RaccoonFileNormal", { fg = tonumber("555555", 16) })
    vim.api.nvim_set_hl(0, "RaccoonFileInCommit", { fg = tonumber("666666", 16) })
    vim.api.nvim_set_hl(0, "RaccoonFileVisible", { fg = tonumber("777777", 16) })

    local raccoon = fresh_raccoon()
    raccoon.setup({})

    assert.equals(tonumber("111111", 16), vim.api.nvim_get_hl(0, { name = "RaccoonAdd" }).bg)
    assert.equals(tonumber("222222", 16), vim.api.nvim_get_hl(0, { name = "RaccoonDelete" }).bg)
    assert.equals(tonumber("333333", 16), vim.api.nvim_get_hl(0, { name = "RaccoonAddSign" }).fg)
    assert.equals(tonumber("444444", 16), vim.api.nvim_get_hl(0, { name = "RaccoonDeleteSign" }).fg)
    assert.equals(tonumber("555555", 16), vim.api.nvim_get_hl(0, { name = "RaccoonFileNormal" }).fg)
    assert.equals(tonumber("666666", 16), vim.api.nvim_get_hl(0, { name = "RaccoonFileInCommit" }).fg)
    assert.equals(tonumber("777777", 16), vim.api.nvim_get_hl(0, { name = "RaccoonFileVisible" }).fg)
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

  it("clears and recreates the ColorScheme autocmd group on repeated setup", function()
    config.load_shortcuts = function()
      return { pr_list = false, show_shortcuts = false }
    end

    local raccoon = fresh_raccoon()
    raccoon.setup({})
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

  it("installs nonrecursive silent keymaps whose callbacks invoke the UI", function()
    local keymap_calls = {}
    local pr_list_calls = 0
    local shortcuts_calls = 0

    config.load_shortcuts = function()
      return {
        pr_list = "<leader>pp",
        show_shortcuts = "<leader>ss",
      }
    end
    package.loaded["raccoon.ui"] = {
      show_pr_list = function()
        pr_list_calls = pr_list_calls + 1
      end,
      show_shortcuts = function()
        shortcuts_calls = shortcuts_calls + 1
      end,
    }
    vim.keymap.set = function(mode, lhs, rhs, opts)
      keymap_calls[lhs] = {
        mode = mode,
        rhs = rhs,
        opts = opts,
      }
    end

    local raccoon = fresh_raccoon()
    raccoon.setup({})

    assert.same("n", keymap_calls["<leader>pp"].mode)
    assert.is_true(keymap_calls["<leader>pp"].opts.noremap)
    assert.is_true(keymap_calls["<leader>pp"].opts.silent)
    assert.equals("Raccoon: PR list", keymap_calls["<leader>pp"].opts.desc)
    assert.same("n", keymap_calls["<leader>ss"].mode)
    assert.is_true(keymap_calls["<leader>ss"].opts.noremap)
    assert.is_true(keymap_calls["<leader>ss"].opts.silent)
    assert.equals("Raccoon: Show shortcuts", keymap_calls["<leader>ss"].opts.desc)

    keymap_calls["<leader>pp"].rhs()
    keymap_calls["<leader>ss"].rhs()

    assert.equals(1, pr_list_calls)
    assert.equals(1, shortcuts_calls)
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
