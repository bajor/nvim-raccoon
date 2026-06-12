local diff = require("raccoon.diff")
local inline_diff = require("raccoon.inline_diff")

local function inline_opts(overrides)
  return vim.tbl_deep_extend("force", vim.deepcopy(require("raccoon.config").defaults.inline_diff), overrides or {})
end

local function byte_range(text, start_char, end_char)
  return {
    start_col = vim.str_byteindex(text, start_char),
    end_col = vim.str_byteindex(text, end_char),
  }
end

local function find_chunk(chunks, text, hl_group)
  for _, chunk in ipairs(chunks) do
    if chunk.text == text and chunk.hl_group == hl_group then
      return chunk
    end
  end
  return nil
end

local function has_inline_virt_line(mark)
  local details = mark[4] or {}
  for _, line in ipairs(details.virt_lines or {}) do
    for _, chunk in ipairs(line) do
      if chunk[2] == "RaccoonDeleteInline" then
        return true
      end
    end
  end
  return false
end

local function has_padded_delete_chunk(mark)
  local details = mark[4] or {}
  for _, line in ipairs(details.virt_lines or {}) do
    for _, chunk in ipairs(line) do
      if chunk[2] == "RaccoonDelete" and chunk[1] and #chunk[1] > 200 then
        return true
      end
    end
  end
  return false
end

local function has_exact_delete_background(mark)
  local details = mark[4] or {}
  for _, line in ipairs(details.virt_lines or {}) do
    for _, chunk in ipairs(line) do
      if chunk[2] == "RaccoonDelete" then
        return true
      end
    end
  end
  return false
end

