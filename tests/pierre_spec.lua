local raccoon = require("raccoon")

describe("raccoon.pierre", function()
  local original_config = vim.deepcopy(raccoon.config)
  local original_system

  local function reload_pierre()
    package.loaded["raccoon.pierre"] = nil
    return require("raccoon.pierre")
  end

  before_each(function()
    original_system = vim.system
    raccoon.config.diff_renderer = {
      provider = "auto",
      timeout_ms = 25,
      command = { "node", "stub" },
      inline_word_diff = true,
    }
  end)

  after_each(function()
    vim.system = original_system
    raccoon.config = vim.deepcopy(original_config)
    package.loaded["raccoon.pierre"] = nil
  end)

  it("is disabled in builtin mode", function()
    raccoon.config.diff_renderer.provider = "builtin"
    vim.system = function()
      error("vim.system should not be called when Pierre is disabled")
    end

    local pierre = reload_pierre()
    local plan, err = pierre.render_patch("@@ -1,1 +1,1 @@\n line", "x.lua")

    assert.is_nil(plan)
    assert.equals("disabled", err)
  end)

  it("runs the configured command, decodes JSON, and caches successful plans", function()
    local calls = {}
    vim.system = function(cmd, opts)
      table.insert(calls, { cmd = cmd, opts = opts })
      return {
        wait = function(_, timeout)
          calls[#calls].timeout = timeout
          return {
            code = 0,
            stdout = vim.json.encode({
              version = 1,
              hunks = { { start_line = 10, end_line = 12 } },
              added = { 11 },
              deleted = {},
              reviewable = { 10, 11, 12 },
              inline_add = {},
            }),
            stderr = "",
          }
        end,
      }
    end

    local pierre = reload_pierre()
    local plan, err = pierre.render_patch("@@ -10,2 +10,3 @@\n line\n+new\n line", "x.lua")
    local cached = pierre.render_patch("@@ -10,2 +10,3 @@\n line\n+new\n line", "x.lua")

    assert.is_nil(err)
    assert.equals(1, #calls)
    assert.same({ "node", "stub" }, calls[1].cmd)
    assert.equals(25, calls[1].timeout)
    assert.equals("x.lua", vim.json.decode(calls[1].opts.stdin).filename)
    assert.is_true(vim.json.decode(calls[1].opts.stdin).inline_word_diff)
    assert.is_true(plan.reviewable[10])
    assert.is_true(plan.reviewable[11])
    assert.is_true(plan.reviewable[12])
    assert.same(plan, cached)
  end)

  it("returns an error when the process exits non-zero", function()
    vim.system = function()
      return {
        wait = function()
          return { code = 1, stdout = "", stderr = "missing @pierre/diffs" }
        end,
      }
    end

    local pierre = reload_pierre()
    local plan, err = pierre.render_patch("@@ -1,1 +1,1 @@\n line", "x.lua")

    assert.is_nil(plan)
    assert.equals("missing @pierre/diffs", err)
  end)

  it("returns an error when the process times out", function()
    vim.system = function()
      return {
        wait = function()
          return nil
        end,
      }
    end

    local pierre = reload_pierre()
    local plan, err = pierre.render_patch("@@ -1,1 +1,1 @@\n line", "x.lua")

    assert.is_nil(plan)
    assert.equals("timeout", err)
  end)

  it("returns an error for invalid JSON", function()
    vim.system = function()
      return {
        wait = function()
          return { code = 0, stdout = "{", stderr = "" }
        end,
      }
    end

    local pierre = reload_pierre()
    local plan, err = pierre.render_patch("@@ -1,1 +1,1 @@\n line", "x.lua")

    assert.is_nil(plan)
    assert.equals("invalid json", err)
  end)
end)
