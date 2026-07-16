local jsdiff = require("raccoon.vendor.jsdiff")

-- Behavioral fixtures ported from jsdiff v9.0.0:
-- test/diff/character.js and test/diff/word.js.
-- The originals are BSD-3-Clause; see licenses/jsdiff.txt and vendor/README.md.
local function markup(changes)
  local parts = {}
  for _, change in ipairs(changes) do
    if change.removed then
      table.insert(parts, "<del>" .. change.value .. "</del>")
    elseif change.added then
      table.insert(parts, "<ins>" .. change.value .. "</ins>")
    else
      table.insert(parts, change.value)
    end
  end
  return table.concat(parts)
end

describe("vendored jsdiff 9.0.0 subset", function()
  describe("diff_words_with_space", function()
    it("preserves whitespace changes around replaced words", function()
      local changes = jsdiff.diff_words_with_space("New Value", "New  ValueMoreData")
      assert.equals("New<del> Value</del><ins>  ValueMoreData</ins>", markup(changes))

      changes = jsdiff.diff_words_with_space("New Value  ", "New  ValueMoreData ")
      assert.equals("New<del> Value</del>  <ins>ValueMoreData </ins>", markup(changes))
    end)

    it("keeps punctuation anchors around inserted content", function()
      assert.equals("(<ins>word</ins>)", markup(jsdiff.diff_words_with_space("()", "(word)")))
      assert.equals("[<ins>word</ins>]", markup(jsdiff.diff_words_with_space("[]", "[word]")))
      assert.equals("{<ins>word</ins>}", markup(jsdiff.diff_words_with_space("{}", "{word}")))
    end)

    it("treats LF and CRLF as individual tokens", function()
      local changes = jsdiff.diff_words_with_space("foo\nbar", "foo\n\n\nbar")
      assert.equals("foo\n<ins>\n\n</ins>bar", markup(changes))

      changes = jsdiff.diff_words_with_space("A\r\n\r\nB\r\n", "A\r\nB\r\n")
      assert.equals("A\r\n<del>\r\n</del>B\r\n", markup(changes))
    end)

    it("matches upstream tie-breaking when there is no unique anchor", function()
      local changes = jsdiff.diff_words_with_space("New Value New Value", "Value Value New New")
      assert.equals(
        "<del>New</del><ins>Value</ins> Value New <del>Value</del><ins>New</ins>",
        markup(changes)
      )
    end)

    it("handles empty and Unicode input deterministically", function()
      assert.same({}, jsdiff.diff_words_with_space("", ""))
      local expected = "你好世<del>界</del><ins>间</ins>"
      assert.equals(expected, markup(jsdiff.diff_words_with_space("你好世界", "你好世间")))
      assert.equals(expected, markup(jsdiff.diff_words_with_space("你好世界", "你好世间")))
    end)
  end)

  describe("diff_chars", function()
    it("matches the upstream character fixture", function()
      local changes = jsdiff.diff_chars("Old Value.", "New ValueMoreData.")
      assert.equals("<del>Old</del><ins>New</ins> Value<ins>MoreData</ins>.", markup(changes))
    end)

    it("treats an astral Unicode code point as one character", function()
      local changes = jsdiff.diff_chars("𝟘𝟙𝟚𝟛", "𝟘𝟙𝟚𝟜𝟝𝟞")
      assert.equals("𝟘𝟙𝟚<del>𝟛</del><ins>𝟜𝟝𝟞</ins>", markup(changes))
      assert.equals(1, changes[2].count)
      assert.equals(3, changes[3].count)
    end)

    it("aborts before Myers work exceeds the caller's token-product cap", function()
      local changes, reason = jsdiff.diff_chars("abcd", "wxyz", { max_sequence_product = 15 })
      assert.is_nil(changes)
      assert.equals("comparison_too_large", reason)
    end)

    it("ports upstream maxEditLength fallback", function()
      local changes, reason = jsdiff.diff_chars("abcd", "wxyz", { max_edit_length = 7 })
      assert.is_nil(changes)
      assert.equals("max_edit_length_exceeded", reason)
    end)
  end)
end)
