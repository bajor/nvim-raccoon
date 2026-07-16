local diff = require("raccoon.diff")
local intraline = require("raccoon.intraline")

local function assert_ranges(expected, actual)
  assert.same(expected, actual)
end

local function one_block(lines, old_count, new_count)
  local patch_lines = { string.format("@@ -1,%d +1,%d @@", old_count, new_count) }
  vim.list_extend(patch_lines, lines)
  return diff.parse_patch(table.concat(patch_lines, "\n"))[1].change_blocks[1]
end

local function is_utf8_boundary(text, column)
  if column == 0 or column == #text then return true end
  local byte = text:byte(column + 1)
  return byte < 0x80 or byte > 0xBF
end

describe("raccoon.intraline", function()
  describe("compute_inline_ranges", function()
    it("highlights changed identifier words without unchanged prefixes or suffixes", function()
      local old = "old_timeout = calculate_timeout(config)"
      local new = "new_timeout = calculate_timeout(options)"
      local old_ranges, new_ranges = intraline.compute_inline_ranges(old, new)

      assert_ranges({
        { start_col = 0, end_col = 3 },
        { start_col = 32, end_col = 38 },
      }, old_ranges)
      assert_ranges({
        { start_col = 0, end_col = 3 },
        { start_col = 32, end_col = 39 },
      }, new_ranges)
    end)

    it("uses whole ordinary words when character fragments would reduce readability", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("config", "options")
      assert_ranges({ { start_col = 0, end_col = 6 } }, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 7 } }, new_ranges)
    end)

    it("refines identifier-internal changes to characters", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("oldTimeout", "newTimeout")
      assert_ranges({ { start_col = 0, end_col = 3 } }, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 3 } }, new_ranges)

      old_ranges, new_ranges = intraline.compute_inline_ranges("v1", "v2")
      assert_ranges({ { start_col = 1, end_col = 2 } }, old_ranges)
      assert_ranges({ { start_col = 1, end_col = 2 } }, new_ranges)
    end)

    it("keeps short prose replacements at word granularity", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("cat", "bat")
      assert_ranges({ { start_col = 0, end_col = 3 } }, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 3 } }, new_ranges)
    end)

    it("supports an explicit character mode", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("cat", "bat", { mode = "character" })
      assert_ranges({ { start_col = 0, end_col = 1 } }, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 1 } }, new_ranges)
    end)

    it("refines punctuation-only changes", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("call(foo)", "call[foo]")
      assert_ranges({
        { start_col = 4, end_col = 5 },
        { start_col = 8, end_col = 9 },
      }, old_ranges)
      assert_ranges({
        { start_col = 4, end_col = 5 },
        { start_col = 8, end_col = 9 },
      }, new_ranges)
    end)

    it("makes tab and space replacements visible", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("a\tb", "a  b")
      assert_ranges({ { start_col = 1, end_col = 2 } }, old_ranges)
      assert_ranges({ { start_col = 1, end_col = 3 } }, new_ranges)
    end)

    it("highlights leading and trailing whitespace without the unchanged text", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges(" value ", "\tvalue  ")
      assert_ranges({
        { start_col = 0, end_col = 1 },
        { start_col = 6, end_col = 7 },
      }, old_ranges)
      assert_ranges({
        { start_col = 0, end_col = 1 },
        { start_col = 6, end_col = 8 },
      }, new_ranges)
    end)

    it("handles empty and completely replaced lines", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("", "replacement")
      assert_ranges({}, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 11 } }, new_ranges)

      old_ranges, new_ranges = intraline.compute_inline_ranges("alpha", "omega")
      assert_ranges({ { start_col = 0, end_col = 5 } }, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 5 } }, new_ranges)
    end)

    it("returns no ranges for identical empty lines", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("", "")
      assert_ranges({}, old_ranges)
      assert_ranges({}, new_ranges)
    end)

    it("handles repeated words deterministically", function()
      local old = "one two one two"
      local new = "one three one two"
      local first_old, first_new = intraline.compute_inline_ranges(old, new)
      local second_old, second_new = intraline.compute_inline_ranges(old, new)

      assert_ranges({ { start_col = 4, end_col = 7 } }, first_old)
      assert_ranges({ { start_col = 4, end_col = 9 } }, first_new)
      assert.same(first_old, second_old)
      assert.same(first_new, second_new)
    end)

    it("refines long identifiers while bounded and falls back safely above the work cap", function()
      local prefix = string.rep("a", 900)
      local old_ranges, new_ranges = intraline.compute_inline_ranges(prefix .. "Old", prefix .. "New")
      assert_ranges({ { start_col = 900, end_col = 903 } }, old_ranges)
      assert_ranges({ { start_col = 900, end_col = 903 } }, new_ranges)

      prefix = string.rep("a", 1100)
      old_ranges, new_ranges = intraline.compute_inline_ranges(prefix .. "Old", prefix .. "New")
      assert_ranges({ { start_col = 0, end_col = 1103 } }, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 1103 } }, new_ranges)
    end)

    it("returns UTF-8 byte ranges for accents, CJK, emoji, and combining marks", function()
      local cases = {
        { "café", "cafe", { { start_col = 0, end_col = 5 } }, { { start_col = 0, end_col = 4 } } },
        { "你好世界", "你好世间", { { start_col = 9, end_col = 12 } }, { { start_col = 9, end_col = 12 } } },
        { "status 😀 ok", "status 😁 ok", { { start_col = 7, end_col = 11 } }, { { start_col = 7, end_col = 11 } } },
        { "café", "cafe", { { start_col = 4, end_col = 6 } }, {} },
      }

      for _, case in ipairs(cases) do
        local old_ranges, new_ranges = intraline.compute_inline_ranges(case[1], case[2])
        assert_ranges(case[3], old_ranges)
        assert_ranges(case[4], new_ranges)
        for _, range in ipairs(old_ranges) do
          assert.is_true(is_utf8_boundary(case[1], range.start_col))
          assert.is_true(is_utf8_boundary(case[1], range.end_col))
        end
        for _, range in ipairs(new_ranges) do
          assert.is_true(is_utf8_boundary(case[2], range.start_col))
          assert.is_true(is_utf8_boundary(case[2], range.end_col))
        end
      end
    end)

    it("normalizes a CR from CRLF input before calculating columns", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("old\r", "new\r")
      assert_ranges({ { start_col = 0, end_col = 3 } }, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 3 } }, new_ranges)
    end)

    it("merges adjacent ranges", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("a+b", "x-y")
      assert_ranges({ { start_col = 0, end_col = 3 } }, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 3 } }, new_ranges)
    end)

    it("ports Pierre word-alt single-space span joining", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("aa ", "a a")
      assert_ranges({ { start_col = 0, end_col = 3 } }, old_ranges)
      assert_ranges({ { start_col = 0, end_col = 3 } }, new_ranges)
    end)

    it("uses Pierre's UTF-16 unit rule when joining neutral spans", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("a🙂b", "x🙂y")
      assert_ranges({
        { start_col = 0, end_col = 1 },
        { start_col = 5, end_col = 6 },
      }, old_ranges)
      assert_ranges({
        { start_col = 0, end_col = 1 },
        { start_col = 5, end_col = 6 },
      }, new_ranges)
    end)

    it("skips lines and sequences above explicit safety limits", function()
      local old_ranges, new_ranges, reason = intraline.compute_inline_ranges(
        "123456", "abcdef", { max_line_length = 5 }
      )
      assert.is_nil(old_ranges)
      assert.is_nil(new_ranges)
      assert.equals("line_too_long", reason)

      old_ranges, new_ranges, reason = intraline.compute_inline_ranges(
        "a-b-c-d", "w-x-y-z", { max_sequence_product = 4 }
      )
      assert.is_nil(old_ranges)
      assert.is_nil(new_ranges)
      assert.equals("comparison_too_large", reason)

      old_ranges, new_ranges, reason = intraline.compute_inline_ranges(
        "abcd", "wxyz", { mode = "character", max_edit_length = 7 }
      )
      assert.is_nil(old_ranges)
      assert.is_nil(new_ranges)
      assert.equals("max_edit_length_exceeded", reason)
    end)

    it("supports none mode and rejects unknown modes", function()
      local old_ranges, new_ranges = intraline.compute_inline_ranges("old", "new", { mode = "none" })
      assert_ranges({}, old_ranges)
      assert_ranges({}, new_ranges)

      local reason
      old_ranges, new_ranges, reason = intraline.compute_inline_ranges("old", "new", { mode = "invalid" })
      assert.is_nil(old_ranges)
      assert.is_nil(new_ranges)
      assert.equals("invalid_mode", reason)
    end)
  end)

  describe("pair_changed_lines", function()
    it("pairs equal multi-line replacements through vim.diff linematch", function()
      local block = one_block({
        "-local first = old_value",
        "-local second = old_value",
        "+local first = new_value",
        "+local second = new_value",
      }, 2, 2)
      local result = intraline.pair_changed_lines(block)

      assert.same({
        { deletion_index = 1, addition_index = 1, changed = true },
        { deletion_index = 2, addition_index = 2, changed = true },
      }, result.pairs)
      assert.same({}, result.unpaired_deletions)
      assert.same({}, result.unpaired_additions)
    end)

    it("aligns an inserted line instead of shifting every later pair", function()
      local block = one_block({
        "-local first = old_value",
        "-local second = old_value",
        "+inserted unrelated",
        "+local first = new_value",
        "+local second = new_value",
      }, 2, 3)
      local result = intraline.pair_changed_lines(block)

      assert.same({
        { deletion_index = 1, addition_index = 2, changed = true },
        { deletion_index = 2, addition_index = 3, changed = true },
      }, result.pairs)
      assert.same({}, result.unpaired_deletions)
      assert.same({ 1 }, result.unpaired_additions)
    end)

    it("aligns an insertion inside a replacement block", function()
      local block = one_block({
        "-local first = old_value",
        "-local second = old_value",
        "+local first = new_value",
        "+inserted unrelated",
        "+local second = new_value",
      }, 2, 3)
      local result = intraline.pair_changed_lines(block)

      assert.same({
        { deletion_index = 1, addition_index = 1, changed = true },
        { deletion_index = 2, addition_index = 3, changed = true },
      }, result.pairs)
      assert.same({}, result.unpaired_deletions)
      assert.same({ 2 }, result.unpaired_additions)
    end)

    it("aligns a removed line instead of shifting every later pair", function()
      local block = one_block({
        "-removed unrelated",
        "-local first = old_value",
        "-local second = old_value",
        "+local first = new_value",
        "+local second = new_value",
      }, 3, 2)
      local result = intraline.pair_changed_lines(block)

      assert.same({
        { deletion_index = 2, addition_index = 1, changed = true },
        { deletion_index = 3, addition_index = 2, changed = true },
      }, result.pairs)
      assert.same({ 1 }, result.unpaired_deletions)
      assert.same({}, result.unpaired_additions)
    end)

    it("aligns a deletion inside a replacement block", function()
      local block = one_block({
        "-local first = old_value",
        "-removed unrelated",
        "-local second = old_value",
        "+local first = new_value",
        "+local second = new_value",
      }, 3, 2)
      local result = intraline.pair_changed_lines(block)

      assert.same({
        { deletion_index = 1, addition_index = 1, changed = true },
        { deletion_index = 3, addition_index = 2, changed = true },
      }, result.pairs)
      assert.same({ 2 }, result.unpaired_deletions)
      assert.same({}, result.unpaired_additions)
    end)

    it("uses linematch to choose one row from an unequal replacement", function()
      local block = one_block({ "-apple", "-banana", "+zebra" }, 2, 1)
      local result = intraline.pair_changed_lines(block)
      assert.same({
        { deletion_index = 2, addition_index = 1, changed = true },
      }, result.pairs)
      assert.same({ 1 }, result.unpaired_deletions)
      assert.same({}, result.unpaired_additions)
    end)

    it("falls back to Pierre row pairing when linematch leaves replacement rows uncovered", function()
      local block = one_block({
        "-}",
        "-return old;",
        "+if (ready) {",
        "+return new;",
        "+}",
      }, 2, 3)
      local result = intraline.pair_changed_lines(block)

      assert.equals("incomplete_linematch", result.fallback_reason)
      assert.same({
        { deletion_index = 1, addition_index = 1, changed = true },
        { deletion_index = 2, addition_index = 2, changed = true },
      }, result.pairs)
      assert.same({}, result.unpaired_deletions)
      assert.same({ 3 }, result.unpaired_additions)
    end)

    it("handles add-only and delete-only blocks", function()
      local additions = one_block({ "+one", "+two" }, 0, 2)
      local result = intraline.pair_changed_lines(additions)
      assert.same({}, result.pairs)
      assert.same({}, result.unpaired_deletions)
      assert.same({ 1, 2 }, result.unpaired_additions)

      local deletions = one_block({ "-one", "-two" }, 2, 0)
      result = intraline.pair_changed_lines(deletions)
      assert.same({}, result.pairs)
      assert.same({ 1, 2 }, result.unpaired_deletions)
      assert.same({}, result.unpaired_additions)
    end)

    it("skips oversized replacement blocks deterministically", function()
      local block = one_block({ "-one", "-two", "+three", "+four" }, 2, 2)
      local first = intraline.pair_changed_lines(block, { max_change_block_lines = 3 })
      local second = intraline.pair_changed_lines(block, { max_change_block_lines = 3 })

      assert.equals("block_too_large", first.skipped_reason)
      assert.same({ 1, 2 }, first.unpaired_deletions)
      assert.same({ 1, 2 }, first.unpaired_additions)
      assert.same(first, second)
    end)
  end)

  describe("plans", function()
    it("attaches old and new ranges to their original hunk rows", function()
      local patch = table.concat({
        "@@ -1,2 +1,2 @@",
        "-old_timeout = calculate_timeout(config)",
        "+new_timeout = calculate_timeout(options)",
        " context",
      }, "\n")
      local hunk = diff.parse_patch(patch)[1]
      local plan = intraline.plan_hunk(hunk)

      assert_ranges({
        { start_col = 0, end_col = 3 },
        { start_col = 32, end_col = 38 },
      }, plan.ranges[1])
      assert_ranges({
        { start_col = 0, end_col = 3 },
        { start_col = 32, end_col = 39 },
      }, plan.ranges[2])
      assert.is_nil(plan.ranges[3])
      assert.equals(1, #plan.pairs)
      assert.same({}, plan.skipped_blocks)
    end)

    it("gives unpaired lines whole-line highlighting only", function()
      local block = one_block({ "-apple", "-banana", "+zebra" }, 2, 1)
      local hunk = { change_blocks = { block } }
      local plan = intraline.plan_hunk(hunk)
      assert.is_nil(plan.ranges[1])
      assert_ranges({ { start_col = 0, end_col = 6 } }, plan.ranges[2])
      assert_ranges({ { start_col = 0, end_col = 5 } }, plan.ranges[3])
    end)

    it("skips a long pair without suppressing shorter pairs in the block", function()
      local content = string.rep("x", 20)
      local block = one_block({
        "-" .. content,
        "-return old;",
        "+" .. string.rep("y", 20),
        "+return new;",
      }, 2, 2)
      local hunk = { change_blocks = { block } }
      local plan = intraline.plan_hunk(hunk, { max_line_length = 15 })

      assert.is_nil(plan.ranges[1])
      assert_ranges({ { start_col = 7, end_col = 10 } }, plan.ranges[2])
      assert.is_nil(plan.ranges[3])
      assert_ranges({ { start_col = 7, end_col = 10 } }, plan.ranges[4])
      assert.equals(2, #plan.pairs)
      assert.same({}, plan.skipped_blocks)
    end)

    it("enforces hunk and file byte budgets", function()
      local patch = table.concat({
        "@@ -1 +1 @@",
        "-old one",
        "+new one",
        "@@ -10 +10 @@",
        "-old two",
        "+new two",
      }, "\n")
      local hunks = diff.parse_patch(patch)

      local hunk_plan = intraline.plan_hunk(hunks[1], { max_hunk_inline_bytes = 5 })
      assert.equals("hunk_budget_exceeded", hunk_plan.skipped_blocks[1].reason)

      local file_plan = intraline.plan_hunks(hunks, { max_file_inline_bytes = 16 })
      assert.equals(14, file_plan.compared_bytes)
      assert.equals("file_budget_exceeded", file_plan.hunks[2].skipped_blocks[1].reason)
    end)

    it("never pairs changes across hunk boundaries", function()
      local patch = table.concat({
        "@@ -1 +1 @@",
        "-first old",
        "+first new",
        "@@ -20 +20 @@",
        "-second old",
        "+second new",
      }, "\n")
      local plan = intraline.plan_hunks(diff.parse_patch(patch))
      assert.equals(1, #plan.hunks[1].pairs)
      assert.equals(1, #plan.hunks[2].pairs)
      assert.equals(1, plan.hunks[1].pairs[1].block_index)
      assert.equals(1, plan.hunks[2].pairs[1].block_index)
    end)
  end)
end)
