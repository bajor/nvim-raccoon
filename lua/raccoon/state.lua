---@class RaccoonState
---Session state for the current PR review
local M = {}

--- Current review session state
M.session = {
  --- Is a review session active?
  active = false,
  --- Current PR data
  pr = nil,
  --- Repository owner
  owner = nil,
  --- Repository name
  repo = nil,
  --- PR number
  number = nil,
  --- PR URL
  url = nil,
  --- Local clone path
  clone_path = nil,
  --- List of changed files
  files = {},
  --- Current file index (1-based)
  current_file = 1,
  --- Comments indexed by file path
  comments = {},
  --- Buffers created for this session
  buffers = {},
  --- Sync status with base branch
  sync_status = {
    behind = 0,
    has_conflicts = false,
    conflict_files = {},
    checked = false,
  },
}

--- Reset the session state
function M.reset()
  M.session = {
    active = false,
    pr = nil,
    owner = nil,
    repo = nil,
    number = nil,
    url = nil,
    clone_path = nil,
    files = {},
    current_file = 1,
    comments = {},
    buffers = {},
    sync_status = {
      behind = 0,
      has_conflicts = false,
      conflict_files = {},
      checked = false,
    },
  }
end

--- Start a new review session
---@param opts table Session options: owner, repo, number, url, clone_path
function M.start(opts)
  M.reset()
  M.session.active = true
  M.session.owner = opts.owner
  M.session.repo = opts.repo
  M.session.number = opts.number
  M.session.url = opts.url
  M.session.clone_path = opts.clone_path
end

--- End the current review session
function M.stop()
  -- Close all session buffers
  for _, buf in ipairs(M.session.buffers) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end
  M.reset()
end

--- Check if a review session is active
---@return boolean
function M.is_active()
  return M.session.active
end

--- Get the current PR
---@return table|nil
function M.get_pr()
  return M.session.pr
end

--- Set the current PR data
---@param pr table PR data from API
function M.set_pr(pr)
  M.session.pr = pr
end

--- Get the list of files
---@return table[]
function M.get_files()
  return M.session.files
end

--- Set the list of files
---@param files table[] Files from API
function M.set_files(files)
  M.session.files = files
end

--- Get the current file
---@return table|nil
function M.get_current_file()
  if M.session.current_file > 0 and M.session.current_file <= #M.session.files then
    return M.session.files[M.session.current_file]
  end
  return nil
end

--- Get the current file index
---@return number
function M.get_current_file_index()
  return M.session.current_file
end

--- Navigate to the next file
---@return boolean success
function M.next_file()
  if M.session.current_file < #M.session.files then
    M.session.current_file = M.session.current_file + 1
    return true
  end
  return false
end

--- Navigate to the previous file
---@return boolean success
function M.prev_file()
  if M.session.current_file > 1 then
    M.session.current_file = M.session.current_file - 1
    return true
  end
  return false
end

--- Go to a specific file by index
---@param index number File index (1-based)
---@return boolean success
function M.goto_file(index)
  if index >= 1 and index <= #M.session.files then
    M.session.current_file = index
    return true
  end
  return false
end

--- Set comments for a file
---@param path string File path
---@param comments table[] Comments
function M.set_comments(path, comments)
  M.session.comments[path] = comments
end

--- Get comments for a file
---@param path string File path
---@return table[]
function M.get_comments(path)
  return M.session.comments[path] or {}
end

--- Add a buffer to the session
---@param buf number Buffer ID
function M.add_buffer(buf)
  table.insert(M.session.buffers, buf)
end

--- Get the clone path
---@return string|nil
function M.get_clone_path()
  return M.session.clone_path
end

--- Get the owner
---@return string|nil
function M.get_owner()
  return M.session.owner
end

--- Get the repo name
---@return string|nil
function M.get_repo()
  return M.session.repo
end

--- Get the PR number
---@return number|nil
function M.get_number()
  return M.session.number
end

--- Get sync status
---@return table
function M.get_sync_status()
  return M.session.sync_status
end

--- Set sync status
---@param status table
function M.set_sync_status(status)
  M.session.sync_status = status
end

--- Get statusline component string
---@return string
function M.get_statusline_component()
  if not M.session.active then
    return ""
  end

  local parts = {}
  local sync = M.session.sync_status

  if not sync.checked then
    return ""
  end

  -- Show behind count
  if sync.behind > 0 then
    table.insert(parts, string.format("⚠ %d behind", sync.behind))
  end

  -- Show conflict warning
  if sync.has_conflicts then
    table.insert(parts, "⛔ CONFLICTS")
  end

  if #parts == 0 then
    return "✓ In sync"
  end

  return table.concat(parts, " │ ")
end

return M
