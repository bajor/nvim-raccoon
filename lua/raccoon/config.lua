---@class RaccoonConfig
---@field github_host string GitHub host (default: "github.com", set for GitHub Enterprise)
---@field tokens table<string, string|{token:string, host:string}> Per-owner/org tokens
---@field repos string[] Optional list of repos to show PRs from ("owner/repo" format)
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
local function is_valid_shortcut_string(value)
  return type(value) == "string" and value:match("%S") ~= nil
end

--- Check whether a shortcut binding is enabled.
---@param value any
---@return boolean
function M.is_enabled(value)
  return is_valid_shortcut_string(value)
end

--- Default configuration values
M.defaults = {
  github_host = "github.com",
  tokens = {},
  repos = {},
  clone_root = vim.fs.joinpath(vim.fn.stdpath("data"), "raccoon", "repos"),
  pull_changes_interval = 300,
  commit_viewer = {
    grid = { rows = 2, cols = 2 },
    base_commits_count = 20,
    sidebar_width = 50,
    commit_message_max_lines = 3,
    passthrough_keys = {},
  },
  parallel_agents = {
    enabled = false,
    command = "",
    suffix_prompt = "",
    shortcut = "<leader>aa",
    popup_width = 70,
  },
  human_edit = {
    shortcut = "<leader>ee",
    command = "git add <FILE> && git commit -m 'human edit <TIMESTAMP>' && git push",
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

--- Validate required fields in config
---@param config table
---@return boolean, string?
local function validate_config(config)
  -- Require tokens map
  local has_tokens = config.tokens and type(config.tokens) == "table" and next(config.tokens) ~= nil
  if not has_tokens then
    return false, "tokens is required (maps owner/org name to GitHub token)"
  end

  -- Validate each token entry is a string or {token, host} table
  for key, value in pairs(config.tokens) do
    if type(value) == "table" then
      if type(value.token) ~= "string" or value.token == "" then
        return false, string.format("tokens['%s'].token must be a non-empty string", key)
      end
      if value.host ~= nil and (type(value.host) ~= "string" or value.host == "") then
        return false, string.format("tokens['%s'].host must be a non-empty string", key)
      end
    elseif type(value) ~= "string" or value == "" then
      return false, string.format("tokens['%s'] must be a non-empty string or {token, host} table", key)
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

  -- Normalize github_host: lowercase, strip whitespace/protocol/trailing slashes
  config.github_host = config.github_host:lower():gsub("^%s+", ""):gsub("%s+$", "")
  config.github_host = config.github_host:gsub("^https?://", ""):gsub("/+$", "")

  -- Normalize host in table token entries
  if config.tokens and type(config.tokens) == "table" then
    for key, value in pairs(config.tokens) do
      if type(value) == "table" and value.host then
        value.host = value.host:lower():gsub("^%s+", ""):gsub("%s+$", "")
        value.host = value.host:gsub("^https?://", ""):gsub("/+$", "")
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

  local default = {
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

--- Read and parse the JSON config file.
--- Returns the parsed table, or nil on failure.
---@param opts? table { silent?: boolean }
---@return table?, string?
local function read_config_json(opts)
  opts = opts or {}
  local path = M.config_path
  local stat = vim.uv.fs_stat(path)
  if not stat then return nil, "missing" end
  local file = io.open(path, "r")
  if not file then return nil, "read_error" end
  local content = file:read("*a")
  file:close()
  local ok, parsed = pcall(vim.json.decode, content)
  if not ok or type(parsed) ~= "table" then
    if not opts.silent then
      vim.notify("Raccoon: failed to parse config.json, using defaults", vim.log.levels.WARN)
    end
    return nil, "parse_error"
  end
  return parsed, nil
end

--- Return val if it is a boolean, otherwise return default.
---@param val any
---@param default boolean
---@return boolean
local function bool_field(val, default)
  if type(val) == "boolean" then return val end
  return default
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

--- Return only valid key strings from the legacy top-level passthrough_keymaps list.
--- Supports entries shaped like { key = "<leader>x" } for backward compatibility.
---@param val any
---@return string[]
local function sanitize_legacy_passthrough_keymaps(val)
  if type(val) ~= "table" then return {} end

  local keys = {}
  for _, item in ipairs(val) do
    if type(item) == "string" then
      table.insert(keys, item)
    elseif type(item) == "table" then
      table.insert(keys, item.key)
    end
  end

  return sanitize_string_list(keys)
end

--- Resolve a shortcut field: false to disable, valid string to override, else default.
---@param user_val any Value from user config
---@param default_val string Default shortcut
---@return string|false
local function resolve_shortcut(user_val, default_val)
  if user_val == false then return false end
  if is_valid_shortcut_string(user_val) then return user_val end
  return default_val
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
    elseif key == "close" then
      if is_valid_shortcut_string(val) then
        result[key] = val
      else
        result[key] = default_val
      end
    elseif val == false then
      result[key] = false
    elseif is_valid_shortcut_string(val) then
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
  local passthrough_keys = sanitize_string_list(user.passthrough_keys)
  for _, lhs in ipairs(sanitize_legacy_passthrough_keymaps(parsed.passthrough_keymaps)) do
    table.insert(passthrough_keys, lhs)
  end
  viewer.passthrough_keys = sanitize_string_list(passthrough_keys)
  return viewer
end

--- Load parallel_agents config, falling back to defaults gracefully.
--- Unlike load(), this does not require valid tokens.
---@return table parallel_agents
function M.load_parallel_agents()
  local defaults = M.defaults.parallel_agents

  local parsed = read_config_json()
  if not parsed then
    return vim.deepcopy(defaults)
  end

  local user = parsed.parallel_agents
  if type(user) ~= "table" then
    return vim.deepcopy(defaults)
  end

  return {
    enabled = bool_field(user.enabled, defaults.enabled),
    command = type(user.command) == "string" and user.command or defaults.command,
    suffix_prompt = type(user.suffix_prompt) == "string" and user.suffix_prompt or defaults.suffix_prompt,
    shortcut = resolve_shortcut(user.shortcut, defaults.shortcut),
    popup_width = type(user.popup_width) == "number" and user.popup_width > 0
      and math.floor(user.popup_width) or defaults.popup_width,
  }
end

--- Load human_edit config, falling back to defaults gracefully.
---@return table human_edit
function M.load_human_edit()
  local defaults = M.defaults.human_edit

  local parsed = read_config_json()
  if not parsed then
    return vim.deepcopy(defaults)
  end

  local user = parsed.human_edit
  if type(user) ~= "table" then
    return vim.deepcopy(defaults)
  end

  return {
    shortcut = resolve_shortcut(user.shortcut, defaults.shortcut),
    command = user.command == false and ""
      or (type(user.command) == "string" and user.command or defaults.command),
  }
end

--- Get the token and host for a given owner/org from the tokens table
---@param config RaccoonConfig
---@param owner string
---@return string? token, string? host
function M.get_token_for_owner(config, owner)
  if not config.tokens or not config.tokens[owner] then
    return nil, nil
  end
  local value = config.tokens[owner]
  if type(value) == "table" then
    return value.token, value.host or config.github_host
  end
  return value, config.github_host
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

--- Get all token entries normalized as {key, token, host}
---@param config RaccoonConfig
---@return {key: string, token: string, host: string}[]
function M.get_all_tokens(config)
  local entries = {}
  if not config.tokens or type(config.tokens) ~= "table" then
    return entries
  end
  for key, value in pairs(config.tokens) do
    if type(value) == "table" and value.token then
      table.insert(entries, { key = key, token = value.token, host = value.host or config.github_host })
    elseif type(value) == "string" then
      table.insert(entries, { key = key, token = value, host = config.github_host })
    end
  end
  return entries
end

--- Validate `shortcuts.close` in user config.
--- Missing config file is treated as valid (defaults apply).
---@return table { valid: boolean, reason?: string, value?: any }
function M.validate_close_shortcut()
  local parsed, read_err = read_config_json({ silent = true })
  if read_err == "missing" then
    return { valid = true }
  end
  if not parsed then
    return { valid = true }
  end

  if type(parsed.shortcuts) ~= "table" then
    -- No shortcuts object means load_shortcuts() will use defaults (which include a valid close key)
    return { valid = true }
  end

  local close = parsed.shortcuts.close
  if not is_valid_shortcut_string(close) then
    return {
      valid = false,
      reason = "shortcuts.close must be a non-empty shortcut string",
      value = close,
    }
  end

  return { valid = true, value = close }
end

local close_warning_shown = false

--- Warn once per Neovim session when shortcuts.close is invalid.
function M.warn_invalid_close_shortcut_once()
  if close_warning_shown then
    return
  end
  local check = M.validate_close_shortcut()
  if check.valid then
    return
  end
  close_warning_shown = true
  vim.notify(
    "Raccoon: invalid shortcuts.close in config.json. "
      .. "Set \"shortcuts\": { \"close\": \"<leader>q\" }. "
      .. "Most :Raccoon commands are blocked until fixed. Run :Raccoon config.",
    vim.log.levels.WARN
  )
end

--- Best-effort minimal textual patch for required shortcuts.close.
---@param content string
---@param parsed table
---@return string|nil patched, string? err
local function patch_required_close_shortcut(content, parsed)
  local desired = "\"<leader>q\""
  local has_shortcuts = type(parsed.shortcuts) == "table"
  local has_close_key = has_shortcuts and parsed.shortcuts.close ~= nil

  if has_close_key then
    -- Scope the replacement to inside the shortcuts object to avoid matching
    -- a "close" key elsewhere in the config.
    local sc_start, sc_end = content:find('"shortcuts"%s*:%s*%{')
    if not sc_start or not sc_end then
      return nil, "could not locate shortcuts object for close replacement"
    end
    local before = content:sub(1, sc_end)
    local rest = content:sub(sc_end + 1)
    local replaced, count = rest:gsub('("close"%s*:%s*)([^,%}%]]+)', "%1" .. desired, 1)
    if count == 1 then
      return before .. replaced, nil
    end
    return nil, "could not safely patch existing shortcuts.close value"
  end

  if has_shortcuts then
    local start_i, end_i = content:find('"shortcuts"%s*:%s*%{')
    if not start_i or not end_i then
      return nil, "could not locate shortcuts object for close insertion"
    end

    local line_prefix = content:sub(1, start_i):match("([^\n]*)$") or ""
    local indent = line_prefix:match("^(%s*)") or ""
    local multiline = content:find("\n", end_i + 1, true) ~= nil
    local insertion
    if multiline then
      insertion = "\n" .. indent .. "  \"close\": \"<leader>q\","
    else
      insertion = " \"close\": \"<leader>q\","
    end
    return content:sub(1, end_i) .. insertion .. content:sub(end_i + 1), nil
  end

  -- No shortcuts object: inject minimal path at root.
  local close_obj_multiline = '"shortcuts": {\n  "close": "<leader>q"\n}'
  local close_obj_inline = '"shortcuts": {"close": "<leader>q"}'
  local insert_pos = content:match("()%s*}$")
  if not insert_pos then
    return nil, "could not locate root object close brace for shortcuts insertion"
  end

  local existing_keys = next(parsed) ~= nil
  local has_newline = content:find("\n", 1, true) ~= nil
  local prefix = content:sub(1, insert_pos - 1)
  local suffix = content:sub(insert_pos)

  local injection
  if has_newline then
    if existing_keys then
      injection = ",\n  " .. close_obj_multiline
    else
      injection = "\n  " .. close_obj_multiline .. "\n"
    end
  else
    if existing_keys then
      injection = "," .. close_obj_inline
    else
      injection = close_obj_inline
    end
  end

  return prefix .. injection .. suffix, nil
end

--- Auto-fix invalid/missing shortcuts.close in config.json.
---@return table
function M.autofix_close_shortcut()
  local stat = vim.uv.fs_stat(M.config_path)
  if not stat then
    return { changed = false, skipped = true, reason = "missing_config" }
  end

  local file = io.open(M.config_path, "r")
  if not file then
    return { changed = false, skipped = true, reason = "read_error" }
  end
  local content = file:read("*a")
  file:close()

  local ok, parsed = pcall(vim.json.decode, content)
  if not ok or type(parsed) ~= "table" then
    return { changed = false, skipped = true, reason = "parse_error" }
  end

  local old_value = nil
  if type(parsed.shortcuts) == "table" then
    old_value = parsed.shortcuts.close
  end
  local check = M.validate_close_shortcut()
  if check.valid then
    return { changed = false, skipped = true, reason = "already_valid", old_value = old_value }
  end

  local patched, patch_err = patch_required_close_shortcut(content, parsed)
  if not patched then
    return {
      changed = false,
      skipped = true,
      reason = "unsafe_patch",
      error = patch_err,
      old_value = old_value,
    }
  end

  local out = io.open(M.config_path, "w")
  if not out then
    return { changed = false, skipped = true, reason = "write_error", old_value = old_value }
  end
  out:write(patched)
  out:close()

  return {
    changed = true,
    old_value = old_value,
    new_value = "<leader>q",
  }
end

return M
