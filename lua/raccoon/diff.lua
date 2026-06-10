---@class RaccoonDiff
---Diff parsing and display functionality
local M = {}

local state = require("raccoon.state")

--- Namespace for diff highlights
local ns_id = vim.api.nvim_create_namespace("raccoon_diff")

M.MAX_SYNTAX_ROWS = 5000
M.MAX_SYNTAX_SIDE_BYTES = 500 * 1024
M.MAX_INLINE_DIFF_DISPLAY_CHARS = 1000

local SPLIT_SEPARATOR = " │ "
local split_metadata_by_buf = {}

--- Parse a unified diff hunk header into old and new ranges.
---@param header string Hunk header like "@@ -1,4 +1,5 @@"
---@return table|nil ranges {old_start, old_count, new_start, new_count}
function M.parse_hunk_ranges(header)
  if type(header) ~= "string" then
    return nil
  end
  local old_start, old_count, new_start, new_count =
    header:match("^@@%s+%-(%d+),?(%d*)%s+%+(%d+),?(%d*)%s*@@")
  if not old_start or not new_start then
    return nil
  end
  return {
    old_start = tonumber(old_start),
    old_count = old_count ~= "" and tonumber(old_count) or 1,
    new_start = tonumber(new_start),
    new_count = new_count ~= "" and tonumber(new_count) or 1,
  }
end

