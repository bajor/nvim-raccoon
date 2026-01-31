--- End-to-end workflow tests for PR review system
--- These tests simulate a complete PR review workflow without actual network calls

local state = require("raccoon.state")
local diff = require("raccoon.diff")
local comments = require("raccoon.comments")

-- Mock PR data
local mock_pr = {
  id = 1,
  number = 42,
  title = "Add new feature",
  body = "This PR adds an important feature.",
  state = "open",
  html_url = "https://github.com/test/repo/pull/42",
  user = { id = 1, login = "contributor", avatar_url = nil },
  head = { ref = "feature-branch", sha = "abc123def456" },
  base = { ref = "main", sha = "def456abc123" },
  created_at = "2026-01-01T00:00:00Z",
  updated_at = "2026-01-01T12:00:00Z",
}

-- Mock files
local mock_files = {
  {
    sha = "abc123",
    filename = "src/main.lua",
    status = "modified",
    additions = 10,
    deletions = 5,
    changes = 15,
    patch = "@@ -1,5 +1,10 @@\n local M = {}\n-local old = true\n+local new = false\n+local added = 1\n return M",
  },
  {
    sha = "def456",
    filename = "src/utils.lua",
    status = "added",
    additions = 20,
    deletions = 0,
    changes = 20,
    patch = "@@ -0,0 +1,20 @@\n+-- New utility file\n+local M = {}\n+return M",
  },
  {
    sha = "ghi789",
    filename = "README.md",
    status = "modified",
    additions = 2,
    deletions = 1,
    changes = 3,
    patch = "@@ -1,3 +1,4 @@\n # Project\n-Old description\n+New description\n+More info",
  },
}

-- Mock comments
local mock_comments = {
  ["src/main.lua"] = {
    { id = 1, path = "src/main.lua", line = 3, body = "Why change this?", user = { login = "reviewer1" } },
    { id = 2, path = "src/main.lua", line = 5, body = "Add a test for this", user = { login = "reviewer2" } },
  },
  ["src/utils.lua"] = {
    { id = 3, path = "src/utils.lua", line = 1, body = "Nice utility!", user = { login = "reviewer1" } },
  },
  ["README.md"] = {},
}

