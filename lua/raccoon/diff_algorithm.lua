---@class RaccoonDiffAlgorithm
local M = {}

local MAX_CHAIN_LENGTH = 64
local MAX_MYERS_CELLS = 20000
local MAX_INLINE_CHAR_CELLS = 12000
local MIN_LINE_SIMILARITY = 0.55
local MIN_TOKEN_SIMILARITY = 0.45

local function utf_char_count(text)
  return select(1, vim.str_utfindex(text or ""))
end

local function char_at(text, char_index)
  local start_col = vim.str_byteindex(text, char_index)
  local end_col = vim.str_byteindex(text, char_index + 1)
  return {
    text = text:sub(start_col + 1, end_col),
    start_col = start_col,
    end_col = end_col,
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
  local count = utf_char_count(line or "")

  for i = 0, count - 1 do
    local ch = char_at(line, i)
    local kind = classify_char(ch.text)
    local current = tokens[#tokens]

    if current and current.kind == kind and kind ~= "punct" then
      current.text = current.text .. ch.text
      current.end_col = ch.end_col
    else
      table.insert(tokens, {
        text = ch.text,
        kind = kind,
        start_col = ch.start_col,
        end_col = ch.end_col,
      })
    end
  end

  return tokens
end

local function append_chunk(chunks, text, kind)
  if text == "" then
    return
  end

  local last = chunks[#chunks]
  if last and last.kind == kind then
    last.text = last.text .. text
    return
  end

  table.insert(chunks, { text = text, kind = kind })
end

local function append_range(ranges, start_col, end_col)
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

local function count_occurrences(items, key_fn)
  local counts = {}
  for _, item in ipairs(items) do
    local key = key_fn(item)
    counts[key] = (counts[key] or 0) + 1
  end
  return counts
end

local function lcs_pairs(old_items, new_items, key_fn, max_cells)
  local old_len = #old_items
  local new_len = #new_items
  if old_len == 0 or new_len == 0 then
    return {}
  end
  if old_len * new_len > max_cells then
    return nil
  end

  local old_counts = count_occurrences(old_items, key_fn)
  local new_counts = count_occurrences(new_items, key_fn)
  local dp = {}
  for i = 0, old_len do
    dp[i] = {}
    for j = 0, new_len do
      dp[i][j] = 0
    end
  end

  for i = 1, old_len do
    for j = 1, new_len do
      local old_key = key_fn(old_items[i])
      local new_key = key_fn(new_items[j])
      if old_key == new_key
          and old_counts[old_key] <= MAX_CHAIN_LENGTH
          and new_counts[new_key] <= MAX_CHAIN_LENGTH then
        dp[i][j] = dp[i - 1][j - 1] + 1
      else
        dp[i][j] = math.max(dp[i - 1][j], dp[i][j - 1])
      end
    end
  end

  local pairs = {}
  local i = old_len
  local j = new_len
  while i > 0 and j > 0 do
    local old_key = key_fn(old_items[i])
    local new_key = key_fn(new_items[j])
    if old_key == new_key
        and old_counts[old_key] <= MAX_CHAIN_LENGTH
        and new_counts[new_key] <= MAX_CHAIN_LENGTH then
      table.insert(pairs, 1, { old_index = i, new_index = j })
      i = i - 1
      j = j - 1
    elseif dp[i - 1][j] >= dp[i][j - 1] then
      i = i - 1
    else
      j = j - 1
    end
  end

  return pairs
end

local function append_edit(edits, edit)
  table.insert(edits, edit)
end

local function diff_items(old_items, new_items, key_fn, max_cells)
  local pairs = lcs_pairs(old_items, new_items, key_fn, max_cells)
  local edits = {}

  if not pairs then
    for i, item in ipairs(old_items) do
      append_edit(edits, { kind = "del", old_index = i, old_item = item })
    end
    for i, item in ipairs(new_items) do
      append_edit(edits, { kind = "add", new_index = i, new_item = item })
    end
    return edits
  end

  local old_cursor = 1
  local new_cursor = 1
  for _, pair in ipairs(pairs) do
    while old_cursor < pair.old_index do
      append_edit(edits, { kind = "del", old_index = old_cursor, old_item = old_items[old_cursor] })
      old_cursor = old_cursor + 1
    end
    while new_cursor < pair.new_index do
      append_edit(edits, { kind = "add", new_index = new_cursor, new_item = new_items[new_cursor] })
      new_cursor = new_cursor + 1
    end
    append_edit(edits, {
      kind = "equal",
      old_index = pair.old_index,
      new_index = pair.new_index,
      old_item = old_items[pair.old_index],
      new_item = new_items[pair.new_index],
    })
    old_cursor = pair.old_index + 1
    new_cursor = pair.new_index + 1
  end

  while old_cursor <= #old_items do
    append_edit(edits, { kind = "del", old_index = old_cursor, old_item = old_items[old_cursor] })
    old_cursor = old_cursor + 1
  end
  while new_cursor <= #new_items do
    append_edit(edits, { kind = "add", new_index = new_cursor, new_item = new_items[new_cursor] })
    new_cursor = new_cursor + 1
  end

  return edits
end

---Diff two sequences into normalized edits.
---@param old_items any[]
---@param new_items any[]
---@param opts? table
---@return table[]
function M.diff_sequence(old_items, new_items, opts)
  opts = opts or {}
  local key_fn = opts.key_fn or function(item) return item end
  return diff_items(old_items or {}, new_items or {}, key_fn, opts.max_cells or MAX_MYERS_CELLS)
end

local function line_tokens(line)
  local tokens = {}
  local counts = {}
  for _, token in ipairs(tokenize(line or "")) do
    if token.kind ~= "space" then
      counts[token.text] = (counts[token.text] or 0) + 1
      table.insert(tokens, token.text)
    end
  end

  local filtered = {}
  for _, token in ipairs(tokens) do
    if counts[token] <= MAX_CHAIN_LENGTH then
      table.insert(filtered, token)
    end
  end
  return filtered
end

local function lcs_length(left, right)
  local pairs = lcs_pairs(left, right, function(item) return item end, MAX_MYERS_CELLS)
  if not pairs then
    return 0
  end
  return #pairs
end

local function token_similarity(old_line, new_line)
  if old_line == new_line then
    return 1
  end

  local old_tokens = line_tokens(old_line)
  local new_tokens = line_tokens(new_line)
  local max_len = math.max(#old_tokens, #new_tokens)
  if max_len == 0 then
    return old_line == new_line and 1 or 0
  end

  return lcs_length(old_tokens, new_tokens) / max_len
end

---Pair replacement block lines by similarity while preserving order.
---@param old_lines string[]
---@param new_lines string[]
---@return table[]
function M.pair_lines(old_lines, new_lines)
  old_lines = old_lines or {}
  new_lines = new_lines or {}
  local old_len = #old_lines
  local new_len = #new_lines
  if old_len == 0 then
    local rows = {}
    for i = 1, new_len do
      table.insert(rows, { new_index = i })
    end
    return rows
  end
  if new_len == 0 then
    local rows = {}
    for i = 1, old_len do
      table.insert(rows, { old_index = i })
    end
    return rows
  end

  if old_len * new_len > MAX_MYERS_CELLS then
    local rows = {}
    for i = 1, old_len do
      table.insert(rows, { old_index = i })
    end
    for i = 1, new_len do
      table.insert(rows, { new_index = i })
    end
    return rows
  end

  local scores = {}
  local actions = {}
  for i = 0, old_len do
    scores[i] = {}
    actions[i] = {}
    for j = 0, new_len do
      scores[i][j] = 0
    end
  end

  for i = 1, old_len do
    for j = 1, new_len do
      local best = scores[i - 1][j]
      local action = "old"
      if scores[i][j - 1] > best then
        best = scores[i][j - 1]
        action = "new"
      end

      local similarity = token_similarity(old_lines[i], new_lines[j])
      if similarity >= MIN_LINE_SIMILARITY then
        local pair_score = scores[i - 1][j - 1] + similarity
        if pair_score > best then
          best = pair_score
          action = "pair"
        end
      end

      scores[i][j] = best
      actions[i][j] = action
    end
  end

  local matches = {}
  local i = old_len
  local j = new_len
  while i > 0 or j > 0 do
    local action = i > 0 and j > 0 and actions[i][j] or nil
    if action == "pair" then
      table.insert(matches, 1, { old_index = i, new_index = j })
      i = i - 1
      j = j - 1
    elseif j > 0 and (i == 0 or action == "new") then
      j = j - 1
    else
      i = i - 1
    end
  end

  local rows = {}
  local old_cursor = 1
  local new_cursor = 1
  for _, match in ipairs(matches) do
    while new_cursor < match.new_index do
      table.insert(rows, { new_index = new_cursor })
      new_cursor = new_cursor + 1
    end
    while old_cursor < match.old_index do
      table.insert(rows, { old_index = old_cursor })
      old_cursor = old_cursor + 1
    end
    table.insert(rows, match)
    old_cursor = match.old_index + 1
    new_cursor = match.new_index + 1
  end

  while old_cursor <= old_len do
    table.insert(rows, { old_index = old_cursor })
    old_cursor = old_cursor + 1
  end
  while new_cursor <= new_len do
    table.insert(rows, { new_index = new_cursor })
    new_cursor = new_cursor + 1
  end

  return rows
end

local function chars(text)
  local result = {}
  for i = 0, utf_char_count(text) - 1 do
    table.insert(result, char_at(text, i))
  end
  return result
end

local function chars_text(items, first, last)
  local result = {}
  for i = first, last do
    table.insert(result, items[i].text)
  end
  return table.concat(result)
end

local function char_similarity(old_chars, new_chars)
  local old_text = {}
  local new_text = {}
  for _, ch in ipairs(old_chars) do
    table.insert(old_text, ch.text)
  end
  for _, ch in ipairs(new_chars) do
    table.insert(new_text, ch.text)
  end

  local max_len = math.max(#old_text, #new_text)
  if max_len == 0 then
    return 1
  end

  return lcs_length(old_text, new_text) / max_len
end

local function refine_changed_text(old_text, new_text, new_line, new_start_col)
  local old_chars = chars(old_text)
  local new_chars = chars(new_text)
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

  local old_middle_start = prefix_len + 1
  local old_middle_end = old_len - suffix_len
  local new_middle_start = prefix_len
  local new_middle_end = new_len - suffix_len
  local old_middle = ""
  if old_middle_start <= old_middle_end then
    old_middle = chars_text(old_chars, old_middle_start, old_middle_end)
  end
  local old_chunks = {}
  local new_ranges = {}
  local exact = true

  append_chunk(old_chunks, chars_text(old_chars, 1, prefix_len), "same")

  if old_middle ~= "" then
    append_chunk(old_chunks, old_middle, "del")
  end

  append_chunk(old_chunks, chars_text(old_chars, old_len - suffix_len + 1, old_len), "same")

  if new_middle_start < new_middle_end then
    local start_col = new_start_col + vim.str_byteindex(new_text, new_middle_start)
    local end_col = new_start_col + vim.str_byteindex(new_text, new_middle_end)
    append_range(new_ranges, start_col, end_col)
  end

  if (old_len - prefix_len - suffix_len) * (new_len - prefix_len - suffix_len) > MAX_INLINE_CHAR_CELLS then
    exact = false
  elseif old_middle ~= "" and new_middle_start < new_middle_end then
    local old_mid_chars = {}
    local new_mid_chars = {}
    for i = old_middle_start, old_middle_end do
      table.insert(old_mid_chars, old_chars[i])
    end
    for i = new_middle_start + 1, new_middle_end do
      table.insert(new_mid_chars, new_chars[i])
    end
    if char_similarity(old_mid_chars, new_mid_chars) < MIN_TOKEN_SIMILARITY then
      exact = true
    end
  end

  return {
    old_chunks = old_chunks,
    new_ranges = new_ranges,
    exact = exact,
    new_line = new_line,
  }
end

local function tokens_text(tokens)
  local result = {}
  for _, token in ipairs(tokens) do
    table.insert(result, token.text)
  end
  return table.concat(result)
end

local function append_old_tokens(chunks, tokens, kind)
  for _, token in ipairs(tokens) do
    append_chunk(chunks, token.text, kind)
  end
end

local function append_new_token_ranges(ranges, tokens)
  for _, token in ipairs(tokens) do
    append_range(ranges, token.start_col, token.end_col)
  end
end

---Compute inline old-side chunks and new-side byte ranges for a paired line.
---@param old_line string
---@param new_line string
---@return table
function M.diff_inline(old_line, new_line)
  old_line = old_line or ""
  new_line = new_line or ""

  if old_line == new_line then
    return {
      old_chunks = old_line == "" and {} or { { text = old_line, kind = "same" } },
      new_ranges = {},
      exact = true,
    }
  end

  local old_tokens = tokenize(old_line)
  local new_tokens = tokenize(new_line)
  local edits = diff_items(old_tokens, new_tokens, function(token) return token.text end, MAX_MYERS_CELLS)
  local old_chunks = {}
  local new_ranges = {}
  local exact = true
  local i = 1

  while i <= #edits do
    local edit = edits[i]
    if edit.kind == "equal" then
      append_chunk(old_chunks, edit.old_item.text, "same")
      i = i + 1
    else
      local old_run = {}
      local new_run = {}
      while i <= #edits and edits[i].kind ~= "equal" do
        if edits[i].kind == "del" then
          table.insert(old_run, edits[i].old_item)
        elseif edits[i].kind == "add" then
          table.insert(new_run, edits[i].new_item)
        end
        i = i + 1
      end

      if #old_run > 0 and #new_run > 0 then
        local refined = refine_changed_text(tokens_text(old_run), tokens_text(new_run), new_line, new_run[1].start_col)
        for _, chunk in ipairs(refined.old_chunks) do
          append_chunk(old_chunks, chunk.text, chunk.kind)
        end
        for _, range in ipairs(refined.new_ranges) do
          append_range(new_ranges, range.start_col, range.end_col)
        end
        exact = exact and refined.exact
      elseif #old_run > 0 then
        append_old_tokens(old_chunks, old_run, "del")
      elseif #new_run > 0 then
        append_new_token_ranges(new_ranges, new_run)
      end
    end
  end

  return {
    old_chunks = old_chunks,
    new_ranges = new_ranges,
    exact = exact,
  }
end

return M
