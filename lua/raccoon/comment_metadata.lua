---@class RaccoonCommentMetadata
---Helpers for preserving selected file lines when GitHub falls back to file-level review comments.
local M = {}

local FILE_LINE_PREFIX = "<!-- raccoon:file-line "
local FILE_LINE_SUFFIX = " -->"

---@param line number
---@param body string
---@return string
function M.encode_file_line_anchor(line, body)
  local normalized_body = body or ""
  return string.format("%s%d%s\n%s", FILE_LINE_PREFIX, line, FILE_LINE_SUFFIX, normalized_body)
end

---@param body string|nil
---@return number|nil
---@return string
function M.decode_file_line_anchor(body)
  local text = body or ""
  local prefix_pattern = "^<!%-%- raccoon:file%-line (%d+) %-%->(.*)$"
  local line_str, remainder = text:match(prefix_pattern)
  if not line_str then
    return nil, text
  end

  if remainder:sub(1, 2) == "\r\n" then
    remainder = remainder:sub(3)
  elseif remainder:sub(1, 1) == "\n" or remainder:sub(1, 1) == "\r" then
    remainder = remainder:sub(2)
  end

  return tonumber(line_str), remainder
end

---@param comment table
function M.normalize_file_level_comment(comment)
  if type(comment) ~= "table" or comment.subject_type ~= "file" then
    return
  end

  local anchored_line, clean_body = M.decode_file_line_anchor(comment.body)
  comment.body = clean_body
  comment.position = nil

  if anchored_line then
    comment.line = anchored_line
    comment.original_line = anchored_line
    return
  end

  comment.line = nil
  comment.original_line = nil
end

return M
