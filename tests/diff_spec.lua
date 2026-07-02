local diff = require("raccoon.diff")
local raccoon = require("raccoon")
local state = require("raccoon.state")

describe("raccoon.diff", function()
  local original_config = vim.deepcopy(raccoon.config)

  before_each(function()
    state.reset()
  end)

  after_each(function()
    raccoon.config = vim.deepcopy(original_config)
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

  describe("pierre render plans", function()
    local original_system
    local original_pierre

    local function reload_diff_with_pierre(fake_pierre)
      package.loaded["raccoon.diff"] = nil
      package.loaded["raccoon.pierre"] = fake_pierre
      diff = require("raccoon.diff")
      return diff
    end

    local function reload_diff_with_real_pierre()
      package.loaded["raccoon.diff"] = nil
      package.loaded["raccoon.pierre"] = nil
      diff = require("raccoon.diff")
      return diff
    end

    local function get_extmarks(buf)
      return vim.api.nvim_buf_get_extmarks(buf, diff.get_namespace(), 0, -1, { details = true })
    end

    local function has_extmark_with(buf, predicate)
      for _, mark in ipairs(get_extmarks(buf)) do
        if predicate(mark[4] or {}) then
          return true
        end
      end
      return false
    end

    local function create_buf(lines)
      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      return buf
    end

    local function assert_builtin_fallback_marks_addition(buf)
      assert.is_true(has_extmark_with(buf, function(details)
        return type(details.sign_text) == "string"
          and details.sign_text:match("^%+")
          and details.line_hl_group == "RaccoonAdd"
      end))
    end

    before_each(function()
      original_system = vim.system
      original_pierre = package.loaded["raccoon.pierre"]
      raccoon.config.diff_renderer = {
        provider = "pierre",
        timeout_ms = 25,
        command = { "node", "stub" },
        inline_word_diff = true,
      }
    end)

    after_each(function()
      vim.system = original_system
      package.loaded["raccoon.diff"] = nil
      package.loaded["raccoon.pierre"] = original_pierre
      diff = require("raccoon.diff")
    end)

    it("applies extmarks from a Pierre render plan", function()
      local plan = {
        version = 1,
        added = { 2 },
        deleted = {
          {
            line_num = 3,
            rows = {
              {
                { text = "- old value", hl = "RaccoonDelete" },
              },
            },
          },
        },
        reviewable = { [2] = true },
        hunks = { { start_line = 2, end_line = 3 } },
        inline_add = {
          { line_num = 2, start_col = 4, end_col = 9 },
        },
      }

      reload_diff_with_pierre({
        is_enabled = function()
          return true
        end,
        render_patch = function()
          return plan
        end,
      })

      local buf = create_buf({ "line 1", "new value", "line 3" })
      diff.apply_highlights(buf, "@@ -1,2 +1,3 @@\n line 1\n+new value\n line 3", { filename = "x.lua" })

      assert.is_true(has_extmark_with(buf, function(details)
        return type(details.sign_text) == "string"
          and details.sign_text:match("^%+")
          and details.line_hl_group == "RaccoonAdd"
      end))
      assert.is_true(has_extmark_with(buf, function(details)
        return type(details.sign_text) == "string" and details.sign_text:match("^%-") and details.virt_lines ~= nil
      end))
      assert.is_true(has_extmark_with(buf, function(details)
        return details.hl_group == "RaccoonAddInline"
      end))

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("falls back to builtin highlights when Pierre returns invalid JSON", function()
      local calls = 0
      vim.system = function()
        calls = calls + 1
        return {
          wait = function()
            return { code = 0, stdout = "not json", stderr = "" }
          end,
        }
      end

      reload_diff_with_real_pierre()

      local buf = create_buf({ "line 1", "new value", "line 2" })
      diff.apply_highlights(buf, "@@ -1,2 +1,3 @@\n line 1\n+new value\n line 2", { filename = "x.lua" })

      assert.equals(1, calls)
      assert_builtin_fallback_marks_addition(buf)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("falls back to builtin highlights when the Pierre process fails", function()
      local calls = 0
      vim.system = function()
        calls = calls + 1
        return {
          wait = function()
            return { code = 1, stdout = "", stderr = "boom" }
          end,
        }
      end

      reload_diff_with_real_pierre()

      local buf = create_buf({ "line 1", "new value", "line 2" })
      diff.apply_highlights(buf, "@@ -1,2 +1,3 @@\n line 1\n+new value\n line 2", { filename = "x.lua" })

      assert.equals(1, calls)
      assert_builtin_fallback_marks_addition(buf)

      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("uses plan reviewable lines when present", function()
      reload_diff_with_pierre({
        is_enabled = function()
          return true
        end,
        render_patch = function()
          return {
            version = 1,
            reviewable = { [50] = true },
            hunks = {},
            added = {},
            deleted = {},
          }
        end,
      })

      assert.is_true(diff.is_line_in_review_context("@@ -1,1 +1,1 @@\n line 1", 50))
      assert.is_false(diff.is_line_in_review_context("@@ -1,1 +1,1 @@\n line 1", 1))
    end)

    it("uses plan hunk starts for diff navigation when present", function()
      reload_diff_with_pierre({
        is_enabled = function()
          return true
        end,
        render_patch = function()
          return {
            version = 1,
            reviewable = {},
            hunks = {
              { start_line = 40, end_line = 41 },
            },
            added = {},
            deleted = {},
          }
        end,
      })

      local lines = {}
      for i = 1, 50 do
        table.insert(lines, "line " .. i)
      end
      local buf = create_buf(lines)
      vim.api.nvim_set_current_buf(buf)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      state.start({ owner = "o", repo = "r", number = 1, clone_path = "/tmp/raccoon-test" })
      state.set_files({
        { filename = "x.lua", patch = "@@ -1,1 +2,1 @@\n+new value" },
      })

      assert.is_true(diff.next_diff())
      assert.equals(40, vim.api.nvim_win_get_cursor(0)[1])

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
