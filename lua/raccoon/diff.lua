---@class RaccoonDiff
---Diff parsing and display functionality
local M = {}

local inline_diff = require("raccoon.inline_diff")
local state = require("raccoon.state")
local inline_diff_warning_shown = false
local buffer_highlight_generations = {}

--- Namespace for diff highlights
local ns_id = vim.api.nvim_create_namespace("raccoon_diff")

local function normalize_content(content)
  return (content or ""):gsub("\r$", "")
end

local function warn_inline_diff_fallback()
  if inline_diff_warning_shown then return end
  inline_diff_warning_shown = true
  vim.notify("Inline diff planning exceeded its safety budget; using line-level highlights", vim.log.levels.WARN)
end

local function monotonic_clock_ms()
  local uv = vim.uv or vim.loop
  if uv and uv.hrtime then return uv.hrtime() / 1000000 end
  return os.clock() * 1000
end

--- Safely plan every line group under one deadline.
---@param line_groups RaccoonPatchLine[][]
---@return RaccoonInlinePlan[]|nil
function M.plan_inline_groups(line_groups)
  local plan_ok, plans = pcall(inline_diff.plan_many, line_groups, { clock = monotonic_clock_ms })
  if plan_ok and type(plans) == "table" and #plans == #line_groups then
    for index = 1, #line_groups do
      local plan = plans[index]
      local validate_ok, valid = pcall(inline_diff.validate, plan, line_groups[index])
      if not validate_ok or not valid then
        warn_inline_diff_fallback()
        return nil
      end
    end
    return plans
  end
  warn_inline_diff_fallback()
  return nil
end

--- Safely plan inline ranges, with one fallback warning per Neovim session.
---@param lines RaccoonPatchLine[]
---@return RaccoonInlinePlan|nil
function M.plan_inline(lines)
  local plans = M.plan_inline_groups({ lines })
  return plans and plans[1] or nil
end

local function ranges_from_plan(plan)
  local result = {}
  for _, row in ipairs(plan.rows) do
    if row.old_index then
      result[row.old_index] = { content = row.old_content, ranges = row.old_ranges }
    end
    if row.new_index then
      result[row.new_index] = { content = row.new_content, ranges = row.new_ranges }
    end
  end
  return result
end

--- Convert validated plans into source-indexed rendering data.
---@param line_groups RaccoonPatchLine[][]
---@return table<integer, table<integer, {content:string, ranges:RaccoonInlineRange[]}>>|nil
function M.get_inline_range_groups(line_groups)
  local plans = M.plan_inline_groups(line_groups)
  if not plans then return nil end
  local result = {}
  for index, plan in ipairs(plans) do result[index] = ranges_from_plan(plan) end
  return result
end

--- Convert a validated plan into source-indexed rendering data.
---@param lines RaccoonPatchLine[]
---@return table<integer, {content:string, ranges:RaccoonInlineRange[]}>|nil
function M.get_inline_ranges(lines)
  local groups = M.get_inline_range_groups({ lines })
  return groups and groups[1] or nil
end

--- Test helper for the session-scoped warning guard.
function M._reset_inline_diff_warning()
  inline_diff_warning_shown = false
end

--- Parse a unified diff hunk header
--- Returns start_line, count for the new file (right side)
---@param header string Hunk header like "@@ -1,4 +1,5 @@"
---@return number|nil start_line
---@return number|nil count
function M.parse_hunk_header(header)
  -- Format: @@ -old_start,old_count +new_start,new_count @@
  -- Sometimes count is omitted if it's 1
  local _, _, new_start, new_count = header:match(
    "^@@%s+%-(%d+),?(%d*)%s+%+(%d+),?(%d*)%s+@@"
  )
  if not new_start then
    return nil, nil
  end
  new_start = tonumber(new_start)
  new_count = tonumber(new_count) or 1
  return new_start, new_count
end

--- Parse both sides of a unified diff hunk header.
---@param header string
---@return number|nil old_start
---@return number|nil old_count
---@return number|nil new_start
---@return number|nil new_count
local function parse_hunk_coordinates(header)
  local old_start, old_count, new_start, new_count = header:match(
    "^@@%s+%-(%d+),?(%d*)%s+%+(%d+),?(%d*)%s+@@"
  )
  if not old_start then
    return nil, nil, nil, nil
  end

  return tonumber(old_start), tonumber(old_count) or 1, tonumber(new_start), tonumber(new_count) or 1
end

