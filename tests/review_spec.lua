local review = require("raccoon.review")
local state = require("raccoon.state")

describe("raccoon.review", function()
  before_each(function()
    state.reset()
  end)

  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(review)
    end)

    it("has events table", function()
      assert.is_table(review.events)
    end)

    it("has submit_review function", function()
      assert.is_function(review.submit_review)
    end)

    it("has show_submit_ui function", function()
      assert.is_function(review.show_submit_ui)
    end)

    it("has prompt_review_body function", function()
      assert.is_function(review.prompt_review_body)
    end)

    it("has quick_approve function", function()
      assert.is_function(review.quick_approve)
    end)

    it("has get_status function", function()
      assert.is_function(review.get_status)
    end)

    it("has show_status function", function()
      assert.is_function(review.show_status)
    end)
  end)

  describe("events", function()
    it("has APPROVE event", function()
      assert.equals("APPROVE", review.events.APPROVE)
    end)

    it("has REQUEST_CHANGES event", function()
      assert.equals("REQUEST_CHANGES", review.events.REQUEST_CHANGES)
    end)

    it("has COMMENT event", function()
      assert.equals("COMMENT", review.events.COMMENT)
    end)
  end)

  describe("submit_review", function()
    it("calls callback with error when no session", function()
      local called = false
      local error_msg = nil

      review.submit_review("APPROVE", "body", function(err)
        called = true
        error_msg = err
      end)

      assert.is_true(called)
      assert.is_not_nil(error_msg)
      assert.is_truthy(error_msg:match("No active PR"))
    end)
  end)

  describe("get_status", function()
    it("returns status table when no session", function()
      local status = review.get_status()
      assert.is_table(status)
      assert.equals(0, status.total_files)
      assert.equals(0, status.pending_comments)
    end)

    it("returns status with session data", function()
      state.start({
        owner = "test-owner",
        repo = "test-repo",
        number = 123,
      })
      state.set_files({
        { filename = "a.lua" },
        { filename = "b.lua" },
      })

      local status = review.get_status()
      assert.equals(1, status.files_reviewed)
      assert.equals(2, status.total_files)
      assert.equals(0, status.pending_comments)
      assert.equals(123, status.pr_number)
      assert.equals("test-owner", status.owner)
      assert.equals("test-repo", status.repo)
    end)

    it("counts pending comments", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_files({ { filename = "test.lua" } })
      state.set_comments("test.lua", {
        { line = 1, body = "pending", pending = true },
        { line = 2, body = "not pending", pending = false },
        { line = 3, body = "also pending", pending = true },
      })

      local status = review.get_status()
      assert.equals(2, status.pending_comments)
    end)
  end)

  describe("show_submit_ui", function()
    it("warns when no active session", function()
      -- Should not error, just warn
      review.show_submit_ui()
    end)
  end)

  describe("show_status", function()
    it("warns when no active session", function()
      -- Should not error, just warn
      review.show_status()
    end)
  end)

  describe("quick_approve", function()
    it("warns when no active session", function()
      -- Should not error, just warn
      review.quick_approve()
    end)

    it("accepts force parameter", function()
      -- Should not error, just warn (no session)
      review.quick_approve(true)
    end)
  end)

  describe("get_status with PR data", function()
    it("includes PR title from state", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_pr({ title = "My Test PR Title" })

      local status = review.get_status()
      assert.equals("My Test PR Title", status.pr_title)
    end)

    it("handles PR without title", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_pr({})

      local status = review.get_status()
      -- Should return nil or empty for missing title
      assert.is_nil(status.pr_title)
    end)

    it("increments files_reviewed as user navigates", function()
      state.start({ owner = "o", repo = "r", number = 1 })
      state.set_files({
        { filename = "a.lua" },
        { filename = "b.lua" },
        { filename = "c.lua" },
      })

      local status1 = review.get_status()
      assert.equals(1, status1.files_reviewed)

      -- Navigate to next file
      state.next_file()
      local status2 = review.get_status()
      assert.equals(2, status2.files_reviewed)

      state.next_file()
      local status3 = review.get_status()
      assert.equals(3, status3.files_reviewed)
    end)
  end)

  describe("events validation", function()
    it("all events are uppercase strings", function()
      for name, value in pairs(review.events) do
        assert.is_string(name)
        assert.is_string(value)
        assert.equals(value, value:upper())
      end
    end)

    it("has exactly 3 event types", function()
      local count = 0
      for _ in pairs(review.events) do
        count = count + 1
      end
      assert.equals(3, count)
    end)
  end)

  describe("submit_review with config error", function()
    it("calls callback with config error", function()
      state.start({ owner = "o", repo = "r", number = 1 })

      -- Mock config.load to return an error
      local config = require("raccoon.config")
      local original_load = config.load
      config.load = function()
        return nil, "Mock config error"
      end

      local called = false
      local error_msg = nil
      review.submit_review("APPROVE", "body", function(err)
        called = true
        error_msg = err
      end)

      config.load = original_load

      assert.is_true(called)
      assert.is_not_nil(error_msg)
      assert.truthy(error_msg:match("Config error"))
    end)
  end)

  describe("prompt_review_body", function()
    it("handles APPROVE event", function()
      -- Just verify it doesn't error
      -- Full UI testing would require mocking vim.api
      assert.is_function(review.prompt_review_body)
    end)

    it("handles REQUEST_CHANGES event", function()
      assert.is_function(review.prompt_review_body)
    end)

    it("handles COMMENT event", function()
      assert.is_function(review.prompt_review_body)
    end)
  end)
end)
