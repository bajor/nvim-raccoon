---@class RaccoonInlineDiff
local M = {}

local INLINE_DELETE = "RaccoonDeleteInline"
local UNCHANGED_DELETE = "Comment"

M.defaults = {
  enabled = true,
  max_cells = 200000,
  max_line_pairs = 200000,
  char_similarity_floor = 0.35,
  highlight_priority = 110,
  ignore_cr_at_eol = true,
}

local LINE_PAIR_TIE_BREAK_BONUS = 0.001
local WORD_TOKEN_REFINE_SIMILARITY_FLOOR = 0.5

function M.merge_opts(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

local function utf_char_count(text)
  return select(1, vim.str_utfindex(text))
end

local function char_at(text, char_index)
  local start_col = vim.str_byteindex(text, char_index)
  local end_col = vim.str_byteindex(text, char_index + 1)
  return {
    text = text:sub(start_col + 1, end_col),
    start_col = start_col,
    end_col = end_col,
    start_char = char_index,
    end_char = char_index + 1,
  }
end

local function classify_char(text)
  if text:match("^%s$") then
    return "space"
  end
  if text:match("^[%w_]$") then
    return "word"
  end
  return "punct"
end

local function tokenize(line)
  local tokens = {}
  local char_count = utf_char_count(line)

  for i = 0, char_count - 1 do
    local ch = char_at(line, i)
    local kind = classify_char(ch.text)
    local current = tokens[#tokens]

    if current and current.kind == kind then
      current.text = current.text .. ch.text
      current.end_col = ch.end_col
      current.end_char = ch.end_char
    else
      table.insert(tokens, {
        text = ch.text,
        kind = kind,
        start_col = ch.start_col,
        end_col = ch.end_col,
        start_char = ch.start_char,
        end_char = ch.end_char,
      })
    end
  end

  return tokens
end

local function strip_cr(line, opts)
  if opts.ignore_cr_at_eol and line:sub(-1) == "\r" then
    return line:sub(1, -2), "\r"
  end
  return line, ""
end

local function lcs_pairs(left, right, value_fn, max_cells)
  local left_len = #left
  local right_len = #right
  if left_len == 0 or right_len == 0 then
    return {}
  end
  if left_len * right_len > max_cells then
    return nil
  end

  local dp = {}
  for i = 0, left_len do
    dp[i] = {}
    for j = 0, right_len do
      dp[i][j] = 0
    end
  end

  for i = 1, left_len do
    for j = 1, right_len do
      if value_fn(left[i]) == value_fn(right[j]) then
        dp[i][j] = dp[i - 1][j - 1] + 1
      else
        dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1])
      end
    end
  end

  local pairs = {}
  local i = left_len
  local j = right_len
  while i > 0 and j > 0 do
    if value_fn(left[i]) == value_fn(right[j]) then
      table.insert(pairs, 1, { left = i, right = j })
      i = i - 1
      j = j - 1
    elseif dp[i - 1][j] > dp[i][j - 1] then
      i = i - 1
    else
      j = j - 1
    end
  end

  return pairs
end

