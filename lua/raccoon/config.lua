---@class RaccoonConfig
---@field github_host string GitHub host (default: "github.com", set for GitHub Enterprise)
---@field tokens table<string, string|{token:string, host:string?, login:string?}> Per-owner/org tokens
---@field repos string[] Optional list of repos to show PRs from ("owner/repo" format)
---@field clone_root string Root directory for cloned PR repos
---@field sync_interval number Auto-sync interval in seconds (default: 300, minimum: 10)

local compat = require("raccoon.config_compat")

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
  github_host = "github.com",
  tokens = {},
  repos = {},
  clone_root = vim.fs.joinpath(vim.fn.stdpath("data"), "raccoon", "repos"),
  sync_interval = 300,
  commit_viewer = {
    grid = { rows = 2, cols = 2 },
    base_commits_count = 20,
    sidebar_width = 50,
    commit_message_max_lines = 3,
    passthrough_keys = {},
  },
  shortcuts = {
    -- Global
    pr_list = "<leader>pr",
    show_shortcuts = "<leader>?",
    sync = "<leader>r",
    -- Review navigation
    next_point = "<leader>j",
    prev_point = "<leader>k",
    next_file = "<leader>nf",
    prev_file = "<leader>pf",
    next_thread = "<leader>nt",
    prev_thread = "<leader>pt",
    next_needs_reply_thread = "<leader>nr",
    -- Review actions
    comment = "<leader>c",
    description = "<leader>dd",
    list_comments = "<leader>ll",
    list_files = "<leader>lf",
    list_threads = "<leader>lt",
    merge = "<leader>mr",
    commit_viewer_toggle = "<leader>cm",
    -- Comment editor
    comment_send = "<leader>s",
    comment_resolve = "<leader>cr",
    comment_unresolve = "<leader>cu",
    -- Common
    close = "<leader>q",
    -- Commit viewer mode
    commit_viewer = {
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

---@param path string
---@return string
local function shrink_home(path)
  local home = vim.fn.expand("~")
  if path:sub(1, #home) == home then
    return "~" .. path:sub(#home + 1)
  end
  return path
end

---@return string
function M.default_config_template()
  local commit_viewer = M.defaults.commit_viewer
  local shortcuts = M.defaults.shortcuts
  local clone_root = shrink_home(M.defaults.clone_root)

  return string.format([[{
  "github_host": "github.com",
  "tokens": {
    "your-username": "ghp_xxxxxxxxxxxxxxxxxxxx"
  },
  "repos": [],
  "clone_root": "%s",
  "sync_interval": %d,
  "commit_viewer": {
    "grid": { "rows": %d, "cols": %d },
    "base_commits_count": %d,
    "sidebar_width": %d,
    "commit_message_max_lines": %d,
    "passthrough_keys": []
  },
  "shortcuts": {
    "pr_list": "%s",
    "show_shortcuts": "%s",
    "sync": "%s",
    "next_point": "%s",
    "prev_point": "%s",
    "next_file": "%s",
    "prev_file": "%s",
    "next_thread": "%s",
    "prev_thread": "%s",
    "next_needs_reply_thread": "%s",
    "comment": "%s",
    "description": "%s",
    "list_comments": "%s",
    "list_files": "%s",
    "list_threads": "%s",
    "merge": "%s",
    "commit_viewer_toggle": "%s",
    "comment_send": "%s",
    "comment_resolve": "%s",
    "comment_unresolve": "%s",
    "close": "%s",
    "commit_viewer": {
      "next_page": "%s",
      "prev_page": "%s",
      "next_page_alt": "%s",
      "exit": "%s",
      "maximize_prefix": "%s",
      "browse_files": "%s"
    }
  }
}]],
    clone_root,
    M.defaults.sync_interval,
    commit_viewer.grid.rows,
    commit_viewer.grid.cols,
    commit_viewer.base_commits_count,
    commit_viewer.sidebar_width,
    commit_viewer.commit_message_max_lines,
    shortcuts.pr_list,
    shortcuts.show_shortcuts,
    shortcuts.sync,
    shortcuts.next_point,
    shortcuts.prev_point,
    shortcuts.next_file,
    shortcuts.prev_file,
    shortcuts.next_thread,
    shortcuts.prev_thread,
    shortcuts.next_needs_reply_thread,
    shortcuts.comment,
    shortcuts.description,
    shortcuts.list_comments,
    shortcuts.list_files,
    shortcuts.list_threads,
    shortcuts.merge,
    shortcuts.commit_viewer_toggle,
    shortcuts.comment_send,
    shortcuts.comment_resolve,
    shortcuts.comment_unresolve,
    shortcuts.close,
    shortcuts.commit_viewer.next_page,
    shortcuts.commit_viewer.prev_page,
    shortcuts.commit_viewer.next_page_alt,
    shortcuts.commit_viewer.exit,
    shortcuts.commit_viewer.maximize_prefix,
    shortcuts.commit_viewer.browse_files
  )
end

--- Validate required fields in config
---@param config table
---@return boolean, string?
local function validate_config(config)
  -- Require tokens map
  local has_tokens = config.tokens and type(config.tokens) == "table" and next(config.tokens) ~= nil
  if not has_tokens then
    return false, "tokens is required (maps owner/org name to GitHub token)"
  end

  -- Validate each token entry is a string or {token, host, login} table
  for key, value in pairs(config.tokens) do
    if type(value) == "table" then
      if type(value.token) ~= "string" or value.token == "" then
        return false, string.format("tokens['%s'].token must be a non-empty string", key)
      end
      if value.host ~= nil and (type(value.host) ~= "string" or value.host == "") then
        return false, string.format("tokens['%s'].host must be a non-empty string", key)
      end
      if value.login ~= nil and (type(value.login) ~= "string" or value.login == "") then
        return false, string.format("tokens['%s'].login must be a non-empty string", key)
      end
    elseif type(value) ~= "string" or value == "" then
      return false, string.format("tokens['%s'] must be a non-empty string or {token, host, login} table", key)
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

  -- Migrate any deprecated keys to their current names so the rest of the
  -- loader sees only the current schema.
  parsed = compat.normalize(parsed)

  -- Merge with defaults
  local config = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), parsed)
  config.inline_diff = nil

  -- Normalize github_host: lowercase, strip whitespace/protocol/trailing slashes
  config.github_host = config.github_host:lower():gsub("^%s+", ""):gsub("%s+$", "")
  config.github_host = config.github_host:gsub("^https?://", ""):gsub("/+$", "")

  -- Normalize host in table token entries
  if config.tokens and type(config.tokens) == "table" then
    for key, value in pairs(config.tokens) do
      if type(value) == "table" then
        if value.host then
          value.host = value.host:lower():gsub("^%s+", ""):gsub("%s+$", "")
          value.host = value.host:gsub("^https?://", ""):gsub("/+$", "")
        end
        if value.login then
          value.login = value.login:gsub("^%s+", ""):gsub("%s+$", "")
        end
        config.tokens[key] = value
      end
    end
  end

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

  local file = io.open(M.config_path, "w")
  if not file then
    return false, "Cannot create config file"
  end

  file:write(M.default_config_template())
  file:close()

  return true, nil
end

--- Read and parse the JSON config file.
--- Returns the parsed table, or nil on any failure.
---@return table?
local function read_config_json()
  local path = M.config_path
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil end
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  local ok, parsed = pcall(vim.json.decode, content)
  if not ok or type(parsed) ~= "table" then
    vim.notify("Raccoon: failed to parse config.json, using defaults", vim.log.levels.WARN)
    return nil
  end
  return compat.normalize(parsed)
end

--- Return only non-empty string entries from a list, preserving order and removing duplicates.
---@param val any
---@return string[]
local function sanitize_string_list(val)
  if type(val) ~= "table" then return {} end

  local result = {}
  local seen = {}
  for _, item in ipairs(val) do
    if type(item) == "string" and item ~= "" and not seen[item] then
      seen[item] = true
      table.insert(result, item)
    end
  end
  return result
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
--- Unlike load(), this does not require valid tokens.
---@return table shortcuts
function M.load_shortcuts()
  local parsed = read_config_json()
  if not parsed then
    return vim.deepcopy(M.defaults.shortcuts)
  end

  local merged = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults.shortcuts), parsed.shortcuts or {})
  return sanitize_shortcuts(merged, M.defaults.shortcuts)
