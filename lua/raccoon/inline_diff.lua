---@class RaccoonInlineRange
---@field start_col integer Zero-based byte column
---@field end_col integer End-exclusive byte column

---@class RaccoonInlineRow
---@field kind "replacement"|"suppressed_replacement"|"addition"|"deletion"
---@field old_index integer|nil
---@field old_line RaccoonPatchLine|nil
---@field old_content string|nil
---@field old_ranges RaccoonInlineRange[]|nil
---@field new_index integer|nil
---@field new_line RaccoonPatchLine|nil
---@field new_content string|nil
---@field new_ranges RaccoonInlineRange[]|nil

---@class RaccoonInlinePlan
---@field rows RaccoonInlineRow[]

local M = {}

local MAX_LINE_DIFF_UTF16_UNITS = 1000
local INLINE_DIFF_TIMEOUT_MS = 500
local DEADLINE_CHECK_STEPS = 1024
local PLANNING_ABORTED = {}

local function default_clock_ms()
  return os.clock() * 1000
end

local function new_deadline(options)
  options = options or {}
  local timeout_ms = options.timeout_ms or INLINE_DIFF_TIMEOUT_MS
  local clock = options.clock or default_clock_ms
  assert(type(timeout_ms) == "number" and timeout_ms > 0, "inline diff timeout must be positive")
  assert(type(clock) == "function", "inline diff clock must be a function")
  return {
    clock = clock,
    started_at = clock(),
    timeout_ms = timeout_ms,
    steps = 0,
  }
end

local function abort_planning()
  error(PLANNING_ABORTED, 0)
end

local function check_deadline(deadline, force)
  deadline.steps = force and DEADLINE_CHECK_STEPS or deadline.steps + 1
  if deadline.steps < DEADLINE_CHECK_STEPS then return end
  deadline.steps = 0
  if deadline.clock() - deadline.started_at >= deadline.timeout_ms then abort_planning() end
end

local function normalize_content(content)
  return (content or ""):gsub("\r$", "")
end

local function is_integer(value)
  return type(value) == "number" and value >= 0 and value == math.floor(value)
end

local function new_range(start_col, end_col)
  assert(is_integer(start_col), "inline range start must be a non-negative integer")
  assert(is_integer(end_col) and end_col > start_col, "inline range end must follow start")
  return { start_col = start_col, end_col = end_col }
end

