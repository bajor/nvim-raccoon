---@class RaccoonDiff
---Diff parsing and display functionality
local M = {}

local inline_diff = require("raccoon.inline_diff")
local state = require("raccoon.state")

--- Namespace for diff highlights
local ns_id = vim.api.nvim_create_namespace("raccoon_diff")

local function utf_char_count(text)
  return select(1, vim.str_utfindex(text or ""))
end

local function merge_inline_opts(opts)
  return inline_diff.merge_opts(opts)
end

local function whole_deleted_chunks(content)
  return { { text = content or "", hl_group = "RaccoonDelete" } }
end

local function line_byte_length(buf, line_idx)
  local lines = vim.api.nvim_buf_get_lines(buf, line_idx, line_idx + 1, false)
  return #(lines[1] or "")
end

local function empty_plan(fallback)
  return {
    fallback = fallback,
    added = {},
    deleted = {},
  }
end

local function append_line_only(plan, line)
  if line.type == "add" then
    table.insert(plan.added, {
      line_num = line.line_num,
      content = line.content or "",
      ranges = {},
    })
  elseif line.type == "del" then
    table.insert(plan.deleted, {
      line_num = line.line_num,
      content = line.content or "",
      chunks = whole_deleted_chunks(line.content),
    })
  end
end

local function build_line_only_plan(hunks)
  local plan = empty_plan(true)
  for _, hunk in ipairs(hunks) do
    for _, line in ipairs(hunk.lines) do
      append_line_only(plan, line)
    end
  end
  return plan
end

local function changed_line_count(hunks)
  local count = 0
  for _, hunk in ipairs(hunks) do
    for _, line in ipairs(hunk.lines) do
      if line.type == "add" or line.type == "del" then
        count = count + 1
      end
    end
  end
  return count
end

local function has_oversized_change_block(hunks, opts)
  for _, hunk in ipairs(hunks) do
    local block_count = 0

    for _, line in ipairs(hunk.lines) do
      if line.type == "add" or line.type == "del" then
        block_count = block_count + 1
        if block_count > opts.max_block_lines or utf_char_count(line.content) > opts.max_line_chars then
          return true
        end
      else
        block_count = 0
      end
    end
  end

  return false
end

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

  local normalized_patch = patch
  if normalized_patch:sub(-1) ~= "\n" then
    normalized_patch = normalized_patch .. "\n"
  end

  local hunks = {}
  local current_hunk = nil
  local line_num = 0

  for line in normalized_patch:gmatch("(.-)\n") do
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
      elseif not line:match("^\\ No newline at end of file$") and (line:match("^%s") or line == "") then
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

--- Check whether a file line is in GitHub PR review diff context.
--- GitHub accepts review comments on added lines and unchanged context lines
--- that are shown inside a diff hunk.
---@param patch string|nil
---@param target_line number|nil
---@return boolean
function M.is_line_in_review_context(patch, target_line)
  if type(target_line) ~= "number" or target_line < 1 then
    return false
  end

  local hunks = M.parse_patch(patch)
  for _, hunk in ipairs(hunks) do
    for _, line in ipairs(hunk.lines) do
      if line.line_num == target_line and (line.type == "add" or line.type == "ctx") then
        return true
      end
    end
  end

  return false
end

local function append_replacement_plan(plan, old_block, new_block, opts)
  local old_lines = {}
  local new_lines = {}

  for _, line in ipairs(old_block) do
    table.insert(old_lines, line.content or "")
  end
  for _, line in ipairs(new_block) do
    table.insert(new_lines, line.content or "")
  end

  local rows = inline_diff.plan_replacement(old_lines, new_lines, opts)
  local old_index = 1
  local new_index = 1

  for _, row in ipairs(rows) do
    local old_item = nil
    local new_item = nil

    if row.old ~= nil then
      old_item = old_block[old_index]
      old_index = old_index + 1
    end
    if row.new ~= nil then
      new_item = new_block[new_index]
      new_index = new_index + 1
    end

    if new_item then
      table.insert(plan.added, {
        line_num = new_item.line_num,
        content = new_item.content or "",
        ranges = row.inline and row.inline.new_ranges or {},
      })
    end
    if old_item then
      table.insert(plan.deleted, {
        line_num = old_item.line_num,
        content = old_item.content or "",
        chunks = row.inline and row.inline.old_chunks or whole_deleted_chunks(old_item.content),
      })
    end
  end
end

