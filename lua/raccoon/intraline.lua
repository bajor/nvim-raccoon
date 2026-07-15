---@class RaccoonInlineRange
---@field start_col number Zero-based byte column
---@field end_col number End-exclusive byte column

---@class RaccoonLinePair
---@field deletion_index number
---@field addition_index number
---@field changed boolean

local M = {}

-- These caps bound the input passed to vim.diff. Exceeding a cap disables only
-- inline emphasis; callers still render the authoritative whole-line diff.
M.MAX_LINE_LENGTH = 2000
M.MAX_CHANGE_BLOCK_LINES = 100
M.MAX_HUNK_INLINE_BYTES = 64 * 1024
M.MAX_FILE_INLINE_BYTES = 256 * 1024
M.MAX_SEQUENCE_PRODUCT = 1000 * 1000

local MIN_COMMON_CHARS_FOR_REFINEMENT = 3

local function normalize_line(text)
  return (text or ""):gsub("\r$", "")
end

local function get_limits(opts)
  opts = opts or {}
  return {
    max_line_length = opts.max_line_length or M.MAX_LINE_LENGTH,
    max_change_block_lines = opts.max_change_block_lines or M.MAX_CHANGE_BLOCK_LINES,
    max_hunk_inline_bytes = opts.max_hunk_inline_bytes or M.MAX_HUNK_INLINE_BYTES,
    max_file_inline_bytes = opts.max_file_inline_bytes or M.MAX_FILE_INLINE_BYTES,
    max_sequence_product = opts.max_sequence_product or M.MAX_SEQUENCE_PRODUCT,
  }
end

