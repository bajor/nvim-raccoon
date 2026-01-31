describe("raccoon.spinner", function()
  local spinner

  before_each(function()
    spinner = require("raccoon.spinner")
    spinner.stop_all()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(spinner)
    end)

    it("has start function", function()
      assert.is_function(spinner.start)
    end)

    it("has stop function", function()
      assert.is_function(spinner.stop)
    end)

    it("has is_active function", function()
      assert.is_function(spinner.is_active)
    end)

    it("has stop_all function", function()
      assert.is_function(spinner.stop_all)
    end)
  end)

  describe("start", function()
    it("returns a spinner ID", function()
      local id = spinner.start({ message = "Test" })
      assert.is_string(id)
      assert.is_true(#id > 0)
      spinner.stop(id)
    end)

    it("creates an active spinner", function()
      local id = spinner.start({ message = "Test" })
      assert.is_true(spinner.is_active(id))
      spinner.stop(id)
    end)
  end)

  describe("stop", function()
    it("deactivates the spinner", function()
      local id = spinner.start({ message = "Test" })
      spinner.stop(id)
      assert.is_false(spinner.is_active(id))
    end)

    it("handles non-existent ID gracefully", function()
      -- Should not error
      spinner.stop("non-existent-id")
    end)
  end)

  describe("is_active", function()
    it("returns false for non-existent ID", function()
      assert.is_false(spinner.is_active("non-existent"))
    end)

    it("returns true for active spinner", function()
      local id = spinner.start({ message = "Test" })
      assert.is_true(spinner.is_active(id))
      spinner.stop(id)
    end)

    it("returns false after stop", function()
      local id = spinner.start({ message = "Test" })
      spinner.stop(id)
      assert.is_false(spinner.is_active(id))
    end)
  end)

  describe("stop_all", function()
    it("stops all active spinners", function()
      local id1 = spinner.start({ message = "Test 1" })
      local id2 = spinner.start({ message = "Test 2" })

      spinner.stop_all()

      assert.is_false(spinner.is_active(id1))
      assert.is_false(spinner.is_active(id2))
    end)

    it("handles empty state gracefully", function()
      -- Should not error
      spinner.stop_all()
    end)
  end)
end)
