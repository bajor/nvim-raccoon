local intraline = require("raccoon.intraline")

local M = {}

-- Tree-sitter uses priority 100. Row backgrounds stay at that level while
-- inline backgrounds render above them without replacing syntax foregrounds.
M.ROW_PRIORITY = 100
M.INLINE_PRIORITY = 200

local function is_valid_buffer(buf)
  return type(buf) == "number" and vim.api.nvim_buf_is_valid(buf)
end

local function line_kind(line)
  if line.kind then return line.kind end
  if line.type == "add" then return "addition" end
  if line.type == "del" then return "deletion" end
  return "context"
end

local function normalize_ranges(ranges, content_length)
  local normalized = {}
  for _, range in ipairs(ranges or {}) do
    local start_col = tonumber(range.start_col)
    local end_col = tonumber(range.end_col)
    if start_col and end_col and start_col >= 0 and end_col > start_col and end_col <= content_length then
      table.insert(normalized, { start_col = start_col, end_col = end_col })
    end
  end
  table.sort(normalized, function(left, right) return left.start_col < right.start_col end)

  local merged = {}
  for _, range in ipairs(normalized) do
    local previous = merged[#merged]
    if previous and range.start_col <= previous.end_col then
      previous.end_col = math.max(previous.end_col, range.end_col)
    else
      table.insert(merged, range)
    end
  end
  return merged
end

local function set_inline_extmarks(ns_id, buf, row, content, ranges, highlight)
  for _, range in ipairs(normalize_ranges(ranges, #content)) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, row, range.start_col, {
      end_col = range.end_col,
      hl_group = highlight,
      hl_mode = "combine",
      priority = M.INLINE_PRIORITY,
    })
  end
end

--- Apply whole-line and inline highlights to real buffer rows.
---@param ns_id number
---@param buf number
---@param line_list RaccoonPatchLine[]
---@param ranges_by_line? table<number, RaccoonInlineRange[]>
---@param opts? {line_offset?:number, clear?:boolean}
function M.apply_real_lines(ns_id, buf, line_list, ranges_by_line, opts)
  if not is_valid_buffer(buf) then return end
  opts = opts or {}
  if opts.clear ~= false then vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1) end

  local line_count = vim.api.nvim_buf_line_count(buf)
  local line_offset = opts.line_offset or 0
  for index, line in ipairs(line_list or {}) do
    local row = line_offset + index - 1
    local kind = line_kind(line)
    if row >= 0 and row < line_count and (kind == "addition" or kind == "deletion") then
      local is_addition = kind == "addition"
      local row_group = is_addition and "RaccoonAdd" or "RaccoonDelete"
      local sign_group = is_addition and "RaccoonAddSign" or "RaccoonDeleteSign"
      local text_group = is_addition and "RaccoonAddText" or "RaccoonDeleteText"
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, row, 0, {
        line_hl_group = row_group,
        sign_text = is_addition and "+" or "-",
        sign_hl_group = sign_group,
        hl_mode = "combine",
        priority = M.ROW_PRIORITY,
      })
      set_inline_extmarks(ns_id, buf, row, line.content or "", ranges_by_line and ranges_by_line[index], text_group)
    end
  end
end