local function append_range(ranges, start_col, end_col)
  if end_col <= start_col then return end
  local previous = ranges[#ranges]
  if previous and start_col <= previous.end_col then
    previous.end_col = math.max(previous.end_col, end_col)
    return
  end
  table.insert(ranges, { start_col = start_col, end_col = end_col })
end

local function utf8_width(text, byte_index)
  local first = text:byte(byte_index)
  if not first or first < 0x80 then return 1 end

  local width
  if first >= 0xC2 and first <= 0xDF then
    width = 2
  elseif first >= 0xE0 and first <= 0xEF then
    width = 3
  elseif first >= 0xF0 and first <= 0xF4 then
    width = 4
  else
    return 1
  end

  if byte_index + width - 1 > #text then return 1 end
  for offset = 1, width - 1 do
    local byte = text:byte(byte_index + offset)
    if not byte or byte < 0x80 or byte > 0xBF then return 1 end
  end

  -- Reject overlong encodings, UTF-16 surrogates, and values beyond U+10FFFF.
  local second = text:byte(byte_index + 1)
  if first == 0xE0 and second < 0xA0 then return 1 end
  if first == 0xED and second > 0x9F then return 1 end
  if first == 0xF0 and second < 0x90 then return 1 end
  if first == 0xF4 and second > 0x8F then return 1 end
  return width
end

local function split_characters(text, base_col)
  local units = {}
  local byte_index = 1
  base_col = base_col or 0
  while byte_index <= #text do
    local width = utf8_width(text, byte_index)
    table.insert(units, {
      text = text:sub(byte_index, byte_index + width - 1),
      start_col = base_col + byte_index - 1,
      end_col = base_col + byte_index + width - 1,
      kind = "character",
    })
    byte_index = byte_index + width
  end
  return units
end

local function character_kind(character)
  local byte = character:byte(1)
  if #character > 1 then return "unicode" end
  if (byte >= 48 and byte <= 57) or (byte >= 65 and byte <= 90) or (byte >= 97 and byte <= 122) then
    return "word"
  end
  if character == " " or character == "\t" or character == "\v" or character == "\f" then
    return "whitespace"
  end
  if character == "_" then return "identifier_separator" end
  return "punctuation"
end

local function split_words(text)
  local characters = split_characters(text)
  local units = {}
  for _, character in ipairs(characters) do
    local kind = character_kind(character.text)
    local previous = units[#units]
    if previous and previous.kind == kind then
      previous.text = previous.text .. character.text
      previous.end_col = character.end_col
    else
      table.insert(units, {
        text = character.text,
        start_col = character.start_col,
        end_col = character.end_col,
        kind = kind,
      })
    end
  end
  return units
end

local function encode_units(units)
  local encoded = {}
  for _, unit in ipairs(units) do
    if unit.text:find("\n", 1, true) or unit.text:find("\0", 1, true) then return nil end
    table.insert(encoded, unit.text)
  end
  if #encoded == 0 then return "" end
  return table.concat(encoded, "\n") .. "\n"
end

local function diff_units(old_units, new_units, opts)
  local old_text = encode_units(old_units)
  local new_text = encode_units(new_units)
  if not old_text or not new_text then return nil end

  local ok, result = pcall(vim.diff, old_text, new_text, opts)
  if not ok or type(result) ~= "table" then return nil end
  return result
end

local function unit_range(units, start_index, count)
  if count <= 0 then return nil end
  local first = units[start_index]
  local last = units[start_index + count - 1]
  if not first or not last then return nil end
  return first.start_col, last.end_col
end

local function ranges_from_diff(old_units, new_units, diff_result)
  local old_ranges = {}
  local new_ranges = {}
  for _, hunk in ipairs(diff_result) do
    local old_start, old_count, new_start, new_count = unpack(hunk)
    local old_range_start, old_range_end = unit_range(old_units, old_start, old_count)
    local new_range_start, new_range_end = unit_range(new_units, new_start, new_count)
    if old_range_start then append_range(old_ranges, old_range_start, old_range_end) end
    if new_range_start then append_range(new_ranges, new_range_start, new_range_end) end
  end
  return old_ranges, new_ranges
end

local function segment(units, start_index, count, text)
  local start_col, end_col = unit_range(units, start_index, count)
  if not start_col then return "", 0 end
  return text:sub(start_col + 1, end_col), start_col
end

local function contains_refinable_punctuation(units, start_index, count)
  for index = start_index, start_index + count - 1 do
    local unit = units[index]
    if unit and (unit.kind == "punctuation" or unit.kind == "identifier_separator") then return true end
  end
  return false
end

local function common_edge_count(old_characters, new_characters)
  local shorter = math.min(#old_characters, #new_characters)
  local prefix = 0
  while prefix < shorter and old_characters[prefix + 1].text == new_characters[prefix + 1].text do
    prefix = prefix + 1
  end

  local suffix = 0
  while suffix < shorter - prefix
      and old_characters[#old_characters - suffix].text == new_characters[#new_characters - suffix].text do
    suffix = suffix + 1
  end
  return prefix + suffix
end

local function should_refine(old_units, new_units, old_start, old_count, new_start, new_count, old_text, new_text)
  if old_count == 0 or new_count == 0 then return false end
  if contains_refinable_punctuation(old_units, old_start, old_count)
      or contains_refinable_punctuation(new_units, new_start, new_count) then
    return true
  end
  if old_count ~= 1 or new_count ~= 1 then return false end

  local old_segment = segment(old_units, old_start, old_count, old_text)
  local new_segment = segment(new_units, new_start, new_count, new_text)
  local old_characters = split_characters(old_segment)
  local new_characters = split_characters(new_segment)
  local common = common_edge_count(old_characters, new_characters)
  if common >= MIN_COMMON_CHARS_FOR_REFINEMENT then return true end

  local contains_digit = old_segment:find("%d") or new_segment:find("%d")
  return contains_digit and common > 0
end

local function refined_ranges(old_units, new_units, old_start, old_count, new_start, new_count,
                              old_text, new_text, max_sequence_product)
  local old_segment, old_base = segment(old_units, old_start, old_count, old_text)
  local new_segment, new_base = segment(new_units, new_start, new_count, new_text)
  local old_characters = split_characters(old_segment, old_base)
  local new_characters = split_characters(new_segment, new_base)
  if #old_characters * #new_characters > max_sequence_product then return nil end

  local result = diff_units(old_characters, new_characters, {
    result_type = "indices",
    algorithm = "minimal",
  })
  if not result then return nil end
  return ranges_from_diff(old_characters, new_characters, result)
end

--- Compute byte ranges for a paired line using only Neovim's built-in diff engine.
---@param old_text string
---@param new_text string
---@param opts? table Supports mode="word"|"character"|"none" and safety-limit overrides
---@return RaccoonInlineRange[]|nil old_ranges
---@return RaccoonInlineRange[]|nil new_ranges
---@return string|nil skipped_reason
function M.compute_inline_ranges(old_text, new_text, opts)
  opts = opts or {}
  local limits = get_limits(opts)
  local mode = opts.mode or "word"
  old_text = normalize_line(old_text)
  new_text = normalize_line(new_text)

  if mode == "none" then return {}, {}, nil end
  if mode ~= "word" and mode ~= "character" then return nil, nil, "invalid_mode" end
  if #old_text > limits.max_line_length or #new_text > limits.max_line_length then
    return nil, nil, "line_too_long"
  end
  if old_text:find("\n", 1, true) or new_text:find("\n", 1, true)
      or old_text:find("\0", 1, true) or new_text:find("\0", 1, true) then
    return nil, nil, "non_text_line"
  end
  if old_text == new_text then return {}, {}, nil end

  local old_units = mode == "character" and split_characters(old_text) or split_words(old_text)
  local new_units = mode == "character" and split_characters(new_text) or split_words(new_text)
  if #old_units * #new_units > limits.max_sequence_product then
    return nil, nil, "comparison_too_large"
  end

  local result = diff_units(old_units, new_units, {
    result_type = "indices",
    algorithm = "minimal",
  })
  if not result then return nil, nil, "diff_failed" end
  if mode == "character" then
    local old_ranges, new_ranges = ranges_from_diff(old_units, new_units, result)
    return old_ranges, new_ranges, nil
  end

  local old_ranges = {}
  local new_ranges = {}
  for _, hunk in ipairs(result) do
    local old_start, old_count, new_start, new_count = unpack(hunk)
    local refined
    if should_refine(old_units, new_units, old_start, old_count, new_start, new_count, old_text, new_text) then
      refined = { refined_ranges(
        old_units, new_units, old_start, old_count, new_start, new_count,
        old_text, new_text, limits.max_sequence_product
      ) }
    end

    if refined and refined[1] then
      for _, range in ipairs(refined[1]) do append_range(old_ranges, range.start_col, range.end_col) end
      for _, range in ipairs(refined[2]) do append_range(new_ranges, range.start_col, range.end_col) end
    else
      local old_range_start, old_range_end = unit_range(old_units, old_start, old_count)
      local new_range_start, new_range_end = unit_range(new_units, new_start, new_count)
      if old_range_start then append_range(old_ranges, old_range_start, old_range_end) end
      if new_range_start then append_range(new_ranges, new_range_start, new_range_end) end
    end
  end
  return old_ranges, new_ranges, nil
end

local function join_block_lines(lines)
  local contents = {}
  for _, line in ipairs(lines) do
    local content = normalize_line(line.content)
    if content:find("\n", 1, true) or content:find("\0", 1, true) then return nil end
    table.insert(contents, content)
  end
  if #contents == 0 then return "" end
  return table.concat(contents, "\n") .. "\n"
end

local function gap_end(start_index, count)
  return count == 0 and start_index or start_index - 1
end

local function next_index(start_index, count)
  return count == 0 and start_index + 1 or start_index + count
end

--- Pair replacement lines using vim.diff's built-in linematch pass.
---@param block RaccoonChangeBlock
---@param opts? table Safety-limit overrides
---@return table result {pairs, unpaired_deletions, unpaired_additions, skipped_reason?}
function M.pair_changed_lines(block, opts)
  local limits = get_limits(opts)
  local deletions = block and block.deletions or {}
  local additions = block and block.additions or {}
  local result = { pairs = {}, unpaired_deletions = {}, unpaired_additions = {} }

  if #deletions == 0 or #additions == 0 then
    for index = 1, #deletions do table.insert(result.unpaired_deletions, index) end
    for index = 1, #additions do table.insert(result.unpaired_additions, index) end
    return result
  end
  if #deletions + #additions > limits.max_change_block_lines then
    result.skipped_reason = "block_too_large"
    for index = 1, #deletions do table.insert(result.unpaired_deletions, index) end
    for index = 1, #additions do table.insert(result.unpaired_additions, index) end
    return result
  end
  for _, line in ipairs(deletions) do
    if #normalize_line(line.content) > limits.max_line_length then result.skipped_reason = "line_too_long" end
  end
  for _, line in ipairs(additions) do
    if #normalize_line(line.content) > limits.max_line_length then result.skipped_reason = "line_too_long" end
  end
  if result.skipped_reason then
    for index = 1, #deletions do table.insert(result.unpaired_deletions, index) end
    for index = 1, #additions do table.insert(result.unpaired_additions, index) end
    return result
  end

  local old_text = join_block_lines(deletions)
  local new_text = join_block_lines(additions)
  local diff_result = old_text and new_text and select(2, pcall(vim.diff, old_text, new_text, {
    result_type = "indices",
    algorithm = "minimal",
    linematch = limits.max_change_block_lines,
  })) or nil
  if type(diff_result) ~= "table" then
    result.skipped_reason = "diff_failed"
    for index = 1, #deletions do table.insert(result.unpaired_deletions, index) end
    for index = 1, #additions do table.insert(result.unpaired_additions, index) end
    return result
  end

  local paired_deletions = {}
  local paired_additions = {}
  local old_cursor = 1
  local new_cursor = 1
  local function add_pair(deletion_index, addition_index, changed)
    table.insert(result.pairs, {
      deletion_index = deletion_index,
      addition_index = addition_index,
      changed = changed,
    })
    paired_deletions[deletion_index] = true
    paired_additions[addition_index] = true
  end

  for _, hunk in ipairs(diff_result) do
    local old_start, old_count, new_start, new_count = unpack(hunk)
    local old_gap_end = gap_end(old_start, old_count)
    local new_gap_end = gap_end(new_start, new_count)
    while old_cursor <= old_gap_end and new_cursor <= new_gap_end do
      add_pair(old_cursor, new_cursor, false)
      old_cursor = old_cursor + 1
      new_cursor = new_cursor + 1
    end
    -- linematch has already aligned insertions and deletions around this
    -- replacement run. Equal-sized runs therefore represent paired rows from
    -- that built-in alignment, rather than a positional pairing of the block.
    if old_count > 0 and old_count == new_count then
      for offset = 0, old_count - 1 do add_pair(old_start + offset, new_start + offset, true) end
    end
    old_cursor = next_index(old_start, old_count)
    new_cursor = next_index(new_start, new_count)
  end
  while old_cursor <= #deletions and new_cursor <= #additions do
    add_pair(old_cursor, new_cursor, false)
    old_cursor = old_cursor + 1
    new_cursor = new_cursor + 1
  end

  for index = 1, #deletions do
    if not paired_deletions[index] then table.insert(result.unpaired_deletions, index) end
  end
  for index = 1, #additions do
    if not paired_additions[index] then table.insert(result.unpaired_additions, index) end
  end
  return result
end

local function block_byte_count(block)
  local total = 0
  for _, line in ipairs(block.deletions) do total = total + #normalize_line(line.content) end
  for _, line in ipairs(block.additions) do total = total + #normalize_line(line.content) end
  return total
end

local function plan_hunk_with_budget(hunk, opts, limits, budget)
  local plan = { ranges = {}, pairs = {}, skipped_blocks = {}, compared_bytes = 0 }
  local hunk_bytes = 0
  for block_index, block in ipairs(hunk.change_blocks or {}) do
    local is_replacement = #block.deletions > 0 and #block.additions > 0
    local bytes = is_replacement and block_byte_count(block) or 0
    local reason
    if hunk_bytes + bytes > limits.max_hunk_inline_bytes then
      reason = "hunk_budget_exceeded"
    elseif budget.file_bytes + bytes > limits.max_file_inline_bytes then
      reason = "file_budget_exceeded"
    end

    local pairing
    if not reason then
      pairing = M.pair_changed_lines(block, opts)
      reason = pairing.skipped_reason
    end
    if reason then
      table.insert(plan.skipped_blocks, { block_index = block_index, reason = reason })
    else
      hunk_bytes = hunk_bytes + bytes
      budget.file_bytes = budget.file_bytes + bytes
      plan.compared_bytes = plan.compared_bytes + bytes
      for _, pair in ipairs(pairing.pairs) do
        table.insert(plan.pairs, {
          block_index = block_index,
          deletion_index = pair.deletion_index,
          addition_index = pair.addition_index,
          changed = pair.changed,
        })
        if pair.changed then
          local deletion = block.deletions[pair.deletion_index]
          local addition = block.additions[pair.addition_index]
          local old_ranges, new_ranges = M.compute_inline_ranges(deletion.content, addition.content, opts)
          if old_ranges and new_ranges then
            if #old_ranges > 0 then plan.ranges[deletion.hunk_line_index] = old_ranges end
            if #new_ranges > 0 then plan.ranges[addition.hunk_line_index] = new_ranges end
          end
        end
      end
    end
  end
  return plan
end

--- Plan all inline ranges for one parsed hunk.
---@param hunk table Parsed hunk from raccoon.diff.parse_patch
---@param opts? table Safety-limit and mode overrides
---@return table plan
function M.plan_hunk(hunk, opts)
  return plan_hunk_with_budget(hunk, opts or {}, get_limits(opts), { file_bytes = 0 })
end

--- Plan hunks together so the file-wide comparison budget is shared.
---@param hunks table[] Parsed hunks from raccoon.diff.parse_patch
---@param opts? table Safety-limit and mode overrides
---@return table plan {hunks, compared_bytes}
function M.plan_hunks(hunks, opts)
  opts = opts or {}
  local limits = get_limits(opts)
  local budget = { file_bytes = 0 }
  local plans = {}
  for index, hunk in ipairs(hunks or {}) do
    plans[index] = plan_hunk_with_budget(hunk, opts, limits, budget)
  end
  return { hunks = plans, compared_bytes = budget.file_bytes }
end

return M