---@class RaccoonPatchLine
---@field kind "context"|"addition"|"deletion"
---@field type "ctx"|"add"|"del" Compatibility discriminator
---@field content string
---@field old_line number|nil One-based pre-image line
---@field new_line number|nil One-based post-image line
---@field anchor_line number Post-image coordinate used to place the rendered row
---@field line_num number Compatibility post-image coordinate

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
  local old_line = 0
  local new_line = 0

  for line in normalized_patch:gmatch("(.-)\n") do
    if line:match("^@@") then
      -- New hunk
      if current_hunk then
        table.insert(hunks, current_hunk)
      end
      local old_start, old_count, new_start, new_count = parse_hunk_coordinates(line)
      current_hunk = {
        header = line,
        lines = {},
        old_start_line = old_start or 1,
        old_count = old_count or 0,
        new_start_line = new_start or 1,
        new_count = new_count or 0,
        start_line = new_start or 1,
        count = new_count or 0,
        changes = {},
      }
      old_line = (old_start or 1) - 1
      new_line = (new_start or 1) - 1
    elseif current_hunk then
      if line:match("^%+") then
        -- Added line
        new_line = new_line + 1
        table.insert(current_hunk.lines, {
          kind = "addition",
          type = "add",
          content = line:sub(2),
          old_line = nil,
          new_line = new_line,
          anchor_line = new_line,
          line_num = new_line,
        })
        table.insert(current_hunk.changes, { type = "add", line_num = new_line })
      elseif line:match("^%-") then
        -- Removed line (doesn't increment line number in new file)
        -- Store the content for virtual text display
        old_line = old_line + 1
        local anchor_line = math.max(0, new_line)
        table.insert(current_hunk.lines, {
          kind = "deletion",
          type = "del",
          content = line:sub(2),
          old_line = old_line,
          new_line = nil,
          anchor_line = anchor_line,
          line_num = anchor_line,
        })
        table.insert(current_hunk.changes, { type = "del", line_num = anchor_line, content = line:sub(2) })
      elseif not line:match("^\\ No newline at end of file$") and (line:match("^%s") or line == "") then
        -- Context line
        old_line = old_line + 1
        new_line = new_line + 1
        table.insert(current_hunk.lines, {
          kind = "context",
          type = "ctx",
          content = line:sub(2),
          old_line = old_line,
          new_line = new_line,
          anchor_line = new_line,
          line_num = new_line,
        })
      end
    end
  end

  if current_hunk then
    table.insert(hunks, current_hunk)
  end

  return hunks
end

--- Summarize a patch and verify that every hunk contains its declared lines.
---@param patch string|nil
---@return {additions:integer,deletions:integer,complete:boolean}
function M.get_patch_stats(patch)
  local hunks = M.parse_patch(patch)
  local stats = { additions = 0, deletions = 0, complete = #hunks > 0 }

  for _, hunk in ipairs(hunks) do
    local old_lines, new_lines = 0, 0
    for _, line in ipairs(hunk.lines) do
      if line.kind == "context" then
        old_lines = old_lines + 1
        new_lines = new_lines + 1
      elseif line.kind == "addition" then
        stats.additions = stats.additions + 1
        new_lines = new_lines + 1
      elseif line.kind == "deletion" then
        stats.deletions = stats.deletions + 1
        old_lines = old_lines + 1
      end
    end
    if old_lines ~= hunk.old_count or new_lines ~= hunk.new_count then
      stats.complete = false
    end
  end

  return stats
end

--- Check whether a GitHub file entry contains a complete textual patch.
---@param file table
---@return boolean
function M.is_file_patch_complete(file)
  if type(file) ~= "table" then return false end
  local expected_additions = type(file.additions) == "number" and file.additions or nil
  local expected_deletions = type(file.deletions) == "number" and file.deletions or nil
  if type(file.patch) ~= "string" or file.patch == "" then
    return expected_additions == 0 and expected_deletions == 0
  end

  local stats = M.get_patch_stats(file.patch)
  if not stats.complete then return false end
  if expected_additions and stats.additions ~= expected_additions then return false end
  if expected_deletions and stats.deletions ~= expected_deletions then return false end
  return true
end

--- Get all changed line numbers from a patch
---@param patch string The patch content
---@return table changes { added = {line_nums}, deleted = {{line_num, content}} }
function M.get_changed_lines(patch)
  local hunks = M.parse_patch(patch)
  local changes = { added = {}, deleted = {} }

  for _, hunk in ipairs(hunks) do
    for _, line in ipairs(hunk.lines) do
      if line.kind == "addition" and line.new_line then
        table.insert(changes.added, line.new_line)
      elseif line.kind == "deletion" then
        -- For deleted lines, we track the line after which they were deleted + content
        table.insert(changes.deleted, { line_num = line.anchor_line, content = line.content })
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
      local is_reviewable = line.kind == "addition" or line.kind == "context"
      if line.new_line == target_line and is_reviewable then
        return true
      end
    end
  end

  return false
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

  local hunks = M.parse_patch(patch)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local additions = {}
  local grouped_deletions = {}
  local line_groups = {}
  for index, hunk in ipairs(hunks) do line_groups[index] = hunk.lines end
  local inline_range_groups = M.get_inline_range_groups(line_groups)

  for hunk_index, hunk in ipairs(hunks) do
    local inline_ranges = inline_range_groups and inline_range_groups[hunk_index] or nil
    for index, line in ipairs(hunk.lines) do
      if line.kind == "addition" then
        table.insert(additions, {
          line_num = line.new_line,
          inline = inline_ranges and inline_ranges[index] or nil,
        })
      elseif line.kind == "deletion" and line.anchor_line >= 0 then
        if not grouped_deletions[line.anchor_line] then grouped_deletions[line.anchor_line] = {} end
        table.insert(grouped_deletions[line.anchor_line], {
          content = inline_ranges and inline_ranges[index].content or normalize_content(line.content),
          ranges = inline_ranges and inline_ranges[index].ranges or nil,
        })
      end
    end
  end

  -- Apply green highlight to added lines.
  for _, addition in ipairs(additions) do
    local line_idx = addition.line_num - 1
    if line_idx >= 0 and line_idx < line_count then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, 0, {
        line_hl_group = addition.inline and "RaccoonAdd" or "RaccoonAddInline",
        sign_text = "+",
        sign_hl_group = "RaccoonAddSign",
      })
      if addition.inline then
        for _, range in ipairs(addition.inline.ranges) do
          pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, line_idx, range.start_col, {
            end_col = range.end_col,
            hl_group = "RaccoonAddInline",
            priority = 200,
          })
        end
      end
    end
  end

  -- Display grouped deleted lines as virtual text
  for line_idx, deletions in pairs(grouped_deletions) do
    -- Anchor above the following row, except at EOF where there is no following row.
    local at_eof = line_idx >= line_count
    local target_line = at_eof and line_count - 1 or line_idx
    if target_line >= 0 then
      -- Create virtual lines for deleted content
      local virt_lines = {}
      for _, deletion in ipairs(deletions) do
        local chunks = {}
        if not deletion.ranges then
          table.insert(chunks, { "- " .. deletion.content .. string.rep(" ", 300), "RaccoonDeleteInline" })
        else
          table.insert(chunks, { "- ", "RaccoonDelete" })
          local cursor = 0
          for _, range in ipairs(deletion.ranges) do
            if range.start_col > cursor then
              table.insert(chunks, { deletion.content:sub(cursor + 1, range.start_col), "RaccoonDelete" })
            end
            table.insert(chunks, {
              deletion.content:sub(range.start_col + 1, range.end_col),
              "RaccoonDeleteInline",
            })
            cursor = range.end_col
          end
          if cursor < #deletion.content then
            table.insert(chunks, { deletion.content:sub(cursor + 1), "RaccoonDelete" })
          end
          table.insert(chunks, { string.rep(" ", 300), "RaccoonDelete" })
        end
        table.insert(virt_lines, chunks)
      end

      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, target_line, 0, {
        virt_lines = virt_lines,
        virt_lines_above = not at_eof,
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

  local buf
  if vim.fn.filereadable(file_path) == 0 then
    if file.status == "removed" then
      local existing_buf = vim.fn.bufnr(file_path)
      if existing_buf >= 0 and vim.api.nvim_buf_is_valid(existing_buf) then
        buf = existing_buf
      else
        buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_name(buf, file_path)
      end
      vim.api.nvim_set_current_buf(buf)
      vim.bo[buf].modifiable = true
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
      vim.bo[buf].buftype = "nofile"
      vim.bo[buf].swapfile = false
      local filetype = vim.filetype.match({ filename = file.filename })
      if filetype then vim.bo[buf].filetype = filetype end
    else
      vim.notify("File not found: " .. file.filename, vim.log.levels.ERROR)
      return nil
    end
  else
    -- Open the file (wrapped in pcall to handle treesitter/filetype plugin errors gracefully)
    local ok, err = pcall(vim.cmd, "edit! " .. vim.fn.fnameescape(file_path))
    if not ok then
      local short_err = tostring(err):match("^[^\n]+") or "unknown error"
      vim.notify("Failed to open file: " .. file.filename .. " (" .. short_err .. ")", vim.log.levels.WARN)
    end
    buf = vim.api.nvim_get_current_buf()
    if not ok and vim.api.nvim_buf_get_name(buf) ~= file_path then return nil end
  end

  -- Track buffer in session
  state.add_buffer(buf)
  vim.bo[buf].modifiable = false
  local highlight_generation = (buffer_highlight_generations[buf] or 0) + 1
  buffer_highlight_generations[buf] = highlight_generation
  M.clear_highlights(buf)

  local has_textual_patch = type(file.patch) == "string" and file.patch ~= ""
  if file.diff_unavailable then
    vim.notify("Complete diff unavailable for " .. file.filename, vim.log.levels.WARN)
  elseif not has_textual_patch and file.additions == 0 and file.deletions == 0 then
    vim.notify("No textual diff for " .. file.filename .. " (binary or metadata-only change)", vim.log.levels.INFO)
  end

  -- Apply diff highlights
  if has_textual_patch then
    -- Defer to allow buffer to fully load
    vim.schedule(function()
      if buffer_highlight_generations[buf] == highlight_generation then
        M.apply_highlights(buf, file.patch)
      end
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
  local line_count = vim.api.nvim_buf_line_count(0)
  for _, del in ipairs(changes.deleted) do
    if del.line_num then
      table.insert(lines, math.max(1, math.min(del.line_num, line_count)))
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