--- Parse a unified diff hunk header
--- Returns start_line, count for the new file (right side)
---@param header string Hunk header like "@@ -1,4 +1,5 @@"
---@return number|nil start_line
---@return number|nil count
function M.parse_hunk_header(header)
  local ranges = M.parse_hunk_ranges(header)
  if not ranges then
    return nil, nil
  end
  return ranges.new_start, ranges.new_count
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
  local old_line_num = 0
  local new_line_num = 0

  for line in normalized_patch:gmatch("(.-)\n") do
    if line:match("^@@") then
      -- New hunk
      if current_hunk then
        table.insert(hunks, current_hunk)
      end
      local ranges = M.parse_hunk_ranges(line)
      local start_line = ranges and ranges.new_start or 1
      local count = ranges and ranges.new_count or 0
      current_hunk = {
        header = line,
        lines = {},
        start_line = start_line or 1,
        count = count or 0,
        old_start = ranges and ranges.old_start or 1,
        old_count = ranges and ranges.old_count or 0,
        new_start = start_line or 1,
        new_count = count or 0,
        changes = {},
      }
      line_num = (start_line or 1) - 1
      old_line_num = (current_hunk.old_start or 1)
      new_line_num = (current_hunk.new_start or 1)
    elseif current_hunk then
      if line:match("^%+") and not line:match("^%+%+%+") then
        -- Added line
        line_num = line_num + 1
        table.insert(current_hunk.lines, {
          type = "add",
          content = line:sub(2),
          line_num = line_num,
          new_line = new_line_num,
        })
        table.insert(current_hunk.changes, { type = "add", line_num = line_num })
        new_line_num = new_line_num + 1
      elseif line:match("^%-") and not line:match("^%-%-%-") then
        -- Removed line (doesn't increment line number in new file)
        -- Store the content for virtual text display
        table.insert(current_hunk.lines, {
          type = "del",
          content = line:sub(2),
          line_num = line_num,
          old_line = old_line_num,
        })
        table.insert(current_hunk.changes, {
          type = "del",
          line_num = line_num,
          old_line = old_line_num,
          content = line:sub(2),
        })
        old_line_num = old_line_num + 1
      elseif not line:match("^\\ No newline at end of file$") and (line:match("^%s") or line == "") then
        -- Context line
        line_num = line_num + 1
        table.insert(current_hunk.lines, {
          type = "ctx",
          content = line:sub(2),
          line_num = line_num,
          old_line = old_line_num,
          new_line = new_line_num,
        })
        old_line_num = old_line_num + 1
        new_line_num = new_line_num + 1
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
        table.insert(changes.deleted, {
          line_num = change.line_num,
          old_line = change.old_line,
          content = change.content,
        })
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
---@param side? string "LEFT" for old-side comments, "RIGHT" for new-side comments
---@return boolean
function M.is_line_in_review_context(patch, target_line, side)
  if type(target_line) ~= "number" or target_line < 1 then
    return false
  end
  side = side == "LEFT" and "LEFT" or "RIGHT"

  local hunks = M.parse_patch(patch)
  for _, hunk in ipairs(hunks) do
    for _, line in ipairs(hunk.lines) do
      if side == "LEFT" then
        if line.old_line == target_line and (line.type == "del" or line.type == "ctx") then
          return true
        end
      elseif line.line_num == target_line and (line.type == "add" or line.type == "ctx") then
        return true
      end
    end
  end

  return false
end

local function string_byte_count(lines)
  local total = 0
  for _, line in ipairs(lines or {}) do
    total = total + #(line or "") + 1
  end
  return total
end

local function line_or_hunk_content(lines, line_num, fallback)
  if type(line_num) == "number" and lines and lines[line_num] ~= nil then
    return lines[line_num]
  end
  return fallback or ""
end

local function changed_span(left, right)
  if #left > M.MAX_INLINE_DIFF_DISPLAY_CHARS or #right > M.MAX_INLINE_DIFF_DISPLAY_CHARS then
    return nil, nil
  end

  local prefix = 0
  local max_prefix = math.min(#left, #right)
  while prefix < max_prefix and left:sub(prefix + 1, prefix + 1) == right:sub(prefix + 1, prefix + 1) do
    prefix = prefix + 1
  end

  local left_suffix = #left
  local right_suffix = #right
  while left_suffix > prefix
    and right_suffix > prefix
    and left:sub(left_suffix, left_suffix) == right:sub(right_suffix, right_suffix)
  do
    left_suffix = left_suffix - 1
    right_suffix = right_suffix - 1
  end

  local old_span = nil
  if left_suffix > prefix then
    old_span = { start_col = prefix, end_col = left_suffix }
  end
  local new_span = nil
  if right_suffix > prefix then
    new_span = { start_col = prefix, end_col = right_suffix }
  end
  return old_span, new_span
end

local function append_pair_spans(spans, left_line, right_line, left_content, right_content, left_hl, right_hl)
  local old_span, new_span = changed_span(left_content or "", right_content or "")
  if old_span then
    table.insert(spans, {
      line = left_line,
      start_col = old_span.start_col,
      end_col = old_span.end_col,
      hl = left_hl,
    })
  end
  if new_span then
    table.insert(spans, {
      line = right_line,
      start_col = new_span.start_col,
      end_col = new_span.end_col,
      hl = right_hl,
    })
  end
end

--- Build inline spans for stacked hunk buffers.
---@param line_list table[] Array of {type, content}
---@return table[] spans Array of {line, start_col, end_col, hl}
function M.render_stacked_inline_spans(line_list)
  local spans = {}
  local idx = 1

  while idx <= #(line_list or {}) do
    local line_data = line_list[idx]
    if line_data and (line_data.type == "del" or line_data.type == "add") then
      local dels = {}
      local adds = {}
      while idx <= #line_list and (line_list[idx].type == "del" or line_list[idx].type == "add") do
        if line_list[idx].type == "del" then
          table.insert(dels, { index = idx, content = line_list[idx].content or "" })
        else
          table.insert(adds, { index = idx, content = line_list[idx].content or "" })
        end
        idx = idx + 1
      end
      for pair_idx = 1, math.min(#dels, #adds) do
        append_pair_spans(
          spans,
          dels[pair_idx].index,
          adds[pair_idx].index,
          dels[pair_idx].content,
          adds[pair_idx].content,
          "RaccoonInlineDelete",
          "RaccoonInlineAdd"
        )
      end
    else
      idx = idx + 1
    end
  end

  table.sort(spans, function(left, right)
    if left.line ~= right.line then
      return left.line < right.line
    end
    return left.start_col < right.start_col
  end)
  return spans
end

local function build_hunk_rows(hunk)
  local rows = {}
  local idx = 1
  while idx <= #hunk.lines do
    local line_data = hunk.lines[idx]
    if line_data.type == "del" or line_data.type == "add" then
      local dels = {}
      local adds = {}
      while idx <= #hunk.lines and (hunk.lines[idx].type == "del" or hunk.lines[idx].type == "add") do
        if hunk.lines[idx].type == "del" then
          table.insert(dels, hunk.lines[idx])
        else
          table.insert(adds, hunk.lines[idx])
        end
        idx = idx + 1
      end
      local count = math.max(#dels, #adds)
      for pair_idx = 1, count do
        local del = dels[pair_idx]
        local add = adds[pair_idx]
        table.insert(rows, {
          old_line = del and del.old_line or nil,
          new_line = add and add.new_line or nil,
          old_content = del and del.content or nil,
          new_content = add and add.content or nil,
          kind = del and add and "change" or (del and "del" or "add"),
          in_diff_context = true,
        })
      end
    else
      table.insert(rows, {
        old_line = line_data.old_line,
        new_line = line_data.new_line,
        old_content = line_data.content,
        new_content = line_data.content,
        kind = "context",
        in_diff_context = true,
      })
      idx = idx + 1
    end
  end
  return rows
end

local function append_unchanged_rows(rows, path, old_lines, new_lines, old_idx, new_idx, old_stop, new_stop)
  while old_idx < old_stop or new_idx < new_stop do
    local old_line = old_idx < old_stop and old_idx or nil
    local new_line = new_idx < new_stop and new_idx or nil
    table.insert(rows, {
      path = path,
      old_line = old_line,
      new_line = new_line,
      old_content = old_line and old_lines[old_line] or "",
      new_content = new_line and new_lines[new_line] or "",
      kind = "context",
      in_diff_context = false,
    })
    if old_line then old_idx = old_idx + 1 end
    if new_line then new_idx = new_idx + 1 end
  end
  return old_idx, new_idx
end

local function build_split_rows(opts)
  local path = opts.path
  local old_lines = opts.old_lines or {}
  local new_lines = opts.new_lines or {}
  local rows = {}

  local hunks = M.parse_patch(opts.patch)
  if #hunks == 0 then
    local max_lines = math.max(#old_lines, #new_lines)
    for idx = 1, max_lines do
      table.insert(rows, {
        path = path,
        old_line = old_lines[idx] ~= nil and idx or nil,
        new_line = new_lines[idx] ~= nil and idx or nil,
        old_content = old_lines[idx] or "",
        new_content = new_lines[idx] or "",
        kind = "context",
        in_diff_context = false,
      })
    end
    return rows
  end

  local old_idx = 1
  local new_idx = 1
  for _, hunk in ipairs(hunks) do
    local old_stop = math.max(1, hunk.old_start or 1)
    local new_stop = math.max(1, hunk.new_start or 1)
    old_idx, new_idx = append_unchanged_rows(rows, path, old_lines, new_lines, old_idx, new_idx, old_stop, new_stop)

    local max_old_line = nil
    local max_new_line = nil
    for _, row in ipairs(build_hunk_rows(hunk)) do
      row.path = path
      row.old_content = line_or_hunk_content(old_lines, row.old_line, row.old_content)
      row.new_content = line_or_hunk_content(new_lines, row.new_line, row.new_content)
      table.insert(rows, row)
      if row.old_line then
        max_old_line = math.max(max_old_line or row.old_line, row.old_line)
      end
      if row.new_line then
        max_new_line = math.max(max_new_line or row.new_line, row.new_line)
      end
    end
    if max_old_line then
      old_idx = math.max(old_idx, max_old_line + 1)
    end
    if max_new_line then
      new_idx = math.max(new_idx, max_new_line + 1)
    end
  end

  append_unchanged_rows(rows, path, old_lines, new_lines, old_idx, new_idx, #old_lines + 1, #new_lines + 1)
  return rows
end

local function split_to_display_width(text, width)
  width = math.max(1, width)
  text = text or ""
  if text == "" then
    return { "" }
  end
  local chunks = {}
  local current = ""
  local current_width = 0
  local char_count = vim.fn.strchars(text)
  for idx = 0, char_count - 1 do
    local char = vim.fn.strcharpart(text, idx, 1)
    local char_width = math.max(1, vim.fn.strdisplaywidth(char))
    if current ~= "" and current_width + char_width > width then
      table.insert(chunks, current)
      current = char
      current_width = char_width
    else
      current = current .. char
      current_width = current_width + char_width
    end
  end
  table.insert(chunks, current)
  return chunks
end

local function pad_to_display_width(text, width)
  local result = text or ""
  local display_width = vim.fn.strdisplaywidth(result)
  if display_width >= width then
    return result
  end
  return result .. string.rep(" ", width - display_width)
end

local function format_side(line_num, chunk, line_num_width, content_width)
  local label = line_num and tostring(line_num) or ""
  label = string.rep(" ", math.max(0, line_num_width - #label)) .. label
  return label .. " " .. pad_to_display_width(chunk or "", content_width)
end

local function split_layout(width, max_line)
  width = math.max(20, width or vim.o.columns or 80)
  local line_num_width = math.max(1, #tostring(math.max(1, max_line or 1)))
  local separator_width = #SPLIT_SEPARATOR
  local side_width = math.max(line_num_width + 2, math.floor((width - separator_width) / 2))
  local content_width = math.max(1, side_width - line_num_width - 1)
  return {
    line_num_width = line_num_width,
    side_width = side_width,
    content_width = content_width,
    separator_col = side_width,
    left_range = {
      start_col = 0,
      end_col = side_width - 1,
      content_start_col = line_num_width + 1,
      content_end_col = side_width - 1,
    },
    right_range = {
      start_col = side_width + separator_width,
      end_col = side_width + separator_width + side_width - 1,
      content_start_col = side_width + separator_width + line_num_width + 1,
      content_end_col = side_width + separator_width + side_width - 1,
    },
  }
end

local function syntax_status(opts, rendered_row_count)
  if rendered_row_count > M.MAX_SYNTAX_ROWS then
    return false, "row cap", nil
  end
  if string_byte_count(opts.old_lines) > M.MAX_SYNTAX_SIDE_BYTES
      or string_byte_count(opts.new_lines) > M.MAX_SYNTAX_SIDE_BYTES
  then
    return false, "byte cap", nil
  end

  local ft = vim.filetype.match({ filename = opts.path })
  if not ft then
    return false, "no filetype", nil
  end
  local ok, lang = pcall(vim.treesitter.language.get_lang, ft)
  if not ok or not lang then
    return false, "no parser", nil
  end
  return true, nil, lang
end

local function syntax_query_for(lang)
  if not vim.treesitter or not vim.treesitter.query then
    return nil
  end
  local ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
  if ok then
    return query
  end
  return nil
end

local function collect_syntax_highlights_for_side(lang, source_lines, line_map, content_start_col, content_width)
  local query = syntax_query_for(lang)
  if not query then
    return nil
  end

  local temp_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(temp_buf, 0, -1, false, source_lines or {})
  local ok_parser, parser = pcall(vim.treesitter.get_parser, temp_buf, lang)
  if not ok_parser or not parser then
    pcall(vim.api.nvim_buf_delete, temp_buf, { force = true })
    return nil
  end

  local ok_parse, trees = pcall(parser.parse, parser)
  if not ok_parse or not trees then
    pcall(vim.api.nvim_buf_delete, temp_buf, { force = true })
    return nil
  end

  local highlights = {}
  for _, tree in ipairs(trees) do
    local root = tree:root()
    for capture_id, node in query:iter_captures(root, temp_buf, 0, -1) do
      local capture = query.captures[capture_id]
      local start_row, start_col, end_row, end_col = node:range()
      if start_row == end_row then
        local rendered_line = line_map[start_row + 1]
        if rendered_line and start_col < content_width then
          table.insert(highlights, {
            line = rendered_line,
            start_col = content_start_col + start_col,
            end_col = content_start_col + math.min(end_col, content_width),
            hl = "@" .. capture,
          })
        end
      end
    end
  end

  pcall(vim.api.nvim_buf_delete, temp_buf, { force = true })
  return highlights
end

local function collect_syntax_highlights(lang, rendered, old_lines, new_lines)
  local left_map = {}
  local right_map = {}
  for row_idx, row in ipairs(rendered.rows or {}) do
    if row.old_line and not row.left_continuation then
      left_map[row.old_line] = row_idx - 1
    end
    if row.new_line and not row.right_continuation then
      right_map[row.new_line] = row_idx - 1
    end
  end

  local highlights = {}
  local left_highlights = collect_syntax_highlights_for_side(
    lang,
    old_lines,
    left_map,
    rendered.left_range.content_start_col,
    rendered.content_width
  )
  if not left_highlights then
    return nil
  end
  local right_highlights = collect_syntax_highlights_for_side(
    lang,
    new_lines,
    right_map,
    rendered.right_range.content_start_col,
    rendered.content_width
  )
  if not right_highlights then
    return nil
  end

  for _, hl in ipairs(left_highlights) do
    table.insert(highlights, hl)
  end
  for _, hl in ipairs(right_highlights) do
    table.insert(highlights, hl)
  end
  return highlights
end

local function line_highlight(kind)
  if kind == "add" then
    return "RaccoonAdd"
  elseif kind == "del" then
    return "RaccoonDelete"
  elseif kind == "change" then
    return "RaccoonChange"
  end
  return nil
end

--- Render a changed file as a read-only full-file split diff.
---@param opts table {path, previous_path?, status?, old_lines?, new_lines?, patch?, width?, binary?}
---@return table rendered {lines, rows, highlights, separator_col, left_range, right_range}
function M.render_split_file(opts)
  opts = opts or {}
  local path = opts.path or opts.filename or ""
  local old_lines = opts.old_lines or {}
  local new_lines = opts.new_lines or {}
  local max_line = math.max(#old_lines, #new_lines)
  local layout = split_layout(opts.width, max_line)
  local lines = {}
  local rows = {}
  local highlights = {}

  local function append_rendered_row(row)
    local left_chunks = split_to_display_width(row.old_content or "", layout.content_width)
    local right_chunks = split_to_display_width(row.new_content or "", layout.content_width)
    local chunk_count = math.max(#left_chunks, #right_chunks)
    local first_line = #lines + 1
    for chunk_idx = 1, chunk_count do
      local left_num = chunk_idx == 1 and row.old_line or nil
      local right_num = chunk_idx == 1 and row.new_line or nil
      local left_side = format_side(
        left_num,
        left_chunks[chunk_idx] or "",
        layout.line_num_width,
        layout.content_width
      )
      local right_side = format_side(
        right_num,
        right_chunks[chunk_idx] or "",
        layout.line_num_width,
        layout.content_width
      )
      table.insert(lines, left_side .. SPLIT_SEPARATOR .. right_side)
      local rendered_row = {
        path = row.path or path,
        old_line = row.old_line,
        new_line = row.new_line,
        kind = row.kind,
        in_diff_context = row.in_diff_context == true,
        left_continuation = chunk_idx > 1 and row.old_line ~= nil,
        right_continuation = chunk_idx > 1 and row.new_line ~= nil,
        hunk = row.hunk,
      }
      table.insert(rows, rendered_row)
      local hl = line_highlight(row.kind)
      if hl then
        table.insert(highlights, { line = #lines - 1, line_hl_group = hl })
      end
    end

    if row.kind == "change" and first_line == #lines then
      local old_span, new_span = changed_span(row.old_content or "", row.new_content or "")
      if old_span then
        table.insert(highlights, {
          line = first_line - 1,
          start_col = layout.left_range.content_start_col + old_span.start_col,
          end_col = layout.left_range.content_start_col + old_span.end_col,
          hl = "RaccoonInlineDelete",
        })
      end
      if new_span then
        table.insert(highlights, {
          line = first_line - 1,
          start_col = layout.right_range.content_start_col + new_span.start_col,
          end_col = layout.right_range.content_start_col + new_span.end_col,
          hl = "RaccoonInlineAdd",
        })
      end
    end
  end

  if opts.binary or opts.unreadable then
    append_rendered_row({
      path = path,
      old_content = "Binary or unreadable file",
      new_content = "Binary or unreadable file",
      kind = "file",
      in_diff_context = false,
    })
  else
    if opts.status == "renamed" and opts.previous_path and opts.previous_path ~= path then
      append_rendered_row({
        path = path,
        old_content = "renamed from " .. opts.previous_path,
        new_content = "renamed to " .. path,
        kind = "file",
        in_diff_context = false,
      })
    end
    for _, row in ipairs(build_split_rows({
      path = path,
      old_lines = old_lines,
      new_lines = new_lines,
      patch = opts.patch,
    })) do
      append_rendered_row(row)
    end
  end

  local syntax_enabled, syntax_skip_reason, syntax_lang = syntax_status({
    path = path,
    old_lines = old_lines,
    new_lines = new_lines,
  }, #rows)

  local rendered = {
    lines = lines,
    rows = rows,
    highlights = highlights,
    separator_col = layout.separator_col,
    left_range = layout.left_range,
    right_range = layout.right_range,
    side_width = layout.side_width,
    content_width = layout.content_width,
    syntax_enabled = syntax_enabled,
    syntax_skip_reason = syntax_skip_reason,
  }
  if syntax_enabled then
    local syntax_highlights = collect_syntax_highlights(syntax_lang, rendered, old_lines, new_lines)
    if syntax_highlights then
      for _, hl in ipairs(syntax_highlights) do
        table.insert(rendered.highlights, hl)
      end
    else
      rendered.syntax_enabled = false
      rendered.syntax_skip_reason = "no parser"
    end
  end
  return rendered
end

--- Attach split diff metadata to a buffer.
---@param buf number
---@param rendered table
function M.attach_split_metadata(buf, rendered)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  split_metadata_by_buf[buf] = rendered
  vim.b[buf].raccoon_split_diff = true
end

--- Return split diff metadata for a buffer.
---@param buf number
---@return table|nil
function M.get_split_metadata(buf)
  return split_metadata_by_buf[buf]
end

--- Resolve a buffer row/column into a GitHub review target.
---@param buf number
---@param row number 1-based row
---@param col number 0-based column
---@return table|nil target {path, line, side, in_diff_context, row}
function M.resolve_cursor_target(buf, row, col)
  local rendered = M.get_split_metadata(buf)
  if not rendered then
    return nil
  end
  local meta = rendered.rows and rendered.rows[row]
  if not meta then
    return nil
  end

  local side = "RIGHT"
  if col >= rendered.left_range.start_col and col <= rendered.left_range.end_col then
    side = "LEFT"
  elseif col >= rendered.right_range.start_col and col <= rendered.right_range.end_col then
    side = "RIGHT"
  end

  local line = side == "LEFT" and meta.old_line or meta.new_line
  if not line and side == "LEFT" and meta.new_line then
    side = "RIGHT"
    line = meta.new_line
  elseif not line and side == "RIGHT" and meta.old_line then
    side = "LEFT"
    line = meta.old_line
  end

  return {
    path = meta.path,
    line = line,
    side = side,
    in_diff_context = meta.in_diff_context == true,
    kind = meta.kind,
    row = row,
  }
end

--- Apply rendered split diff content and highlights to a buffer.
---@param buf number
---@param rendered table
function M.apply_split_render(buf, rendered)
  if not buf or not vim.api.nvim_buf_is_valid(buf) or not rendered then
    return
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, rendered.lines or {})
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  for _, hl in ipairs(rendered.highlights or {}) do
    if hl.line_hl_group then
      pcall(vim.api.nvim_buf_set_extmark, buf, ns_id, hl.line, 0, {
        line_hl_group = hl.line_hl_group,
      })
    elseif hl.start_col and hl.end_col and hl.end_col > hl.start_col then
      pcall(vim.api.nvim_buf_add_highlight, buf, ns_id, hl.hl, hl.line, hl.start_col, hl.end_col)
    end
  end
  M.attach_split_metadata(buf, rendered)
end

local function replace_range(lines, start_idx, count, replacement)
  local result = {}
  start_idx = math.max(1, start_idx)
  for idx = 1, start_idx - 1 do
    table.insert(result, lines[idx])
  end
  for _, line in ipairs(replacement or {}) do
    table.insert(result, line)
  end
  for idx = start_idx + count, #lines do
    table.insert(result, lines[idx])
  end
  return result
end

--- Reconstruct old-side content from new-side content and a patch.
---@param new_lines string[]
---@param patch string|nil
---@return string[]
function M.derive_old_lines_from_patch(new_lines, patch)
  local old_lines = vim.deepcopy(new_lines or {})
  local hunks = M.parse_patch(patch)
  for hunk_idx = #hunks, 1, -1 do
    local hunk = hunks[hunk_idx]
    local replacement = {}
    for _, line_data in ipairs(hunk.lines) do
      if line_data.type == "ctx" or line_data.type == "del" then
        table.insert(replacement, line_data.content or "")
      end
    end
    local start_idx = math.max(1, hunk.new_start or 1)
    old_lines = replace_range(old_lines, start_idx, hunk.new_count or 0, replacement)
  end
  return old_lines
end

local function read_worktree_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  return lines
end

local function resolve_active_target(buf)
  local win = vim.fn.bufwinid(buf)
  if win == -1 then
    return nil
  end
  local cursor = vim.api.nvim_win_get_cursor(win)
  return M.resolve_cursor_target(buf, cursor[1], cursor[2])
end

--- Resolve a semantic split target to its rendered row and side content column.
---@param rendered table|nil rendered split metadata
---@param target table|nil {path:string, line:number, side:string}
---@return number|nil row 1-based rendered row
---@return number|nil col 0-based side content column
function M.find_split_row(rendered, target)
  if not rendered or not target then
    return nil
  end
  local side = target.side == "LEFT" and "LEFT" or "RIGHT"
  for idx, row in ipairs(rendered.rows or {}) do
    if row.path == target.path then
      if side == "LEFT" and row.old_line == target.line and not row.left_continuation then
        return idx, rendered.left_range and rendered.left_range.content_start_col or 0
      end
      if side == "RIGHT" and row.new_line == target.line and not row.right_continuation then
        return idx, rendered.right_range and rendered.right_range.content_start_col or 0
      end
    end
  end
  return nil
end

local function restore_target_cursor(buf, rendered, target)
  local win = vim.fn.bufwinid(buf)
  if win == -1 or not target then
    return
  end
  local row, col = M.find_split_row(rendered, target)
  if not row then
    return
  end
  pcall(vim.api.nvim_win_set_cursor, win, { row, col })
end

local function render_split_to_buffer(buf, file, old_lines, new_lines, binary)
  local target = resolve_active_target(buf)
  local win = vim.fn.bufwinid(buf)
  local width = win ~= -1 and vim.api.nvim_win_get_width(win) or vim.o.columns
  local rendered = M.render_split_file({
    path = file.filename,
    previous_path = file.previous_filename,
    status = file.status,
    old_lines = old_lines,
    new_lines = new_lines,
    patch = file.patch,
    binary = binary,
    width = width,
  })
  M.apply_split_render(buf, rendered)
  restore_target_cursor(buf, rendered, target)
  return rendered
end

local function setup_split_resize(buf, file, source)
  local group = vim.api.nvim_create_augroup("RaccoonSplitDiff" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      if not vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_del_augroup_by_id, group)
        return
      end
      render_split_to_buffer(buf, file, source.old_lines, source.new_lines, source.binary)
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      split_metadata_by_buf[buf] = nil
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
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

  local new_lines = read_worktree_file(file_path)
  local binary = false
  if not new_lines then
    if file.status == "removed" then
      new_lines = {}
    else
      binary = true
      new_lines = {}
    end
  end

  local old_lines = M.derive_old_lines_from_patch(new_lines, file.patch)
  if file.status == "added" then
    old_lines = {}
  elseif file.status == "removed" and #old_lines == 0 then
    old_lines = M.derive_old_lines_from_patch({}, file.patch)
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, file_path)
  vim.api.nvim_set_current_buf(buf)
  vim.bo[buf].modifiable = false
  local ft = vim.filetype.match({ filename = file.filename })
  if ft then
    vim.bo[buf].filetype = ft
  end
  vim.wo.wrap = false
  vim.wo.number = false
  vim.wo.relativenumber = false
  vim.wo.signcolumn = "yes:2"

  -- Track buffer in session
  state.add_buffer(buf)

  local source = {
    old_lines = old_lines,
    new_lines = new_lines,
    binary = binary,
  }
  render_split_to_buffer(buf, file, source.old_lines, source.new_lines, source.binary)
  setup_split_resize(buf, file, source)

  local pr = state.get_pr()
  local base_ref = pr and pr.base and pr.base.ref
  if base_ref then
    local git = require("raccoon.git")
    git.merge_base(clone_path, "HEAD", "origin/" .. base_ref, function(merge_base, merge_err)
      if merge_err or not merge_base then
        return
      end
      local old_path = file.previous_filename or file.filename
      git.show_file_content(clone_path, merge_base, old_path, function(base_lines, _base_err)
        if not vim.api.nvim_buf_is_valid(buf) or not base_lines then
          return
        end
        source.old_lines = base_lines
        source.binary = false
        render_split_to_buffer(buf, file, source.old_lines, source.new_lines, source.binary)
        local ok_comments, comments = pcall(require, "raccoon.comments")
        if ok_comments then
          comments.show_comments(buf, state.get_comments(file.filename))
        end
      end)
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

local function get_current_split_change_rows()
  local rendered = M.get_split_metadata(vim.api.nvim_get_current_buf())
  if not rendered then
    return nil
  end
  local rows = {}
  for idx, row in ipairs(rendered.rows or {}) do
    local is_change = row.kind == "add" or row.kind == "del" or row.kind == "change"
    local is_continuation = row.left_continuation or row.right_continuation
    if is_change and not is_continuation then
      local previous = rows[#rows]
      if not previous or idx > previous + 1 then
        table.insert(rows, idx)
      end
    end
  end
  return rows
end

--- Navigate to the next diff hunk in the current file
---@return boolean success
function M.next_diff()
  if not state.is_active() then
    vim.notify("No active PR session", vim.log.levels.WARN)
    return false
  end

  local split_rows = get_current_split_change_rows()
  if split_rows then
    if #split_rows == 0 then
      vim.notify("No changes in this file", vim.log.levels.INFO)
      return false
    end
    local current_line = vim.fn.line(".")
    for _, line in ipairs(split_rows) do
      if line > current_line then
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        vim.cmd("normal! zz")
        return true
      end
    end
    vim.notify("No more changes below", vim.log.levels.INFO)
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

  local split_rows = get_current_split_change_rows()
  if split_rows then
    if #split_rows == 0 then
      vim.notify("No changes in this file", vim.log.levels.INFO)
      return false
    end
    local current_line = vim.fn.line(".")
    for i = #split_rows, 1, -1 do
      local line = split_rows[i]
      if line < current_line then
        vim.api.nvim_win_set_cursor(0, { line, 0 })
        vim.cmd("normal! zz")
        return true
      end
    end
    vim.notify("No more changes above", vim.log.levels.INFO)
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
