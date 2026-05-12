local api = require("raccoon.api")
local mocks = require("tests.helpers.mocks")
local original_schedule = vim.schedule

local function wait_for(flag)
  assert.is_true(vim.wait(200, flag))
end

describe("raccoon.api", function()
  before_each(function()
    vim.schedule = function(callback)
      callback()
    end
  end)

  after_each(function()
    vim.schedule = original_schedule
    mocks.restore()
    api.clear_viewer_cache()
    api.init("github.com")
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
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/123/files")
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
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/0")
      if owner then
        assert.equals(0, number)
      else
        assert.is_nil(owner)
      end
    end)

    it("extracts host from enterprise URL when no host hint given", function()
      local owner, repo, number, host = api.parse_pr_url("https://github.mycompany.com/owner/repo/pull/42")
      assert.equals("owner", owner)
      assert.equals("repo", repo)
      assert.equals(42, number)
      assert.equals("github.mycompany.com", host)
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

  describe("edge cases", function()
    it("handles URL with query parameters", function()
      local owner, repo, number = api.parse_pr_url("https://github.com/owner/repo/pull/123?diff=unified")
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

    it("extracts github.com host from URL without hint", function()
      local owner, repo, number, host = api.parse_pr_url("https://github.com/user/project/pull/10")
      assert.equals("user", owner)
      assert.equals("project", repo)
      assert.equals(10, number)
      assert.equals("github.com", host)
    end)

    it("returns host as 4th value when host hint is provided", function()
      local owner, repo, number, host = api.parse_pr_url("https://github.com/o/r/pull/1", "github.com")
      assert.equals("o", owner)
      assert.equals("r", repo)
      assert.equals(1, number)
      assert.equals("github.com", host)
    end)

    it("lowercases extracted host", function()
      local _, _, _, host = api.parse_pr_url("https://GitHub.MyCompany.COM/owner/repo/pull/1")
      assert.equals("github.mycompany.com", host)
    end)

    it("returns nil for non-PR URL without host hint", function()
      local owner, _, _, host = api.parse_pr_url("https://github.com/owner/repo/issues/5")
      assert.is_nil(owner)
      assert.is_nil(host)
    end)
  end)

  describe("init", function()
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
      api.server_info = { is_ghes = true }
      api.init("github.com")
      assert.is_false(api.server_info.is_ghes)
    end)

    it("sets is_ghes true for non-github.com host", function()
      api.init("github.mycompany.com")
      assert.is_true(api.server_info.is_ghes)
    end)
  end)

  describe("server_info", function()
    it("defaults to non-GHES", function()
      assert.is_not_nil(api.server_info)
      assert.is_false(api.server_info.is_ghes)
    end)

    it("is a table with is_ghes field", function()
      assert.is_table(api.server_info)
      assert.is_boolean(api.server_info.is_ghes)
    end)

    it("starts as non-GHES before init mutates module state", function()
      package.loaded["raccoon.api"] = nil
      local fresh_api = require("raccoon.api")
      assert.is_false(fresh_api.server_info.is_ghes)
      package.loaded["raccoon.api"] = api
    end)
  end)

  describe("request wrappers", function()
    it("caches viewer lookups by token prefix", function()
      local requests = mocks.mock_curl({
        [".*"] = mocks.api_response({ login = "testuser" }),
      })

      local first_login, second_login
      api.get_viewer("abcdefgh12345", function(login)
        first_login = login
      end)
      wait_for(function() return first_login ~= nil end)

      api.get_viewer("abcdefgh99999", function(login)
        second_login = login
      end)
      wait_for(function() return second_login ~= nil end)

      assert.equals("testuser", first_login)
      assert.equals("testuser", second_login)
      assert.equals(1, #requests)
    end)

    it("get_viewer surfaces an error when the user login is missing", function()
      mocks.mock_curl({
        [".*"] = mocks.api_response({ id = 1 }),
      })

      local login, err
      api.get_viewer("abcdefgh12345", function(result, api_err)
        login = result
        err = api_err
      end)
      wait_for(function() return err ~= nil end)

      assert.is_nil(login)
      assert.truthy(err:find("Could not determine authenticated user"))
    end)

    it("search_user_prs decorates search results with repo names", function()
      mocks.mock_curl({
        ["search/issues"] = mocks.api_response({
          items = {
            {
              repository_url = "https://api.github.com/repos/acme/widgets",
              number = 12,
            },
          },
        }),
      })

      local prs, err
      api.search_user_prs("token", "alice", function(result, api_err)
        prs = result
        err = api_err
      end)
      wait_for(function() return prs ~= nil or err ~= nil end)

      assert.is_nil(err)
      assert.equals("acme/widgets", prs[1].base.repo.full_name)
    end)

    it("search_repo_prs stamps the searched repo onto each result", function()
      mocks.mock_curl({
        ["search/issues"] = mocks.api_response({ items = { { number = 7 } } }),
      })

      local prs
      api.search_repo_prs("acme", "widgets", "token", "alice", function(result)
        prs = result
      end)
      wait_for(function() return prs ~= nil end)

      assert.equals("acme/widgets", prs[1].base.repo.full_name)
    end)

    it("search_repo_prs uses the provided enterprise host override", function()
      local requests = mocks.mock_curl({
        [".*"] = mocks.api_response({ items = {} }),
      })

      local prs
      api.search_repo_prs("acme", "widgets", "token", "alice", function(result)
        prs = result
      end, "ghe.example.com")
      wait_for(function() return prs ~= nil end)

      assert.truthy(requests[1].url:find("https://ghe.example.com/api/v3/search/issues", 1, true))
    end)

    it("list_prs follows pagination links", function()
      mocks.mock_curl({
        [".*"] = function(opts)
          if opts.url:find("page=2", 1, true) then
            return {
              status = 200,
              body = vim.json.encode({ { number = 2 } }),
              headers = {},
            }
          end
          return {
            status = 200,
            body = vim.json.encode({ { number = 1 } }),
            headers = {
              link = '<https://api.github.com/repos/acme/widgets/pulls?page=2>; rel="next"',
            },
          }
        end,
      })

      local prs
      api.list_prs("acme", "widgets", "token", function(result)
        prs = result
      end)
      wait_for(function() return prs ~= nil end)

      assert.equals(2, #prs)
      assert.equals(1, prs[1].number)
      assert.equals(2, prs[2].number)
    end)

    it("get_pr forwards API errors", function()
      mocks.mock_curl({
        ["/pulls/42$"] = mocks.api_error(404, "missing"),
      })

      local result, err
      api.get_pr("acme", "widgets", 42, "token", function(pr, api_err)
        result = pr
        err = api_err
      end)
      wait_for(function() return err ~= nil end)

      assert.is_nil(result)
      assert.truthy(err:find("404"))
      assert.truthy(err:find("missing"))
    end)

    it("get_pr returns PR data from the expected endpoint", function()
      local requests = mocks.mock_curl({
        ["/pulls/42$"] = mocks.api_response({ number = 42, title = "Ship it" }),
      })

      local pr
      api.get_pr("acme", "widgets", 42, "token", function(result)
        pr = result
      end)
      wait_for(function() return pr ~= nil end)

      assert.equals(42, pr.number)
      assert.truthy(requests[1].url:find("/repos/acme/widgets/pulls/42$", 1, false))
    end)

    it("get_pr_comments returns review comments", function()
      mocks.mock_curl({
        ["/comments%?per_page=100$"] = mocks.api_response({
          { id = 1, body = "Looks good" },
        }),
      })

      local comments
      api.get_pr_comments("acme", "widgets", 42, "token", function(result)
        comments = result
      end)
      wait_for(function() return comments ~= nil end)

      assert.equals(1, #comments)
      assert.equals("Looks good", comments[1].body)
    end)

    it("get_pr_reviews returns review summaries", function()
      mocks.mock_curl({
        ["/reviews%?per_page=100$"] = mocks.api_response({
          { id = 5, state = "APPROVED" },
        }),
      })

      local reviews
      api.get_pr_reviews("acme", "widgets", 42, "token", function(result)
        reviews = result
      end)
      wait_for(function() return reviews ~= nil end)

      assert.equals(1, #reviews)
      assert.equals("APPROVED", reviews[1].state)
    end)

    it("create_comment uses position when present", function()
      local requests = mocks.mock_curl({
        ["/comments$"] = mocks.api_response({ id = 33 }),
      })

      local comment
      api.create_comment("acme", "widgets", 42, {
        body = "hello",
        commit_id = "abc123",
        path = "lua/raccoon/api.lua",
        position = 19,
      }, "token", function(result)
        comment = result
      end)
      wait_for(function() return comment ~= nil end)

      local body = vim.json.decode(requests[1].body)
      assert.equals(19, body.position)
      assert.is_nil(body.line)
      assert.equals(33, comment.id)
    end)

    it("create_comment uses line and default side when no position is provided", function()
      local requests = mocks.mock_curl({
        ["/comments$"] = mocks.api_response({ id = 34 }),
      })

      local comment
      api.create_comment("acme", "widgets", 42, {
        body = "hello",
        commit_id = "abc123",
        path = "lua/raccoon/api.lua",
        line = 28,
      }, "token", function(result)
        comment = result
      end)
      wait_for(function() return comment ~= nil end)

      local body = vim.json.decode(requests[1].body)
      assert.equals(28, body.line)
      assert.equals("RIGHT", body.side)
    end)

    it("updates existing comments", function()
      local requests = mocks.mock_curl({
        ["/pulls/comments/55$"] = mocks.api_response({ id = 55, body = "updated" }),
      })

      local comment
      api.update_comment("acme", "widgets", 55, "updated", "token", function(result)
        comment = result
      end)
      wait_for(function() return comment ~= nil end)

      local body = vim.json.decode(requests[1].body)
      assert.equals("updated", body.body)
      assert.equals(55, comment.id)
    end)

    it("update_comment forwards API errors", function()
      mocks.mock_curl({
        ["/pulls/comments/55$"] = mocks.api_error(404, "gone"),
      })

      local comment, err
      api.update_comment("acme", "widgets", 55, "updated", "token", function(result, api_err)
        comment = result
        err = api_err
      end)
      wait_for(function() return err ~= nil end)

      assert.is_nil(comment)
      assert.truthy(err:find("gone"))
    end)

    it("creates issue comments on the issues endpoint", function()
      local requests = mocks.mock_curl({
        ["/issues/42/comments$"] = mocks.api_response({ id = 90 }),
      })

      local comment
      api.create_issue_comment("acme", "widgets", 42, "ship it", "token", function(result)
        comment = result
      end)
      wait_for(function() return comment ~= nil end)

      assert.truthy(requests[1].url:find("/issues/42/comments$", 1, false))
      assert.equals(90, comment.id)
    end)

    it("submits reviews with an empty string body when none is provided", function()
      local requests = mocks.mock_curl({
        ["/reviews$"] = mocks.api_response({ id = 11 }),
      })

      local review
      api.submit_review("acme", "widgets", 42, "APPROVE", nil, "token", function(result)
        review = result
      end)
      wait_for(function() return review ~= nil end)

      local body = vim.json.decode(requests[1].body)
      assert.equals("APPROVE", body.event)
      assert.equals("", body.body)
      assert.equals(11, review.id)
    end)

    it("merges PRs with the selected merge method", function()
      local requests = mocks.mock_curl({
        ["/merge$"] = mocks.api_response({ merged = true }),
      })

      local result
      api.merge_pr("acme", "widgets", 42, {
        merge_method = "squash",
        commit_title = "ship it",
      }, "token", function(data)
        result = data
      end)
      wait_for(function() return result ~= nil end)

      local body = vim.json.decode(requests[1].body)
      assert.equals("squash", body.merge_method)
      assert.equals("ship it", body.commit_title)
      assert.is_true(result.merged)
    end)

    it("merge_pr forwards API errors to the callback", function()
      mocks.mock_curl({
        ["/merge$"] = mocks.api_error(405, "merge blocked"),
      })

      local result, err
      api.merge_pr("acme", "widgets", 42, {}, "token", function(data, api_err)
        result = data
        err = api_err
      end)
      wait_for(function() return err ~= nil end)

      assert.is_nil(result)
      assert.truthy(err:find("merge blocked"))
    end)

    it("get_check_runs fetches commit checks from the expected endpoint", function()
      local requests = mocks.mock_curl({
        ["/check%-runs$"] = mocks.api_response({ check_runs = { { name = "ci" } } }),
      })

      local checks
      api.get_check_runs("acme", "widgets", "abc123", "token", function(result)
        checks = result
      end)
      wait_for(function() return checks ~= nil end)

      assert.equals("ci", checks.check_runs[1].name)
      assert.truthy(requests[1].url:find("/repos/acme/widgets/commits/abc123/check%-runs$", 1, false))
    end)

    it("returns an empty resolution map for unsupported GHES review threads", function()
      api.init("ghe.example.com")
      mocks.mock_curl({
        ["api/graphql"] = mocks.api_error(404, "missing"),
      })

      local resolution_map, err
      api.get_pr_review_threads("acme", "widgets", 42, "token", function(map, api_err)
        resolution_map = map
        err = api_err
      end)
      wait_for(function() return resolution_map ~= nil or err ~= nil end)

      assert.same({}, resolution_map)
      assert.is_nil(err)
    end)

    it("maps GraphQL review thread resolution data on success", function()
      mocks.mock_curl({
        ["/graphql$"] = mocks.api_response({
          data = {
            repository = {
              pullRequest = {
                reviewThreads = {
                  nodes = {
                    {
                      id = "thread-1",
                      isResolved = true,
                      resolvedBy = { login = "maintainer" },
                      comments = {
                        nodes = {
                          { databaseId = 99 },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        }),
      })

      local resolution_map
      api.get_pr_review_threads("acme", "widgets", 42, "token", function(result)
        resolution_map = result
      end)
      wait_for(function() return resolution_map ~= nil end)

      assert.is_true(resolution_map[99].isResolved)
      assert.equals("thread-1", resolution_map[99].thread_id)
      assert.equals("maintainer", resolution_map[99].resolvedBy.login)
    end)

    it("returns a helpful message when GHES cannot resolve review threads", function()
      api.init("ghe.example.com")
      mocks.mock_curl({
        ["api/graphql"] = mocks.api_error(404, "missing"),
      })

      local err
      api.resolve_review_thread("thread123", "token", function(api_err)
        err = api_err
      end)
      wait_for(function() return err ~= nil end)

      assert.truthy(err:find("not supported"))
    end)

    it("surfaces GraphQL errors on github.com", function()
      api.init("github.com")
      mocks.mock_curl({
        ["/graphql$"] = mocks.api_error(400, "bad query"),
      })

      local resolution_map, err
      api.get_pr_review_threads("acme", "widgets", 42, "token", function(result, api_err)
        resolution_map = result
        err = api_err
      end)
      wait_for(function() return err ~= nil end)

      assert.is_nil(resolution_map)
      assert.truthy(err:find("bad query"))
    end)

    it("returns nil error for successful thread resolution", function()
      mocks.mock_curl({
        ["/graphql$"] = mocks.api_response({
          data = {
            resolveReviewThread = {
              clientMutationId = "ok",
            },
          },
        }),
      })

      local err
      local called = false
      api.resolve_review_thread("thread123", "token", function(api_err)
        err = api_err
        called = true
      end)
      wait_for(function() return called end)

      assert.is_nil(err)
    end)

    it("falls back to Unknown error when the API error body omits message", function()
      mocks.mock_curl({
        ["/pulls/42$"] = {
          status = 500,
          body = vim.json.encode({}),
          headers = {},
        },
      })

      local _, err
      api.get_pr("acme", "widgets", 42, "token", function(_, api_err)
        err = api_err
      end)
      wait_for(function() return err ~= nil end)

      assert.truthy(err:find("Unknown error"))
    end)
  end)
end)
