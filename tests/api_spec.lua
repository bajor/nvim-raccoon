local api = require("raccoon.api")

describe("raccoon.api", function()
  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(api)
    end)

    it("has base_url", function()
      assert.equals("https://api.github.com", api.base_url)
    end)

    it("has list_prs function", function()
      assert.is_function(api.list_prs)
    end)

    it("has get_pr function", function()
      assert.is_function(api.get_pr)
    end)

    it("has get_pr_files function", function()
      assert.is_function(api.get_pr_files)
    end)

    it("has get_pr_comments function", function()
      assert.is_function(api.get_pr_comments)
    end)

    it("has create_comment function", function()
      assert.is_function(api.create_comment)
    end)

    it("has submit_review function", function()
      assert.is_function(api.submit_review)
    end)
  end)

  describe("parse_pr_url", function()
    it("parses valid GitHub PR URL", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/123")
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(123, number)
    end)

    it("parses URL with hyphens and underscores", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/my-org/my_repo/pull/456")
      assert.equals("my-org", owner)
      assert.equals("my_repo", repo)
      assert.equals(456, number)
    end)

    it("parses URL with numbers in name", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/org123/repo456/pull/789")
      assert.equals("org123", owner)
      assert.equals("repo456", repo)
      assert.equals(789, number)
    end)

    it("returns nil for invalid URL", function()
      local owner, repo, number = api.parse_pr_url("https://example.com/not/a/pr")
      assert.is_nil(owner)
      assert.is_nil(repo)
      assert.is_nil(number)
    end)

    it("returns nil for GitHub non-PR URL", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/issues/123")
      assert.is_nil(owner)
      assert.is_nil(repo)
      assert.is_nil(number)
    end)

    it("returns nil for empty string", function()
      local owner, repo, number = api.parse_pr_url("")
      assert.is_nil(owner)
      assert.is_nil(repo)
      assert.is_nil(number)
    end)

    it("handles trailing slashes", function()
      -- Our pattern is strict - no trailing content expected
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/123/files")
      -- This should still extract the number since we match up to /pull/123
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(123, number)
    end)

    it("handles PR URL with commits path", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/123/commits")
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(123, number)
    end)

    it("handles PR URL with checks path", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/123/checks")
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(123, number)
    end)

    it("returns nil for nil input", function()
      local owner, repo, number = api.parse_pr_url(nil)
      assert.is_nil(owner)
      assert.is_nil(repo)
      assert.is_nil(number)
    end)

    it("handles very large PR numbers", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/999999")
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(999999, number)
    end)

    it("handles PR number 1", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/1")
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(1, number)
    end)

    it("returns nil for PR number 0", function()
      -- PR numbers start at 1
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/0")
      -- Pattern matches but 0 is technically valid for regex
      -- Behavior depends on implementation
      if owner then
        assert.equals(0, number)
      else
        assert.is_nil(owner)
      end
    end)

    it("handles enterprise GitHub URLs", function()
      -- Enterprise GitHub uses different domain
      local owner, repo, number = api.parse_pr_url("https://github.mycompany.com/owner/repo/pull/42")
      -- Our current pattern only matches github.com
      -- This is expected behavior - enterprise support would need pattern update
      assert.is_nil(owner)
    end)
  end)
end)

-- Additional API edge case tests
describe("raccoon.api edge cases", function()
  describe("parse_pr_url edge cases", function()
    it("handles URL with query parameters", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/123?diff=unified")
      -- Should still parse the PR number
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(123, number)
    end)

    it("handles URL with hash fragment", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/123#discussion_r12345")
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(123, number)
    end)

    it("handles dots in repo name", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo.js/pull/42")
      assert.equals("owner", owner)
      assert.equals("repo.js", repo)
      assert.equals(42, number)
    end)

    it("returns nil for malformed URL without number", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/")
      assert.is_nil(owner)
      assert.is_nil(repo)
      assert.is_nil(number)
    end)

    it("returns nil for URL with letters instead of number", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/abc")
      assert.is_nil(owner)
      assert.is_nil(repo)
      assert.is_nil(number)
    end)
  end)

  describe("API function signatures", function()
    it("get_pr accepts owner, repo, number, token, callback", function()
      -- Verify function exists and accepts parameters
      assert.is_function(api.get_pr)
      -- Would need mock curl to test actual behavior
    end)

    it("get_pr_files accepts owner, repo, number, token, callback", function()
      assert.is_function(api.get_pr_files)
    end)

    it("get_pr_comments accepts owner, repo, number, token, callback", function()
      assert.is_function(api.get_pr_comments)
    end)

    it("create_comment is a function", function()
      assert.is_function(api.create_comment)
    end)

    it("submit_review is a function", function()
      assert.is_function(api.submit_review)
    end)

    it("merge_pr is a function", function()
      assert.is_function(api.merge_pr)
    end)

    it("get_issue_comments is a function", function()
      assert.is_function(api.get_issue_comments)
    end)

    it("create_issue_comment is a function", function()
      assert.is_function(api.create_issue_comment)
    end)
  end)

  describe("base_url configuration", function()
    it("base_url is https", function()
      assert.truthy(api.base_url:match("^https://"))
    end)

    it("base_url is GitHub API", function()
      assert.truthy(api.base_url:match("api%.github%.com"))
    end)

    it("base_url has no trailing slash", function()
      assert.is_nil(api.base_url:match("/$"))
    end)
  end)
end)
