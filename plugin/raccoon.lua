-- Prevent loading twice
if vim.g.loaded_raccoon then
  return
end
vim.g.loaded_raccoon = 1

-- Create the Raccoon command
vim.api.nvim_create_user_command("Raccoon", function(opts)
  local args = opts.fargs
  local subcommand = args[1]

  if not subcommand then
    vim.notify("Usage: :Raccoon <prs|list|description|sync|merge|local|close>", vim.log.levels.WARN)
    return
  end

  if subcommand == "open" then
    -- Internal command used by macOS app to open PRs
    local url = args[2]
    -- If no URL provided, read from temp file (written by macOS app to avoid long command line issues)
    if not url then
      local url_file = vim.fs.joinpath(vim.fn.stdpath("data"), "raccoon-url.txt")
      local f = io.open(url_file, "r")
      if f then
        url = f:read("*a"):gsub("%s+$", "")
        f:close()
        os.remove(url_file)
      end
    end
    if not url or url == "" then
      vim.notify("Usage: :Raccoon open <url>", vim.log.levels.WARN)
      return
    end
    local pr_open = require("raccoon.open")
    pr_open.open_pr(url)
  elseif subcommand == "prs" then
    local ui = require("raccoon.ui")
    ui.show_pr_list()
  elseif subcommand == "list" then
    local pr_comments = require("raccoon.comments")
    pr_comments.list_comments()
  elseif subcommand == "description" or subcommand == "desc" then
    local ui = require("raccoon.ui")
    ui.show_description()
  elseif subcommand == "sync" or subcommand == "update" or subcommand == "refresh" then
    local pr_open = require("raccoon.open")
    pr_open.sync()
  elseif subcommand == "close" then
    local pr_open = require("raccoon.open")
    pr_open.close_pr()
  elseif subcommand == "merge" or subcommand == "squash" or subcommand == "rebase" then
    local state = require("raccoon.state")
    local api = require("raccoon.api")
    local config = require("raccoon.config")

    if not state.is_active() then
      vim.notify("No active PR review session", vim.log.levels.WARN)
      return
    end

    local owner = state.get_owner()
    local repo = state.get_repo()
    local number = state.get_number()
    local pr = state.get_pr()

    -- Check for conflicts first
    local sync_status = state.get_sync_status()
    if sync_status.has_conflicts then
      vim.notify("Cannot merge: PR has merge conflicts", vim.log.levels.ERROR)
      return
    end

    local cfg, cfg_err = config.load()
    if cfg_err then
      vim.notify("Config error: " .. cfg_err, vim.log.levels.ERROR)
      return
    end

    api.init(state.get_github_host() or cfg.github_host)
    local token = config.get_token_for_owner(cfg, owner)
    if not token then
      vim.notify(
        string.format("No token configured for '%s'. Add it to tokens in config.", owner),
        vim.log.levels.ERROR
      )
      return
    end

    -- Determine merge method
    local merge_method = "merge"
    local method_name = "Merging"
    if subcommand == "squash" then
      merge_method = "squash"
      method_name = "Squash merging"
    elseif subcommand == "rebase" then
      merge_method = "rebase"
      method_name = "Rebasing and merging"
    end

    vim.notify(method_name .. " PR #" .. number .. "...", vim.log.levels.INFO)

    api.merge_pr(owner, repo, number, {
      merge_method = merge_method,
      commit_title = pr.title,
    }, token, function(_result, err)
      vim.schedule(function()
        if err then
          vim.notify("Merge failed: " .. err, vim.log.levels.ERROR)
          return
        end
        vim.notify("PR #" .. number .. " merged successfully!", vim.log.levels.INFO)
        -- Close the review session after merge
        local pr_open = require("raccoon.open")
        pr_open.close_pr()
      end)
    end)
  elseif subcommand == "shortcuts" then
    local ui = require("raccoon.ui")
    ui.show_shortcuts()
  elseif subcommand == "commits" then
    local commits_mod = require("raccoon.commits")
    commits_mod.toggle()
  elseif subcommand == "local" then
    local localcommits = require("raccoon.localcommits")
    localcommits.toggle()
  elseif subcommand == "config" then
    -- Open config file in current buffer
    local cfg = require("raccoon.config")
    local config_path = cfg.config_path
    if vim.fn.filereadable(config_path) == 0 then
      local ok, err = cfg.create_default()
      if not ok then
        vim.notify("Failed to create config file: " .. err, vim.log.levels.ERROR)
        return
      end
    end
    vim.cmd("edit " .. vim.fn.fnameescape(config_path))
  else
    vim.notify("Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  complete = function(_, cmdline, _)
    local args = vim.split(cmdline, "%s+")
    if #args == 2 then
      -- Complete subcommands
      return {
        "prs", "list", "description", "sync", "merge", "squash",
        "rebase", "commits", "local", "shortcuts", "close", "config",
      }
    end
    return {}
  end,
  desc = "Raccoon commands",
})
