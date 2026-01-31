---@class RaccoonConfig
---@field github_token string GitHub personal access token (default/fallback)
---@field github_username string GitHub username
---@field repos string[] List of repos to watch (format: "owner/repo")
---@field tokens? table<string, string> Per-owner/org tokens (owner -> token)
---@field clone_root string Root directory for cloned PR repos
---@field poll_interval_seconds number Polling interval in seconds
---@field ghostty_path string Path to Ghostty.app
---@field nvim_path string Path to nvim binary
---@field notifications? RaccoonNotificationConfig Notification settings

---@class RaccoonNotificationConfig
---@field new_commits? boolean Notify on new commits
---@field new_comments? boolean Notify on new comments
---@field sound? boolean Play sound with notifications

local M = {}

--- Default configuration values
M.defaults = {
  github_token = "",
  github_username = "",
  repos = {},
  tokens = {},
  clone_root = "~/.local/share/raccoon/repos",
  poll_interval_seconds = 300,
  ghostty_path = "/Applications/Ghostty.app",
  nvim_path = "/opt/homebrew/bin/nvim",
  notifications = {
    new_commits = true,
    new_comments = true,
    sound = true,
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

--- Validate required fields in config
---@param config table
---@return boolean, string?
local function validate_config(config)
  -- Require either github_token or tokens map
  local has_token = config.github_token and config.github_token ~= ""
  local has_tokens = config.tokens and type(config.tokens) == "table" and next(config.tokens) ~= nil
  if not has_token and not has_tokens then
    return false, "github_token or tokens is required"
  end

  if not config.github_username or config.github_username == "" then
    return false, "github_username is required"
  end

  -- repos is optional (empty means auto-discovery in Swift app)
  -- Validate repo format if repos are specified
  if config.repos and type(config.repos) == "table" then
    for _, repo in ipairs(config.repos) do
      if not repo:match("^[%w%-_.]+/[%w%-_.]+$") then
        return false, string.format("Invalid repo format: '%s' (expected 'owner/repo')", repo)
      end
    end
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

  -- Expand paths
  config.clone_root = expand_path(config.clone_root)
  config.ghostty_path = expand_path(config.ghostty_path)
  config.nvim_path = expand_path(config.nvim_path)

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

  -- Create default config (token comes from GITHUB_TOKEN env var)
  local default = {
    github_username = "your-username",
    repos = { "owner/repo1", "owner/repo2" },
    clone_root = "~/.local/share/raccoon/repos",
    poll_interval_seconds = 300,
    ghostty_path = "/Applications/Ghostty.app",
    nvim_path = "/opt/homebrew/bin/nvim",
    notifications = {
      new_commits = true,
      new_comments = true,
      sound = true,
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

--- Get the appropriate token for a given owner/org
--- Returns the owner-specific token if available, otherwise the default github_token
---@param config RaccoonConfig
---@param owner string
---@return string
function M.get_token_for_owner(config, owner)
  if config.tokens and config.tokens[owner] then
    return config.tokens[owner]
  end
  return config.github_token
end

--- Get the appropriate token for a repo string ("owner/repo")
--- Extracts owner from the repo string and resolves the token
---@param config RaccoonConfig
---@param repo string Repository in "owner/repo" format
---@return string
function M.get_token_for_repo(config, repo)
  local owner = repo:match("^([^/]+)/")
  if not owner then
    return config.github_token
  end
  return M.get_token_for_owner(config, owner)
end

return M
