---@class RaccoonConfig
---@field github_username string GitHub username
---@field github_host string GitHub host (default: "github.com", set for GitHub Enterprise)
---@field tokens table<string, string> Per-owner/org tokens (owner -> token)
---@field clone_root string Root directory for cloned PR repos
---@field pull_changes_interval number Auto-sync interval in seconds (default: 300)

local M = {}

--- Vim mode constants for vim.keymap.set / vim.keymap.del
M.NORMAL = "n"
M.INSERT = "i"

--- Check whether a shortcut binding is enabled (not disabled by user).
--- Users can set a shortcut to false (JSON false) or null (JSON null -> vim.NIL) to disable it.
---@param value any The shortcut value from config
---@return boolean
function M.is_enabled(value)
  return type(value) == "string" and value ~= ""
end

--- Default configuration values
M.defaults = {
  github_username = "",
  github_host = "github.com",
  tokens = {},
  clone_root = vim.fs.joinpath(vim.fn.stdpath("data"), "raccoon", "repos"),
  pull_changes_interval = 300,
  commit_viewer = {
    grid = { rows = 2, cols = 2 },
    base_commits_count = 20,
  },
  shortcuts = {
    -- Global
    pr_list = "<leader>pr",
    show_shortcuts = "<leader>?",
    -- Review navigation
    next_point = "<leader>j",
    prev_point = "<leader>k",
    next_file = "<leader>nf",
    prev_file = "<leader>pf",
    next_thread = "<leader>nt",
    prev_thread = "<leader>pt",
    -- Review actions
    comment = "<leader>c",
    description = "<leader>dd",
    list_comments = "<leader>ll",
    merge = "<leader>rr",
    commit_viewer = "<leader>cm",
    -- Comment editor
    comment_save = "<leader>s",
    comment_resolve = "<leader>r",
    comment_unresolve = "<leader>u",
    -- Common
    close = "<leader>q",
    -- Commit viewer mode
    commit_mode = {
      next_page = "<leader>j",
      prev_page = "<leader>k",
      next_page_alt = "<leader>l",
      exit = "<leader>cm",
      maximize_prefix = "<leader>m",
      browse_files = "<leader>f",
    },
  },
}

--- Config file path
M.config_path = vim.fn.expand("~/.config/raccoon/config.json")

--- Expand tilde in paths
---@param path string
---@return string
local function expand_path(path)
  if path:sub(1, 1) == "~" then
    return vim.fn.expand(path)
  end
  return path
end

--- Whether the GHES version warning has been shown this session
local ghes_warned = false

--- Validate required fields in config
---@param config table
---@return boolean, string?
local function validate_config(config)
  -- Require tokens map
  local has_tokens = config.tokens and type(config.tokens) == "table" and next(config.tokens) ~= nil
  if not has_tokens then
    return false, "tokens is required (maps owner/org name to GitHub token)"
  end

  -- One-time GHES version reminder
  if config.github_host ~= "github.com" and not ghes_warned then
    ghes_warned = true
    vim.notify("raccoon: GitHub Enterprise requires GHES 3.9+", vim.log.levels.INFO)
  end

  return true, nil
end

--- Load configuration from JSON file
---@return RaccoonConfig?, string?
function M.load()
  local path = M.config_path

  -- Check if file exists
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return nil, string.format("Config file not found: %s", path)
  end

  -- Read file
  local file = io.open(path, "r")
  if not file then
    return nil, string.format("Cannot open config file: %s", path)
  end

  local content = file:read("*a")
  file:close()

  -- Parse JSON
  local ok, parsed = pcall(vim.json.decode, content)
  if not ok then
    return nil, string.format("Invalid JSON in config file: %s", parsed)
  end

  -- Merge with defaults
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), parsed)

  -- Sanitize optional string fields (JSON null decodes to vim.NIL)
  if type(config.github_username) ~= "string" then
    config.github_username = ""
  end

  -- Normalize github_host: lowercase, strip whitespace/protocol/trailing slashes
  config.github_host = config.github_host:lower():gsub("^%s+", ""):gsub("%s+$", "")
  config.github_host = config.github_host:gsub("^https?://", ""):gsub("/+$", "")

  -- Expand paths
  config.clone_root = expand_path(config.clone_root)

  -- Validate
  local valid, err = validate_config(config)
  if not valid then
    return nil, err
  end

  return config, nil
