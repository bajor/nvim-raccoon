---@class RaccoonDiff
---Diff parsing and display functionality
local M = {}

local state = require("raccoon.state")

--- Namespace for diff highlights
local ns_id = vim.api.nvim_create_namespace("raccoon_diff")

--- Parse a unified diff hunk header
--- Returns start_line, count for the new file (right side)
---@param header string Hunk header like "@@ -1,4 +1,5 @@"
---@return number|nil start_line
---@return number|nil count
function M.parse_hunk_header(header)
  -- Format: @@ -old_start,old_count +new_start,new_count @@
  -- Sometimes count is omitted if it's 1
  local new_start, new_count = header:match("^@@.-+(%d+),?(%d*)%s*@@")
  if not new_start then
    return nil, nil
  end
  new_start = tonumber(new_start)
  new_count = tonumber(new_count) or 1
  return new_start, new_count
end

--- Parse a unified diff patch into structured hunks
---@param patch string The patch content
---@return table[] hunks Array of hunk tables with {header, lines, start_line, changes}
function M.parse_patch(patch)
  if not patch or patch == "" then
    return {}
  end

  local hunks = {}
  local current_hunk = nil
  local line_num = 0

  for line in patch:gmatch("[^\n]+") do
    if line:match("^@@") then
      -- New hunk
      if current_hunk then
        table.insert(hunks, current_hunk)
      end
      local start_line, count = M.parse_hunk_header(line)
      current_hunk = {
        header = line,
        lines = {},
        start_line = start_line or 1,
        count = count or 0,
        changes = {},
      }
      line_num = (start_line or 1) - 1
    elseif current_hunk then
      if line:match("^%+") and not line:match("^%+%+%+") then
        -- Added line
        line_num = line_num + 1
        table.insert(current_hunk.lines, { type = "add", content = line:sub(2), line_num = line_num })
        table.insert(current_hunk.changes, { type = "add", line_num = line_num })
      elseif line:match("^%-") and not line:match("^%-%-%-") then
        -- Removed line (doesn't increment line number in new file)
        -- Store the content for virtual text display
        table.insert(current_hunk.lines, { type = "del", content = line:sub(2), line_num = line_num })
        table.insert(current_hunk.changes, { type = "del", line_num = line_num, content = line:sub(2) })
      elseif line:match("^%s") or line == "" then
        -- Context line
        line_num = line_num + 1
        table.insert(current_hunk.lines, { type = "ctx", content = line:sub(2), line_num = line_num })
      end
    end
  end

  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  return hunks
end

--- Get all changed line numbers from a patch
---@param patch string The patch content
---@return table changes { added = {line_nums}, deleted = {{line_num, content}} }
function M.get_changed_lines(patch)
  local hunks = M.parse_patch(patch)
  local changes = { added = {}, deleted = {} }

  for _, hunk in ipairs(hunks) do
    for _, change in ipairs(hunk.changes) do
      if change.type == "add" and change.line_num then
        table.insert(changes.added, change.line_num)
      elseif change.type == "del" then
        -- For deleted lines, we track the line after which they were deleted + content
        table.insert(changes.deleted, { line_num = change.line_num, content = change.content })
      end
    end
  end

  return changes
end

--- Apply diff highlights to a buffer
---@param buf number Buffer ID
---@param patch string|nil The patch content
function M.apply_highlights(buf, patch)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  if not patch or patch == "" then
    return
  end

  local changes = M.get_changed_lines(patch)
  local line_count = vim.api.nvim_buf_line_count(buf)

  -- Apply green highlight to added lines
  for _, line_num in ipairs(changes.added) do
    local line_idx = line_num - 1
    if line_idx >= 0 and line_idx < line_count then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
        line_hl_group = "RaccoonAdd",
        sign_text = "+",
        sign_hl_group = "RaccoonAddSign",
      })
    end
  end

  -- For deleted lines, show virtual text with red background
  -- Group consecutive deletions together
  local grouped_deletions = {}
  for _, del in ipairs(changes.deleted) do
    local line_idx = del.line_num
    if line_idx >= 0 then
      if not grouped_deletions[line_idx] then
        grouped_deletions[line_idx] = {}
      end
      table.insert(grouped_deletions[line_idx], del.content or "")
    end
  end

  -- Display grouped deleted lines as virtual text
  for line_idx, contents in pairs(grouped_deletions) do
    -- Ensure line_idx is within buffer bounds
    local target_line = math.min(line_idx, line_count - 1)
    if target_line >= 0 then
      -- Create virtual lines for deleted content
      local virt_lines = {}
      for _, content in ipairs(contents) do
        local display_content = "- " .. (content or "")
        -- Truncate if too long
        if #display_content > 120 then
          display_content = display_content:sub(1, 117) .. "..."
        end
        local pad = string.rep(" ", 300)
        table.insert(virt_lines, { { display_content .. pad, "RaccoonDelete" } })
      end

      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, target_line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
        sign_text = "-",
        sign_hl_group = "RaccoonDeleteSign",
      })
    end
  end
