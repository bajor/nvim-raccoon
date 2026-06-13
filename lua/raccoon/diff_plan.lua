---@class RaccoonDiffPlan
local M = {}

local algo = require("raccoon.diff_algorithm")

local function copy_line(line, buf_row)
  local kind = line.kind or line.type
  return {
    kind = kind,
    type = kind,
    content = line.content or "",
    old_line = line.old_line,
    new_line = line.new_line,
    anchor_line = line.anchor_line,
    line_num = line.line_num,
    buf_row = buf_row,
  }
end

local function whole_old_chunks(line)
  local content = line and line.content or ""
  if content == "" then
    return {}
  end
  return { { text = content, kind = "del" } }
end

local function whole_new_ranges(line)
  local content = line and line.content or ""
  if content == "" then
    return {}
  end
  return { { start_col = 0, end_col = #content } }
end

local function new_only_row(line, exact, mode)
  return {
    old_line = nil,
    new_line = line,
    old_chunks = {},
    new_ranges = mode == "exact" and whole_new_ranges(line) or {},
    exact = exact,
  }
end

local function old_only_row(line, exact)
  return {
    old_line = line,
    new_line = nil,
    old_chunks = whole_old_chunks(line),
    new_ranges = {},
    exact = exact,
  }
end

local function paired_row(old_line, new_line)
  local inline = algo.diff_inline(old_line.content, new_line.content)
  return {
    old_line = old_line,
    new_line = new_line,
    old_chunks = inline.old_chunks,
    new_ranges = inline.new_ranges,
    exact = inline.exact,
  }
end

local function line_mode_rows(block)
  local rows = {}
  for _, line in ipairs(block) do
    if line.kind == "del" then
      table.insert(rows, old_only_row(line, false))
    elseif line.kind == "add" then
      table.insert(rows, new_only_row(line, false, "line"))
    end
  end
  return rows
end

local function exact_rows(block)
  local old_block = {}
  local new_block = {}
  local old_lines = {}
  local new_lines = {}

  for _, line in ipairs(block) do
    if line.kind == "del" then
      table.insert(old_block, line)
      table.insert(old_lines, line.content)
    elseif line.kind == "add" then
      table.insert(new_block, line)
      table.insert(new_lines, line.content)
    end
  end

  local rows = {}
  for _, pair in ipairs(algo.pair_lines(old_lines, new_lines)) do
    local old_line = pair.old_index and old_block[pair.old_index] or nil
    local new_line = pair.new_index and new_block[pair.new_index] or nil

    if old_line and new_line then
      table.insert(rows, paired_row(old_line, new_line))
    elseif old_line then
      table.insert(rows, old_only_row(old_line, true))
    elseif new_line then
      table.insert(rows, new_only_row(new_line, true, "exact"))
    end
  end

  return rows
end

local function append_rows(target, rows)
  for _, row in ipairs(rows) do
    table.insert(target, row)
  end
end

local function flush_block(render, block)
  if #block == 0 then
    return
  end

  if render.mode == "line" then
    append_rows(render.rows, line_mode_rows(block))
  else
    append_rows(render.rows, exact_rows(block))
  end
end

local function mode_from_opts(opts)
  opts = opts or {}
  return opts.mode == "line" and "line" or "exact"
end

---Build a render plan from parsed patch hunks.
---@param hunks table[]
---@param opts? table
---@return table
function M.from_hunks(hunks, opts)
  local render = { mode = mode_from_opts(opts), rows = {} }

  for _, hunk in ipairs(hunks or {}) do
    local block = {}
    for _, line in ipairs(hunk.lines or {}) do
      local normalized = copy_line(line)
      if normalized.kind == "add" or normalized.kind == "del" then
        table.insert(block, normalized)
      else
        flush_block(render, block)
        block = {}
      end
    end
    flush_block(render, block)
  end

  return render
end

---Build a render plan from commit/local buffer line entries.
---@param line_list table[]
---@param opts? table
---@return table
function M.from_line_list(line_list, opts)
  local render = { mode = mode_from_opts(opts), rows = {} }
  local block = {}

  for idx, line in ipairs(line_list or {}) do
    local normalized = copy_line(line, idx - 1)
    if normalized.kind == "add" or normalized.kind == "del" then
      table.insert(block, normalized)
    else
      flush_block(render, block)
      block = {}
    end
  end
  flush_block(render, block)

  return render
end

return M
