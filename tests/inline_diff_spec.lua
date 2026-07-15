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

local function plan_and_validate(lines, options)
  local plan = inline_diff.plan(lines, options)
  local valid, reason = inline_diff.validate(plan, lines)
  assert.is_true(valid, reason)
  assert.is_nil(reason)
  return plan
end

local function row_signature(row)
  return {
    kind = row.kind,
    old_index = row.old_index,
    new_index = row.new_index,
    old_ranges = row.old_ranges,
    new_ranges = row.new_ranges,
  }
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
  it("pairs similar lines after an inserted line without index pairing", function()
    local lines = {
      deletion("return call(foo bar)"),
      deletion("local line_idx = line_num - 1"),
      addition("local ranges = add.ranges or {}"),
      addition("return call(foo, bar)"),
      addition("local line_idx = add.line_num - 1"),
    }

    local plan = plan_and_validate(lines)
    local punctuation_pair = find_row(plan, "replacement", 1, 4)
    local identifier_pair = find_row(plan, "replacement", 2, 5)

    assert.is_not_nil(punctuation_pair)
    assert.same({}, punctuation_pair.old_ranges)
    assert.same({ range(15, 16) }, punctuation_pair.new_ranges)
    assert.is_not_nil(identifier_pair)
    assert.is_not_nil(find_row(plan, "addition", nil, 3))
  end)

  it("keeps unrelated one-to-one lines as a readable whole-content replacement", function()
    local lines = {
      deletion("local count = calculate_total(items)"),
      addition("raise RuntimeError('connection unavailable')"),
    }

    local first = plan_and_validate(lines)
    local second = plan_and_validate(lines)
    local row = first.rows[1]

    assert.equals(1, #first.rows)
    assert.equals("replacement", row.kind)
    assert.same({ range(0, #lines[1].content) }, row.old_ranges)
    assert.same({ range(0, #lines[2].content) }, row.new_ranges)
    assert.same(row_signature(row), row_signature(second.rows[1]))
  end)

  it("resolves repeated ambiguous input deterministically", function()
    local lines = {
      deletion("value = repeat(alpha)"),
      deletion("value = repeat(beta)"),
      deletion("value = repeat(alpha)"),
      addition("value = repeat(alpha)"),
      addition("value = repeat(alpha)"),
      addition("value = repeat(beta)"),
    }

    local first = plan_and_validate(lines)
    local second = plan_and_validate(lines)
    local first_signature, second_signature = {}, {}
    for _, row in ipairs(first.rows) do table.insert(first_signature, row_signature(row)) end
    for _, row in ipairs(second.rows) do table.insert(second_signature, row_signature(row)) end

    assert.same(first_signature, second_signature)
  end)

  it("keeps the earliest common prefix when repeated characters are ambiguous", function()
    local lines = {
      deletion("value = 10"),
      addition("value = 11"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(9, 10) }, row.old_ranges)
    assert.same({ range(9, 10) }, row.new_ranges)
  end)

  it("pairs a short insertion that has few shared character bigrams", function()
    local lines = {
      deletion("abc"),
      addition("axbc"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({}, row.old_ranges)
    assert.same({ range(1, 2) }, row.new_ranges)
  end)

  it("highlights an inserted punctuation codepoint exactly", function()
    local lines = {
      deletion("return call(foo bar)"),
      addition("return call(foo, bar)"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({}, row.old_ranges)
    assert.same({ range(15, 16) }, row.new_ranges)
  end)

  it("keeps unchanged call punctuation outside a short identifier replacement", function()
    local lines = {
      deletion("foo()"),
      addition("bar()"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(0, 3) }, row.old_ranges)
    assert.same({ range(0, 3) }, row.new_ranges)
  end)

  it("keeps an unchanged terminator outside a short identifier replacement", function()
    local lines = {
      deletion("foo;"),
      addition("bar;"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(0, 3) }, row.old_ranges)
    assert.same({ range(0, 3) }, row.new_ranges)
  end)

  it("keeps internal punctuation outside a short low-similarity replacement", function()
    local row = plan_and_validate({ deletion("a.b"), addition("x.y") }).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(0, 1), range(2, 3) }, row.old_ranges)
    assert.same({ range(0, 1), range(2, 3) }, row.new_ranges)
  end)

  it("keeps internal punctuation outside a short UTF-8 replacement", function()
    local row = plan_and_validate({ deletion("α.β"), addition("γ.δ") }).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(0, 2), range(3, 5) }, row.old_ranges)
    assert.same({ range(0, 2), range(3, 5) }, row.new_ranges)
  end)

  it("keeps long low-similarity singleton replacements conservative", function()
    local old_content = string.rep("a", 33) .. "." .. string.rep("b", 33)
    local new_content = string.rep("x", 33) .. "." .. string.rep("y", 33)
    local row = plan_and_validate({ deletion(old_content), addition(new_content) }).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(0, #old_content) }, row.old_ranges)
    assert.same({ range(0, #new_content) }, row.new_ranges)
  end)

  it("refines a short identifier without shared token anchors", function()
    local row = plan_and_validate({ deletion("ab"), addition("ac") }).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(1, 2) }, row.old_ranges)
    assert.same({ range(1, 2) }, row.new_ranges)
  end)

  it("refines a changed identifier to its differing suffix", function()
    local lines = {
      deletion("local total_count = item.count"),
      addition("local total_size = item.count"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(12, 17) }, row.old_ranges)
    assert.same({ range(12, 16) }, row.new_ranges)
  end)

  it("includes inserted spaces in final spans while ignoring them for line pairing", function()
    local lines = {
      deletion("local value=1"),
      addition("local value = 1"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({}, row.old_ranges)
    assert.same({ range(11, 12), range(13, 14) }, row.new_ranges)
  end)

  it("highlights a tab-to-spaces replacement on both sides", function()
    local lines = {
      deletion("\tvalue = 1"),
      addition("  value = 1"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(0, 1) }, row.old_ranges)
    assert.same({ range(0, 2) }, row.new_ranges)
  end)

  it("returns zero-based end-exclusive UTF-8 byte columns", function()
    local lines = {
      deletion('local icon = "✓"'),
      addition('local icon = "✗"'),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(14, 17) }, row.old_ranges)
    assert.same({ range(14, 17) }, row.new_ranges)
  end)

  it("normalizes trailing carriage returns before matching and range validation", function()
    local lines = {
      deletion("value = 10\r"),
      addition("value = 12\r"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("value = 10", row.old_content)
    assert.equals("value = 12", row.new_content)
    assert.same({ range(9, 10) }, row.old_ranges)
    assert.same({ range(9, 10) }, row.new_ranges)
  end)

  it("leaves identical content outside ranges for representative one-to-one edits", function()
    local cases = {
      { old = "abc", new = "axbc" },
      { old = "alpha\tbeta", new = "alphabeta" },
      { old = 'local icon = "✓"', new = 'local icon = "🚀"' },
    }

    for _, case in ipairs(cases) do
      local lines = { deletion(case.old), addition(case.new) }
      local first = plan_and_validate(lines, { clock = function() return 0 end })
      local second = plan_and_validate(lines, { clock = function() return 0 end })
      local row = first.rows[1]

      assert.equals("replacement", row.kind)
      assert.equals(
        content_outside_ranges(row.old_content, row.old_ranges),
        content_outside_ranges(row.new_content, row.new_ranges)
      )
      assert.same(row_signature(row), row_signature(second.rows[1]))
    end
  end)

  it("plans large replacement blocks that fit the raised line-pair cap", function()
    local lines = {}
    for index = 1, 65 do table.insert(lines, deletion("local value_" .. index .. " = old")) end
    for index = 1, 64 do table.insert(lines, addition("local value_" .. index .. " = new")) end

    local plan = plan_and_validate(lines, { clock = function() return 0 end })
    local replacements = 0
    for _, row in ipairs(plan.rows) do
      if row.kind == "replacement" then replacements = replacements + 1 end
    end

    assert.equals(65, #plan.rows)
    assert.equals(64, replacements)
  end)

  it("does not reject exact pairing because of a fixed aggregate cell budget", function()
    local lines = {}
    for index = 1, 64 do
      table.insert(lines, deletion(string.format("local old_value_%02d = source_%02d", index, index)))
    end
    for index = 1, 64 do
      table.insert(lines, addition(string.format("local new_value_%02d = source_%02d", index, index)))
    end

    local plan = plan_and_validate(lines, { clock = function() return 0 end })

    assert.equals(64, #plan.rows)
    for _, row in ipairs(plan.rows) do
      assert.equals("replacement", row.kind)
    end
  end)

  it("returns no plan when a mixed block exceeds the hard line-pair cap", function()
    local lines = {}
    for index = 1, 129 do table.insert(lines, deletion("old " .. index)) end
    for index = 1, 128 do table.insert(lines, addition("new " .. index)) end

    local plan, reason = inline_diff.plan(lines, { clock = function() return 0 end })

    assert.is_nil(plan)
    assert.matches("budget exceeded", reason)
  end)

  it("returns no plan when a line exceeds the hard token-count cap", function()
    local old_parts, new_parts = {}, {}
    for index = 1, 1025 do
      table.insert(old_parts, "item")
      table.insert(new_parts, "item")
      if index < 1025 then
        table.insert(old_parts, " ")
        table.insert(new_parts, index == 513 and "\t" or " ")
      end
    end
    local lines = {
      deletion(table.concat(old_parts)),
      addition(table.concat(new_parts)),
    }

    local plan, reason = inline_diff.plan(lines, { clock = function() return 0 end })

    assert.is_nil(plan)
    assert.matches("budget exceeded", reason)
  end)

  it("refines token-heavy lines that exceeded the previous safety cap", function()
    local old_parts, new_parts = {}, {}
    for index = 1, 300 do
      table.insert(old_parts, "item")
      table.insert(new_parts, "item")
      if index < 300 then
        table.insert(old_parts, " ")
        table.insert(new_parts, index == 150 and "\t" or " ")
      end
    end
    local lines = {
      deletion(table.concat(old_parts)),
      addition(table.concat(new_parts)),
    }

    local row = plan_and_validate(lines, { clock = function() return 0 end }).rows[1]

    assert.equals("replacement", row.kind)
    assert.equals(1, #row.old_ranges)
    assert.equals(1, row.old_ranges[1].end_col - row.old_ranges[1].start_col)
    assert.equals(1, #row.new_ranges)
    assert.equals(1, row.new_ranges[1].end_col - row.new_ranges[1].start_col)
  end)

  it("refines long identifiers that exceeded the previous character cap", function()
    local changed_col = #"prefix_" + 300
    local lines = {
      deletion("prefix_" .. string.rep("a", 300) .. "x_suffix"),
      addition("prefix_" .. string.rep("a", 300) .. "y_suffix"),
    }

    local row = plan_and_validate(lines, { clock = function() return 0 end }).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({ range(changed_col, changed_col + 1) }, row.old_ranges)
    assert.same({ range(changed_col, changed_col + 1) }, row.new_ranges)
  end)

  it("returns no plan when character LCS memory would exceed its hard cap", function()
    local lines = {
      deletion(string.rep("a", 2049)),
      addition(string.rep("a", 2048) .. "b"),
    }

    local plan, reason = inline_diff.plan(lines, { clock = function() return 0 end })

    assert.is_nil(plan)
    assert.matches("budget exceeded", reason)
  end)

  it("interrupts exact LCS work when the injected deadline expires", function()
    local clock_calls = 0
    local function advancing_clock()
      clock_calls = clock_calls + 1
      return clock_calls >= 4 and 501 or 0
    end
    local lines = {
      deletion(string.rep("a", 1024) .. "b"),
      addition(string.rep("a", 1024) .. "c"),
    }

    local plan, reason = inline_diff.plan(lines, { timeout_ms = 500, clock = advancing_clock })

    assert.is_nil(plan)
    assert.matches("budget exceeded", reason)
    assert.equals(4, clock_calls)
  end)

  it("discards earlier group plans when a later group reaches the deadline", function()
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

  it("gives pure additions and deletions whole-content bright ranges", function()
    local lines = {
      deletion("removed line"),
      context("unchanged"),
      addition("added line"),
      addition(""),
    }

    local plan = plan_and_validate(lines)

    assert.same({ range(0, #"removed line") }, find_row(plan, "deletion", 1).old_ranges)
    assert.same({ range(0, #"added line") }, find_row(plan, "addition", nil, 3).new_ranges)
    assert.same({}, find_row(plan, "addition", nil, 4).new_ranges)
  end)

  describe("validate", function()
    it("rejects invalid row discriminants and side combinations", function()
      local add_line = addition("added")
      local invalid_kind = { rows = { { kind = "context" } } }
      local invalid_side = {
        rows = {
          {
            kind = "addition",
            old_index = 1,
            old_line = deletion("removed"),
            old_content = "removed",
            old_ranges = { range(0, 7) },
            new_index = 1,
            new_line = add_line,
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
      local missing = {
        rows = {
          {
            kind = "deletion",
            old_index = 1,
            old_line = lines[1],
            old_content = "removed",
            old_ranges = { range(0, 7) },
          },
        },
      }
      local duplicate = {
        rows = {
          missing.rows[1],
          missing.rows[1],
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
  end)
end)