end

--- Clear diff highlights from a buffer
---@param buf number Buffer ID
function M.clear_highlights(buf)
  if buf and vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  end
end

--- Open a file from the PR with diff highlighting
---@param file table File data with filename and patch
---@return number|nil buf Buffer ID or nil on error
function M.open_file(file)
  if not file or not file.filename then
    vim.notify("Invalid file data", vim.log.levels.ERROR)
    return nil
  end

  local clone_path = state.get_clone_path()
  if not clone_path then
    vim.notify("No active PR session", vim.log.levels.ERROR)
    return nil
  end

  local file_path = vim.fs.joinpath(clone_path, file.filename)

  -- Check if file exists (might be deleted)
  if vim.fn.filereadable(file_path) == 0 then
    if file.status == "removed" then
      vim.notify("File was deleted: " .. file.filename, vim.log.levels.WARN)
    else
      vim.notify("File not found: " .. file.filename, vim.log.levels.ERROR)
    end
    return nil
  end

  -- Open the file (wrapped in pcall to handle treesitter/filetype plugin errors gracefully)
  local ok, err = pcall(vim.cmd, "edit! " .. vim.fn.fnameescape(file_path))
  if not ok then
    -- Extract first line of error for cleaner display
    local short_err = tostring(err):match("^[^\n]+") or "unknown error"
    vim.notify("Failed to open file: " .. file.filename .. " (" .. short_err .. ")", vim.log.levels.WARN)
    -- File may still be open despite the error, continue if buffer exists
  end
  local buf = vim.api.nvim_get_current_buf()

  -- Track buffer in session
  state.add_buffer(buf)
  vim.bo[buf].modifiable = false

  -- Apply diff highlights
  if file.patch then
    -- Defer to allow buffer to fully load
    vim.schedule(function()
      M.apply_highlights(buf, file.patch)
    end)
  end

  return buf
end

--- Navigate to the next file in the PR (wraps to first file at end)
---@return boolean success
function M.next_file()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end

  local files = state.get_files()
  if #files == 0 then
    return false
  end

  if not state.next_file() then
    -- At last file, wrap to first
    state.goto_file(1)
  end

  local file = state.get_current_file()
  if file then
    M.open_file(file)
    vim.notify(file.filename)
    return true
  end
  return false
end

