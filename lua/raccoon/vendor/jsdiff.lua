-- Mechanically adapted from jsdiff 9.0.0 (tag v9.0.0, commit
-- ed13aca03aa25735fafc0645d1185e7a1c68fd8c).
--
-- Copyright (c) 2009-2015, Kevin Decker <kpdecker@gmail.com>
-- SPDX-License-Identifier: BSD-3-Clause
--
-- Modified for nvim-raccoon on 2026-07-16: translated the synchronous,
-- case-sensitive Myers core and the character/words-with-space tokenizers to
-- Lua; removed async callbacks and options unused by Pierre's inline renderer;
-- retained upstream max-edit-length fallback and added a caller-supplied
-- token-product safety limit. See vendor/README.md.

local M = {}

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

  local second = text:byte(byte_index + 1)
  if first == 0xE0 and second < 0xA0 then return 1 end
  if first == 0xED and second > 0x9F then return 1 end
  if first == 0xF0 and second < 0x90 then return 1 end
  if first == 0xF4 and second > 0x8F then return 1 end
  return width
end

local function code_point(text, byte_index, width)
  local first = text:byte(byte_index)
  if width == 1 then return first end

  local second = text:byte(byte_index + 1)
  if width == 2 then return (first - 0xC0) * 0x40 + second - 0x80 end

  local third = text:byte(byte_index + 2)
  if width == 3 then
    return (first - 0xE0) * 0x1000 + (second - 0x80) * 0x40 + third - 0x80
  end

  local fourth = text:byte(byte_index + 3)
  return (first - 0xF0) * 0x40000
    + (second - 0x80) * 0x1000
    + (third - 0x80) * 0x40
    + fourth - 0x80
end

local function next_code_point(text, byte_index)
  local width = utf8_width(text, byte_index)
  return code_point(text, byte_index, width), width
end

local function tokenize_characters(value)
  local tokens = {}
  local byte_index = 1
  while byte_index <= #value do
    local _, width = next_code_point(value, byte_index)
    table.insert(tokens, value:sub(byte_index, byte_index + width - 1))
    byte_index = byte_index + width
  end
  return tokens
end

local function is_extended_word(code)
  return code == 0x5F
    or (code >= 0x30 and code <= 0x39)
    or (code >= 0x41 and code <= 0x5A)
    or (code >= 0x61 and code <= 0x7A)
    or code == 0xAD
    or (code >= 0xC0 and code <= 0xD6)
    or (code >= 0xD8 and code <= 0xF6)
    or (code >= 0xF8 and code <= 0x2C6)
    or (code >= 0x2C8 and code <= 0x2D7)
    or (code >= 0x2DE and code <= 0x2FF)
    or (code >= 0x1E00 and code <= 0x1EFF)
end

local function is_javascript_whitespace(code)
  return (code >= 0x09 and code <= 0x0D)
    or code == 0x20
    or code == 0xA0
    or code == 0x1680
    or (code >= 0x2000 and code <= 0x200A)
    or code == 0x2028
    or code == 0x2029
    or code == 0x202F
    or code == 0x205F
    or code == 0x3000
    or code == 0xFEFF
end

local function scan_run(value, byte_index, predicate)
  local cursor = byte_index
  while cursor <= #value do
    local code, width = next_code_point(value, cursor)
    if not predicate(code) then break end
    cursor = cursor + width
  end
  return cursor
end

local function is_non_newline_whitespace(code)
  return code ~= 0x0A and code ~= 0x0D and is_javascript_whitespace(code)
end

local function tokenize_words_with_space(value)
  local tokens = {}
  local byte_index = 1
  while byte_index <= #value do
    if value:sub(byte_index, byte_index + 1) == "\r\n" then
      table.insert(tokens, "\r\n")
      byte_index = byte_index + 2
    else
      local code, width = next_code_point(value, byte_index)
      local end_index
      if code == 0x0A then
        end_index = byte_index + width
      elseif is_extended_word(code) then
        end_index = scan_run(value, byte_index, is_extended_word)
      elseif is_non_newline_whitespace(code) then
        end_index = scan_run(value, byte_index, is_non_newline_whitespace)
      else
        end_index = byte_index + width
      end
      table.insert(tokens, value:sub(byte_index, end_index - 1))
      byte_index = end_index
    end
  end
  return tokens
end

local function add_to_path(path, added, removed, old_pos_increment)
  local last = path.last_component
  local component
  if last and last.added == added and last.removed == removed then
    component = {
      count = last.count + 1,
      added = added,
      removed = removed,
      previous_component = last.previous_component,
    }
  else
    component = {
      count = 1,
      added = added,
      removed = removed,
      previous_component = last,
    }
  end
  return { old_pos = path.old_pos + old_pos_increment, last_component = component }
end