local function flush_change_block(plan, block, opts)
  if #block == 0 then
    return
  end

  local old_block = {}
  local new_block = {}
  for _, line in ipairs(block) do
    if line.type == "del" then
      table.insert(old_block, line)
    elseif line.type == "add" then
      table.insert(new_block, line)
    end
  end

  if #old_block > 0 and #new_block > 0 and opts.enabled ~= false then
    append_replacement_plan(plan, old_block, new_block, opts)
    return
  end

  for _, line in ipairs(block) do
    append_line_only(plan, line)
  end
end

---Build a buffer render plan from a GitHub patch.
---Hunk and review line numbers stay sourced from the unified diff parser.
---@param patch string|nil
---@param opts? table
---@return {fallback:boolean, added:table[], deleted:table[]}
function M.build_render_plan(patch, opts)
  opts = merge_inline_opts(opts)
  local hunks = M.parse_patch(patch)

  if not patch or patch == "" or #hunks == 0 then
    return empty_plan(true)
  end

  if opts.enabled == false
      or changed_line_count(hunks) > opts.max_changed_lines
      or has_oversized_change_block(hunks, opts) then
    return build_line_only_plan(hunks)
  end

  local plan = empty_plan(false)

  for _, hunk in ipairs(hunks) do
    local block = {}

    for _, line in ipairs(hunk.lines) do
      if line.type == "add" or line.type == "del" then
        table.insert(block, line)
      else
        flush_change_block(plan, block, opts)
        block = {}
      end
    end

    flush_change_block(plan, block, opts)
  end

  return plan
end

--- Apply diff highlights to a buffer
---@param buf number Buffer ID
---@param patch string|nil The patch content
---@param opts? table Inline diff options
function M.apply_highlights(buf, patch, opts)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Clear existing highlights
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  if not patch or patch == "" then
    return
  end

  opts = merge_inline_opts(opts)
  local plan = M.build_render_plan(patch, opts)
  local line_count = vim.api.nvim_buf_line_count(buf)

  -- Apply green highlight to added lines
  for _, add in ipairs(plan.added) do
    local line_idx = add.line_num - 1
    if line_idx >= 0 and line_idx < line_count then
      local ranges = add.ranges or {}
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
        line_hl_group = plan.fallback and "RaccoonAdd" or nil,
        sign_text = "+",
        sign_hl_group = "RaccoonAddSign",
        priority = opts.highlight_priority,
      })

      if not plan.fallback and #ranges == 0 then
        local end_col = line_byte_length(buf, line_idx)
        if end_col > 0 then
          pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
            end_col = end_col,
            hl_group = "RaccoonAddInline",
            priority = opts.highlight_priority,
          })
        end
      end

      for _, range in ipairs(ranges) do
        if range.start_col < range.end_col then
          pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, range.start_col, {
            end_col = range.end_col,
            hl_group = "RaccoonAddInline",
            priority = opts.highlight_priority,
          })
        end
      end
    end
  end

  -- For deleted lines, show virtual text with red background
  -- Group consecutive deletions together
  local grouped_deletions = {}
  for _, del in ipairs(plan.deleted) do
    local line_idx = del.line_num
    if line_idx >= 0 then
      if not grouped_deletions[line_idx] then
        grouped_deletions[line_idx] = {}
      end
      table.insert(grouped_deletions[line_idx], del.chunks or whole_deleted_chunks(del.content))
    end
  end

  -- Display grouped deleted lines as virtual text
  for line_idx, lines in pairs(grouped_deletions) do
    -- Ensure line_idx is within buffer bounds
    local target_line = math.min(line_idx, line_count - 1)
    if target_line >= 0 then
      -- Create virtual lines for deleted content
      local virt_lines = {}
      for _, chunks in ipairs(lines) do
        local delete_prefix_hl = plan.fallback and "RaccoonDelete" or "RaccoonDeleteSign"
        local default_chunk_hl = plan.fallback and "RaccoonDelete" or "Normal"
        local virt_line = { { "- ", delete_prefix_hl } }
        for _, chunk in ipairs(chunks) do
          table.insert(virt_line, { chunk.text or "", chunk.hl_group or default_chunk_hl })
        end
        if plan.fallback then
          local pad = string.rep(" ", 300)
          table.insert(virt_line, { pad, "RaccoonDelete" })
        end
        table.insert(virt_lines, virt_line)
      end

      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, target_line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
        sign_text = "-",
        sign_hl_group = "RaccoonDeleteSign",
        priority = opts.highlight_priority,
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
