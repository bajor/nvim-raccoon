---@class RaccoonInlineRange
---@field start_col integer Zero-based byte column
---@field end_col integer End-exclusive byte column

---@class RaccoonInlineRow
---@field kind "replacement"|"addition"|"deletion"
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

local MAX_LINE_PAIR_CELLS = 16384
local MAX_TOKENS_PER_LINE = 2048
local MAX_TOKEN_LCS_CELLS = 4194304
local MAX_CHAR_LCS_CELLS = 4194304
local INLINE_DIFF_TIMEOUT_MS = 500
local DEADLINE_CHECK_STEPS = 1024
local LCS_DIRECTION_BASE = 4
local LCS_DIRECTIONS_PER_WORD = 16
local LCS_DIRECTION_UP = 1
local LCS_DIRECTION_LEFT = 2
local LCS_DIRECTION_MATCH = 3
local MIN_LINE_SIMILARITY = 0.55
local MIN_CHAR_REFINE_SIMILARITY = 0.50
local MIN_FORCED_PAIR_TOKEN_SIMILARITY = 0.50
local MAX_FORCED_PAIR_EXACT_CODEPOINTS = 32
local SCORE_EPSILON = 0.0000001
local PLANNING_ABORTED = {}
local LCS_DIRECTION_POWERS = {}
for index = 0, LCS_DIRECTIONS_PER_WORD - 1 do
  LCS_DIRECTION_POWERS[index + 1] = LCS_DIRECTION_BASE ^ index
end

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

local function check_cell_limit(left_count, right_count, limit)
  if left_count > 0 and right_count > math.floor(limit / left_count) then abort_planning() end
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

local function new_addition(index, line, ranges)
  assert(line.kind == "addition", "addition row requires an addition source")
  return {
    kind = "addition",
    new_index = index,
    new_line = line,
    new_content = normalize_content(line.content),
    new_ranges = ranges,
  }
end

local function new_deletion(index, line, ranges)
  assert(line.kind == "deletion", "deletion row requires a deletion source")
  return {
    kind = "deletion",
    old_index = index,
    old_line = line,
    old_content = normalize_content(line.content),
    old_ranges = ranges,
  }
end