local function extract_common(base_path, new_tokens, old_tokens, diagonal_path)
  local new_length = #new_tokens
  local old_length = #old_tokens
  local old_pos = base_path.old_pos
  local new_pos = old_pos - diagonal_path
  local common_count = 0

  while new_pos + 1 < new_length
      and old_pos + 1 < old_length
      and old_tokens[old_pos + 2] == new_tokens[new_pos + 2] do
    new_pos = new_pos + 1
    old_pos = old_pos + 1
    common_count = common_count + 1
  end

  if common_count > 0 then
    base_path.last_component = {
      count = common_count,
      added = false,
      removed = false,
      previous_component = base_path.last_component,
    }
  end

  base_path.old_pos = old_pos
  return new_pos
end

local function join_slice(tokens, start_pos, count)
  local values = {}
  for offset = 1, count do values[offset] = tokens[start_pos + offset] end
  return table.concat(values)
end

local function build_values(last_component, new_tokens, old_tokens)
  local reversed = {}
  while last_component do
    table.insert(reversed, last_component)
    last_component = last_component.previous_component
  end

  local components = {}
  local old_pos = 0
  local new_pos = 0
  for index = #reversed, 1, -1 do
    local draft = reversed[index]
    local component = {
      count = draft.count,
      added = draft.added,
      removed = draft.removed,
    }
    if not component.removed then
      component.value = join_slice(new_tokens, new_pos, component.count)
      new_pos = new_pos + component.count
      if not component.added then old_pos = old_pos + component.count end
    else
      component.value = join_slice(old_tokens, old_pos, component.count)
      old_pos = old_pos + component.count
    end
    table.insert(components, component)
  end
  return components
end

local function diff_tokens(old_tokens, new_tokens, configured_max_edit_length)
  local new_length = #new_tokens
  local old_length = #old_tokens
  local best_path = { [0] = { old_pos = -1 } }
  local new_pos = extract_common(best_path[0], new_tokens, old_tokens, 0)
  if best_path[0].old_pos + 1 >= old_length and new_pos + 1 >= new_length then
    return build_values(best_path[0].last_component, new_tokens, old_tokens)
  end

  local edit_length = 1
  local max_edit_length = new_length + old_length
  if configured_max_edit_length then
    max_edit_length = math.min(max_edit_length, configured_max_edit_length)
  end
  local min_diagonal = -math.huge
  local max_diagonal = math.huge

  while edit_length <= max_edit_length do
    local first_diagonal = math.max(min_diagonal, -edit_length)
    local last_diagonal = math.min(max_diagonal, edit_length)
    for diagonal_path = first_diagonal, last_diagonal, 2 do
      local remove_path = best_path[diagonal_path - 1]
      local add_path = best_path[diagonal_path + 1]
      if remove_path then best_path[diagonal_path - 1] = nil end

      local can_add = false
      if add_path then
        local add_path_new_pos = add_path.old_pos - diagonal_path
        can_add = add_path_new_pos >= 0 and add_path_new_pos < new_length
      end
      local can_remove = remove_path ~= nil and remove_path.old_pos + 1 < old_length

      if not can_add and not can_remove then
        best_path[diagonal_path] = nil
      else
        local base_path
        if not can_remove or (can_add and remove_path.old_pos < add_path.old_pos) then
          base_path = add_to_path(add_path, true, false, 0)
        else
          base_path = add_to_path(remove_path, false, true, 1)
        end

        new_pos = extract_common(base_path, new_tokens, old_tokens, diagonal_path)
        if base_path.old_pos + 1 >= old_length and new_pos + 1 >= new_length then
          return build_values(base_path.last_component, new_tokens, old_tokens)
        end

        best_path[diagonal_path] = base_path
        if base_path.old_pos + 1 >= old_length then
          max_diagonal = math.min(max_diagonal, diagonal_path - 1)
        end
        if new_pos + 1 >= new_length then
          min_diagonal = math.max(min_diagonal, diagonal_path + 1)
        end
      end
    end
    edit_length = edit_length + 1
  end
  return nil, "max_edit_length_exceeded"
end

local function diff(old_value, new_value, tokenizer, opts)
  local old_tokens = tokenizer(old_value)
  local new_tokens = tokenizer(new_value)
  local max_product = opts and opts.max_sequence_product
  if max_product and #old_tokens * #new_tokens > max_product then
    return nil, "comparison_too_large"
  end

  local result, reason = diff_tokens(old_tokens, new_tokens, opts and opts.max_edit_length)
  if not result then return nil, reason or "diff_failed" end
  return result
end

function M.diff_chars(old_value, new_value, opts)
  return diff(old_value, new_value, tokenize_characters, opts)
end

function M.diff_words_with_space(old_value, new_value, opts)
  return diff(old_value, new_value, tokenize_words_with_space, opts)
end

return M
