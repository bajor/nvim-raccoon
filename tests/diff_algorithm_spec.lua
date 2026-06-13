local algo = require("raccoon.diff_algorithm")

local function byte_range(text, start_char, end_char)
  return {
    start_col = vim.str_byteindex(text, start_char),
    end_col = vim.str_byteindex(text, end_char),
  }
end

local function find_chunk(chunks, text, kind)
  for _, chunk in ipairs(chunks) do
    if chunk.text == text and chunk.kind == kind then
      return chunk
    end
  end
  return nil
end

describe("raccoon.diff_algorithm", function()
  it("diffs sequences with stable equal anchors", function()
    local edits = algo.diff_sequence(
      { "}", "local a = 1", "}", "return a" },
      { "}", "local b = 1", "}", "return b" },
      { mode = "line" }
    )

    local equal_count = 0
    for _, edit in ipairs(edits) do
      if edit.kind == "equal" then
        equal_count = equal_count + 1
      end
    end

    assert.is_true(equal_count >= 2)
  end)

  it("finds shifted similar lines without index pairing", function()
    local old = { "return call(foo bar)", "local line_idx = line_num - 1" }
    local new = { "local ranges = add.ranges or {}", "return call(foo, bar)", "local line_idx = add.line_num - 1" }

    local pairs = algo.pair_lines(old, new)

    assert.is_nil(pairs[1].old_index)
    assert.equals(1, pairs[1].new_index)
    assert.equals(1, pairs[2].old_index)
    assert.equals(2, pairs[2].new_index)
    assert.equals(2, pairs[3].old_index)
    assert.equals(3, pairs[3].new_index)
  end)

  it("does not pair low-similarity replacement lines", function()
    local pairs = algo.pair_lines({ "removed one" }, { "added one" })

    assert.equals(2, #pairs)
    assert.equals(1, pairs[1].old_index)
    assert.is_nil(pairs[1].new_index)
    assert.is_nil(pairs[2].old_index)
    assert.equals(1, pairs[2].new_index)
  end)

  it("returns UTF-8 byte ranges for changed characters", function()
    local new_line = 'local icon = "✗"'
    local result = algo.diff_inline('local icon = "✓"', new_line)

    assert.same({ byte_range(new_line, 14, 15) }, result.new_ranges)
    assert.is_not_nil(find_chunk(result.old_chunks, "✓", "del"))
    assert.is_true(result.exact)
  end)

  it("highlights punctuation insertion exactly", function()
    local new_line = "return call(foo, bar)"
    local result = algo.diff_inline("return call(foo bar)", new_line)

    assert.same({ byte_range(new_line, 15, 16) }, result.new_ranges)
    assert.is_nil(find_chunk(result.old_chunks, ",", "del"))
  end)

  it("highlights only removed punctuation in old chunks", function()
    local result = algo.diff_inline("return call(foo, bar)", "return call(foo bar)")

    assert.same({}, result.new_ranges)
    assert.same({
      { text = "return call(foo", kind = "same" },
      { text = ",", kind = "del" },
      { text = " bar)", kind = "same" },
    }, result.old_chunks)
  end)

  it("keeps whole identifier object names instead of tiny shared character matches", function()
    local old_line = "for _, del in ipairs(changes.deleted) do"
    local new_line = "for _, del in ipairs(plan.deleted) do"
    local result = algo.diff_inline(old_line, new_line)

    assert.same({ byte_range(new_line, 21, 25) }, result.new_ranges)
    assert.is_not_nil(find_chunk(result.old_chunks, "changes", "del"))
    assert.is_nil(find_chunk(result.old_chunks, "ch", "del"))
    assert.is_nil(find_chunk(result.old_chunks, "ges", "del"))
  end)
end)
