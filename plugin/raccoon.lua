-- Prevent loading twice
if vim.g.loaded_raccoon then
  return
end
vim.g.loaded_raccoon = 1

local function format_config_value(value)
  if value == nil or value == vim.NIL then
    return "null"
  end
  if type(value) == "string" then
    return string.format("%q", value)
  end
  return tostring(value)
end

local function create_default_config(config_path)
  local clone_root = vim.fs.joinpath(vim.fn.stdpath("data"), "raccoon", "repos")
  local home = vim.fn.expand("~")
  clone_root = clone_root:gsub("^" .. vim.pesc(home), "~")
  local default_config = string.format([[{
  "github_host": "github.com",
  "tokens": {
    "your-username": "ghp_xxxxxxxxxxxxxxxxxxxx"
  },
  "clone_root": "%s",
  "pull_changes_interval": 300,
  "commit_viewer": {
    "grid": { "rows": 2, "cols": 2 },
    "base_commits_count": 20
  },
  "shortcuts": {
    "pr_list": "<leader>pr",
    "show_shortcuts": "<leader>?",
    "next_point": "<leader>j",
    "prev_point": "<leader>k",
    "next_file": "<leader>nf",
    "prev_file": "<leader>pf",
    "next_thread": "<leader>nt",
    "prev_thread": "<leader>pt",
    "comment": "<leader>c",
    "description": "<leader>dd",
    "list_comments": "<leader>ll",
    "merge": "<leader>rr",
    "commit_viewer": "<leader>cm",
    "comment_save": "<leader>s",
    "comment_resolve": "<leader>r",
    "comment_unresolve": "<leader>u",
    "close": "<leader>q",
    "commit_mode": {
      "next_page": "<leader>j",
      "prev_page": "<leader>k",
      "next_page_alt": "<leader>l",
      "exit": "<leader>cm",
      "maximize_prefix": "<leader>m",
      "browse_files": "<leader>f"
    }
  }
}]], clone_root)
  local file = io.open(config_path, "w")
  if file then
    file:write(default_config)
    file:close()
  end
end

local function open_config_with_autofix()
  local cfg = require("raccoon.config")
  local config_path = cfg.config_path
  local config_dir = vim.fn.fnamemodify(config_path, ":h")
  if vim.fn.isdirectory(config_dir) == 0 then
    vim.fn.mkdir(config_dir, "p")
  end

  if vim.fn.filereadable(config_path) == 0 then
    create_default_config(config_path)
    vim.cmd("edit " .. config_path)
    return
  end

  local fix = cfg.autofix_close_shortcut()
  if fix.changed then
    vim.notify(
      string.format(
        "Raccoon config auto-fix: shortcuts.close %s -> %q",
        format_config_value(fix.old_value),
        fix.new_value
      ),
      vim.log.levels.WARN
    )
  elseif fix.reason == "parse_error" then
    vim.notify(
      "Raccoon: config.json has invalid JSON; skipped auto-fix for shortcuts.close",
      vim.log.levels.WARN
    )
  elseif fix.reason == "unsafe_patch" then
    vim.notify(
      "Raccoon: could not safely auto-fix shortcuts.close in-place; open and update it manually.",
      vim.log.levels.WARN
    )
  end

  vim.cmd("edit " .. config_path)
end

local known_subcommands = {
  open = true,
  prs = true,
  list = true,
  description = true,
  desc = true,
  sync = true,
  update = true,
  refresh = true,
  exit = true,
  merge = true,
  squash = true,
  rebase = true,
  shortcuts = true,
  commits = true,
  ["local"] = true,
  config = true,
}

local function validate_required_close_or_warn(subcommand)
  if subcommand == "config" or subcommand == "exit" then
    return true
  end

  local cfg = require("raccoon.config")
  local check = cfg.validate_close_shortcut()
  if check.valid then
    return true
  end

  local msg = string.format(
    "Cannot run :Raccoon %s because shortcuts.close is invalid (%s).\n"
      .. "Current value: %s\n"
      .. "Fix config to include: \"shortcuts\": { \"close\": \"<leader>q\" }\n"
      .. "Run :Raccoon config to auto-fix.",
    subcommand,
    check.reason or "invalid value",
    format_config_value(check.value)
  )
  vim.notify(msg, vim.log.levels.ERROR)
  return false
end

-- Create the Raccoon command
vim.api.nvim_create_user_command("Raccoon", function(opts)
  local args = opts.fargs
  local subcommand = args[1]

  if not subcommand then
    vim.notify("Usage: :Raccoon <prs|list|description|sync|merge|local|exit>", vim.log.levels.WARN)
    return
  end

  if not known_subcommands[subcommand] then
    vim.notify("Unknown subcommand: " .. subcommand, vim.log.levels.ERROR)
    return
  end

  if subcommand == "config" then
    open_config_with_autofix()
    return
  end

  if subcommand == "exit" then
    local pr_open = require("raccoon.open")
    pr_open.close_all_sessions()
    return
  end

  if not validate_required_close_or_warn(subcommand) then
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
  end
end, {
  nargs = "*",
  complete = function(_, cmdline, _)
    local args = vim.split(cmdline, "%s+")
    if #args == 2 then
      -- Complete subcommands
      return {
        "open", "prs", "list", "description", "desc", "sync", "update", "refresh",
        "merge", "squash", "rebase", "commits", "local", "shortcuts", "exit", "config",
      }
    end
    return {}
  end,
  desc = "Raccoon commands",
})
