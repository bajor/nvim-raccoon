local diff = require("raccoon.diff")
local state = require("raccoon.state")

describe("raccoon.diff", function()
  before_each(function()
    state.reset()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(diff)
    end)

    it("has parse_hunk_header function", function()
      assert.is_function(diff.parse_hunk_header)
    end)

    it("has parse_patch function", function()
      assert.is_function(diff.parse_patch)
    end)

    it("has get_changed_lines function", function()
      assert.is_function(diff.get_changed_lines)
    end)

    it("has apply_highlights function", function()
      assert.is_function(diff.apply_highlights)
    end)

    it("has clear_highlights function", function()
      assert.is_function(diff.clear_highlights)
    end)

    it("has open_file function", function()
      assert.is_function(diff.open_file)
    end)

    it("has next_file function", function()
      assert.is_function(diff.next_file)
    end)

    it("has prev_file function", function()
      assert.is_function(diff.prev_file)
    end)

    it("has goto_file function", function()
      assert.is_function(diff.goto_file)
    end)

    it("has setup_keymaps function", function()
      assert.is_function(diff.setup_keymaps)
    end)

    it("has clear_keymaps function", function()
      assert.is_function(diff.clear_keymaps)
    end)

    it("has get_namespace function", function()
      assert.is_function(diff.get_namespace)
    end)
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
end)
