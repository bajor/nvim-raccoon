---@class RaccoonThreadIndex
---Exact review-thread indexing for the current PR session.
local M = {}

local state = require("raccoon.state")

local function is_real_number(val)
  return type(val) == "number" and val > 0
end

--- Get a valid line number from a comment, handling vim.NIL from JSON null.
---@param comment table
---@return number|nil
function M.get_comment_line(comment)
  for _, field in ipairs({ "line", "original_line", "position" }) do
    local value = comment[field]
    if is_real_number(value) then
      return value
    end
  end
  return nil
end

---@param comment table
---@return boolean
function M.is_issue_comment(comment)
  return comment.issue_comment == true or comment.is_issue_comment == true
end

local function normalize_nil(value)
  if value == vim.NIL then
    return nil
  end
  return value
end

local function compare_iso(a, b)
  local left = a or ""
  local right = b or ""
  if left ~= right then
    return left < right
  end
  return false
end

local function sort_comments_oldest_first(comments)
  table.sort(comments, function(left, right)
    local left_ts = normalize_nil(left.created_at) or normalize_nil(left.submitted_at)
    local right_ts = normalize_nil(right.created_at) or normalize_nil(right.submitted_at)
    if left_ts ~= right_ts then
      return compare_iso(left_ts, right_ts)
    end
    return (left.id or 0) < (right.id or 0)
  end)
end

local function sort_reviews_oldest_first(reviews)
  table.sort(reviews, function(left, right)
    local left_ts = normalize_nil(left.submitted_at) or normalize_nil(left.created_at)
    local right_ts = normalize_nil(right.submitted_at) or normalize_nil(right.created_at)
    if left_ts ~= right_ts then
      return compare_iso(left_ts, right_ts)
    end
    return (left.id or 0) < (right.id or 0)
  end)
end

local function line_sort_value(thread)
  if is_real_number(thread.line) then
    return thread.line
  end
  return math.huge
end

local function compare_threads_flat(left, right)
  if left.file_index ~= right.file_index then
    return left.file_index < right.file_index
  end
  local left_line = line_sort_value(left)
  local right_line = line_sort_value(right)
  if left_line ~= right_line then
    return left_line < right_line
  end
  return left.order < right.order
end

local function compare_threads_for_history(left, right)
  if left.file_index ~= right.file_index then
    return left.file_index < right.file_index
  end
  local left_line = line_sort_value(left)
  local right_line = line_sort_value(right)
  if left_line ~= right_line then
    return left_line < right_line
  end
  if left.resolved ~= right.resolved then
    return left.resolved == false
  end
  return left.order < right.order
end

local function ensure_line_bucket(path_map, path, line)
  local line_map = path_map[path]
  if not line_map then
    line_map = {}
    path_map[path] = line_map
  end
  local bucket = line_map[line]
  if not bucket then
    bucket = {
      threads = {},
      issue_comments = {},
      counts = { nr = 0, u = 0, i = 0 },
    }
    line_map[line] = bucket
  end
  return bucket
end

