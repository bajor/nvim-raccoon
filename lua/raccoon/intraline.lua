---@class RaccoonInlineRange
---@field start_col number Zero-based byte column
---@field end_col number End-exclusive byte column

---@class RaccoonLinePair
---@field deletion_index number
---@field addition_index number
---@field changed boolean

local jsdiff = require("raccoon.vendor.jsdiff")

local M = {}

-- These caps bound the input passed to the inline and line-matching engines.
-- Exceeding a cap disables only inline emphasis; callers still render the
-- authoritative whole-line diff.
M.MAX_LINE_LENGTH = 2000
M.MAX_CHANGE_BLOCK_LINES = 100
M.MAX_HUNK_INLINE_BYTES = 64 * 1024
M.MAX_FILE_INLINE_BYTES = 256 * 1024
M.MAX_SEQUENCE_PRODUCT = 1000 * 1000
M.MAX_EDIT_LENGTH = 256

local MIN_COMMON_CHARACTERS_FOR_IDENTIFIER_REFINEMENT = 3

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
    max_edit_length = opts.max_edit_length or M.MAX_EDIT_LENGTH,
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

local function is_one_character(text)
  local ok, character_count = pcall(vim.str_utfindex, text)
  return (ok and character_count == 1) or (not ok and #text == 1)
end

-- Mechanically adapted from @pierre/diffs 1.2.12
-- packages/diffs/src/utils/parseDiffDecorations.ts. The tuple became a named
-- Lua table and byte-length conversion is deferred until spans are complete.
local function push_or_join_span(spans, item, enable_join, is_neutral, is_last_item)
  local previous = spans[#spans]
  if not previous or is_last_item or not enable_join then
    table.insert(spans, { highlighted = not is_neutral, value = item.value })
    return
  end

  local previous_is_neutral = not previous.highlighted
  if is_neutral == previous_is_neutral
      or (is_neutral and is_one_character(item.value) and not previous_is_neutral) then
    previous.value = previous.value .. item.value
  else
    table.insert(spans, { highlighted = not is_neutral, value = item.value })
  end
end

local function ranges_from_spans(spans)
  local ranges = {}
  local byte_col = 0
  for _, span in ipairs(spans) do
    local end_col = byte_col + #span.value
    if span.highlighted then append_range(ranges, byte_col, end_col) end
    byte_col = end_col
  end
  return ranges
end

local function ranges_from_changes(changes, enable_join)
  local deletion_spans = {}
  local addition_spans = {}
  for index, item in ipairs(changes) do
    local is_last_item = index == #changes
    local is_neutral = not item.added and not item.removed
    if is_neutral then
      push_or_join_span(deletion_spans, item, enable_join, true, is_last_item)
      push_or_join_span(addition_spans, item, enable_join, true, is_last_item)
    elseif item.removed then
      push_or_join_span(deletion_spans, item, enable_join, false, is_last_item)
    else
      push_or_join_span(addition_spans, item, enable_join, false, is_last_item)
    end
  end
  return ranges_from_spans(deletion_spans), ranges_from_spans(addition_spans)
end

local function is_ascii_identifier(text)
  return text:match("^[A-Za-z_][A-Za-z0-9_]*$") ~= nil
end

local function has_identifier_structure(text)
  return text:find("_", 1, true) ~= nil
    or text:find("%l%u") ~= nil
    or text:find("%d") ~= nil
end

local function useful_character_refinement(changes, old_value, new_value)
  local common_characters = 0
  local has_deletion = false
  local has_addition = false
  for _, item in ipairs(changes) do
    if item.removed then
      has_deletion = true
    elseif item.added then
      has_addition = true
    else
      common_characters = common_characters + item.count
    end
  end
  local minimum_common = MIN_COMMON_CHARACTERS_FOR_IDENTIFIER_REFINEMENT
  if old_value:find("%d") or new_value:find("%d") then minimum_common = 1 end
  return has_deletion and has_addition and common_characters >= minimum_common
end

local function refine_change_group(group, limits)
  local old_parts = {}
  local new_parts = {}
  for _, item in ipairs(group) do
    if item.removed then table.insert(old_parts, item.value) end
    if item.added then table.insert(new_parts, item.value) end
  end

  local old_value = table.concat(old_parts)
  local new_value = table.concat(new_parts)
  local structured = has_identifier_structure(old_value) or has_identifier_structure(new_value)
  if not structured or not is_ascii_identifier(old_value) or not is_ascii_identifier(new_value) then return group end

  local refined = jsdiff.diff_chars(old_value, new_value, {
    max_sequence_product = limits.max_sequence_product,
    max_edit_length = limits.max_edit_length,
  })
  if not refined or not useful_character_refinement(refined, old_value, new_value) then return group end
  return refined
end

local function refine_identifier_changes(changes, limits)
  local refined = {}
  local group = {}
  local function flush_group()
    if #group == 0 then return end
    for _, item in ipairs(refine_change_group(group, limits)) do table.insert(refined, item) end
    group = {}
  end

  for _, item in ipairs(changes) do
    if item.added or item.removed then
      table.insert(group, item)
    else
      flush_group()
      table.insert(refined, item)
    end
  end
  flush_group()
  return refined
end

--- Compute byte ranges for a paired line using the pinned jsdiff/Pierre behavior.
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

  local diff_function = mode == "character" and jsdiff.diff_chars or jsdiff.diff_words_with_space
  local changes, reason = diff_function(old_text, new_text, {
    max_sequence_product = limits.max_sequence_product,
    max_edit_length = limits.max_edit_length,
  })
  if not changes then return nil, nil, reason or "diff_failed" end
  if mode == "word" then changes = refine_identifier_changes(changes, limits) end
  local old_ranges, new_ranges = ranges_from_changes(changes, mode == "word")
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
