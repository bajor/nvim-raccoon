local diff = require("raccoon.diff")
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

  describe("parse_hunk_ranges", function()
    it("parses old and new hunk coordinates", function()
      local ranges = diff.parse_hunk_ranges("@@ -10,2 +20,3 @@ function")

      assert.same({
        old_start = 10,
        old_count = 2,
        new_start = 20,
        new_count = 3,
      }, ranges)
    end)

    it("defaults omitted counts to one", function()
      local ranges = diff.parse_hunk_ranges("@@ -7 +9 @@")

      assert.same({
        old_start = 7,
        old_count = 1,
        new_start = 9,
        new_count = 1,
      }, ranges)
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

    before_each(function()
      original_notify = vim.notify
      vim.notify = function() end
    end)

    after_each(function()
      vim.notify = original_notify
    end)

    it("next_diff returns false when no session", function()
      assert.is_false(diff.next_diff())
    end)

    it("prev_diff returns false when no session", function()
      assert.is_false(diff.prev_diff())
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
  end)

  describe("render_stacked_inline_spans", function()
    it("pairs delete and add lines by index within a contiguous change block", function()
      local line_list = {
        { type = "del", content = "local value = 1" },
        { type = "del", content = "local other = true" },
        { type = "add", content = "local value = 42" },
        { type = "add", content = "local other = false" },
      }

      local spans = diff.render_stacked_inline_spans(line_list)

      assert.equals(4, #spans)
      assert.equals(1, spans[1].line)
      assert.equals(2, spans[2].line)
      assert.equals(3, spans[3].line)
      assert.equals(4, spans[4].line)
      assert.equals("RaccoonInlineDelete", spans[1].hl)
      assert.equals("RaccoonInlineAdd", spans[3].hl)
      assert.is_true(spans[1].start_col < spans[1].end_col)
      assert.is_true(spans[3].start_col < spans[3].end_col)
    end)

    it("skips inline spans when either paired line exceeds the display cap", function()
      local long = string.rep("x", diff.MAX_INLINE_DIFF_DISPLAY_CHARS + 1)
      local spans = diff.render_stacked_inline_spans({
        { type = "del", content = long },
        { type = "add", content = long .. "y" },
      })

      assert.equals(0, #spans)
    end)
  end)

  describe("render_split_file", function()
    it("aligns full old and new file content with split row metadata", function()
      local rendered = diff.render_split_file({
        path = "lua/a.lua",
        old_lines = { "one", "old", "three" },
        new_lines = { "one", "new", "three" },
        patch = "@@ -1,3 +1,3 @@\n one\n-old\n+new\n three",
        width = 80,
      })

      assert.equals(3, #rendered.lines)
      assert.matches("one", rendered.lines[1])
      assert.matches("old", rendered.lines[2])
      assert.matches("new", rendered.lines[2])
      assert.same({
        path = "lua/a.lua",
        old_line = 2,
        new_line = 2,
        kind = "change",
        in_diff_context = true,
        left_continuation = false,
        right_continuation = false,
      }, {
        path = rendered.rows[2].path,
        old_line = rendered.rows[2].old_line,
        new_line = rendered.rows[2].new_line,
        kind = rendered.rows[2].kind,
        in_diff_context = rendered.rows[2].in_diff_context,
        left_continuation = rendered.rows[2].left_continuation,
        right_continuation = rendered.rows[2].right_continuation,
      })
      assert.is_true(rendered.separator_col > rendered.left_range.start_col)
      assert.is_true(rendered.right_range.start_col > rendered.separator_col)
    end)

    it("wraps long split-side lines into continuation rows with stable semantic line numbers", function()
      local rendered = diff.render_split_file({
        path = "lua/a.lua",
        old_lines = { "before", "old " .. string.rep("x", 24), "after" },
        new_lines = { "before", "new " .. string.rep("y", 24), "after" },
        patch = "@@ -1,3 +1,3 @@\n before\n-old xxxxxxxxxxxxxxxxxxxxxxxx\n+new yyyyyyyyyyyyyyyyyyyyyyyy\n after",
        width = 42,
      })

      assert.is_true(#rendered.lines > 3)
      local continuation
      for _, row in ipairs(rendered.rows) do
        if row.old_line == 2 and row.new_line == 2 and (row.left_continuation or row.right_continuation) then
          continuation = row
          break
        end
      end

      assert.is_not_nil(continuation)
      assert.equals("change", continuation.kind)
      assert.is_true(continuation.in_diff_context)
    end)

    it("renders added, deleted, and renamed files", function()
      local added = diff.render_split_file({
        path = "lua/new.lua",
        status = "added",
        old_lines = {},
        new_lines = { "new line" },
        patch = "@@ -0,0 +1 @@\n+new line",
        width = 80,
      })
      local deleted = diff.render_split_file({
        path = "lua/old.lua",
        status = "removed",
        old_lines = { "old line" },
        new_lines = {},
        patch = "@@ -1 +0,0 @@\n-old line",
        width = 80,
      })
      local renamed = diff.render_split_file({
        path = "lua/new-name.lua",
        previous_path = "lua/old-name.lua",
        status = "renamed",
        old_lines = { "same" },
        new_lines = { "same" },
        patch = "",
        width = 80,
      })

      assert.is_nil(added.rows[1].old_line)
      assert.equals(1, added.rows[1].new_line)
      assert.equals(1, deleted.rows[1].old_line)
      assert.is_nil(deleted.rows[1].new_line)
      assert.matches("renamed from lua/old%-name%.lua", renamed.lines[1])
    end)

    it("renders binary or unreadable files as file-level placeholder rows", function()
      local rendered = diff.render_split_file({
        path = "assets/logo.png",
        binary = true,
        width = 80,
      })

      assert.equals(1, #rendered.lines)
      assert.matches("Binary or unreadable file", rendered.lines[1])
      assert.equals("file", rendered.rows[1].kind)
      assert.equals("assets/logo.png", rendered.rows[1].path)
      assert.is_false(rendered.rows[1].in_diff_context)
    end)

    it("skips syntax projection above documented caps", function()
      local lines = {}
      for i = 1, diff.MAX_SYNTAX_ROWS + 1 do
        lines[i] = "line " .. i
      end

      local rendered = diff.render_split_file({
        path = "lua/big.lua",
        old_lines = lines,
        new_lines = lines,
        patch = "",
        width = 80,
      })

      assert.is_false(rendered.syntax_enabled)
      assert.equals("row cap", rendered.syntax_skip_reason)
    end)
  end)

  describe("resolve_cursor_target", function()
    it("uses cursor column to choose left or right side", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local rendered = diff.render_split_file({
        path = "lua/a.lua",
        old_lines = { "old" },
        new_lines = { "new" },
        patch = "@@ -1 +1 @@\n-old\n+new",
        width = 80,
      })
      diff.attach_split_metadata(buf, rendered)

      local left = diff.resolve_cursor_target(buf, 1, rendered.left_range.start_col)
      local right = diff.resolve_cursor_target(buf, 1, rendered.right_range.start_col)

      assert.equals("LEFT", left.side)
      assert.equals(1, left.line)
      assert.equals("RIGHT", right.side)
      assert.equals(1, right.line)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("falls back to right side when the cursor is ambiguous", function()
      local buf = vim.api.nvim_create_buf(false, true)
      local rendered = diff.render_split_file({
        path = "lua/a.lua",
        old_lines = { "old" },
        new_lines = { "new" },
        patch = "@@ -1 +1 @@\n-old\n+new",
        width = 80,
      })
      diff.attach_split_metadata(buf, rendered)

      local target = diff.resolve_cursor_target(buf, 1, rendered.separator_col)

      assert.equals("RIGHT", target.side)
      assert.equals(1, target.line)

      vim.api.nvim_buf_delete(buf, { force = true })
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