describe("E2E: PR review workflow", function()
  before_each(function()
    state.reset()
  end)

  after_each(function()
    state.reset()
  end)

  describe("Session lifecycle", function()
    it("initializes session correctly", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 42,
        url = "https://github.com/test/repo/pull/42",
        clone_path = "/tmp/test/repo/pr-42",
      })

      assert.is_true(state.is_active())
      assert.equals("test", state.get_owner())
      assert.equals("repo", state.get_repo())
      assert.equals(42, state.get_number())
    end)

    it("sets PR data", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 42,
        url = "https://github.com/test/repo/pull/42",
        clone_path = "/tmp/test/repo/pr-42",
      })

      state.set_pr(mock_pr)

      local pr = state.get_pr()
      assert.equals(42, pr.number)
      assert.equals("Add new feature", pr.title)
      assert.equals("feature-branch", pr.head.ref)
    end)

    it("sets files", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 42,
        url = "https://github.com/test/repo/pull/42",
        clone_path = "/tmp/test/repo/pr-42",
      })

      state.set_files(mock_files)

      local files = state.get_files()
      assert.equals(3, #files)
      assert.equals("src/main.lua", files[1].filename)
    end)

    it("sets comments per file", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 42,
        url = "https://github.com/test/repo/pull/42",
        clone_path = "/tmp/test/repo/pr-42",
      })

      state.set_files(mock_files)

      for filename, file_comments in pairs(mock_comments) do
        state.set_comments(filename, file_comments)
      end

      local main_comments = state.get_comments("src/main.lua")
      assert.equals(2, #main_comments)

      local utils_comments = state.get_comments("src/utils.lua")
      assert.equals(1, #utils_comments)

      local readme_comments = state.get_comments("README.md")
      assert.equals(0, #readme_comments)
    end)
  end)

  describe("File navigation", function()
    before_each(function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 42,
        url = "https://github.com/test/repo/pull/42",
        clone_path = "/tmp/test/repo/pr-42",
      })
      state.set_pr(mock_pr)
      state.set_files(mock_files)
    end)

    it("tracks current file index via navigation", function()
      -- State starts with file index at 1
      assert.equals(1, state.get_current_file_index())

      -- Navigate to next file
      state.next_file()
      assert.equals(2, state.get_current_file_index())

      state.next_file()
      assert.equals(3, state.get_current_file_index())
    end)

    it("gets current file", function()
      -- First file
      local file = state.get_current_file()
      assert.equals("src/main.lua", file.filename)
      assert.equals("modified", file.status)

      -- Navigate to second file
      state.next_file()
      file = state.get_current_file()
      assert.equals("src/utils.lua", file.filename)
      assert.equals("added", file.status)
    end)

    it("stops at boundaries without wrapping", function()
      -- Navigate to last file
      local success = state.next_file() -- 2
      assert.is_true(success)
      success = state.next_file() -- 3
      assert.is_true(success)
      assert.equals(3, state.get_current_file_index())

      -- Next returns false at boundary, stays at 3
      success = state.next_file()
      assert.is_false(success)
      assert.equals(3, state.get_current_file_index())

      -- prev_file works similarly
      success = state.prev_file() -- 2
      assert.is_true(success)
      state.prev_file() -- 1
      success = state.prev_file() -- stays at 1
      assert.is_false(success)
      assert.equals(1, state.get_current_file_index())
    end)
  end)

  describe("Comment tracking", function()
    before_each(function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 42,
        url = "https://github.com/test/repo/pull/42",
        clone_path = "/tmp/test/repo/pr-42",
      })
      state.set_pr(mock_pr)
      state.set_files(mock_files)
      for filename, file_comments in pairs(mock_comments) do
        state.set_comments(filename, file_comments)
      end
    end)

    it("counts total comments", function()
      local total = 0
      for _, file in ipairs(state.get_files()) do
        local file_comments = state.get_comments(file.filename)
        total = total + #file_comments
      end
      assert.equals(3, total)
    end)

    it("can add pending comment", function()
      local main_comments = state.get_comments("src/main.lua")
      table.insert(main_comments, {
        id = nil, -- Pending comments have no ID yet
        path = "src/main.lua",
        line = 10,
        body = "My new comment",
        user = { login = "me" },
        pending = true,
      })
      state.set_comments("src/main.lua", main_comments)

      local pending = comments.get_pending_comments()
      assert.equals(1, #pending)
      assert.equals("My new comment", pending[1].body)
    end)

    it("can clear pending comments after submit", function()
      local main_comments = state.get_comments("src/main.lua")
      table.insert(main_comments, {
        id = nil,
        path = "src/main.lua",
        line = 10,
        body = "My pending comment",
        pending = true,
      })
      state.set_comments("src/main.lua", main_comments)

      -- Simulate submit - mark as not pending, add ID
      main_comments = state.get_comments("src/main.lua")
      for i, comment in ipairs(main_comments) do
        if comment.pending then
          main_comments[i].pending = false
          main_comments[i].id = 999 -- ID from server
        end
      end
      state.set_comments("src/main.lua", main_comments)

      local pending = comments.get_pending_comments()
      assert.equals(0, #pending)
    end)
  end)

  describe("Diff parsing integration", function()
    it("parses hunk headers correctly", function()
      -- parse_hunk_header returns new_start, new_count (for the + side)
      local header = "@@ -1,5 +1,10 @@"
      local new_start, new_count = diff.parse_hunk_header(header)
      assert.equals(1, new_start)
      assert.equals(10, new_count)
    end)

    it("handles patch with additions and deletions", function()
      local patch = "@@ -1,3 +1,4 @@\n local M = {}\n-local old = true\n+local new = false\n+local added = 1\n return M"
      local changed = diff.get_changed_lines(patch)
      assert.is_table(changed)
    end)
  end)

  describe("Session cleanup", function()
    it("resets state on close", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 42,
        url = "https://github.com/test/repo/pull/42",
        clone_path = "/tmp/test/repo/pr-42",
      })
      state.set_pr(mock_pr)
      state.set_files(mock_files)

      assert.is_true(state.is_active())

      state.stop()

      assert.is_false(state.is_active())
      assert.is_nil(state.get_pr())
      assert.equals(0, #state.get_files())
    end)

    it("clears comments on reset", function()
      state.start({
        owner = "test",
        repo = "repo",
        number = 42,
        url = "https://github.com/test/repo/pull/42",
        clone_path = "/tmp/test/repo/pr-42",
      })
      state.set_files(mock_files)
      state.set_comments("src/main.lua", mock_comments["src/main.lua"])

      state.reset()

      local main_comments = state.get_comments("src/main.lua")
      assert.equals(0, #main_comments)
    end)
  end)
end)