--- Build an exact review-thread index for the current session.
--- Returns nil + error if any real review comment cannot be mapped to a thread.
---@return table|nil index, string|nil err
function M.build()
  local files = state.get_files()
  local viewer_login = state.get_viewer_login()
  local file_index_by_path = {}
  for idx, file in ipairs(files) do
    file_index_by_path[file.filename] = idx
  end

  local thread_by_id = {}
  local review_comments = {}
  local issue_entries = {}
  local thread_order = 0

  for path, comments in pairs(state.session.comments or {}) do
    if path ~= "_reviews" then
      for _, comment in ipairs(comments) do
        if M.is_issue_comment(comment) then
          local line = M.get_comment_line(comment)
          if line then
            table.insert(issue_entries, {
              path = path,
              line = line,
              comment = comment,
              file_index = file_index_by_path[path] or math.huge,
            })
          end
        else
          if type(comment.thread_id) ~= "string" or comment.thread_id == "" then
            local comment_id = tostring(comment.id or "?")
            return nil, "missing thread id on review comment " .. comment_id
          end

          table.insert(review_comments, comment)

          local thread = thread_by_id[comment.thread_id]
          if not thread then
            thread_order = thread_order + 1
            thread = {
              thread_id = comment.thread_id,
              comments = {},
              order = thread_order,
              path = path,
              file_index = file_index_by_path[path] or math.huge,
              line = M.get_comment_line(comment),
              resolved = comment.resolved == true,
              root_comment_id = nil,
              is_file_level = comment.subject_type == "file",
            }
            thread_by_id[comment.thread_id] = thread
          end

          table.insert(thread.comments, comment)
          if thread.path == nil and path ~= nil then
            thread.path = path
            thread.file_index = file_index_by_path[path] or math.huge
          end

          local line = M.get_comment_line(comment)
          if thread.line == nil and line ~= nil then
            thread.line = line
          end

          if comment.resolved ~= nil then
            thread.resolved = comment.resolved == true
          end

          if comment.subject_type == "file" then
            thread.is_file_level = true
          end

          if normalize_nil(comment.in_reply_to_id) == nil and is_real_number(comment.id) then
            thread.root_comment_id = comment.id
          end
        end
      end
    end
  end

  local threads = {}
  for _, thread in pairs(thread_by_id) do
    sort_comments_oldest_first(thread.comments)
    thread.comment_count = #thread.comments
    thread.latest_comment = thread.comments[#thread.comments]
    thread.latest_author = thread.latest_comment
      and thread.latest_comment.user
      and thread.latest_comment.user.login
      or "unknown"
    thread.preview = thread.latest_comment and (thread.latest_comment.body or "") or ""
    thread.preview = thread.preview:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    thread.preview = thread.preview:sub(1, 80)
    if thread.is_file_level then
      thread.line_label = "FILE"
    elseif is_real_number(thread.line) then
      thread.line_label = "L" .. thread.line
    else
      thread.line_label = "L?"
    end
    thread.has_my_comment = false
    if viewer_login then
      for _, comment in ipairs(thread.comments) do
        local author = comment.user and comment.user.login
        if author == viewer_login then
          thread.has_my_comment = true
          break
        end
      end
    end
    thread.needs_reply = thread.resolved ~= true
      and viewer_login ~= nil
      and thread.has_my_comment
      and thread.latest_author ~= viewer_login

    if thread.resolved ~= true and not is_real_number(thread.root_comment_id) then
      return nil, "missing root review comment for thread " .. tostring(thread.thread_id)
    end

    table.insert(threads, thread)
  end

  table.sort(threads, compare_threads_flat)

  local unresolved_threads = {}
  local history_threads = {}
  local line_state_by_file = {}
  local comment_line_state_by_file = {}

  for _, thread in ipairs(threads) do
    table.insert(history_threads, thread)
    if is_real_number(thread.line) and thread.path then
      local bucket = ensure_line_bucket(comment_line_state_by_file, thread.path, thread.line)
      table.insert(bucket.threads, thread)
      if thread.resolved ~= true then
        if thread.needs_reply then
          bucket.counts.nr = bucket.counts.nr + 1
        else
          bucket.counts.u = bucket.counts.u + 1
        end
      end
    end
    if thread.resolved ~= true then
      table.insert(unresolved_threads, thread)
      if is_real_number(thread.line) and thread.path then
        local bucket = ensure_line_bucket(line_state_by_file, thread.path, thread.line)
        table.insert(bucket.threads, thread)
        if thread.needs_reply then
          bucket.counts.nr = bucket.counts.nr + 1
        else
          bucket.counts.u = bucket.counts.u + 1
        end
      end
    end
  end

  for _, entry in ipairs(issue_entries) do
    local bucket = ensure_line_bucket(line_state_by_file, entry.path, entry.line)
    table.insert(bucket.issue_comments, entry.comment)
    bucket.counts.i = bucket.counts.i + 1

    local comment_bucket = ensure_line_bucket(comment_line_state_by_file, entry.path, entry.line)
    table.insert(comment_bucket.issue_comments, entry.comment)
    comment_bucket.counts.i = comment_bucket.counts.i + 1
  end

  table.sort(history_threads, compare_threads_for_history)
  sort_reviews_oldest_first(state.get_comments("_reviews"))

  return {
    threads = threads,
    unresolved_threads = unresolved_threads,
    history_threads = history_threads,
    thread_by_id = thread_by_id,
    line_state_by_file = line_state_by_file,
    comment_line_state_by_file = comment_line_state_by_file,
    issue_entries = issue_entries,
    review_comments = review_comments,
    review_bodies = state.get_comments("_reviews"),
    file_index_by_path = file_index_by_path,
    viewer_login = viewer_login,
  }, nil
end

---@param index table
---@param path string
---@param line number
---@return table|nil
function M.get_line_state(index, path, line)
  local file_map = index.line_state_by_file[path]
  if not file_map then
    return nil
  end
  return file_map[line]
end

---@param index table
---@param path string
---@param line number
---@return table|nil
function M.get_comment_line_state(index, path, line)
  local file_map = index.comment_line_state_by_file[path]
  if not file_map then
    return nil
  end
  return file_map[line]
end

return M
