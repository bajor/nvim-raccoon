---@class RaccoonCommentMetadata
---Helpers for normalizing GitHub file-level review comments.
local M = {}

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

  local _, clean_body = M.decode_file_line_anchor(comment.body)
  comment.body = clean_body
  comment.position = nil
  local file_line = comment.line
  if type(file_line) ~= "number" or file_line < 1 then
    file_line = comment.original_line
  end
  if type(file_line) ~= "number" or file_line < 1 then
    file_line = 1
  end
  comment.line = file_line
  comment.original_line = file_line
end

return M