local function append_chunk(chunks, text, hl_group)
  if text == "" then
    return
  end

  local last = chunks[#chunks]
  if last and last.hl_group == hl_group then
    last.text = last.text .. text
    return
  end

  table.insert(chunks, { text = text, hl_group = hl_group })
end

local function merge_range(ranges, start_col, end_col)
  if start_col >= end_col then
    return
  end

  local last = ranges[#ranges]
  if last and last.end_col == start_col then
    last.end_col = end_col
    return
  end

  table.insert(ranges, { start_col = start_col, end_col = end_col })
end

local function tokens_text(tokens, first, last)
  local parts = {}
  for i = first, last do
    table.insert(parts, tokens[i].text)
  end
  return table.concat(parts)
end

local function append_old_tokens(chunks, tokens, first, last, hl_group)
  for i = first, last do
    append_chunk(chunks, tokens[i].text, hl_group)
  end
end

local function add_new_token_ranges(ranges, tokens, first, last)
  for i = first, last do
    merge_range(ranges, tokens[i].start_col, tokens[i].end_col)
  end
end

local function make_chars(text)
  local chars = {}
  for i = 0, utf_char_count(text) - 1 do
    table.insert(chars, char_at(text, i))
  end
  return chars
end

local function chars_text(chars, first, last)
  local text = {}
  for i = first, last do
    table.insert(text, chars[i].text)
  end
  return table.concat(text)
end

local function boundary_refine_chars(old_text, new_text, new_base_char, normalized_new_line)
  local old_chars = make_chars(old_text)
  local new_chars = make_chars(new_text)
  local old_len = #old_chars
  local new_len = #new_chars
  local prefix_len = 0

  while prefix_len < old_len
      and prefix_len < new_len
      and old_chars[prefix_len + 1].text == new_chars[prefix_len + 1].text do
    prefix_len = prefix_len + 1
  end

  local suffix_len = 0
  while suffix_len < old_len - prefix_len
      and suffix_len < new_len - prefix_len
      and old_chars[old_len - suffix_len].text == new_chars[new_len - suffix_len].text do
    suffix_len = suffix_len + 1
  end

  local old_chunks = {}
  append_chunk(old_chunks, chars_text(old_chars, 1, prefix_len), UNCHANGED_DELETE)
  append_chunk(old_chunks, chars_text(old_chars, prefix_len + 1, old_len - suffix_len), INLINE_DELETE)
  append_chunk(old_chunks, chars_text(old_chars, old_len - suffix_len + 1, old_len), UNCHANGED_DELETE)

  local new_ranges = {}
  local new_start_char = new_base_char + prefix_len
  local new_end_char = new_base_char + new_len - suffix_len
  if new_start_char < new_end_char then
    merge_range(
      new_ranges,
      vim.str_byteindex(normalized_new_line, new_start_char),
      vim.str_byteindex(normalized_new_line, new_end_char)
    )
  end

  return {
    old_chunks = old_chunks,
    new_ranges = new_ranges,
  }
end

local function boundary_diff(normalized_old, normalized_new, old_suffix)
  local old_chars = make_chars(normalized_old)
  local new_chars = make_chars(normalized_new)
  local old_len = #old_chars
  local new_len = #new_chars
  local prefix_len = 0

  while prefix_len < old_len
      and prefix_len < new_len
      and old_chars[prefix_len + 1].text == new_chars[prefix_len + 1].text do
    prefix_len = prefix_len + 1
  end

  local suffix_len = 0
  while suffix_len < old_len - prefix_len
      and suffix_len < new_len - prefix_len
      and old_chars[old_len - suffix_len].text == new_chars[new_len - suffix_len].text do
    suffix_len = suffix_len + 1
  end

  local old_chunks = {}
  append_chunk(old_chunks, chars_text(old_chars, 1, prefix_len), UNCHANGED_DELETE)
  append_chunk(old_chunks, chars_text(old_chars, prefix_len + 1, old_len - suffix_len), INLINE_DELETE)
  append_chunk(old_chunks, chars_text(old_chars, old_len - suffix_len + 1, old_len), UNCHANGED_DELETE)
  append_chunk(old_chunks, old_suffix, UNCHANGED_DELETE)

  local new_ranges = {}
  local new_start_char = prefix_len
  local new_end_char = new_len - suffix_len
  if new_start_char < new_end_char then
    merge_range(
      new_ranges,
      vim.str_byteindex(normalized_new, new_start_char),
      vim.str_byteindex(normalized_new, new_end_char)
    )
  end

  return {
    old_chunks = old_chunks,
    new_ranges = new_ranges,
  }
end

local function line_similarity_items(line)
  local tokens = tokenize(line or "")
  local items = {}

  for _, token in ipairs(tokens) do
    if token.kind == "word" then
      table.insert(items, token.text)
    end
  end

  if #items > 0 then
    return items
  end

  for _, token in ipairs(tokens) do
    if token.kind ~= "space" then
      table.insert(items, token.text)
    end
  end

  return items
end

local function line_similarity(old_line, new_line, opts)
  local normalized_old = strip_cr(old_line or "", opts)
  local normalized_new = strip_cr(new_line or "", opts)

  if normalized_old == normalized_new then
    return 1
  end

  local old_items = line_similarity_items(normalized_old)
  local new_items = line_similarity_items(normalized_new)

  if #old_items == 0 and #new_items == 0 then
    return 1
  end
  if #old_items == 0 or #new_items == 0 then
    return 0
  end

  local pairs = lcs_pairs(old_items, new_items, function(item)
    return item
  end, opts.max_cells)

  if not pairs then
    return 0
  end

  return 2 * #pairs / (#old_items + #new_items)
end

local function highlight_whole(old_tokens, old_first, old_last, new_tokens, new_first, new_last, old_chunks, new_ranges)
  append_old_tokens(old_chunks, old_tokens, old_first, old_last, INLINE_DELETE)
  add_new_token_ranges(new_ranges, new_tokens, new_first, new_last)
end

local function refine_chars(old_text, new_text, new_base_char, normalized_new_line, opts)
  local old_chars = make_chars(old_text)
  local new_chars = make_chars(new_text)
  local pairs = lcs_pairs(old_chars, new_chars, function(item)
    return item.text
  end, opts.max_cells)

  if not pairs then
    return boundary_refine_chars(old_text, new_text, new_base_char, normalized_new_line)
  end

  local common = #pairs
  local total = #old_chars + #new_chars
  if total == 0 or (2 * common / total) < opts.char_similarity_floor then
    return nil
  end

  local old_chunks = {}
  local new_ranges = {}
  local old_pos = 1
  local new_pos = 1

  local function add_new_chars(first, last)
    if first > last then
      return
    end

    local start_char = new_base_char + new_chars[first].start_char
    local end_char = new_base_char + new_chars[last].end_char
    merge_range(
      new_ranges,
      vim.str_byteindex(normalized_new_line, start_char),
      vim.str_byteindex(normalized_new_line, end_char)
    )
  end

  local function add_old_chars(first, last, hl_group)
    if first > last then
      return
    end

    local text = {}
    for i = first, last do
      table.insert(text, old_chars[i].text)
    end
    append_chunk(old_chunks, table.concat(text), hl_group)
  end

  for _, pair in ipairs(pairs) do
    add_old_chars(old_pos, pair.left - 1, INLINE_DELETE)
    add_new_chars(new_pos, pair.right - 1)
    add_old_chars(pair.left, pair.left, UNCHANGED_DELETE)
    old_pos = pair.left + 1
    new_pos = pair.right + 1
  end

  add_old_chars(old_pos, #old_chars, INLINE_DELETE)
  add_new_chars(new_pos, #new_chars)

  return { old_chunks = old_chunks, new_ranges = new_ranges }
end

local function add_changed_block(
  old_tokens,
  old_first,
  old_last,
  new_tokens,
  new_first,
  new_last,
  normalized_new_line,
  opts,
  old_chunks,
  new_ranges
)
  if old_first > old_last then
    add_new_token_ranges(new_ranges, new_tokens, new_first, new_last)
    return
  end
  if new_first > new_last then
    append_old_tokens(old_chunks, old_tokens, old_first, old_last, INLINE_DELETE)
    return
  end

  local single_word_replacement = old_first == old_last
      and new_first == new_last
      and old_tokens[old_first].kind == "word"
      and new_tokens[new_first].kind == "word"
  local old_text = tokens_text(old_tokens, old_first, old_last)
  local new_text = tokens_text(new_tokens, new_first, new_last)
  local refine_opts = opts
  if single_word_replacement then
    refine_opts = vim.tbl_extend("force", opts, {
      char_similarity_floor = math.max(opts.char_similarity_floor, WORD_TOKEN_REFINE_SIMILARITY_FLOOR),
    })
  end
  local refined = refine_chars(old_text, new_text, new_tokens[new_first].start_char, normalized_new_line, refine_opts)

  if not refined then
    highlight_whole(old_tokens, old_first, old_last, new_tokens, new_first, new_last, old_chunks, new_ranges)
    return
  end

  for _, chunk in ipairs(refined.old_chunks) do
    append_chunk(old_chunks, chunk.text, chunk.hl_group)
  end
  for _, range in ipairs(refined.new_ranges) do
    merge_range(new_ranges, range.start_col, range.end_col)
  end
end

---Diff a replaced old/new line pair.
---@param old_line string
---@param new_line string
---@param opts? table
---@return {old_chunks: {text:string, hl_group:string}[], new_ranges: table[], fallback:boolean?}
function M.diff_pair(old_line, new_line, opts)
  opts = M.merge_opts(opts)
  old_line = old_line or ""
  new_line = new_line or ""

  local normalized_old, old_suffix = strip_cr(old_line, opts)
  local normalized_new = strip_cr(new_line, opts)

  local old_tokens = tokenize(normalized_old)
  local new_tokens = tokenize(normalized_new)
  local pairs = lcs_pairs(old_tokens, new_tokens, function(item)
    return item.text
  end, opts.max_cells)

  if not pairs then
    return boundary_diff(normalized_old, normalized_new, old_suffix)
  end

  local old_chunks = {}
  local new_ranges = {}
  local old_pos = 1
  local new_pos = 1

  for _, pair in ipairs(pairs) do
    add_changed_block(
      old_tokens,
      old_pos,
      pair.left - 1,
      new_tokens,
      new_pos,
      pair.right - 1,
      normalized_new,
      opts,
      old_chunks,
      new_ranges
    )
    append_chunk(old_chunks, old_tokens[pair.left].text, UNCHANGED_DELETE)
    old_pos = pair.left + 1
    new_pos = pair.right + 1
  end

  add_changed_block(
    old_tokens,
    old_pos,
    #old_tokens,
    new_tokens,
    new_pos,
    #new_tokens,
    normalized_new,
    opts,
    old_chunks,
    new_ranges
  )
  append_chunk(old_chunks, old_suffix, UNCHANGED_DELETE)

  return {
    old_chunks = old_chunks,
    new_ranges = new_ranges,
  }
end

local function replacement_row(old_line, new_line, opts)
  local inline = nil

  if old_line and new_line and opts.enabled ~= false then
    inline = M.diff_pair(old_line, new_line, opts)
    if inline.fallback then
      inline = nil
    end
  end

  return {
    old = old_line,
    new = new_line,
    inline = inline,
  }
end

local function line_pair_score(old_line, new_line, opts)
  return LINE_PAIR_TIE_BREAK_BONUS + line_similarity(old_line, new_line, opts)
end

local function ordered_replacement_rows(old_lines, new_lines, opts)
  local rows = {}
  local pair_count = math.min(#old_lines, #new_lines)

  for i = 1, pair_count do
    table.insert(rows, replacement_row(old_lines[i], new_lines[i], opts))
  end
  for i = pair_count + 1, #old_lines do
    table.insert(rows, replacement_row(old_lines[i], nil, opts))
  end
  for i = pair_count + 1, #new_lines do
    table.insert(rows, replacement_row(nil, new_lines[i], opts))
  end

  return rows
end

---Plan old/new rows for a contiguous replacement block.
---@param old_lines string[]
---@param new_lines string[]
---@param opts? table
---@return {old:string?, new:string?, inline:table?}[]
function M.plan_replacement(old_lines, new_lines, opts)
  opts = M.merge_opts(opts)
  old_lines = old_lines or {}
  new_lines = new_lines or {}

  if #old_lines * #new_lines > opts.max_line_pairs then
    return ordered_replacement_rows(old_lines, new_lines, opts)
  end

  local scores = {}
  local actions = {}
  for i = 0, #old_lines do
    scores[i] = {}
    actions[i] = {}
    scores[i][0] = 0
    actions[i][0] = "del"
  end
  for j = 0, #new_lines do
    scores[0][j] = 0
    actions[0][j] = "add"
  end
  actions[0][0] = nil

  for i = 1, #old_lines do
    for j = 1, #new_lines do
      local best_score = scores[i - 1][j - 1] + line_pair_score(old_lines[i], new_lines[j], opts)
      local best_action = "pair"
      local delete_score = scores[i - 1][j]
      local add_score = scores[i][j - 1]

      if delete_score > best_score then
        best_score = delete_score
        best_action = "del"
      end
      if add_score > best_score then
        best_score = add_score
        best_action = "add"
      end

      scores[i][j] = best_score
      actions[i][j] = best_action
    end
  end

  local rows = {}
  local i = #old_lines
  local j = #new_lines

  while i > 0 or j > 0 do
    local action = actions[i][j]

    if action == "pair" then
      table.insert(rows, 1, replacement_row(old_lines[i], new_lines[j], opts))
      i = i - 1
      j = j - 1
    elseif action == "del" then
      table.insert(rows, 1, replacement_row(old_lines[i], nil, opts))
      i = i - 1
    else
      table.insert(rows, 1, replacement_row(nil, new_lines[j], opts))
      j = j - 1
    end
  end

  return rows
end

return M
