local inline_diff = require("raccoon.inline_diff")

local function addition(content)
  return { kind = "addition", type = "add", content = content }
end

local function deletion(content)
  return { kind = "deletion", type = "del", content = content }
end

local function context(content)
  return { kind = "context", type = "ctx", content = content }
end

local function range(start_col, end_col)
  return { start_col = start_col, end_col = end_col }
end

local function plan_and_validate(lines, options)
  local plan = inline_diff.plan(lines, options)
  local valid, reason = inline_diff.validate(plan, lines)
  assert.is_true(valid, reason)
  assert.is_nil(reason)
  return plan
end

local function find_row(plan, kind, old_index, new_index)
  for _, row in ipairs(plan.rows) do
    if row.kind == kind
        and (old_index == nil or row.old_index == old_index)
        and (new_index == nil or row.new_index == new_index) then
      return row
    end
  end
  return nil
end

local function content_outside_ranges(content, ranges)
  local parts = {}
  local cursor = 0
  for _, item in ipairs(ranges) do
    table.insert(parts, content:sub(cursor + 1, item.start_col))
    cursor = item.end_col
  end
  table.insert(parts, content:sub(cursor + 1))
  return table.concat(parts)
end

describe("raccoon.inline_diff", function()
  describe("diff 9.0.0 character semantics", function()
    local frozen_cases = {
      {
        name = "substitution",
        old = "kitten",
        new = "sitten",
        old_ranges = { range(0, 1) },
        new_ranges = { range(0, 1) },
      },
      {
        name = "insertion",
        old = "abc",
        new = "axbc",
        old_ranges = {},
        new_ranges = { range(1, 2) },
      },
      {
        name = "deletion",
        old = "axbc",
        new = "abc",
        old_ranges = { range(1, 2) },
        new_ranges = {},
      },
      {
        name = "identifier",
        old = "local total_count = item.count",
        new = "local total_size = item.count",
        old_ranges = { range(12, 17) },
        new_ranges = { range(12, 16) },
      },
      {
        name = "number",
        old = "value = 10",
        new = "value = 11",
        old_ranges = { range(9, 10) },
        new_ranges = { range(9, 10) },
      },
      {
        name = "punctuation",
        old = "return call(foo bar)",
        new = "return call(foo, bar)",
        old_ranges = {},
        new_ranges = { range(15, 16) },
      },
      {
        name = "tab to spaces",
        old = "\tvalue = 1",
        new = "  value = 1",
        old_ranges = { range(0, 1) },
        new_ranges = { range(0, 2) },
      },
      {
        name = "inserted spaces",
        old = "local value=1",
        new = "local value = 1",
        old_ranges = {},
        new_ranges = { range(11, 12), range(13, 14) },
      },
      {
        name = "ambiguous swap",
        old = "ab",
        new = "ba",
        old_ranges = { range(0, 1) },
        new_ranges = { range(1, 2) },
      },
      {
        name = "ambiguous repeated subsequence",
        old = "aba",
        new = "aab",
        old_ranges = { range(1, 2) },
        new_ranges = { range(2, 3) },
      },
      {
        name = "repeated insertion",
        old = "aaa",
        new = "aaaa",
        old_ranges = {},
        new_ranges = { range(3, 4) },
      },
      {
        name = "empty old input",
        old = "",
        new = "abc",
        old_ranges = {},
        new_ranges = { range(0, 3) },
      },
      {
        name = "empty new input",
        old = "abc",
        new = "",
        old_ranges = { range(0, 3) },
        new_ranges = {},
      },
      {
        name = "BMP text",
        old = "café",
        new = "cafe",
        old_ranges = { range(3, 5) },
        new_ranges = { range(3, 4) },
      },
      {
        name = "emoji",
        old = "😀a",
        new = "😀b",
        old_ranges = { range(4, 5) },
        new_ranges = { range(4, 5) },
      },
      {
        name = "combining character",
        old = "é",
        new = "é",
        old_ranges = { range(0, 3) },
        new_ranges = { range(0, 2) },
      },
      {
        name = "ZWJ sequence",
        old = "👩‍💻",
        new = "👨‍💻",
        old_ranges = { range(0, 4) },
        new_ranges = { range(0, 4) },
      },
      {
        name = "skin-tone modifier",
        old = "👍",
        new = "👍🏽",
        old_ranges = {},
        new_ranges = { range(4, 8) },
      },
    }

    for _, case in ipairs(frozen_cases) do
      it("matches frozen output for " .. case.name, function()
        local row = plan_and_validate({ deletion(case.old), addition(case.new) }, {
          clock = function() return 0 end,
        }).rows[1]

        assert.equals("replacement", row.kind)
        assert.same(case.old_ranges, row.old_ranges)
        assert.same(case.new_ranges, row.new_ranges)
        assert.equals(
          content_outside_ranges(row.old_content, row.old_ranges),
          content_outside_ranges(row.new_content, row.new_ranges)
        )
      end)
    end

    it("normalizes trailing carriage returns before diffing", function()
      local row = plan_and_validate({ deletion("value = 10\r"), addition("value = 12\r") }).rows[1]

      assert.equals("value = 10", row.old_content)
      assert.equals("value = 12", row.new_content)
      assert.same({ range(9, 10) }, row.old_ranges)
      assert.same({ range(9, 10) }, row.new_ranges)
    end)
  end)

  describe("positional change-block pairing", function()
    it("pairs deletion and addition lines by ordinal position", function()
      local plan = plan_and_validate({
        deletion("alpha"),
        deletion("beta"),
        addition("inserted"),
        addition("alpha"),
        addition("beta"),
      })

      assert.is_not_nil(find_row(plan, "replacement", 1, 3))
      assert.is_not_nil(find_row(plan, "replacement", 2, 4))
      assert.is_not_nil(find_row(plan, "addition", nil, 5))
    end)

    it("does not perform move or similarity matching", function()
      local plan = plan_and_validate({
        deletion("first"),
        deletion("second"),
        addition("second"),
        addition("first"),
      })

      assert.is_not_nil(find_row(plan, "replacement", 1, 3))
      assert.is_not_nil(find_row(plan, "replacement", 2, 4))
    end)

    it("leaves surplus deletions fully bright", function()
      local plan = plan_and_validate({
        deletion("old one"),
        deletion("old two"),
        addition("new one"),
      })

      assert.is_not_nil(find_row(plan, "replacement", 1, 3))
      assert.same({ range(0, #"old two") }, find_row(plan, "deletion", 2).old_ranges)
    end)

    it("leaves surplus additions fully bright", function()
      local plan = plan_and_validate({
        deletion("old one"),
        addition("new one"),
        addition("new two"),
      })

      assert.is_not_nil(find_row(plan, "replacement", 1, 2))
      assert.same({ range(0, #"new two") }, find_row(plan, "addition", nil, 3).new_ranges)
    end)

    it("pairs repeated lines deterministically by position", function()
      local plan = plan_and_validate({
        deletion("same"),
        deletion("same"),
        addition("same"),
        addition("same!"),
      })

      assert.is_not_nil(find_row(plan, "replacement", 1, 3))
      assert.is_not_nil(find_row(plan, "replacement", 2, 4))
    end)

    it("starts a new block at each context line", function()
      local plan = plan_and_validate({
        deletion("old"),
        context("unchanged"),
        addition("new"),
      })

      assert.is_nil(find_row(plan, "replacement"))
      assert.is_not_nil(find_row(plan, "deletion", 1))
      assert.is_not_nil(find_row(plan, "addition", nil, 3))
    end)

    it("pairs case-only function changes ordinally", function()
      local plan = plan_and_validate({
        deletion("FOO()"),
        deletion("BAR()"),
        addition("foo()"),
        addition("bar()"),
      })

      local foo = find_row(plan, "replacement", 1, 3)
      local bar = find_row(plan, "replacement", 2, 4)
      assert.same({ range(0, 3) }, foo.old_ranges)
      assert.same({ range(0, 3) }, foo.new_ranges)
      assert.same({ range(0, 3) }, bar.old_ranges)
      assert.same({ range(0, 3) }, bar.new_ranges)
    end)
  end)

  describe("Pierre line-length suppression", function()
    it("processes exactly 1000 ASCII UTF-16 units", function()
      local prefix = string.rep("a", 999)
      local row = plan_and_validate({ deletion(prefix .. "x"), addition(prefix .. "y") }, {
        clock = function() return 0 end,
      }).rows[1]

      assert.equals("replacement", row.kind)
      assert.same({ range(999, 1000) }, row.old_ranges)
      assert.same({ range(999, 1000) }, row.new_ranges)
    end)

    it("suppresses 1001 ASCII UTF-16 units without failing the plan", function()
      local prefix = string.rep("a", 1000)
      local row = plan_and_validate({ deletion(prefix .. "x"), addition(prefix .. "y") }).rows[1]

      assert.equals("suppressed_replacement", row.kind)
      assert.is_nil(row.old_ranges)
      assert.is_nil(row.new_ranges)
    end)

    it("counts non-BMP code points as two UTF-16 units at the 1000-unit boundary", function()
      local prefix = string.rep("😀", 499)
      local row = plan_and_validate({ deletion(prefix .. "👍"), addition(prefix .. "👎") }, {
        clock = function() return 0 end,
      }).rows[1]
      local changed_start = #prefix

      assert.equals("replacement", row.kind)
      assert.same({ range(changed_start, changed_start + 4) }, row.old_ranges)
      assert.same({ range(changed_start, changed_start + 4) }, row.new_ranges)
    end)

    it("suppresses a non-BMP line with 1001 UTF-16 units", function()
      local prefix = string.rep("😀", 500)
      local row = plan_and_validate({ deletion(prefix .. "x"), addition(prefix .. "y") }).rows[1]

      assert.equals("suppressed_replacement", row.kind)
    end)

    it("keeps exact spans for later pairs after a suppressed pair", function()
      local long_prefix = string.rep("a", 1000)
      local plan = plan_and_validate({
        deletion(long_prefix .. "x"),
        deletion("abc"),
        addition(long_prefix .. "y"),
        addition("axc"),
      })

      assert.is_not_nil(find_row(plan, "suppressed_replacement", 1, 3))
      local exact = find_row(plan, "replacement", 2, 4)
      assert.same({ range(1, 2) }, exact.old_ranges)
      assert.same({ range(1, 2) }, exact.new_ranges)
    end)
  end)

  describe("deadline behavior", function()
    it("interrupts character planning when the injected deadline expires", function()
      local clock_calls = 0
      local function advancing_clock()
        clock_calls = clock_calls + 1
        return clock_calls >= 4 and 501 or 0
      end
      local lines = {
        deletion(string.rep("a", 999) .. "b"),
        addition(string.rep("a", 999) .. "c"),
      }

      local plan, reason = inline_diff.plan(lines, { timeout_ms = 500, clock = advancing_clock })

      assert.is_nil(plan)
      assert.matches("budget exceeded", reason)
    end)

    it("discards all earlier group plans when a later group reaches the deadline", function()
      local clock_calls = 0
      local function later_group_timeout()
        clock_calls = clock_calls + 1
        return clock_calls >= 4 and 501 or 0
      end

      local plans, reason = inline_diff.plan_many({
        { addition("first") },
        { addition("second") },
      }, { timeout_ms = 500, clock = later_group_timeout })

      assert.is_nil(plans)
      assert.matches("budget exceeded", reason)
    end)
  end)

  it("gives pure additions and deletions whole-content bright ranges", function()
    local plan = plan_and_validate({
      deletion("removed line"),
      context("unchanged"),
      addition("added line"),
      addition(""),
    })

    assert.same({ range(0, #"removed line") }, find_row(plan, "deletion", 1).old_ranges)
    assert.same({ range(0, #"added line") }, find_row(plan, "addition", nil, 3).new_ranges)
    assert.same({}, find_row(plan, "addition", nil, 4).new_ranges)
  end)

  describe("validate", function()
    it("rejects invalid row discriminants and side combinations", function()
      local invalid_kind = { rows = { { kind = "context" } } }
      local invalid_side = {
        rows = {
          {
            kind = "addition",
            old_index = 1,
            old_line = deletion("removed"),
            old_content = "removed",
            old_ranges = { range(0, 7) },
            new_index = 2,
            new_line = addition("added"),
            new_content = "added",
            new_ranges = { range(0, 5) },
          },
        },
      }

      local valid_kind, kind_reason = inline_diff.validate(invalid_kind)
      local valid_side, side_reason = inline_diff.validate(invalid_side)

      assert.is_false(valid_kind)
      assert.matches("invalid kind", kind_reason)
      assert.is_false(valid_side)
      assert.matches("cannot contain an old side", side_reason)
    end)

    it("rejects overlapping, out-of-bounds, and mismatched-source ranges", function()
      local lines = { addition("added") }
      local overlapping = {
        rows = {
          {
            kind = "addition",
            new_index = 1,
            new_line = lines[1],
            new_content = "added",
            new_ranges = { range(0, 3), range(2, 5) },
          },
        },
      }
      local out_of_bounds = vim.deepcopy(overlapping)
      out_of_bounds.rows[1].new_line = lines[1]
      out_of_bounds.rows[1].new_ranges = { range(0, 6) }
      local wrong_source = vim.deepcopy(overlapping)
      wrong_source.rows[1].new_line = addition("added")
      wrong_source.rows[1].new_ranges = { range(0, 5) }

      local valid_overlap, overlap_reason = inline_diff.validate(overlapping, lines)
      local valid_bounds, bounds_reason = inline_diff.validate(out_of_bounds, lines)
      local valid_source, source_reason = inline_diff.validate(wrong_source, lines)

      assert.is_false(valid_overlap)
      assert.matches("overlap", overlap_reason)
      assert.is_false(valid_bounds)
      assert.matches("outside content", bounds_reason)
      assert.is_false(valid_source)
      assert.matches("source index", source_reason)
    end)

    it("rejects plans that omit or duplicate a changed source line", function()
      local lines = { deletion("removed"), addition("added") }
      local deletion_row = {
        kind = "deletion",
        old_index = 1,
        old_line = lines[1],
        old_content = "removed",
        old_ranges = { range(0, 7) },
      }
      local missing = { rows = { deletion_row } }
      local duplicate = {
        rows = {
          deletion_row,
          deletion_row,
          {
            kind = "addition",
            new_index = 2,
            new_line = lines[2],
            new_content = "added",
            new_ranges = { range(0, 5) },
          },
        },
      }

      local valid_missing, missing_reason = inline_diff.validate(missing, lines)
      local valid_duplicate, duplicate_reason = inline_diff.validate(duplicate, lines)

      assert.is_false(valid_missing)
      assert.matches("missing", missing_reason)
      assert.is_false(valid_duplicate)
      assert.matches("more than once", duplicate_reason)
    end)

    it("rejects replacements whose unhighlighted content differs", function()
      local lines = { deletion("abc"), addition("xyz") }
      local plan = {
        rows = {
          {
            kind = "replacement",
            old_index = 1,
            old_line = lines[1],
            old_content = "abc",
            old_ranges = { range(1, 2) },
            new_index = 2,
            new_line = lines[2],
            new_content = "xyz",
            new_ranges = { range(1, 2) },
          },
        },
      }

      local valid, reason = inline_diff.validate(plan, lines)

      assert.is_false(valid)
      assert.matches("outside ranges", reason)
    end)

    it("accepts suppression only for an over-limit pair without ranges", function()
      local lines = { deletion("short"), addition("other") }
      local invalid = {
        rows = {
          {
            kind = "suppressed_replacement",
            old_index = 1,
            old_line = lines[1],
            old_content = "short",
            new_index = 2,
            new_line = lines[2],
            new_content = "other",
          },
        },
      }

      local valid, reason = inline_diff.validate(invalid, lines)

      assert.is_false(valid)
      assert.matches("over%-limit", reason)
    end)
  end)
end)