describe("raccoon.inline_diff", function()
  describe("diff_pair", function()
    it("highlights the exact changed span for identifier rename", function()
      local new_line = "local total_size = item.count"
      local result = inline_diff.diff_pair("local total_count = item.count", new_line, inline_opts())

      assert.same({ byte_range(new_line, 12, 16) }, result.new_ranges)
      assert.is_not_nil(find_chunk(result.old_chunks, "count", "RaccoonDeleteInline"))
    end)

    it("highlights whole changed object names in dotted identifiers", function()
      local old_line = "for _, del in ipairs(changes.deleted) do"
      local new_line = "for _, del in ipairs(plan.deleted) do"
      local result = inline_diff.diff_pair(old_line, new_line, inline_opts())

      assert.same({ byte_range(new_line, 21, 25) }, result.new_ranges)
      assert.is_not_nil(find_chunk(result.old_chunks, "changes", "RaccoonDeleteInline"))
      assert.is_not_nil(find_chunk(result.old_chunks, ".deleted) do", "Normal"))
      assert.is_nil(find_chunk(result.old_chunks, "ch", "RaccoonDeleteInline"))
      assert.is_nil(find_chunk(result.old_chunks, "ges", "RaccoonDeleteInline"))
    end)

    it("highlights punctuation insertion exactly", function()
      local new_line = "return call(foo, bar)"
      local result = inline_diff.diff_pair("return call(foo bar)", new_line, inline_opts())

      assert.same({ byte_range(new_line, 15, 16) }, result.new_ranges)
      assert.equals(0, #vim.tbl_filter(function(chunk)
        return chunk.hl_group == "RaccoonDeleteInline"
      end, result.old_chunks))
    end)

    it("keeps old text neutral when a line only receives an insertion", function()
      local new_line = "Review changed files with exact inline diff highlighting"
      local result = inline_diff.diff_pair("Review changed files with inline diff highlighting", new_line, inline_opts())

      assert.is_true(#result.new_ranges > 0)
      assert.equals(0, #vim.tbl_filter(function(chunk)
        return chunk.hl_group == "RaccoonDelete" or chunk.hl_group == "RaccoonDeleteInline"
      end, result.old_chunks))
    end)

    it("computes UTF-8 replacement ranges as byte columns", function()
      local old_line = 'local icon = "✓"'
      local new_line = 'local icon = "✗"'
      local result = inline_diff.diff_pair(old_line, new_line, inline_opts())

      assert.same({ byte_range(new_line, 14, 15) }, result.new_ranges)
      assert.is_not_nil(find_chunk(result.old_chunks, "✓", "RaccoonDeleteInline"))
    end)

    it("ignores CR at end of line when pairing", function()
      local old_line = "value = 10\r"
      local new_line = "value = 11\r"
      local result = inline_diff.diff_pair(old_line, new_line, inline_opts({ ignore_cr_at_eol = true }))

      assert.same({ byte_range(new_line, 9, 10) }, result.new_ranges)
      assert.is_not_nil(find_chunk(result.old_chunks, "0", "RaccoonDeleteInline"))
      assert.is_nil(find_chunk(result.old_chunks, "\r", "RaccoonDeleteInline"))
    end)

    it("falls back to whole-run highlights when similarity is too low", function()
      local new_line = "zzzzzzzzzz"
      local result = inline_diff.diff_pair("aaaaaaaaaa", new_line, inline_opts({ char_similarity_floor = 0.9 }))

      assert.same({ byte_range(new_line, 0, 10) }, result.new_ranges)
      assert.same({ { text = "aaaaaaaaaa", hl_group = "RaccoonDeleteInline" } }, result.old_chunks)
    end)
  end)

  describe("plan_replacement", function()
    it("pairs replacement lines and includes inline detail", function()
      local rows = inline_diff.plan_replacement(
        { "local total_count = item.count" },
        { "local total_size = item.count" },
        inline_opts()
      )

      assert.equals(1, #rows)
      assert.equals("local total_count = item.count", rows[1].old)
      assert.equals("local total_size = item.count", rows[1].new)
      assert.same({ byte_range(rows[1].new, 12, 16) }, rows[1].inline.new_ranges)
    end)

    it("keeps unmatched old and new rows ordered", function()
      local rows = inline_diff.plan_replacement(
        { "removed one", "removed two" },
        { "added one" },
        inline_opts()
      )

      assert.equals(2, #rows)
      assert.equals("removed one", rows[1].old)
      assert.equals("added one", rows[1].new)
      assert.equals("removed two", rows[2].old)
      assert.is_nil(rows[2].new)
    end)

    it("pairs similar lines when added rows shift a multi-line block", function()
      local rows = inline_diff.plan_replacement(
        {
          "return call(foo bar)",
          "local line_idx = line_num - 1",
        },
        {
          "local ranges = add.ranges or {}",
          "return call(foo, bar)",
          "local line_idx = add.line_num - 1",
        },
        inline_opts()
      )

      assert.equals(3, #rows)
      assert.is_nil(rows[1].old)
      assert.equals("local ranges = add.ranges or {}", rows[1].new)
      assert.equals("return call(foo bar)", rows[2].old)
      assert.equals("return call(foo, bar)", rows[2].new)
      assert.same({ byte_range(rows[2].new, 15, 16) }, rows[2].inline.new_ranges)
      assert.equals("local line_idx = line_num - 1", rows[3].old)
      assert.equals("local line_idx = add.line_num - 1", rows[3].new)
      assert.same({ byte_range(rows[3].new, 17, 21) }, rows[3].inline.new_ranges)
    end)
  end)
end)

describe("raccoon.diff inline render plan", function()
  it("builds inline additions and deleted virtual-line chunks from a replacement block", function()
    local patch = table.concat({
      "@@ -1,3 +1,3 @@",
      " context",
      "-local total_count = item.count",
      "+local total_size = item.count",
      " tail",
    }, "\n")

    local plan = diff.build_render_plan(patch, inline_opts())

    assert.is_false(plan.fallback)
    assert.equals(1, #plan.added)
    assert.equals(2, plan.added[1].line_num)
    assert.same({ byte_range(plan.added[1].content, 12, 16) }, plan.added[1].ranges)
    assert.equals(1, #plan.deleted)
    assert.equals(1, plan.deleted[1].line_num)
    assert.is_not_nil(find_chunk(plan.deleted[1].chunks, "count", "RaccoonDeleteInline"))
    assert.is_nil(find_chunk(plan.deleted[1].chunks, "local total_", "RaccoonDelete"))
  end)

  it("keeps exact ranges when similar lines shift inside a multi-line block", function()
    local patch = table.concat({
      "@@ -1,2 +1,3 @@",
      "-return call(foo bar)",
      "-local line_idx = line_num - 1",
      "+local ranges = add.ranges or {}",
      "+return call(foo, bar)",
      "+local line_idx = add.line_num - 1",
    }, "\n")

    local plan = diff.build_render_plan(patch, inline_opts())

    assert.is_false(plan.fallback)
    assert.equals(3, #plan.added)
    assert.equals("local ranges = add.ranges or {}", plan.added[1].content)
    assert.same({}, plan.added[1].ranges)
    assert.equals("return call(foo, bar)", plan.added[2].content)
    assert.same({ byte_range(plan.added[2].content, 15, 16) }, plan.added[2].ranges)
    assert.equals("local line_idx = add.line_num - 1", plan.added[3].content)
    assert.same({ byte_range(plan.added[3].content, 17, 21) }, plan.added[3].ranges)
  end)

  it("keeps line-only data when inline rendering is disabled", function()
    local patch = table.concat({
      "@@ -1,2 +1,2 @@",
      "-old value",
      "+new value",
    }, "\n")

    local plan = diff.build_render_plan(patch, inline_opts({ enabled = false }))

    assert.is_true(plan.fallback)
    assert.equals(1, #plan.added)
    assert.equals(1, plan.added[1].line_num)
    assert.same({}, plan.added[1].ranges)
    assert.equals(1, #plan.deleted)
    assert.same({ { text = "old value", hl_group = "RaccoonDelete" } }, plan.deleted[1].chunks)
  end)

  it("falls back when changed lines exceed the configured limit", function()
    local lines = { "@@ -1,3 +1,3 @@" }
    for i = 1, 3 do
      table.insert(lines, "-old " .. i)
      table.insert(lines, "+new " .. i)
    end

    local plan = diff.build_render_plan(table.concat(lines, "\n"), inline_opts({ max_changed_lines = 2 }))

    assert.is_true(plan.fallback)
    assert.equals(3, #plan.added)
    assert.equals(3, #plan.deleted)
  end)
end)

describe("raccoon.diff inline highlights", function()
  it("adds exact inline extmarks without whole-line backgrounds", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "context",
      "local total_size = item.count",
      "tail",
    })

    local patch = table.concat({
      "@@ -1,3 +1,3 @@",
      " context",
      "-local total_count = item.count",
      "+local total_size = item.count",
      " tail",
    }, "\n")

    diff.apply_highlights(buf, patch, inline_opts())

    local marks = vim.api.nvim_buf_get_extmarks(buf, diff.get_namespace(), 0, -1, { details = true })
    local saw_added_line = false
    local saw_add_sign = false
    local saw_inline_add = false
    local saw_inline_delete = false
    local saw_padded_delete = false
    local saw_delete_background = false

    for _, mark in ipairs(marks) do
      local details = mark[4] or {}
      if mark[2] == 1 and details.line_hl_group == "RaccoonAdd" then
        saw_added_line = true
      end
      if mark[2] == 1
          and type(details.sign_text) == "string"
          and details.sign_text:match("^%+")
          and details.sign_hl_group == "RaccoonAddSign" then
        saw_add_sign = true
      end
      if mark[2] == 1 and details.hl_group == "RaccoonAddInline" then
        saw_inline_add = saw_inline_add
          or (mark[3] == byte_range("local total_size = item.count", 12, 16).start_col
            and details.end_col == byte_range("local total_size = item.count", 12, 16).end_col)
      end
      saw_inline_delete = saw_inline_delete or has_inline_virt_line(mark)
      saw_padded_delete = saw_padded_delete or has_padded_delete_chunk(mark)
      saw_delete_background = saw_delete_background or has_exact_delete_background(mark)
    end

    assert.is_false(saw_added_line)
    assert.is_true(saw_add_sign)
    assert.is_true(saw_inline_add)
    assert.is_true(saw_inline_delete)
    assert.is_false(saw_padded_delete)
    assert.is_false(saw_delete_background)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("highlights only added content for pure additions in inline mode", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "context",
      "new line",
      "tail",
    })

    local patch = table.concat({
      "@@ -1,2 +1,3 @@",
      " context",
      "+new line",
      " tail",
    }, "\n")

    diff.apply_highlights(buf, patch, inline_opts())

    local marks = vim.api.nvim_buf_get_extmarks(buf, diff.get_namespace(), 0, -1, { details = true })
    local saw_added_line = false
    local saw_add_sign = false
    local saw_content_add = false

    for _, mark in ipairs(marks) do
      local details = mark[4] or {}
      if mark[2] == 1 and details.line_hl_group == "RaccoonAdd" then
        saw_added_line = true
      end
      if mark[2] == 1
          and type(details.sign_text) == "string"
          and details.sign_text:match("^%+")
          and details.sign_hl_group == "RaccoonAddSign" then
        saw_add_sign = true
      end
      if mark[2] == 1 and details.hl_group == "RaccoonAddInline" then
        saw_content_add = saw_content_add
          or (mark[3] == 0 and details.end_col == #"new line")
      end
    end

    assert.is_false(saw_added_line)
    assert.is_true(saw_add_sign)
    assert.is_true(saw_content_add)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)

  it("keeps whole-line backgrounds when inline rendering falls back", function()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "context",
      "new line",
      "tail",
    })

    local patch = table.concat({
      "@@ -1,2 +1,3 @@",
      " context",
      "+new line",
      " tail",
    }, "\n")

    diff.apply_highlights(buf, patch, inline_opts({ enabled = false }))

    local marks = vim.api.nvim_buf_get_extmarks(buf, diff.get_namespace(), 0, -1, { details = true })
    local saw_added_line = false

    for _, mark in ipairs(marks) do
      local details = mark[4] or {}
      if mark[2] == 1 and details.line_hl_group == "RaccoonAdd" then
        saw_added_line = true
      end
    end

    assert.is_true(saw_added_line)

    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