end

--- Create a default config file if it doesn't exist
---@return boolean, string?
function M.create_default()
  local dir = vim.fn.fnamemodify(M.config_path, ":h")

  -- Create directory if needed
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  -- Check if file already exists
  if vim.fn.filereadable(M.config_path) == 1 then
    return false, "Config file already exists"
  end

  local default = {
    github_username = "your-username",
    github_host = "github.com",
    tokens = { ["your-username"] = "ghp_xxxxxxxxxxxxxxxxxxxx" },
    clone_root = vim.fs.joinpath(vim.fn.stdpath("data"), "raccoon", "repos"),
    pull_changes_interval = 300,
    commit_viewer = {
      grid = { rows = 2, cols = 2 },
      base_commits_count = 20,
    },
  }

  local json = vim.json.encode(default)
  -- Pretty print JSON
  local formatted = json:gsub(",", ",\n  "):gsub("{", "{\n  "):gsub("}", "\n}")

  local file = io.open(M.config_path, "w")
  if not file then
    return false, "Cannot create config file"
  end

  file:write(formatted)
  file:close()

  return true, nil
end

--- Sanitize merged shortcuts against the defaults structure.
--- Each leaf must be a non-empty string (valid binding) or false (disabled).
--- Anything else (vim.NIL, numbers, empty strings, tables at leaf positions) falls back to the default.
--- Unknown keys not present in defaults are dropped.
---@param merged table Merged shortcuts (user overrides + defaults)
---@param defaults table Default shortcuts (used as schema)
---@return table sanitized
local function sanitize_shortcuts(merged, defaults)
  local result = {}
  for key, default_val in pairs(defaults) do
    local val = merged[key]
    if type(default_val) == "table" then
      result[key] = sanitize_shortcuts(type(val) == "table" and val or {}, default_val)
    elseif val == false then
      result[key] = false
    elseif type(val) == "string" and val ~= "" then
      result[key] = val
    else
      result[key] = default_val
    end
  end
  return result
end

--- Load shortcuts from config, falling back to defaults gracefully.
--- Unlike load(), this does not require valid tokens/username.
---@return table shortcuts
function M.load_shortcuts()
  local path = M.config_path
  local stat = vim.uv.fs_stat(path)
  if not stat then
    return vim.deepcopy(M.defaults.shortcuts)
  end

  local file = io.open(path, "r")
  if not file then
    return vim.deepcopy(M.defaults.shortcuts)
  end

  local content = file:read("*a")
  file:close()

  local ok, parsed = pcall(vim.json.decode, content)
  if not ok or type(parsed) ~= "table" then
    return vim.deepcopy(M.defaults.shortcuts)
  end

  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults.shortcuts), parsed.shortcuts or {})
  return sanitize_shortcuts(merged, M.defaults.shortcuts)
end

--- Get the token for a given owner/org from the tokens table
---@param config RaccoonConfig
---@param owner string
---@return string?
function M.get_token_for_owner(config, owner)
  if config.tokens and config.tokens[owner] then
    return config.tokens[owner]
  end
  return nil
end

--- Get the token for a repo string ("owner/repo")
--- Extracts owner from the repo string and resolves the token
---@param config RaccoonConfig
---@param repo string Repository in "owner/repo" format
---@return string?
function M.get_token_for_repo(config, repo)
  local owner = repo:match("^([^/]+)/")
  if not owner then
    return nil
  end
  return M.get_token_for_owner(config, owner)
end

return M
