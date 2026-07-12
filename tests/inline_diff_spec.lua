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

local function plan_and_validate(lines)
  local plan = inline_diff.plan(lines)
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

  it("keeps low-similarity lines as separate whole-content changes", function()
    local lines = {
      deletion("local count = calculate_total(items)"),
      addition("raise RuntimeError('connection unavailable')"),
    }

    local plan = plan_and_validate(lines)

    assert.equals(2, #plan.rows)
    assert.is_nil(find_row(plan, "replacement"))
    assert.same({ range(0, #lines[1].content) }, find_row(plan, "deletion", 1).old_ranges)
    assert.same({ range(0, #lines[2].content) }, find_row(plan, "addition", nil, 2).new_ranges)
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

  it("uses subdued-only rows when a mixed block exceeds the line-pair cell cap", function()
    local lines = {}
    for index = 1, 65 do table.insert(lines, deletion("local value_" .. index .. " = old")) end
    for index = 1, 64 do table.insert(lines, addition("local value_" .. index .. " = new")) end

    local plan = plan_and_validate(lines)

    assert.equals(129, #plan.rows)
    for _, row in ipairs(plan.rows) do
      assert.is_not_equal("replacement", row.kind)
      assert.same({}, row.old_ranges or row.new_ranges)
    end
  end)

  it("uses subdued rows when aggregate line-similarity work reaches its cap", function()
    local lines = {}
    for index = 1, 64 do
      table.insert(lines, deletion(string.format("local old_value_%02d = source_%02d", index, index)))
    end
    for index = 1, 64 do
      table.insert(lines, addition(string.format("local new_value_%02d = source_%02d", index, index)))
    end

    local plan = plan_and_validate(lines)

    assert.equals(128, #plan.rows)
    for _, row in ipairs(plan.rows) do
      assert.is_not_equal("replacement", row.kind)
      assert.same({}, row.old_ranges or row.new_ranges)
    end
  end)

  it("uses a subdued replacement when a line exceeds the token-count cap", function()
    local old_parts, new_parts = {}, {}
    for index = 1, 129 do
      table.insert(old_parts, "item")
      table.insert(new_parts, "item")
      if index < 129 then
        table.insert(old_parts, " ")
        table.insert(new_parts, index == 65 and "\t" or " ")
      end
    end
    local lines = {
      deletion(table.concat(old_parts)),
      addition(table.concat(new_parts)),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({}, row.old_ranges)
    assert.same({}, row.new_ranges)
  end)

  it("uses a subdued replacement when token LCS cells exceed the cap", function()
    local old_parts, new_parts = {}, {}
    for index = 1, 65 do
      table.insert(old_parts, "item")
      table.insert(new_parts, "item")
      if index < 65 then
        table.insert(old_parts, " ")
        table.insert(new_parts, index == 33 and "\t" or " ")
      end
    end
    local lines = {
      deletion(table.concat(old_parts)),
      addition(table.concat(new_parts)),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({}, row.old_ranges)
    assert.same({}, row.new_ranges)
  end)

  it("uses a subdued replacement when character refinement cells exceed the cap", function()
    local lines = {
      deletion("prefix" .. string.rep(" ", 129) .. "suffix"),
      addition("prefix" .. string.rep("\t", 129) .. "suffix"),
    }

    local row = plan_and_validate(lines).rows[1]

    assert.equals("replacement", row.kind)
    assert.same({}, row.old_ranges)
    assert.same({}, row.new_ranges)
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
  end)
end)