describe("E2E: Multiple PR sessions", function()
  it("handles switching between PRs", function()
    -- First PR
    state.start({
      owner = "owner1",
      repo = "repo1",
      number = 1,
      url = "https://github.com/owner1/repo1/pull/1",
      clone_path = "/tmp/owner1/repo1/pr-1",
    })
    state.set_pr({ number = 1, title = "PR One", head = { ref = "branch1", sha = "sha1" }, base = { ref = "main" } })

    assert.equals("owner1", state.get_owner())
    assert.equals(1, state.get_number())

    -- Switch to second PR
    state.reset()
    state.start({
      owner = "owner2",
      repo = "repo2",
      number = 2,
      url = "https://github.com/owner2/repo2/pull/2",
      clone_path = "/tmp/owner2/repo2/pr-2",
    })
    state.set_pr({ number = 2, title = "PR Two", head = { ref = "branch2", sha = "sha2" }, base = { ref = "main" } })

    assert.equals("owner2", state.get_owner())
    assert.equals(2, state.get_number())

    -- Original PR data should not persist
    local pr = state.get_pr()
    assert.equals(2, pr.number)
    assert.equals("PR Two", pr.title)
  end)
end)

describe("E2E: Edge cases", function()
  before_each(function()
    state.reset()
  end)

  it("handles PR with no files", function()
    state.start({
      owner = "test",
      repo = "repo",
      number = 42,
      url = "https://github.com/test/repo/pull/42",
      clone_path = "/tmp/test",
    })
    state.set_files({})

    local files = state.get_files()
    assert.equals(0, #files)
    assert.is_nil(state.get_current_file())
  end)

  it("handles PR with many files", function()
    state.start({
      owner = "test",
      repo = "repo",
      number = 42,
      url = "https://github.com/test/repo/pull/42",
      clone_path = "/tmp/test",
    })

    local many_files = {}
    for i = 1, 100 do
      table.insert(many_files, {
        filename = string.format("file%03d.lua", i),
        status = "modified",
      })
    end
    state.set_files(many_files)

    local files = state.get_files()
    assert.equals(100, #files)

    -- Navigate to file 50 (starting at 1, need 49 next_file calls)
    for _ = 1, 49 do
      state.next_file()
    end
    local file = state.get_current_file()
    assert.equals("file050.lua", file.filename)
  end)

  it("handles files with many comments", function()
    state.start({
      owner = "test",
      repo = "repo",
      number = 42,
      url = "https://github.com/test/repo/pull/42",
      clone_path = "/tmp/test",
    })
    state.set_files({ { filename = "test.lua" } })

    local many_comments = {}
    for i = 1, 50 do
      table.insert(many_comments, {
        id = i,
        path = "test.lua",
        line = i,
        body = string.format("Comment %d", i),
      })
    end
    state.set_comments("test.lua", many_comments)

    local file_comments = state.get_comments("test.lua")
    assert.equals(50, #file_comments)
  end)
end)
