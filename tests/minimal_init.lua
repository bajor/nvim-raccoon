-- Minimal init for running tests with plenary.busted

-- Add the plugin to runtimepath
vim.opt.runtimepath:prepend(vim.fn.getcwd() .. "/nvim")

-- Add plenary to runtimepath (for CI and local dev)
local plenary_path = vim.fn.expand("~/.local/share/nvim/site/pack/vendor/start/plenary.nvim")
if vim.fn.isdirectory(plenary_path) == 1 then
  vim.opt.runtimepath:prepend(plenary_path)
end

-- Also check for lazy.nvim managed plenary
local lazy_plenary = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
if vim.fn.isdirectory(lazy_plenary) == 1 then
  vim.opt.runtimepath:prepend(lazy_plenary)
end

-- Load plenary
vim.cmd("runtime plugin/plenary.vim")

-- Set leader key for keymap tests
vim.g.mapleader = " "

-- Disable swap files for tests
vim.opt.swapfile = false