--- Navigate to the previous file in the PR (wraps to last file at beginning)
---@return boolean success
function M.prev_file()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end

  local files = state.get_files()
  if #files == 0 then
    return false
  end

  if not state.prev_file() then
    -- At first file, wrap to last
    state.goto_file(#files)
  end

  local file = state.get_current_file()
  if file then
    M.open_file(file)
    vim.notify(file.filename)
    return true
  end
  return false
end

--- Go to a specific file by index
---@param index number File index (1-based)
---@return boolean success
function M.goto_file(index)
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end

  local files = state.get_files()
  if index < 1 or index > #files then
    vim.notify("Invalid file index: " .. index, vim.log.levels.ERROR)
    return false
  end

  state.session.current_file = index
  local file = state.get_current_file()
  if file then
    M.open_file(file)
    vim.notify(file.filename)
    return true
  end
  return false
end

--- Setup keymaps for diff navigation
--- Called when a PR review session starts
function M.setup_keymaps()
  -- Use buffer-local mappings for the PR files
  local opts = { noremap = true, silent = true }

  -- Global navigation (available everywhere during review)
  vim.keymap.set("n", "]f", function()
    M.next_file()
  end, vim.tbl_extend("force", opts, { desc = "Next PR file" }))

  vim.keymap.set("n", "[f", function()
    M.prev_file()
  end, vim.tbl_extend("force", opts, { desc = "Previous PR file" }))
end

--- Clear keymaps when session ends
function M.clear_keymaps()
  pcall(vim.keymap.del, "n", "]f")
  pcall(vim.keymap.del, "n", "[f")
end

--- Get the namespace ID for diff highlights
---@return number
function M.get_namespace()
  return ns_id
end

--- Get the starting lines of each diff hunk in the current file
---@return number[] sorted list of hunk start lines
local function get_current_file_diff_hunks()
  local file = state.get_current_file()
  if not file or not file.patch then
    return {}
  end

  local changes = M.get_changed_lines(file.patch)
  local lines = {}

  -- Combine added and deleted lines
  for _, line in ipairs(changes.added) do
    table.insert(lines, line)
  end
  for _, del in ipairs(changes.deleted) do
    if del.line_num then
      table.insert(lines, del.line_num)
    end
  end

  -- Sort and deduplicate
  table.sort(lines)
  local unique = {}
  local last = nil
  for _, line in ipairs(lines) do
    if line ~= last then
      table.insert(unique, line)
      last = line
    end
  end

  -- Group consecutive lines into hunks, return only the start of each hunk
  local hunks = {}
  local hunk_start = nil
  local prev_line = nil

  for _, line in ipairs(unique) do
    if hunk_start == nil then
      -- First line starts a new hunk
      hunk_start = line
    elseif line > prev_line + 1 then
      -- Gap detected, save previous hunk and start new one
      table.insert(hunks, hunk_start)
      hunk_start = line
    end
    prev_line = line
  end

  -- Don't forget the last hunk
  if hunk_start then
    table.insert(hunks, hunk_start)
  end

  return hunks
end

--- Navigate to the next diff hunk in the current file
---@return boolean success
function M.next_diff()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end

  local hunks = get_current_file_diff_hunks()
  if #hunks == 0 then
    vim.notify("No changes in this file", vim.log.levels.INFO)
    return false
  end

  local current_line = vim.fn.line(".")

  -- Find the next hunk start after current position
  for _, line in ipairs(hunks) do
    if line > current_line then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      vim.cmd("normal! zz") -- Center the line
      return true
    end
  end

  vim.notify("No more changes below", vim.log.levels.INFO)
  return false
end

--- Navigate to the previous diff hunk in the current file
---@return boolean success
function M.prev_diff()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end

  local hunks = get_current_file_diff_hunks()
  if #hunks == 0 then
    vim.notify("No changes in this file", vim.log.levels.INFO)
    return false
  end

  local current_line = vim.fn.line(".")

  -- Find the previous hunk start before current position (iterate in reverse)
  for i = #hunks, 1, -1 do
    local line = hunks[i]
    if line < current_line then
      vim.api.nvim_win_set_cursor(0, { line, 0 })
      vim.cmd("normal! zz") -- Center the line
      return true
    end
  end

  vim.notify("No more changes above", vim.log.levels.INFO)
  return false
end

return M