local function new_replacement(old_index, old_line, new_index, new_line, old_ranges, new_ranges)
  assert(old_line.kind == "deletion", "replacement old source must be a deletion")
  assert(new_line.kind == "addition", "replacement new source must be an addition")
  return {
    kind = "replacement",
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

local function split_codepoints(text, start_col, end_col, deadline)
  local result = {}
  local cursor = start_col
  while cursor < end_col do
    check_deadline(deadline)
    local first = text:byte(cursor + 1)
    local width = utf8_width(first)
    if cursor + width > end_col then
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
    cursor = cursor + width
  end
  return result
end

local function is_whitespace(unit)
  return unit.text == " " or unit.text == "\t" or unit.text == "\n"
    or unit.text == "\f" or unit.text == "\v" or unit.text == "\r"
end

local function is_word(unit)
  local byte = unit.text:byte(1)
  return byte >= 0x80 or unit.text:match("^[A-Za-z0-9_]$") ~= nil
end

local function tokenize(text, deadline)
  local units = split_codepoints(text, 0, #text, deadline)
  local tokens = {}
  local index = 1
  while index <= #units do
    check_deadline(deadline)
    local first = units[index]
    local category = is_whitespace(first) and "whitespace" or (is_word(first) and "word" or "punctuation")
    local last = index
    if category ~= "punctuation" then
      while last + 1 <= #units do
        check_deadline(deadline)
        local next_unit = units[last + 1]
        local next_category = is_whitespace(next_unit) and "whitespace"
          or (is_word(next_unit) and "word" or "punctuation")
        if next_category ~= category then break end
        last = last + 1
      end
    end
    table.insert(tokens, {
      text = text:sub(first.start_col + 1, units[last].end_col),
      start_col = first.start_col,
      end_col = units[last].end_col,
    })
    index = last + 1
  end
  return tokens, #units
end

local function lcs_pairs(left, right, equals, deadline)
  check_deadline(deadline)
  local previous, current = {}, {}
  for column = 0, #right do previous[column + 1] = 0 end
  -- Scores use rolling rows; only packed two-bit directions are retained for backtracking.
  local directions = {}
  local direction_word, direction_offset = 0, 0

  for left_index = 1, #left do
    check_deadline(deadline)
    current[1] = 0
    for right_index = 1, #right do
      local direction
      if equals(left[left_index], right[right_index]) then
        current[right_index + 1] = previous[right_index] + 1
        direction = LCS_DIRECTION_MATCH
      elseif previous[right_index + 1] >= current[right_index] then
        current[right_index + 1] = previous[right_index + 1]
        direction = LCS_DIRECTION_UP
      else
        current[right_index + 1] = current[right_index]
        direction = LCS_DIRECTION_LEFT
      end
      direction_word = direction_word + direction * LCS_DIRECTION_POWERS[direction_offset + 1]
      direction_offset = direction_offset + 1
      if direction_offset == LCS_DIRECTIONS_PER_WORD then
        table.insert(directions, direction_word)
        direction_word, direction_offset = 0, 0
      end
    end
    previous, current = current, previous
  end
  if direction_offset > 0 then table.insert(directions, direction_word) end

  local pairs = {}
  local left_index, right_index = #left, #right
  while left_index > 0 and right_index > 0 do
    check_deadline(deadline)
    local cell_index = (left_index - 1) * #right + right_index - 1
    local word_index = math.floor(cell_index / LCS_DIRECTIONS_PER_WORD) + 1
    local offset = cell_index % LCS_DIRECTIONS_PER_WORD
    local direction = math.floor(
      directions[word_index] / LCS_DIRECTION_POWERS[offset + 1]
    ) % LCS_DIRECTION_BASE
    if direction == LCS_DIRECTION_MATCH then
      table.insert(pairs, 1, { left_index, right_index })
      left_index = left_index - 1
      right_index = right_index - 1
    elseif direction == LCS_DIRECTION_UP then
      left_index = left_index - 1
    else
      right_index = right_index - 1
    end
  end
  return pairs
end

local function lcs_length(left, right, equals, deadline)
  check_deadline(deadline)
  local previous, current = {}, {}
  for right_index = 0, #right do previous[right_index + 1] = 0 end
  for left_index = 1, #left do
    check_deadline(deadline)
    current[1] = 0
    for right_index = 1, #right do
      if equals(left[left_index], right[right_index]) then
        current[right_index + 1] = previous[right_index] + 1
      else
        current[right_index + 1] = math.max(previous[right_index + 1], current[right_index])
      end
    end
    previous, current = current, previous
  end
  return previous[#right + 1]
end

local function merge_ranges(ranges)
  if #ranges < 2 then return ranges end
  table.sort(ranges, function(left, right) return left.start_col < right.start_col end)
  local merged = { ranges[1] }
  for index = 2, #ranges do
    local current = ranges[index]
    local previous = merged[#merged]
    if current.start_col <= previous.end_col then
      previous.end_col = math.max(previous.end_col, current.end_col)
    else
      table.insert(merged, current)
    end
  end
  return merged
end

local function append_range(ranges, start_col, end_col)
  if end_col > start_col then table.insert(ranges, new_range(start_col, end_col)) end
end

local function append_all(target, values)
  for _, value in ipairs(values) do table.insert(target, value) end
end

local function refine_window(
  old_content,
  new_content,
  old_start,
  old_end,
  new_start,
  new_end,
  deadline,
  allow_low_similarity
)
  local old_units = split_codepoints(old_content, old_start, old_end, deadline)
  local new_units = split_codepoints(new_content, new_start, new_end, deadline)
  local prefix = 0
  while prefix < #old_units and prefix < #new_units
      and old_units[prefix + 1].text == new_units[prefix + 1].text do
    check_deadline(deadline)
    prefix = prefix + 1
  end
  local suffix = 0
  while suffix < #old_units - prefix and suffix < #new_units - prefix
      and old_units[#old_units - suffix].text == new_units[#new_units - suffix].text do
    check_deadline(deadline)
    suffix = suffix + 1
  end

  local old_middle, new_middle = {}, {}
  for index = prefix + 1, #old_units - suffix do
    check_deadline(deadline)
    table.insert(old_middle, old_units[index])
  end
  for index = prefix + 1, #new_units - suffix do
    check_deadline(deadline)
    table.insert(new_middle, new_units[index])
  end
  check_cell_limit(#old_middle, #new_middle, MAX_CHAR_LCS_CELLS)

  local pairs = lcs_pairs(old_middle, new_middle, function(left, right) return left.text == right.text end, deadline)
  local total = #old_units + #new_units
  local similarity = total == 0 and 1 or (2 * (prefix + suffix + #pairs) / total)
  if not allow_low_similarity and similarity < MIN_CHAR_REFINE_SIMILARITY then
    local old_ranges, new_ranges = {}, {}
    append_range(old_ranges, old_start, old_end)
    append_range(new_ranges, new_start, new_end)
    return old_ranges, new_ranges
  end

  local old_ranges, new_ranges = {}, {}
  local old_cursor = prefix == 0 and old_start or old_units[prefix].end_col
  local new_cursor = prefix == 0 and new_start or new_units[prefix].end_col
  for _, pair in ipairs(pairs) do
    local old_unit = old_middle[pair[1]]
    local new_unit = new_middle[pair[2]]
    append_range(old_ranges, old_cursor, old_unit.start_col)
    append_range(new_ranges, new_cursor, new_unit.start_col)
    old_cursor = old_unit.end_col
    new_cursor = new_unit.end_col
  end
  local old_changed_end = suffix == 0 and old_end or old_units[#old_units - suffix + 1].start_col
  local new_changed_end = suffix == 0 and new_end or new_units[#new_units - suffix + 1].start_col
  append_range(old_ranges, old_cursor, old_changed_end)
  append_range(new_ranges, new_cursor, new_changed_end)
  return old_ranges, new_ranges
end

local function refine_pair(old_content, new_content, deadline, require_related_tokens)
  local old_tokens, old_codepoint_count = tokenize(old_content, deadline)
  local new_tokens, new_codepoint_count = tokenize(new_content, deadline)
  if #old_tokens > MAX_TOKENS_PER_LINE or #new_tokens > MAX_TOKENS_PER_LINE then abort_planning() end
  check_cell_limit(#old_tokens, #new_tokens, MAX_TOKEN_LCS_CELLS)

  local token_pairs = lcs_pairs(old_tokens, new_tokens, function(left, right)
    return left.text == right.text
  end, deadline)
  if require_related_tokens then
    local total_tokens = #old_tokens + #new_tokens
    local token_similarity = total_tokens == 0 and 1 or (2 * #token_pairs / total_tokens)
    if token_similarity < MIN_FORCED_PAIR_TOKEN_SIMILARITY then
      local allow_low_similarity = old_codepoint_count <= MAX_FORCED_PAIR_EXACT_CODEPOINTS
        and new_codepoint_count <= MAX_FORCED_PAIR_EXACT_CODEPOINTS
      return refine_window(
        old_content,
        new_content,
        0,
        #old_content,
        0,
        #new_content,
        deadline,
        allow_low_similarity
      )
    end
  end
  local old_ranges, new_ranges = {}, {}
  local old_cursor, new_cursor = 0, 0
  for _, pair in ipairs(token_pairs) do
    local old_token = old_tokens[pair[1]]
    local new_token = new_tokens[pair[2]]
    local refined_old, refined_new = refine_window(
      old_content,
      new_content,
      old_cursor,
      old_token.start_col,
      new_cursor,
      new_token.start_col,
      deadline
    )
    append_all(old_ranges, refined_old)
    append_all(new_ranges, refined_new)
    old_cursor = old_token.end_col
    new_cursor = new_token.end_col
  end

  local refined_old, refined_new = refine_window(
    old_content,
    new_content,
    old_cursor,
    #old_content,
    new_cursor,
    #new_content,
    deadline
  )
  append_all(old_ranges, refined_old)
  append_all(new_ranges, refined_new)
  return merge_ranges(old_ranges), merge_ranges(new_ranges)
end

local function non_whitespace_codepoints(content, deadline)
  local result = {}
  for _, unit in ipairs(split_codepoints(content, 0, #content, deadline)) do
    check_deadline(deadline)
    if not is_whitespace(unit) then table.insert(result, unit) end
  end
  return result
end

local function line_signature(content, deadline)
  local units = non_whitespace_codepoints(content, deadline)
  local signature = { normalized = {}, units = units, counts = {} }
  for _, unit in ipairs(units) do
    check_deadline(deadline)
    table.insert(signature.normalized, unit.text)
    signature.counts[unit.text] = (signature.counts[unit.text] or 0) + 1
  end
  signature.normalized = table.concat(signature.normalized)
  return signature
end

local function line_similarity(old_signature, new_signature, deadline)
  if old_signature.normalized == new_signature.normalized then return 1 end
  local old_count, new_count = #old_signature.units, #new_signature.units
  if old_count == 0 or new_count == 0 then return 0 end

  local common = 0
  local smaller = old_count <= new_count and old_signature or new_signature
  local larger = smaller == old_signature and new_signature or old_signature
  for character, count in pairs(smaller.counts) do
    check_deadline(deadline)
    common = common + math.min(count, larger.counts[character] or 0)
  end
  local upper_bound = 2 * common / (old_count + new_count)
  if upper_bound < MIN_LINE_SIMILARITY then return upper_bound end

  check_cell_limit(old_count, new_count, MAX_CHAR_LCS_CELLS)
  local length = lcs_length(old_signature.units, new_signature.units, function(left, right)
    return left.text == right.text
  end, deadline)
  return 2 * length / (old_count + new_count)
end

local function better_score(candidate, current, candidate_priority, current_priority)
  if not current then return true end
  if candidate.score > current.score + SCORE_EPSILON then return true end
  if current.score > candidate.score + SCORE_EPSILON then return false end
  if candidate.pairs ~= current.pairs then return candidate.pairs > current.pairs end
  if candidate.displacement ~= current.displacement then
    return candidate.displacement < current.displacement
  end
  return candidate_priority > current_priority
end

local function pair_lines(deletions, additions, lines, deadline)
  local old_signatures, new_signatures = {}, {}
  for index, line_index in ipairs(deletions) do
    old_signatures[index] = line_signature(normalize_content(lines[line_index].content), deadline)
  end
  for index, line_index in ipairs(additions) do
    new_signatures[index] = line_signature(normalize_content(lines[line_index].content), deadline)
  end

  local similarities = {}
  for old_index = 1, #deletions do
    similarities[old_index] = {}
    for new_index = 1, #additions do
      local similarity = line_similarity(
        old_signatures[old_index],
        new_signatures[new_index],
        deadline
      )
      similarities[old_index][new_index] = similarity
    end
  end

  local scores = { [1] = {} }
  local actions = { [1] = {} }
  for new_index = 0, #additions do
    scores[1][new_index + 1] = { score = 0, pairs = 0, displacement = 0 }
  end
  for old_index = 1, #deletions do
    check_deadline(deadline, true)
    scores[old_index + 1] = { [1] = { score = 0, pairs = 0, displacement = 0 } }
    actions[old_index + 1] = {}
    for new_index = 1, #additions do
      local up = scores[old_index][new_index + 1]
      local left = scores[old_index + 1][new_index]
      local best, action, priority = up, "up", 1
      if better_score(left, best, 2, priority) then
        best, action, priority = left, "left", 2
      end

      local similarity = similarities[old_index][new_index]
      if similarity >= MIN_LINE_SIMILARITY then
        local previous = scores[old_index][new_index]
        local diagonal = {
          score = previous.score + similarity,
          pairs = previous.pairs + 1,
          displacement = previous.displacement + math.abs(old_index - new_index),
        }
        if better_score(diagonal, best, 3, priority) then
          best, action = diagonal, "pair"
        end
      end
      scores[old_index + 1][new_index + 1] = best
      actions[old_index + 1][new_index + 1] = action
    end
  end

  local result = {}
  local old_index, new_index = #deletions, #additions
  while old_index > 0 and new_index > 0 do
    check_deadline(deadline)
    local action = actions[old_index + 1][new_index + 1]
    if action == "pair" then
      table.insert(result, 1, { deletions[old_index], additions[new_index] })
      old_index = old_index - 1
      new_index = new_index - 1
    elseif action == "up" then
      old_index = old_index - 1
    else
      new_index = new_index - 1
    end
  end
  return result
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

  if #deletions == 0 or #additions == 0 then
    local rows = {}
    for _, index in ipairs(block) do
      check_deadline(deadline)
      local line = lines[index]
      local content = normalize_content(line.content)
      if line.kind == "addition" then
        table.insert(rows, new_addition(index, line, whole_range(content)))
      else
        table.insert(rows, new_deletion(index, line, whole_range(content)))
      end
    end
    return rows
  end

  check_cell_limit(#deletions, #additions, MAX_LINE_PAIR_CELLS)
  local pairs = pair_lines(deletions, additions, lines, deadline)
  local require_related_tokens = false
  if #deletions == 1 and #additions == 1 and #pairs == 0 then
    pairs = { { deletions[1], additions[1] } }
    require_related_tokens = true
  end

  local paired_old, paired_new, rows = {}, {}, {}
  for _, pair in ipairs(pairs) do
    check_deadline(deadline)
    local old_index, new_index = pair[1], pair[2]
    paired_old[old_index] = true
    paired_new[new_index] = true
    local old_content = normalize_content(lines[old_index].content)
    local new_content = normalize_content(lines[new_index].content)
    local old_ranges, new_ranges = refine_pair(
      old_content,
      new_content,
      deadline,
      require_related_tokens
    )
    table.insert(rows, new_replacement(
      old_index,
      lines[old_index],
      new_index,
      lines[new_index],
      old_ranges,
      new_ranges
    ))
  end
  for _, index in ipairs(deletions) do
    check_deadline(deadline)
    if not paired_old[index] then
      local content = normalize_content(lines[index].content)
      table.insert(rows, new_deletion(index, lines[index], whole_range(content)))
    end
  end
  for _, index in ipairs(additions) do
    check_deadline(deadline)
    if not paired_new[index] then
      local content = normalize_content(lines[index].content)
      table.insert(rows, new_addition(index, lines[index], whole_range(content)))
    end
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

local function validate_side(row, side, expected_kind, lines, seen)
  local index = row[side .. "_index"]
  local line = row[side .. "_line"]
  local content = row[side .. "_content"]
  local ranges = row[side .. "_ranges"]
  if not is_integer(index) or index < 1 or type(line) ~= "table" or line.kind ~= expected_kind then
    return false, side .. " side does not match its row kind"
  end
  if type(content) ~= "string" or content ~= normalize_content(line.content) then
    return false, side .. " content does not match its source"
  end
  if lines and lines[index] ~= line then return false, side .. " source index does not match input" end
  if seen[index] then return false, "source line is represented more than once" end
  seen[index] = true
  return validate_ranges(ranges, content)
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
