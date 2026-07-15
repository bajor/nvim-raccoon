local diff = require("raccoon.diff")
local diff_render = require("raccoon.diff_render")
local intraline = require("raccoon.intraline")

local function create_buffer(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  return buf
end

local function extmarks(buf, ns_id)
  return vim.api.nvim_buf_get_extmarks(buf, ns_id, 0, -1, { details = true })
end

local function find_mark(marks, predicate)
  for _, mark in ipairs(marks) do
    if predicate(mark[2], mark[3], mark[4]) then return mark end
  end
  return nil
end

local function joined_chunk_text(chunks)
  local parts = {}
  for _, chunk in ipairs(chunks) do table.insert(parts, chunk[1]) end
  return table.concat(parts)
end

describe("raccoon.diff_render", function()
  describe("real lines", function()
    it("layers whole-line, sign, and inline highlights on both sides", function()
      local patch = table.concat({
        "@@ -1,2 +1,2 @@",
        "-old_timeout = calculate_timeout(config)",
        "+new_timeout = calculate_timeout(options)",
        " context",
      }, "\n")
      local hunks = diff.parse_patch(patch)
      local lines = {}
      for _, line in ipairs(hunks[1].lines) do table.insert(lines, line.content) end
      local buf = create_buffer(lines)
      local ns_id = vim.api.nvim_create_namespace("raccoon_test_real_inline")

      diff_render.apply_real_hunks(ns_id, buf, hunks)
      local marks = extmarks(buf, ns_id)

      local deleted_row = find_mark(marks, function(row, _, details)
        return row == 0 and details.line_hl_group == "RaccoonDelete"
      end)
      assert.is_not_nil(deleted_row)
      assert.equals("- ", deleted_row[4].sign_text)
      assert.equals("RaccoonDeleteSign", deleted_row[4].sign_hl_group)

      local added_row = find_mark(marks, function(row, _, details)
        return row == 1 and details.line_hl_group == "RaccoonAdd"
      end)
      assert.is_not_nil(added_row)
      assert.equals("+ ", added_row[4].sign_text)
      assert.equals("RaccoonAddSign", added_row[4].sign_hl_group)

      assert.is_not_nil(find_mark(marks, function(row, col, details)
        return row == 0 and col == 0 and details.end_col == 3
            and details.hl_group == "RaccoonDeleteText" and details.priority == diff_render.INLINE_PRIORITY
      end))
      assert.is_not_nil(find_mark(marks, function(row, col, details)
        return row == 0 and col == 32 and details.end_col == 38
            and details.hl_group == "RaccoonDeleteText"
      end))
      assert.is_not_nil(find_mark(marks, function(row, col, details)
        return row == 1 and col == 0 and details.end_col == 3
            and details.hl_group == "RaccoonAddText" and details.priority == diff_render.INLINE_PRIORITY
      end))
      assert.is_not_nil(find_mark(marks, function(row, col, details)
        return row == 1 and col == 32 and details.end_col == 39
            and details.hl_group == "RaccoonAddText"
      end))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("keeps unrelated namespaces and does not duplicate marks on reapply", function()
      local hunks = diff.parse_patch("@@ -1 +1 @@\n-old value\n+new value")
      local buf = create_buffer({ "old value", "new value" })
      local ns_id = vim.api.nvim_create_namespace("raccoon_test_reapply")
      local unrelated = vim.api.nvim_create_namespace("raccoon_test_unrelated")
      vim.api.nvim_buf_set_extmark(buf, unrelated, 0, 0, {
        end_col = 3,
        hl_group = "Identifier",
      })

      diff_render.apply_real_hunks(ns_id, buf, hunks)
      local first_count = #extmarks(buf, ns_id)
      diff_render.apply_real_hunks(ns_id, buf, hunks)

      assert.equals(first_count, #extmarks(buf, ns_id))
      assert.equals(1, #extmarks(buf, unrelated))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("ignores invalid ranges instead of placing incorrect extmarks", function()
      local buf = create_buffer({ "short" })
      local ns_id = vim.api.nvim_create_namespace("raccoon_test_invalid_range")
      diff_render.apply_real_lines(ns_id, buf, {
        { type = "add", content = "short" },
      }, {
        [1] = {
          { start_col = -1, end_col = 2 },
          { start_col = 1, end_col = 99 },
          { start_col = 3, end_col = 3 },
        },
      })

      local marks = extmarks(buf, ns_id)
      assert.equals(1, #marks)
      assert.equals("RaccoonAdd", marks[1][4].line_hl_group)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("uses valid UTF-8 byte boundaries", function()
      local hunks = diff.parse_patch("@@ -1 +1 @@\n-status 😀 ok\n+status 😁 ok")
      local buf = create_buffer({ "status 😀 ok", "status 😁 ok" })
      local ns_id = vim.api.nvim_create_namespace("raccoon_test_utf8_range")
      diff_render.apply_real_hunks(ns_id, buf, hunks)

      for _, mark in ipairs(extmarks(buf, ns_id)) do
        local details = mark[4]
        if details.hl_group == "RaccoonAddText" or details.hl_group == "RaccoonDeleteText" then
          assert.equals(7, mark[3])
          assert.equals(11, details.end_col)
        end
      end
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("deleted virtual lines", function()
    it("splits unchanged and changed deletion text into distinct chunks", function()
      local chunks = diff_render.build_virtual_deleted_line(
        "old_timeout = calculate_timeout(config)",
        {
          { start_col = 0, end_col = 3 },
          { start_col = 32, end_col = 38 },
        }
      )

      assert.same({
        { "- ", { "RaccoonDelete", "RaccoonDeleteSign" } },
        { "old", "RaccoonDeleteText" },
        { "_timeout = calculate_timeout(", "RaccoonDelete" },
        { "config", "RaccoonDeleteText" },
        { ")", "RaccoonDelete" },
      }, chunks)
    end)

    it("preserves long content without fixed padding or truncation", function()
      local content = string.rep("α", 180) .. " END"
      local chunks = diff_render.build_virtual_deleted_line(content, {})
      assert.equals("- " .. content, joined_chunk_text(chunks))
      assert.is_nil(joined_chunk_text(chunks):find("%.%.%.$"))
    end)

    it("renders inline chunks above the correct post-image anchor", function()
      local old = "old_timeout = calculate_timeout(config)"
      local new = "new_timeout = calculate_timeout(options)"
      local patch = "@@ -1,2 +1,2 @@\n-" .. old .. "\n+" .. new .. "\n tail"
      local buf = create_buffer({ new, "tail" })
      local ns_id = vim.api.nvim_create_namespace("raccoon_test_flat_virtual")

      diff_render.apply_flat_hunks(ns_id, buf, diff.parse_patch(patch))
      local marks = extmarks(buf, ns_id)
      local virtual = find_mark(marks, function(row, _, details)
        return row == 0 and details.virt_lines ~= nil
      end)
      assert.is_not_nil(virtual)
      assert.is_true(virtual[4].virt_lines_above)
      assert.equals("- ", virtual[4].sign_text)

      local chunks = virtual[4].virt_lines[1]
      assert.equals("old", chunks[2][1])
      assert.equals("RaccoonDeleteText", chunks[2][2])
      assert.equals("config", chunks[4][1])
      assert.equals("RaccoonDeleteText", chunks[4][2])

      local addition = find_mark(marks, function(row, col, details)
        return row == 0 and col == 32 and details.end_col == 39
            and details.hl_group == "RaccoonAddText"
      end)
      assert.is_not_nil(addition)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("renders an EOF deletion below the final real line", function()
      local patch = "@@ -1,2 +1 @@\n keep\n-deleted at eof"
      local buf = create_buffer({ "keep" })
      local ns_id = vim.api.nvim_create_namespace("raccoon_test_eof_virtual")
      diff_render.apply_flat_hunks(ns_id, buf, diff.parse_patch(patch))

      local virtual = find_mark(extmarks(buf, ns_id), function(_, _, details)
        return details.virt_lines ~= nil
      end)
      assert.is_not_nil(virtual)
      assert.equals(0, virtual[2])
      assert.is_false(virtual[4].virt_lines_above)
      assert.truthy(joined_chunk_text(virtual[4].virt_lines[1]):find("deleted at eof", 1, true))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("uses whole-line fallback for oversized replacement lines", function()
      local old = string.rep("a", intraline.MAX_LINE_LENGTH + 1)
      local new = string.rep("b", intraline.MAX_LINE_LENGTH + 1)
      local patch = "@@ -1 +1 @@\n-" .. old .. "\n+" .. new
      local buf = create_buffer({ new })
      local ns_id = vim.api.nvim_create_namespace("raccoon_test_large_fallback")
      diff_render.apply_flat_hunks(ns_id, buf, diff.parse_patch(patch))

      local marks = extmarks(buf, ns_id)
      assert.is_not_nil(find_mark(marks, function(_, _, details)
        return details.line_hl_group == "RaccoonAdd"
      end))
      assert.is_not_nil(find_mark(marks, function(_, _, details)
        return details.virt_lines ~= nil
      end))
      assert.is_nil(find_mark(marks, function(_, _, details)
        return details.hl_group == "RaccoonAddText" or details.hl_group == "RaccoonDeleteText"
      end))
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)
end)