local function whole_range(content)
  if #content == 0 then return {} end
  return { new_range(0, #content) }
end

local function new_addition(index, line)
  assert(line.kind == "addition", "addition row requires an addition source")
  local content = normalize_content(line.content)
  return {
    kind = "addition",
    new_index = index,
    new_line = line,
    new_content = content,
    new_ranges = whole_range(content),
  }
end

local function new_deletion(index, line)
  assert(line.kind == "deletion", "deletion row requires a deletion source")
  local content = normalize_content(line.content)
  return {
    kind = "deletion",
    old_index = index,
    old_line = line,
    old_content = content,
    old_ranges = whole_range(content),
  }
end

local function new_replacement(kind, old_index, old_line, new_index, new_line, old_ranges, new_ranges)
  assert(old_line.kind == "deletion", "replacement old source must be a deletion")
  assert(new_line.kind == "addition", "replacement new source must be an addition")
  return {
    kind = kind,
    old_index = old_index,
    old_line = old_line,
    old_content = normalize_content(old_line.content),
    old_ranges = old_ranges,
    new_index = new_index,
    new_line = new_line,
    new_content = normalize_content(new_line.content),
    new_ranges = new_ranges,
  }
end

local function utf8_width(first_byte)
  if first_byte < 0x80 then return 1 end
  if first_byte >= 0xC2 and first_byte <= 0xDF then return 2 end
  if first_byte >= 0xE0 and first_byte <= 0xEF then return 3 end
  if first_byte >= 0xF0 and first_byte <= 0xF4 then return 4 end
  return 1
end

local function is_continuation(byte)
  return byte and byte >= 0x80 and byte <= 0xBF
end

local function split_codepoints(text, deadline)
  local result = {}
  local cursor = 0
  local utf16_units = 0
  while cursor < #text do
    check_deadline(deadline)
    local width = utf8_width(text:byte(cursor + 1))
    if cursor + width > #text then
      width = 1
    else
      for offset = 1, width - 1 do
        if not is_continuation(text:byte(cursor + offset + 1)) then
          width = 1
          break
        end
      end
    end
    table.insert(result, {
      text = text:sub(cursor + 1, cursor + width),
      start_col = cursor,
      end_col = cursor + width,
    })
    utf16_units = utf16_units + (width == 4 and 2 or 1)
    cursor = cursor + width
  end
  return result, utf16_units
end

local function add_to_path(path, added, removed, old_pos_increment)
  local last = path.last_component
  local component
  if last and last.added == added and last.removed == removed then
    component = {
      count = last.count + 1,
      added = added,
      removed = removed,
      previous_component = last.previous_component,
    }
  else
    component = {
      count = 1,
      added = added,
      removed = removed,
      previous_component = last,
    }
  end
  return {
    old_pos = path.old_pos + old_pos_increment,
    last_component = component,
  }
end

local function extract_common(path, new_tokens, old_tokens, diagonal, deadline)
  local old_pos = path.old_pos
  local new_pos = old_pos - diagonal
  local common_count = 0
  while new_pos + 1 < #new_tokens and old_pos + 1 < #old_tokens
      and old_tokens[old_pos + 2].text == new_tokens[new_pos + 2].text do
    check_deadline(deadline)
    new_pos = new_pos + 1
    old_pos = old_pos + 1
    common_count = common_count + 1
  end
  if common_count > 0 then
    path.last_component = {
      count = common_count,
      added = false,
      removed = false,
      previous_component = path.last_component,
    }
  end
  path.old_pos = old_pos
  return new_pos
end

-- Pure-Lua adaptation of the character Myers implementation in diff 9.0.0.
-- Diagonal order, add/remove preference, common-run extraction, and component
-- coalescing intentionally follow upstream src/diff/base.ts.
local function diff_components(old_tokens, new_tokens, deadline)
  local old_length, new_length = #old_tokens, #new_tokens
  local best_path = {
    [0] = { old_pos = -1 },
  }
  local new_pos = extract_common(best_path[0], new_tokens, old_tokens, 0, deadline)
  if best_path[0].old_pos + 1 >= old_length and new_pos + 1 >= new_length then
    return best_path[0].last_component
  end

  local edit_length = 1
  local min_diagonal, max_diagonal = -math.huge, math.huge
  while edit_length <= old_length + new_length do
    check_deadline(deadline, true)
    local diagonal = math.max(min_diagonal, -edit_length)
    while diagonal <= math.min(max_diagonal, edit_length) do
      check_deadline(deadline)
      local remove_path = best_path[diagonal - 1]
      local add_path = best_path[diagonal + 1]
      if remove_path then best_path[diagonal - 1] = nil end

      local can_add = false
      if add_path then
        local add_path_new_pos = add_path.old_pos - diagonal
        can_add = add_path_new_pos >= 0 and add_path_new_pos < new_length
      end
      local can_remove = remove_path and remove_path.old_pos + 1 < old_length
      if not can_add and not can_remove then
        best_path[diagonal] = nil
      else
        local base_path
        if not can_remove or (can_add and remove_path.old_pos < add_path.old_pos) then
          base_path = add_to_path(add_path, true, false, 0)
        else
          base_path = add_to_path(remove_path, false, true, 1)
        end

        new_pos = extract_common(base_path, new_tokens, old_tokens, diagonal, deadline)
        if base_path.old_pos + 1 >= old_length and new_pos + 1 >= new_length then
          return base_path.last_component
        end
        best_path[diagonal] = base_path
        if base_path.old_pos + 1 >= old_length then
          max_diagonal = math.min(max_diagonal, diagonal - 1)
        end
        if new_pos + 1 >= new_length then
          min_diagonal = math.max(min_diagonal, diagonal + 1)
        end
      end
      diagonal = diagonal + 2
    end
    edit_length = edit_length + 1
  end
  error("inline character diff did not produce a path")
end

local function append_range(ranges, start_col, end_col)
  if end_col <= start_col then return end
  local previous = ranges[#ranges]
  if previous and start_col <= previous.end_col then
    previous.end_col = math.max(previous.end_col, end_col)
  else
    table.insert(ranges, new_range(start_col, end_col))
  end
end

local function components_in_order(last_component)
  local reversed = {}
  while last_component do
    table.insert(reversed, last_component)
    last_component = last_component.previous_component
  end
  local components = {}
  for index = #reversed, 1, -1 do table.insert(components, reversed[index]) end
  return components
end

local function changed_ranges(old_tokens, new_tokens, last_component)
  local old_ranges, new_ranges = {}, {}
  local old_index, new_index = 1, 1
  local old_col, new_col = 0, 0
  for _, component in ipairs(components_in_order(last_component)) do
    if component.removed then
      local start_col = old_col
      for _ = 1, component.count do
        old_col = old_tokens[old_index].end_col
        old_index = old_index + 1
      end
      append_range(old_ranges, start_col, old_col)
    elseif component.added then
      local start_col = new_col
      for _ = 1, component.count do
        new_col = new_tokens[new_index].end_col
        new_index = new_index + 1
      end
      append_range(new_ranges, start_col, new_col)
    else
      for _ = 1, component.count do
        old_col = old_tokens[old_index].end_col
        new_col = new_tokens[new_index].end_col
        old_index = old_index + 1
        new_index = new_index + 1
      end
    end
  end
  return old_ranges, new_ranges
end

local function plan_pair(old_index, old_line, new_index, new_line, deadline)
  local old_content = normalize_content(old_line.content)
  local new_content = normalize_content(new_line.content)
  local old_tokens, old_utf16_units = split_codepoints(old_content, deadline)
  local new_tokens, new_utf16_units = split_codepoints(new_content, deadline)
  if old_utf16_units > MAX_LINE_DIFF_UTF16_UNITS
      or new_utf16_units > MAX_LINE_DIFF_UTF16_UNITS then
    return new_replacement(
      "suppressed_replacement",
      old_index,
      old_line,
      new_index,
      new_line
    )
  end
  local components = diff_components(old_tokens, new_tokens, deadline)
  local old_ranges, new_ranges = changed_ranges(old_tokens, new_tokens, components)
  return new_replacement(
    "replacement",
    old_index,
    old_line,
    new_index,
    new_line,
    old_ranges,
    new_ranges
  )
end

local function plan_block(block, lines, deadline)
  local deletions, additions = {}, {}
  for _, index in ipairs(block) do
    check_deadline(deadline)
    if lines[index].kind == "deletion" then
      table.insert(deletions, index)
    else
      table.insert(additions, index)
    end
  end

  local rows = {}
  local pair_count = math.min(#deletions, #additions)
  for ordinal = 1, pair_count do
    check_deadline(deadline)
    local old_index, new_index = deletions[ordinal], additions[ordinal]
    table.insert(rows, plan_pair(
      old_index,
      lines[old_index],
      new_index,
      lines[new_index],
      deadline
    ))
  end
  for ordinal = pair_count + 1, #deletions do
    table.insert(rows, new_deletion(deletions[ordinal], lines[deletions[ordinal]]))
  end
  for ordinal = pair_count + 1, #additions do
    table.insert(rows, new_addition(additions[ordinal], lines[additions[ordinal]]))
  end
  table.sort(rows, function(left, right)
    return math.min(left.old_index or math.huge, left.new_index or math.huge)
      < math.min(right.old_index or math.huge, right.new_index or math.huge)
  end)
  return rows
end

local function plan_lines(lines, deadline)
  assert(type(lines) == "table", "inline diff lines must be a table")
  check_deadline(deadline, true)
  local plan = { rows = {} }
  local block = {}
  local function flush_block()
    if #block == 0 then return end
    for _, row in ipairs(plan_block(block, lines, deadline)) do table.insert(plan.rows, row) end
    block = {}
  end

  for index, line in ipairs(lines) do
    check_deadline(deadline)
    assert(type(line) == "table", "inline diff line must be a table")
    assert(line.kind == "context" or line.kind == "addition" or line.kind == "deletion",
      "inline diff line has an invalid kind")
    assert(type(line.content) == "string", "inline diff line content must be a string")
    if line.kind == "context" then
      flush_block()
    else
      table.insert(block, index)
    end
  end
  flush_block()
  return plan
end

local function run_planning(callback)
  local ok, result = pcall(callback)
  if ok then return result end
  if result == PLANNING_ABORTED then return nil, "inline diff budget exceeded" end
  error(result, 0)
end

--- Build exact inline ranges for multiple independent line groups under one deadline.
---@param line_groups RaccoonPatchLine[][]
---@param options? {timeout_ms?:number, clock?:fun():number}
---@return RaccoonInlinePlan[]|nil plans
---@return string|nil reason
function M.plan_many(line_groups, options)
  assert(type(line_groups) == "table", "inline diff line groups must be a table")
  local deadline = new_deadline(options)
  return run_planning(function()
    local plans = {}
    for index, lines in ipairs(line_groups) do
      check_deadline(deadline, true)
      plans[index] = plan_lines(lines, deadline)
    end
    check_deadline(deadline, true)
    return plans
  end)
end

--- Build exact inline ranges for parsed patch lines.
---@param lines RaccoonPatchLine[]
---@param options? {timeout_ms?:number, clock?:fun():number}
---@return RaccoonInlinePlan|nil plan
---@return string|nil reason
function M.plan(lines, options)
  assert(type(lines) == "table", "inline diff lines must be a table")
  local plans, reason = M.plan_many({ lines }, options)
  return plans and plans[1] or nil, reason
end

local function is_dense_array(value)
  if type(value) ~= "table" then return false end
  local count = 0
  for key, _ in pairs(value) do
    if not is_integer(key) or key < 1 then return false end
    count = count + 1
  end
  return count == #value
end

local function validate_ranges(ranges, content)
  if not is_dense_array(ranges) then return false, "ranges must be a dense array" end
  local previous_end = 0
  for index, range in ipairs(ranges) do
    if type(range) ~= "table" or not is_integer(range.start_col) or not is_integer(range.end_col) then
      return false, "range columns must be non-negative integers"
    end
    if range.start_col >= range.end_col or range.end_col > #content then
      return false, "range columns are outside content"
    end
    if index > 1 and range.start_col < previous_end then return false, "ranges overlap" end
    previous_end = range.end_col
  end
  return true
end

local function content_outside_ranges(content, ranges)
  local parts = {}
  local cursor = 0
  for _, range in ipairs(ranges) do
    table.insert(parts, content:sub(cursor + 1, range.start_col))
    cursor = range.end_col
  end
  table.insert(parts, content:sub(cursor + 1))
  return table.concat(parts)
end

local function validate_source(row, side, expected_kind, lines, seen)
  local index = row[side .. "_index"]
  local line = row[side .. "_line"]
  local content = row[side .. "_content"]
  if not is_integer(index) or index < 1 or type(line) ~= "table" or line.kind ~= expected_kind then
    return false, side .. " side does not match its row kind"
  end
  if type(content) ~= "string" or content ~= normalize_content(line.content) then
    return false, side .. " content does not match its source"
  end
  if lines and lines[index] ~= line then return false, side .. " source index does not match input" end
  if seen[index] then return false, "source line is represented more than once" end
  seen[index] = true
  return true
end

local function validate_side(row, side, expected_kind, lines, seen)
  local valid, reason = validate_source(row, side, expected_kind, lines, seen)
  if not valid then return false, reason end
  return validate_ranges(row[side .. "_ranges"], row[side .. "_content"])
end

local function utf16_length(content)
  local _, length = split_codepoints(content, { steps = 0, clock = function() return 0 end,
    started_at = 0, timeout_ms = 1 })
  return length
end

--- Validate a discriminated inline plan before rendering it.
---@param plan RaccoonInlinePlan
---@param lines? RaccoonPatchLine[]
---@return boolean valid
---@return string|nil reason
function M.validate(plan, lines)
  if type(plan) ~= "table" or not is_dense_array(plan.rows) then
    return false, "plan rows must be a dense array"
  end
  local seen = {}
  for _, row in ipairs(plan.rows) do
    if type(row) ~= "table" then return false, "plan row must be a table" end
    local valid, reason
    if row.kind == "replacement" then
      valid, reason = validate_side(row, "old", "deletion", lines, seen)
      if valid then valid, reason = validate_side(row, "new", "addition", lines, seen) end
      if valid and content_outside_ranges(row.old_content, row.old_ranges)
          ~= content_outside_ranges(row.new_content, row.new_ranges) then
        return false, "replacement content outside ranges must match"
      end
    elseif row.kind == "suppressed_replacement" then
      valid, reason = validate_source(row, "old", "deletion", lines, seen)
      if valid then valid, reason = validate_source(row, "new", "addition", lines, seen) end
      if valid and (row.old_ranges ~= nil or row.new_ranges ~= nil) then
        return false, "suppressed replacement cannot contain ranges"
      end
      if valid and utf16_length(row.old_content) <= MAX_LINE_DIFF_UTF16_UNITS
          and utf16_length(row.new_content) <= MAX_LINE_DIFF_UTF16_UNITS then
        return false, "suppressed replacement requires an over-limit side"
      end
    elseif row.kind == "addition" then
      if row.old_index or row.old_line or row.old_content or row.old_ranges then
        return false, "addition row cannot contain an old side"
      end
      valid, reason = validate_side(row, "new", "addition", lines, seen)
    elseif row.kind == "deletion" then
      if row.new_index or row.new_line or row.new_content or row.new_ranges then
        return false, "deletion row cannot contain a new side"
      end
      valid, reason = validate_side(row, "old", "deletion", lines, seen)
    else
      return false, "plan row has an invalid kind"
    end
    if not valid then return false, reason end
  end

  if lines then
    for index, line in ipairs(lines) do
      if line.kind ~= "context" and not seen[index] then
        return false, "changed source line is missing from plan"
      end
    end
  end
  return true
end

return M
