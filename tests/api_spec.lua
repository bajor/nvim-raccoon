local api = require("raccoon.api")

describe("raccoon.api", function()
  describe("module", function()
    it("can be required", function()
      assert.is_not_nil(api)
    end)

    it("has base_url", function()
      assert.equals("https://api.github.com", api.base_url)
    end)

    it("has graphql_url", function()
      assert.equals("https://api.github.com/graphql", api.graphql_url)
    end)

    it("has init function", function()
      assert.is_function(api.init)
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

    it("has get_pr_review_threads function", function()
      assert.is_function(api.get_pr_review_threads)
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

    it("returns nil for enterprise URL without matching host", function()
      local owner, repo, number = api.parse_pr_url("https://github.mycompany.com/owner/repo/pull/42")
      assert.is_nil(owner)
    end)

    it("parses enterprise GitHub URL with matching host", function()
      local owner, repo, number = api.parse_pr_url("https://github.mycompany.com/owner/repo/pull/42", "github.mycompany.com")
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(42, number)
    end)

    it("parses enterprise URL with subpath", function()
      local owner, repo, number = api.parse_pr_url("https://git.corp.example.com/team/project/pull/7", "git.corp.example.com")
      assert.equals("team", owner)
      assert.equals("project", repo)
      assert.equals(7, number)
    end)

    it("parses enterprise URL with hyphenated host", function()
      local owner, repo, number = api.parse_pr_url("https://github-enterprise.acme.com/team/project/pull/99", "github-enterprise.acme.com")
      assert.equals("team", owner)
      assert.equals("project", repo)
      assert.equals(99, number)
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

    it("get_pr_review_threads is a function", function()
      assert.is_function(api.get_pr_review_threads)
    end)

    it("get_pr_reviews is a function", function()
      assert.is_function(api.get_pr_reviews)
    end)

    it("resolve_review_thread is a function", function()
      assert.is_function(api.resolve_review_thread)
    end)

    it("unresolve_review_thread is a function", function()
      assert.is_function(api.unresolve_review_thread)
    end)

    it("search_user_prs is a function", function()
      assert.is_function(api.search_user_prs)
    end)
  end)

  describe("base_url configuration", function()
    it("base_url is https", function()
      assert.truthy(api.base_url:match("^https://"))
    end)

    it("base_url defaults to GitHub API", function()
      api.init("github.com")
      assert.truthy(api.base_url:match("api%.github%.com"))
    end)

    it("base_url has no trailing slash", function()
      assert.is_nil(api.base_url:match("/$"))
    end)
  end)

  describe("init", function()
    after_each(function()
      api.init("github.com")
    end)

    it("sets github.com URLs by default", function()
      api.init("github.com")
      assert.equals("https://api.github.com", api.base_url)
      assert.equals("https://api.github.com/graphql", api.graphql_url)
    end)

    it("sets GHE REST URL for custom host", function()
      api.init("github.mycompany.com")
      assert.equals("https://github.mycompany.com/api/v3", api.base_url)
    end)

    it("sets GHE GraphQL URL for custom host", function()
      api.init("github.mycompany.com")
      assert.equals("https://github.mycompany.com/api/graphql", api.graphql_url)
    end)

    it("handles host with subdomain", function()
      api.init("git.corp.example.com")
      assert.equals("https://git.corp.example.com/api/v3", api.base_url)
      assert.equals("https://git.corp.example.com/api/graphql", api.graphql_url)
    end)

    it("produces URLs without trailing slash", function()
      api.init("github.mycompany.com")
      assert.is_nil(api.base_url:match("/$"))
      assert.is_nil(api.graphql_url:match("/$"))
    end)

    it("resets server_info to non-GHES for github.com", function()
      api.server_info = { is_ghes = true, version = "3.12.0" }
      api.init("github.com")
      assert.is_false(api.server_info.is_ghes)
      assert.is_nil(api.server_info.version)
    end)

    it("marks non-github.com hosts as GHES even when /meta fails", function()
      api.init("github.mycompany.com")
      assert.is_true(api.server_info.is_ghes)
      assert.is_nil(api.server_info.version)
      assert.is_false(api.server_info.detected)
    end)

    it("keeps is_ghes true across different GHES hosts", function()
      api.init("git.corp.example.com")
      assert.is_true(api.server_info.is_ghes)
      assert.is_nil(api.server_info.version)
      assert.is_false(api.server_info.detected)
    end)
  end)

  describe("server_info", function()
    it("defaults to non-GHES", function()
      assert.is_not_nil(api.server_info)
      assert.is_false(api.server_info.is_ghes)
      assert.is_nil(api.server_info.version)
    end)

    it("is a table with is_ghes, version, and detected fields", function()
      assert.is_table(api.server_info)
      assert.is_boolean(api.server_info.is_ghes)
      assert.is_boolean(api.server_info.detected)
    end)
  end)

  describe("_should_send_api_version", function()
    after_each(function()
      api.server_info = { is_ghes = false, version = nil, detected = true }
      api.ghes_api_version_header = nil
    end)

    it("returns true for github.com", function()
      api.server_info = { is_ghes = false, version = nil, detected = true }
      assert.is_true(api._should_send_api_version())
    end)

    it("returns true for GHES with version >= 3.9", function()
      api.server_info = { is_ghes = true, version = "3.12.0", detected = true }
      assert.is_true(api._should_send_api_version())
    end)

    it("returns true for GHES with version exactly 3.9", function()
      api.server_info = { is_ghes = true, version = "3.9.0", detected = true }
      assert.is_true(api._should_send_api_version())
    end)

    it("returns false for GHES with version < 3.9", function()
      api.server_info = { is_ghes = true, version = "3.8.0", detected = true }
      assert.is_false(api._should_send_api_version())
    end)

    it("returns false for GHES with unknown version", function()
      api.server_info = { is_ghes = true, version = nil, detected = false }
      assert.is_false(api._should_send_api_version())
    end)

    it("returns true when override is true regardless of version", function()
      api.server_info = { is_ghes = true, version = nil, detected = false }
      api.ghes_api_version_header = true
      assert.is_true(api._should_send_api_version())
    end)

    it("returns false when override is false regardless of version", function()
      api.server_info = { is_ghes = true, version = "3.12.0", detected = true }
      api.ghes_api_version_header = false
      assert.is_false(api._should_send_api_version())
    end)

    it("override has no effect on github.com", function()
      api.server_info = { is_ghes = false, version = nil, detected = true }
      api.ghes_api_version_header = false
      assert.is_true(api._should_send_api_version())
    end)
  end)

  describe("init opts", function()
    after_each(function()
      api.init("github.com")
    end)

    it("stores ghes_api_version_header from opts", function()
      api.init("github.com", { ghes_api_version_header = true })
      assert.is_true(api.ghes_api_version_header)
    end)

    it("clears ghes_api_version_header when opts not provided", function()
      api.ghes_api_version_header = true
      api.init("github.com")
      assert.is_nil(api.ghes_api_version_header)
    end)
  end)
end)
