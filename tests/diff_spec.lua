local diff = require("raccoon.diff")
local inline_diff = require("raccoon.inline_diff")
local state = require("raccoon.state")

describe("raccoon.diff", function()
  before_each(function()
    state.reset()
  end)


  describe("parse_hunk_header", function()
    it("parses standard hunk header", function()
      local start, count = diff.parse_hunk_header("@@ -1,4 +1,5 @@")
      assert.equals(1, start)
      assert.equals(5, count)
    end)

    it("parses hunk header with different line numbers", function()
      local start, count = diff.parse_hunk_header("@@ -10,20 +15,25 @@")
      assert.equals(15, start)
      assert.equals(25, count)
    end)

    it("parses hunk header without count (single line)", function()
      local start, count = diff.parse_hunk_header("@@ -1 +1 @@")
      assert.equals(1, start)
      assert.equals(1, count)
    end)

    it("parses hunk header with context", function()
      local start, count = diff.parse_hunk_header("@@ -5,10 +7,12 @@ function foo()")
      assert.equals(7, start)
      assert.equals(12, count)
    end)

    it("returns nil for invalid header", function()
      local start, count = diff.parse_hunk_header("not a hunk header")
      assert.is_nil(start)
      assert.is_nil(count)
    end)

    it("returns nil for empty string", function()
      local start, count = diff.parse_hunk_header("")
      assert.is_nil(start)
      assert.is_nil(count)
    end)
  end)

  describe("parse_patch", function()
    it("returns empty array for nil patch", function()
      local hunks = diff.parse_patch(nil)
      assert.is_table(hunks)
      assert.equals(0, #hunks)
    end)

    it("returns empty array for empty patch", function()
      local hunks = diff.parse_patch("")
      assert.is_table(hunks)
      assert.equals(0, #hunks)
    end)

    it("parses single hunk with additions", function()
      local patch = [[
@@ -1,3 +1,4 @@
 line1
+added line
 line2
 line3]]
      local hunks = diff.parse_patch(patch)
      assert.equals(1, #hunks)
      assert.equals(1, hunks[1].start_line)
      assert.equals(4, hunks[1].count)
    end)

    it("parses single hunk with deletions", function()
      local patch = [[
@@ -1,4 +1,3 @@
 line1
-removed line
 line2
 line3]]
      local hunks = diff.parse_patch(patch)
      assert.equals(1, #hunks)
      assert.equals(1, hunks[1].start_line)
    end)

    it("parses multiple hunks", function()
      local patch = [[
@@ -1,3 +1,4 @@
 line1
+added
 line2
@@ -10,3 +11,4 @@
 line10
+added2
 line11]]
      local hunks = diff.parse_patch(patch)
      assert.equals(2, #hunks)
      assert.equals(1, hunks[1].start_line)
      assert.equals(11, hunks[2].start_line)
    end)

    it("identifies change types correctly", function()
      local patch = [[
@@ -1,3 +1,3 @@
 context
+added
-removed]]
      local hunks = diff.parse_patch(patch)
      assert.equals(1, #hunks)

      local add_found = false
      local del_found = false
      for _, line in ipairs(hunks[1].lines) do
        if line.type == "add" then
          add_found = true
        end
        if line.type == "del" then
          del_found = true
        end
      end
      assert.is_true(add_found)
      assert.is_true(del_found)
    end)

    it("records discriminated old, new, and anchor coordinates", function()
      local patch = table.concat({
        "@@ -7,3 +10,3 @@",
        " context",
        "-before",
        "+after",
        " trailing",
      }, "\n")

      local lines = diff.parse_patch(patch)[1].lines
      assert.same({
        kind = "context",
        type = "ctx",
        content = "context",
        old_line = 7,
        new_line = 10,
        anchor_line = 10,
        line_num = 10,
      }, lines[1])
      assert.same({
        kind = "deletion",
        type = "del",
        content = "before",
        old_line = 8,
        new_line = nil,
        anchor_line = 10,
        line_num = 10,
      }, lines[2])
      assert.same({
        kind = "addition",
        type = "add",
        content = "after",
        old_line = nil,
        new_line = 11,
        anchor_line = 11,
        line_num = 11,
      }, lines[3])
      assert.same({
        kind = "context",
        type = "ctx",
        content = "trailing",
        old_line = 9,
        new_line = 12,
        anchor_line = 12,
        line_num = 12,
      }, lines[4])
    end)

    it("retains hunk coordinates for both patch sides", function()
      local hunk = diff.parse_patch("@@ -7,2 +10,4 @@\n-old\n+new")[1]

      assert.equals(7, hunk.old_start_line)
      assert.equals(2, hunk.old_count)
      assert.equals(10, hunk.new_start_line)
      assert.equals(4, hunk.new_count)
      assert.equals(10, hunk.start_line)
      assert.equals(4, hunk.count)
    end)
  end)

  describe("get_changed_lines", function()
    it("returns empty for nil patch", function()
      local changes = diff.get_changed_lines(nil)
      assert.is_table(changes)
      assert.is_table(changes.added)
      assert.is_table(changes.deleted)
      assert.equals(0, #changes.added)
      assert.equals(0, #changes.deleted)
    end)

    it("returns added line numbers", function()
      local patch = [[
@@ -1,2 +1,3 @@
 line1
+added
 line2]]
      local changes = diff.get_changed_lines(patch)
      assert.equals(1, #changes.added)
      assert.equals(2, changes.added[1])
    end)

    it("returns multiple added line numbers", function()
      local patch = [[
@@ -1,2 +1,4 @@
 line1
+added1
+added2
 line2]]
      local changes = diff.get_changed_lines(patch)
      assert.equals(2, #changes.added)
      assert.equals(2, changes.added[1])
      assert.equals(3, changes.added[2])
    end)

    it("tracks deleted lines", function()
      local patch = [[
@@ -1,3 +1,2 @@
 line1
-removed
 line2]]
      local changes = diff.get_changed_lines(patch)
      assert.equals(1, #changes.deleted)
    end)
  end)

  describe("navigation", function()
    local original_notify

    before_each(function()
      original_notify = vim.notify
      vim.notify = function() end
    end)

    after_each(function()
      vim.notify = original_notify
    end)

    it("next_file returns false when no session", function()
      assert.is_false(diff.next_file())
    end)

    it("prev_file returns false when no session", function()
      assert.is_false(diff.prev_file())
    end)

    it("goto_file returns false when no session", function()
      assert.is_false(diff.goto_file(1))
    end)
  end)

  describe("get_namespace", function()
    it("returns a namespace ID", function()
      local ns = diff.get_namespace()
      assert.is_number(ns)
      assert.is_true(ns > 0)
    end)
  end)

  describe("highlights", function()
    it("clear_highlights handles invalid buffer", function()
      -- Should not error
      diff.clear_highlights(nil)
      diff.clear_highlights(-1)
      diff.clear_highlights(99999)
    end)

    it("apply_highlights handles nil patch", function()
      local buf = vim.api.nvim_create_buf(false, true)
      -- Should not error
      diff.apply_highlights(buf, nil)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("apply_highlights handles empty patch", function()
      local buf = vim.api.nvim_create_buf(false, true)
      -- Should not error
      diff.apply_highlights(buf, "")
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe("open_file", function()
    local original_notify

    before_each(function()
      original_notify = vim.notify
      vim.notify = function() end
    end)

    after_each(function()
      vim.notify = original_notify
    end)

    it("returns nil for nil file", function()
      assert.is_nil(diff.open_file(nil))
    end)

    it("returns nil for file without filename", function()
      assert.is_nil(diff.open_file({}))
    end)

    it("returns nil when no active session", function()
      assert.is_nil(diff.open_file({ filename = "test.lua" }))
    end)
  end)

  describe("next_diff and prev_diff", function()
    local original_notify
    local test_buf

    before_each(function()
      original_notify = vim.notify
      vim.notify = function() end
    end)

    after_each(function()
      vim.notify = original_notify
      if test_buf and vim.api.nvim_buf_is_valid(test_buf) then
        vim.api.nvim_buf_delete(test_buf, { force = true })
      end
    end)

    local function activate_session_with_addition_and_deletion()
      state.start({ owner = "owner", repo = "repo", number = 1 })
      state.set_files({ {
        filename = "test.lua",
        patch = "@@ -2,0 +3,1 @@\n+added\n@@ -7,1 +8,0 @@\n-deleted",
      } })

      test_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(test_buf, 0, -1, false, {
        "line 1", "line 2", "added", "line 3", "line 4",
        "line 5", "line 6", "line 8", "line 9",
      })
      vim.api.nvim_set_current_buf(test_buf)
    end

    it("next_diff returns false when no session", function()
      assert.is_false(diff.next_diff())
    end)

    it("prev_diff returns false when no session", function()
      assert.is_false(diff.prev_diff())
    end)

    it("next_diff uses the addition new line and deletion post-image anchor", function()
      activate_session_with_addition_and_deletion()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      assert.is_true(diff.next_diff())
      assert.equals(3, vim.api.nvim_win_get_cursor(0)[1])
      assert.is_true(diff.next_diff())
      assert.equals(7, vim.api.nvim_win_get_cursor(0)[1])
    end)

    it("prev_diff uses the deletion post-image anchor and addition new line", function()
      activate_session_with_addition_and_deletion()
      vim.api.nvim_win_set_cursor(0, { 9, 0 })

      assert.is_true(diff.prev_diff())
      assert.equals(7, vim.api.nvim_win_get_cursor(0)[1])
      assert.is_true(diff.prev_diff())
      assert.equals(3, vim.api.nvim_win_get_cursor(0)[1])
    end)
  end)

  describe("parse_patch edge cases", function()
    it("handles patch with only additions", function()
      local patch = [[
@@ -0,0 +1,3 @@
+line1
+line2
+line3]]
      local hunks = diff.parse_patch(patch)
      assert.equals(1, #hunks)
      -- Count added lines
      local add_count = 0
      for _, line in ipairs(hunks[1].lines) do
        if line.type == "add" then
          add_count = add_count + 1
        end
      end
      assert.equals(3, add_count)
    end)

    it("handles patch with only deletions", function()
      local patch = [[
@@ -1,3 +0,0 @@
-line1
-line2
-line3]]
      local hunks = diff.parse_patch(patch)
      assert.equals(1, #hunks)
      -- Count deleted lines
      local del_count = 0
      for _, line in ipairs(hunks[1].lines) do
        if line.type == "del" then
          del_count = del_count + 1
        end
      end
      assert.equals(3, del_count)
    end)

    it("handles mixed additions and deletions in same hunk", function()
      local patch = [[
@@ -1,5 +1,5 @@
 context1
-old line 1
-old line 2
+new line 1
+new line 2
 context2]]
      local hunks = diff.parse_patch(patch)
      assert.equals(1, #hunks)

      local add_count = 0
      local del_count = 0
      local ctx_count = 0
      for _, line in ipairs(hunks[1].lines) do
        if line.type == "add" then
          add_count = add_count + 1
        elseif line.type == "del" then
          del_count = del_count + 1
        elseif line.type == "ctx" then
          ctx_count = ctx_count + 1
        end
      end
      assert.equals(2, add_count)
      assert.equals(2, del_count)
      assert.equals(2, ctx_count)
    end)

    it("handles large line numbers", function()
      local start, count = diff.parse_hunk_header("@@ -1000,50 +1050,75 @@")
      assert.equals(1050, start)
      assert.equals(75, count)
    end)

    it("handles single line addition", function()
      local patch = [[
@@ -5,0 +6 @@
+single new line]]
      local hunks = diff.parse_patch(patch)
      assert.equals(1, #hunks)
    end)

    it("handles patch with file headers (should ignore them)", function()
      local patch = [[
--- a/file.lua
+++ b/file.lua
@@ -1,3 +1,4 @@
 line1
+added
 line2
 line3]]
      local hunks = diff.parse_patch(patch)
      assert.equals(1, #hunks)
      -- Verify --- and +++ lines are not counted as changes
      for _, line in ipairs(hunks[1].lines) do
        assert.is_not_nil(line.type)
        if line.type == "add" then
          assert.not_matches("^%+%+%+", "+" .. line.content)
        end
      end
    end)
  end)

  describe("get_changed_lines edge cases", function()
    it("handles consecutive additions correctly", function()
      local patch = [[
@@ -1,2 +1,5 @@
 line1
+add1
+add2
+add3
 line2]]
      local changes = diff.get_changed_lines(patch)
      assert.equals(3, #changes.added)
      assert.equals(2, changes.added[1])
      assert.equals(3, changes.added[2])
      assert.equals(4, changes.added[3])
    end)

    it("handles non-consecutive additions correctly", function()
      local patch = [[
@@ -1,4 +1,6 @@
 line1
+add1
 line2
 line3
+add2
 line4]]
      local changes = diff.get_changed_lines(patch)
      assert.equals(2, #changes.added)
    end)

    it("handles deletion tracking with line content", function()
      local patch = [[
@@ -1,3 +1,2 @@
 line1
-deleted line content
 line2]]
      local changes = diff.get_changed_lines(patch)
      assert.equals(1, #changes.deleted)
      assert.is_not_nil(changes.deleted[1].content)
      assert.equals("deleted line content", changes.deleted[1].content)
    end)
  end)

  describe("is_line_in_review_context", function()
    it("accepts unchanged context lines inside a hunk", function()
      local patch = "@@ -10,2 +10,3 @@\n line 10\n+line 11\n line 12"

      assert.is_true(diff.is_line_in_review_context(patch, 10))
      assert.is_true(diff.is_line_in_review_context(patch, 11))
      assert.is_true(diff.is_line_in_review_context(patch, 12))
    end)

    it("rejects lines outside the diff context", function()
      local patch = "@@ -10,2 +10,3 @@\n line 10\n+line 11\n line 12"

      assert.is_false(diff.is_line_in_review_context(patch, 9))
      assert.is_false(diff.is_line_in_review_context(patch, 13))
      assert.is_false(diff.is_line_in_review_context(patch, 99))
    end)

    it("keeps correct line numbers across blank lines in a hunk", function()
      local patch = "@@ -1,4 +1,5 @@\n line 1\n \n+line 3\n line 4\n line 5"

      assert.is_true(diff.is_line_in_review_context(patch, 1))
      assert.is_true(diff.is_line_in_review_context(patch, 2))
      assert.is_true(diff.is_line_in_review_context(patch, 3))
      assert.is_true(diff.is_line_in_review_context(patch, 4))
      assert.is_true(diff.is_line_in_review_context(patch, 5))
    end)

    it("uses post-image coordinates when old and new hunk positions differ", function()
      local patch = "@@ -4,2 +20,3 @@\n line 20\n-old line\n+new line\n trailing"

      assert.is_false(diff.is_line_in_review_context(patch, 4))
      assert.is_true(diff.is_line_in_review_context(patch, 20))
      assert.is_true(diff.is_line_in_review_context(patch, 21))
      assert.is_true(diff.is_line_in_review_context(patch, 22))
    end)
  end)

  describe("apply_highlights edge cases", function()
    it("handles invalid buffer gracefully", function()
      -- Should not error
      diff.apply_highlights(-1, "@@ -1,1 +1,2 @@\n line\n+added")
      diff.apply_highlights(nil, "@@ -1,1 +1,2 @@\n line\n+added")
    end)

    it("handles buffer with content", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
        "line 1",
        "line 2",
        "line 3",
      })

      local patch = [[
@@ -1,3 +1,4 @@
 line 1
+new line
 line 2
 line 3]]

      -- Should not error
      diff.apply_highlights(buf, patch)

      -- Verify namespace was used
      local ns = diff.get_namespace()
      assert.is_number(ns)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("renders subdued rows, exact spans, and unchanged signs", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local total_size = 1", "unchanged" })
      local patch = table.concat({
        "@@ -1,2 +1,2 @@",
        "-local total_count = 1",
        "+local total_size = 1",
        " unchanged",
      }, "\n")

      diff.apply_highlights(buf, patch)

      local marks = vim.api.nvim_buf_get_extmarks(buf, diff.get_namespace(), 0, -1, { details = true })
      local add_row, add_inline, delete_row
      for _, mark in ipairs(marks) do
        local details = mark[4]
        if details.sign_text == "+ " then add_row = details end
        if details.hl_group == "RaccoonAddInline" then
          add_inline = { row = mark[2], col = mark[3], details = details }
        end
        if details.sign_text == "- " then delete_row = details end
      end

      assert.equals("RaccoonAdd", add_row.line_hl_group)
      assert.equals("RaccoonAddSign", add_row.sign_hl_group)
      assert.same({ row = 0, col = 12 }, { row = add_inline.row, col = add_inline.col })
      assert.equals(16, add_inline.details.end_col)
      assert.equals(200, add_inline.details.priority)
      assert.equals("RaccoonDeleteSign", delete_row.sign_hl_group)
      assert.is_true(delete_row.virt_lines_above)
      local delete_chunks = delete_row.virt_lines[1]
      assert.equals("RaccoonDelete", delete_chunks[1][2])
      assert.equals("RaccoonDeleteInline", delete_chunks[3][2])

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("keeps complete deleted virtual text without an ellipsis", function()
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "remaining" })
      local deleted = string.rep("long-content-", 20)
      local patch = "@@ -1,2 +1,1 @@\n-" .. deleted .. "\n remaining"

      diff.apply_highlights(buf, patch)

      local marks = vim.api.nvim_buf_get_extmarks(buf, diff.get_namespace(), 0, -1, { details = true })
      local rendered
      for _, mark in ipairs(marks) do
        if mark[4].virt_lines then
          local chunks = mark[4].virt_lines[1]
          local parts = {}
          for _, chunk in ipairs(chunks) do table.insert(parts, chunk[1]) end
          rendered = table.concat(parts)
        end
      end
      assert.equals("- " .. deleted .. string.rep(" ", 300), rendered)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("falls back for every hunk when whole-file batch planning fails", function()
      local original_plan_many = inline_diff.plan_many
      local original_notify = vim.notify
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "new one", "between", "new two" })
      inline_diff.plan_many = function(line_groups)
        assert.equals(2, #line_groups)
        return nil, "inline diff budget exceeded"
      end
      vim.notify = function() end
      diff._reset_inline_diff_warning()

      local ok, err = pcall(function()
        diff.apply_highlights(buf, table.concat({
          "@@ -1 +1 @@",
          "-old one",
          "+new one",
          "@@ -3 +3 @@",
          "-old two",
          "+new two",
        }, "\n"))

        local marks = vim.api.nvim_buf_get_extmarks(buf, diff.get_namespace(), 0, -1, { details = true })
        local line_groups = {}
        local bright_ranges = 0
        for _, mark in ipairs(marks) do
          if mark[4].sign_text == "+ " then line_groups[mark[2]] = mark[4].line_hl_group end
          if mark[4].hl_group == "RaccoonAddInline" then bright_ranges = bright_ranges + 1 end
        end
        assert.equals("RaccoonAddInline", line_groups[0])
        assert.equals("RaccoonAddInline", line_groups[2])
        assert.equals(0, bright_ranges)
      end)

      inline_diff.plan_many = original_plan_many
      vim.notify = original_notify
      diff._reset_inline_diff_warning()
      vim.api.nvim_buf_delete(buf, { force = true })
      if not ok then error(err) end
    end)

    it("falls back once to strong line highlights for an invalid plan", function()
      local original_plan_many = inline_diff.plan_many
      local original_notify = vim.notify
      local notifications = 0
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "added" })
      inline_diff.plan_many = function()
        return { { rows = { { kind = "invalid" } } } }
      end
      vim.notify = function() notifications = notifications + 1 end
      diff._reset_inline_diff_warning()

      local ok, err = pcall(function()
        diff.apply_highlights(buf, "@@ -0,0 +1 @@\n+added")
        diff.apply_highlights(buf, "@@ -0,0 +1 @@\n+added")
        local marks = vim.api.nvim_buf_get_extmarks(buf, diff.get_namespace(), 0, -1, { details = true })
        local row_group
        for _, mark in ipairs(marks) do
          if mark[4].sign_text == "+ " then row_group = mark[4].line_hl_group end
        end
        assert.equals("RaccoonAddInline", row_group)
        assert.equals(1, notifications)
      end)

      inline_diff.plan_many = original_plan_many
      vim.notify = original_notify
      diff._reset_inline_diff_warning()
      vim.api.nvim_buf_delete(buf, { force = true })
      if not ok then error(err) end
    end)
  end)

  describe("parse_hunk_header edge cases", function()
    it("handles zero line count", function()
      local start, count = diff.parse_hunk_header("@@ -1,0 +1,0 @@")
      assert.equals(1, start)
      assert.equals(0, count)
    end)

    it("handles hunk with function context", function()
      local start, count = diff.parse_hunk_header("@@ -10,5 +10,7 @@ func TestSomething() {")
      assert.equals(10, start)
      assert.equals(7, count)
    end)

    it("handles hunk with special characters in context", function()
      local start, count = diff.parse_hunk_header("@@ -1,2 +1,3 @@ function foo(a, b) -- comment")
      assert.equals(1, start)
      assert.equals(3, count)
    end)
  end)
end)