--- Flatten parsed hunks while preserving planned ranges and hunk boundaries.
---@param hunks table[]
---@param plan? table Result from intraline.plan_hunks
---@return RaccoonPatchLine[] lines
---@return table<number, RaccoonInlineRange[]> ranges
function M.flatten_hunks(hunks, plan)
  plan = plan or intraline.plan_hunks(hunks)
  local lines = {}
  local ranges = {}
  for hunk_index, hunk in ipairs(hunks or {}) do
    local hunk_plan = plan.hunks[hunk_index]
    for line_index, line in ipairs(hunk.lines or {}) do
      table.insert(lines, line)
      local line_ranges = hunk_plan and hunk_plan.ranges[line_index]
      if line_ranges then ranges[#lines] = line_ranges end
    end
  end
  return lines, ranges
end

--- Plan and flatten hunks once for scratch-buffer population and rendering.
---@param hunks table[]
---@param opts? table Planner options
---@return RaccoonPatchLine[] lines
---@return table<number, RaccoonInlineRange[]> ranges
---@return table plan
function M.prepare_hunks(hunks, opts)
  local plan = intraline.plan_hunks(hunks, opts)
  local lines, ranges = M.flatten_hunks(hunks, plan)
  return lines, ranges, plan
end

--- Plan and highlight parsed hunks rendered as real scratch-buffer lines.
---@param ns_id number
---@param buf number
---@param hunks table[]
---@param opts? table Planner options
---@return table plan
function M.apply_real_hunks(ns_id, buf, hunks, opts)
  local lines, ranges, plan = M.prepare_hunks(hunks, opts)
  M.apply_real_lines(ns_id, buf, lines, ranges)
  return plan
end

local function chunk_highlight(strong)
  return strong and "RaccoonDeleteText" or "RaccoonDelete"
end

--- Build one deleted virtual line from byte ranges without truncating content.
---@param content string
---@param ranges? RaccoonInlineRange[]
---@param target_width? number Display width to cover with the row background
---@return table[] chunks
function M.build_virtual_deleted_line(content, ranges, target_width)
  content = content or ""
  local chunks = {
    { "- ", { "RaccoonDelete", "RaccoonDeleteSign" } },
  }
  local cursor = 0
  for _, range in ipairs(normalize_ranges(ranges, #content)) do
    if range.start_col > cursor then
      table.insert(chunks, { content:sub(cursor + 1, range.start_col), chunk_highlight(false) })
    end
    table.insert(chunks, { content:sub(range.start_col + 1, range.end_col), chunk_highlight(true) })
    cursor = range.end_col
  end
  if cursor < #content then table.insert(chunks, { content:sub(cursor + 1), chunk_highlight(false) }) end

  if target_width then
    local width = vim.fn.strdisplaywidth("- " .. content)
    if width < target_width then
      table.insert(chunks, { string.rep(" ", target_width - width), chunk_highlight(false) })
    end
  end
  return chunks
end

local function virtual_target_width(buf)
  local width = 0
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    if vim.api.nvim_win_is_valid(win) then width = math.max(width, vim.api.nvim_win_get_width(win)) end
  end
  return width > 0 and width or vim.o.columns
end

local function place_virtual_block(ns_id, buf, block, ranges, line_count, target_width)
  if #block.deletions == 0 then return end
  local anchor = block.anchor_new_line_num or 1
  local above = anchor <= line_count
  local row = above and math.max(0, anchor - 1) or math.max(0, line_count - 1)
  local virtual_lines = {}
  for _, line in ipairs(block.deletions) do
    table.insert(virtual_lines, M.build_virtual_deleted_line(
      line.content or "",
      ranges and ranges[line.hunk_line_index],
      target_width
    ))
  end

  pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, row, 0, {
    virt_lines = virtual_lines,
    virt_lines_above = above,
    virt_lines_overflow = "scroll",
    sign_text = "-",
    sign_hl_group = "RaccoonDeleteSign",
    priority = M.ROW_PRIORITY,
  })
end

--- Render parsed hunks over a real post-image file buffer.
---@param ns_id number
---@param buf number
---@param hunks table[]
---@param opts? table Planner options
---@return table|nil plan
function M.apply_flat_hunks(ns_id, buf, hunks, opts)
  if not is_valid_buffer(buf) then return nil end
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  if not hunks or #hunks == 0 then return { hunks = {}, compared_bytes = 0 } end

  local plan = intraline.plan_hunks(hunks, opts)
  local line_count = vim.api.nvim_buf_line_count(buf)
  local target_width = virtual_target_width(buf)
  for hunk_index, hunk in ipairs(hunks) do
    local hunk_plan = plan.hunks[hunk_index]
    local ranges = hunk_plan and hunk_plan.ranges or {}
    for line_index, line in ipairs(hunk.lines) do
      if line_kind(line) == "addition" and line.new_line_num then
        M.apply_real_lines(ns_id, buf, { line }, { [1] = ranges[line_index] }, {
          line_offset = line.new_line_num - 1,
          clear = false,
        })
      end
    end
    for _, block in ipairs(hunk.change_blocks or {}) do
      place_virtual_block(ns_id, buf, block, ranges, line_count, target_width)
    end
  end
  return plan
end

return M
