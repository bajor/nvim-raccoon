local diff = require("raccoon.diff")
local plan = require("raccoon.diff_plan")

local function byte_range(text, start_char, end_char)
  return {
    start_col = vim.str_byteindex(text, start_char),
    end_col = vim.str_byteindex(text, end_char),
  }
end

describe("raccoon.diff_plan", function()
  it("builds exact replacement rows from patch hunks", function()
    local hunks = diff.parse_patch(table.concat({
      "@@ -1,1 +1,1 @@",
      "-local total_count = item.count",
      "+local total_size = item.count",
    }, "\n"))

    local render = plan.from_hunks(hunks)

    assert.equals("exact", render.mode)
    assert.equals(1, #render.rows)
    assert.equals("local total_count = item.count", render.rows[1].old_line.content)
    assert.equals("local total_size = item.count", render.rows[1].new_line.content)
    assert.is_true(render.rows[1].exact)
    assert.same({ byte_range(render.rows[1].new_line.content, 12, 16) }, render.rows[1].new_ranges)
  end)

  it("uses the same planner shape for commit line lists", function()
    local render = plan.from_line_list({
      { type = "del", content = "return call(foo bar)" },
      { type = "add", content = "return call(foo, bar)" },
    })

    assert.equals("exact", render.mode)
    assert.equals(1, #render.rows)
    assert.equals(0, render.rows[1].old_line.buf_row)
    assert.equals(1, render.rows[1].new_line.buf_row)
    assert.is_true(render.rows[1].exact)
    assert.same({ byte_range(render.rows[1].new_line.content, 15, 16) }, render.rows[1].new_ranges)
  end)

  it("keeps shifted added rows before similar replacement pairs", function()
    local render = plan.from_line_list({
      { type = "del", content = "return call(foo bar)" },
      { type = "del", content = "local line_idx = line_num - 1" },
      { type = "add", content = "local ranges = add.ranges or {}" },
      { type = "add", content = "return call(foo, bar)" },
      { type = "add", content = "local line_idx = add.line_num - 1" },
    })

    assert.equals(3, #render.rows)
    assert.is_nil(render.rows[1].old_line)
    assert.equals("local ranges = add.ranges or {}", render.rows[1].new_line.content)
    assert.equals("return call(foo bar)", render.rows[2].old_line.content)
    assert.equals("return call(foo, bar)", render.rows[2].new_line.content)
    assert.equals("local line_idx = line_num - 1", render.rows[3].old_line.content)
    assert.equals("local line_idx = add.line_num - 1", render.rows[3].new_line.content)
  end)

  it("marks pure additions and deletions as whole-line inline ranges in exact mode", function()
    local render = plan.from_line_list({
      { type = "del", content = "removed" },
      { type = "ctx", content = "context" },
      { type = "add", content = "added" },
    })

    assert.equals(2, #render.rows)
    assert.same({ { text = "removed", kind = "del" } }, render.rows[1].old_chunks)
    assert.same({}, render.rows[1].new_ranges)
    assert.same({ { start_col = 0, end_col = #"added" } }, render.rows[2].new_ranges)
  end)

  it("keeps line mode available as an internal fallback", function()
    local render = plan.from_line_list({
      { type = "del", content = "old value" },
      { type = "add", content = "new value" },
    }, { mode = "line" })

    assert.equals("line", render.mode)
    assert.equals(2, #render.rows)
    assert.is_false(render.rows[1].exact)
    assert.is_false(render.rows[2].exact)
    assert.same({}, render.rows[2].new_ranges)
  end)
end)