end

--- Load commit viewer config, falling back to defaults gracefully.
--- Unlike load(), this does not require valid tokens.
---@return table commit_viewer
function M.load_commit_viewer()
  local defaults = M.defaults.commit_viewer
  local parsed = read_config_json()
  if not parsed then
    return vim.deepcopy(defaults)
  end

  local user = type(parsed.commit_viewer) == "table" and parsed.commit_viewer or {}
  local viewer = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user)
  viewer.passthrough_keys = sanitize_string_list(user.passthrough_keys)
  return viewer
end

--- Get the normalized token entry for a given owner/org from the tokens table.
---@param config RaccoonConfig
---@param owner string
---@return {token: string, host: string, login: string|nil}? entry
function M.get_token_entry(config, owner)
  if not config.tokens or not config.tokens[owner] then
    return nil
  end
  local value = config.tokens[owner]
  if type(value) == "table" then
    return {
      token = value.token,
      host = value.host or config.github_host,
      login = value.login,
    }
  end
  return {
    token = value,
    host = config.github_host,
    login = nil,
  }
end

--- Get the token and host for a given owner/org from the tokens table.
---@param config RaccoonConfig
---@param owner string
---@return string? token, string? host
function M.get_token_for_owner(config, owner)
  local entry = M.get_token_entry(config, owner)
  if not entry then
    return nil, nil
  end
  return entry.token, entry.host
end

--- Get the token and host for a repo string ("owner/repo")
--- Extracts owner from the repo string and resolves the token
---@param config RaccoonConfig
---@param repo string Repository in "owner/repo" format
---@return string? token, string? host
function M.get_token_for_repo(config, repo)
  local owner = repo:match("^([^/]+)/")
  if not owner then
    return nil, nil
  end
  return M.get_token_for_owner(config, owner)
end

--- Get all token entries normalized as {key, token, host, login}
---@param config RaccoonConfig
---@return {key: string, token: string, host: string, login: string|nil}[]
function M.get_all_tokens(config)
  local entries = {}
  if not config.tokens or type(config.tokens) ~= "table" then
    return entries
  end
  for key, value in pairs(config.tokens) do
    if type(value) == "table" and value.token then
      table.insert(entries, {
        key = key,
        token = value.token,
        host = value.host or config.github_host,
        login = value.login,
      })
    elseif type(value) == "string" then
      table.insert(entries, { key = key, token = value, host = config.github_host, login = nil })
    end
  end
  return entries
end

return M
