---@class RaccoonAPI
---GitHub API client using plenary.curl
local M = {}

local curl = require("plenary.curl")

--- Base URL for GitHub API
M.base_url = "https://api.github.com"

--- Default headers for API requests
---@param token string GitHub token
---@return table
local function default_headers(token)
  return {
    ["Authorization"] = "Bearer " .. token,
    ["Accept"] = "application/vnd.github+json",
    ["X-GitHub-Api-Version"] = "2022-11-28",
    ["User-Agent"] = "raccoon-nvim",
  }
end

--- Parse Link header for pagination
---@param link_header string|nil
---@return string|nil next_url
local function parse_link_header(link_header)
  if not link_header then
    return nil
  end

  -- Link header format: <url>; rel="next", <url>; rel="last"
  for part in link_header:gmatch("[^,]+") do
    local url = part:match("<([^>]+)>")
    local rel = part:match('rel="([^"]+)"')
    if url and rel == "next" then
      return url
    end
  end

  return nil
end

--- Make an API request
---@param opts table Options: url, method, token, body, callback
---@return table|nil response, string|nil error
local function request(opts)
  local headers = default_headers(opts.token)

  if opts.body then
    headers["Content-Type"] = "application/json"
  end

  local response = curl.request({
    url = opts.url,
    method = opts.method or "GET",
    headers = headers,
    body = opts.body and vim.json.encode(opts.body) or nil,
    timeout = 30000,
  })

  if not response then
    return nil, "Request failed: no response"
  end

  if response.status >= 400 then
    local err_body = vim.json.decode(response.body or "{}") or {}
    local message = err_body.message or "Unknown error"
    return nil, string.format("GitHub API error (%d): %s", response.status, message)
  end

  local body = vim.json.decode(response.body or "[]")
  return {
    data = body,
    headers = response.headers,
    status = response.status,
  }, nil
end

--- Fetch all pages of a paginated endpoint
---@param url string Initial URL
---@param token string GitHub token
---@return table[] items, string|nil error
local function fetch_all_pages(url, token)
  local all_items = {}
  local current_url = url

  while current_url do
    local response, err = request({
      url = current_url,
      method = "GET",
      token = token,
    })

    if err then
      return all_items, err
    end

    -- Append items from this page
    if type(response.data) == "table" then
      for _, item in ipairs(response.data) do
        table.insert(all_items, item)
      end
    end

    -- Get next page URL from Link header
    current_url = parse_link_header(response.headers and response.headers.link)
  end

  return all_items, nil
end

--- List open pull requests for a repository
---@param owner string Repository owner
---@param repo string Repository name
---@param token string GitHub token
---@param callback fun(prs: table[]|nil, err: string|nil)
function M.list_prs(owner, repo, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/pulls?state=open&per_page=100", M.base_url, owner, repo)
    local prs, err = fetch_all_pages(url, token)
    callback(prs, err)
  end)
end

--- Get a single pull request
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param token string GitHub token
---@param callback fun(pr: table|nil, err: string|nil)
function M.get_pr(owner, repo, number, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/pulls/%d", M.base_url, owner, repo, number)
    local response, err = request({
      url = url,
      method = "GET",
      token = token,
    })

    if err then
      callback(nil, err)
      return
    end

    callback(response.data, nil)
  end)
end

--- Get files changed in a pull request
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param token string GitHub token
---@param callback fun(files: table[]|nil, err: string|nil)
function M.get_pr_files(owner, repo, number, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/pulls/%d/files?per_page=100", M.base_url, owner, repo, number)
    local files, err = fetch_all_pages(url, token)
    callback(files, err)
  end)
end

--- Get review comments on a pull request
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param token string GitHub token
---@param callback fun(comments: table[]|nil, err: string|nil)
function M.get_pr_comments(owner, repo, number, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/pulls/%d/comments?per_page=100", M.base_url, owner, repo, number)
    local comments, err = fetch_all_pages(url, token)
    callback(comments, err)
  end)
end

--- Create a review comment on a pull request
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param opts table Comment options: body, commit_id, path, line (or position for old API)
---@param token string GitHub token
---@param callback fun(comment: table|nil, err: string|nil)
function M.create_comment(owner, repo, number, opts, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/pulls/%d/comments", M.base_url, owner, repo, number)

    -- GitHub API requires specific format for PR review comments
    -- See: https://docs.github.com/en/rest/pulls/comments
    local body = {
      body = opts.body,
      commit_id = opts.commit_id,
      path = opts.path,
    }

    -- Use position-based commenting (works with diff hunks)
    -- line + side is for the newer API but requires the line to be in a diff hunk
    if opts.position then
      body.position = opts.position
    else
      -- Try line-based (newer API)
      body.line = opts.line
      body.side = opts.side or "RIGHT"
    end

    local response, err = request({
      url = url,
      method = "POST",
      token = token,
      body = body,
    })

    if err then
      -- Add hint for common 422 error
      if err:find("422") then
        err = err .. " (Line must be in diff context - try commenting on a changed line)"
      end
      callback(nil, err)
      return
    end

    callback(response.data, nil)
  end)
end

--- Update an existing review comment
---@param owner string Repository owner
---@param repo string Repository name
---@param comment_id number Comment ID
---@param body string New comment body
---@param token string GitHub token
---@param callback fun(comment: table|nil, err: string|nil)
function M.update_comment(owner, repo, comment_id, body, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/pulls/comments/%d", M.base_url, owner, repo, comment_id)

    local response, err = request({
      url = url,
      method = "PATCH",
      token = token,
      body = { body = body },
    })

    if err then
      callback(nil, err)
      return
    end

    callback(response.data, nil)
  end)
end

--- Get issue comments on a pull request (general comments, not line-specific)
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param token string GitHub token
---@param callback fun(comments: table[]|nil, err: string|nil)
function M.get_issue_comments(owner, repo, number, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/issues/%d/comments?per_page=100", M.base_url, owner, repo, number)
    local comments, err = fetch_all_pages(url, token)
    callback(comments, err)
  end)
end

--- Create a general PR/issue comment (not line-specific)
--- Use this for commenting on lines outside the diff
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param body string Comment body
---@param token string GitHub token
---@param callback fun(comment: table|nil, err: string|nil)
function M.create_issue_comment(owner, repo, number, body, token, callback)
  vim.schedule(function()
    -- PRs are issues, so we use the issues endpoint
    local url = string.format("%s/repos/%s/%s/issues/%d/comments", M.base_url, owner, repo, number)

    local response, err = request({
      url = url,
      method = "POST",
      token = token,
      body = { body = body },
    })

    if err then
      callback(nil, err)
      return
    end

    callback(response.data, nil)
  end)
end

--- Submit a review on a pull request
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param event string Review event: APPROVE, REQUEST_CHANGES, COMMENT
---@param body string|nil Optional review body
---@param token string GitHub token
---@param callback fun(review: table|nil, err: string|nil)
function M.submit_review(owner, repo, number, event, body, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/pulls/%d/reviews", M.base_url, owner, repo, number)

    local request_body = {
      event = event,
      body = body or "",
    }

    local response, err = request({
      url = url,
      method = "POST",
      token = token,
      body = request_body,
    })

    if err then
      callback(nil, err)
      return
    end

    callback(response.data, nil)
  end)
end

--- Parse a GitHub PR URL to extract owner, repo, and number
---@param url string|nil GitHub PR URL
---@return string|nil owner, string|nil repo, number|nil number
function M.parse_pr_url(url)
  if not url then
    return nil, nil, nil
  end
  -- Match: https://github.com/owner/repo/pull/123
  local owner, repo, num = url:match("github%.com/([^/]+)/([^/]+)/pull/(%d+)")
  if owner and repo and num then
    return owner, repo, tonumber(num)
  end
  return nil, nil, nil
end

--- Get check runs for a commit (CI status)
---@param owner string Repository owner
---@param repo string Repository name
---@param ref string Commit SHA or branch name
---@param token string GitHub token
---@param callback fun(check_runs: table|nil, err: string|nil)
function M.get_check_runs(owner, repo, ref, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/commits/%s/check-runs", M.base_url, owner, repo, ref)
    local response, err = request({
      url = url,
      method = "GET",
      token = token,
    })

    if err then
      callback(nil, err)
      return
    end

    callback(response.data, nil)
  end)
end

--- Make a GraphQL API request
---@param query string GraphQL query
---@param variables table Query variables
---@param token string GitHub token
---@return table|nil response, string|nil error
local function graphql_request(query, variables, token)
  local headers = default_headers(token)
  headers["Content-Type"] = "application/json"

  local response = curl.request({
    url = "https://api.github.com/graphql",
    method = "POST",
    headers = headers,
    body = vim.json.encode({
      query = query,
      variables = variables,
    }),
    timeout = 30000,
  })

  if not response then
    return nil, "GraphQL request failed: no response"
  end

  if response.status >= 400 then
    local err_body = vim.json.decode(response.body or "{}") or {}
    local message = err_body.message or "Unknown error"
    return nil, string.format("GraphQL API error (%d): %s", response.status, message)
  end

  local body = vim.json.decode(response.body or "{}")
  if body.errors then
    local err_msg = body.errors[1] and body.errors[1].message or "Unknown GraphQL error"
    return nil, "GraphQL error: " .. err_msg
  end

  return body.data, nil
end

--- Get review threads with resolution status (GraphQL)
--- This fetches thread resolution status which is not available via REST API
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param token string GitHub token
---@param callback fun(resolution_map: table|nil, err: string|nil)
function M.get_pr_review_threads(owner, repo, number, token, callback)
  vim.schedule(function()
    local query = [[
      query($owner: String!, $repo: String!, $number: Int!) {
        repository(owner: $owner, name: $repo) {
          pullRequest(number: $number) {
            reviewThreads(first: 100) {
              nodes {
                id
                isResolved
                resolvedBy { login }
                comments(first: 100) {
                  nodes {
                    databaseId
                  }
                }
              }
            }
          }
        }
      }
    ]]

    local variables = {
      owner = owner,
      repo = repo,
      number = number,
    }

    local data, err = graphql_request(query, variables, token)
    if err then
      callback(nil, err)
      return
    end

    -- Build comment_id -> resolution map
    local resolution_map = {}
    local threads = data
        and data.repository
        and data.repository.pullRequest
        and data.repository.pullRequest.reviewThreads
        and data.repository.pullRequest.reviewThreads.nodes

    if threads then
      for _, thread in ipairs(threads) do
        local comments = thread.comments and thread.comments.nodes
        if comments then
          for _, comment in ipairs(comments) do
            if comment.databaseId then
              resolution_map[comment.databaseId] = {
                isResolved = thread.isResolved,
                resolvedBy = thread.resolvedBy,
                thread_id = thread.id,
              }
            end
          end
        end
      end
    end

    callback(resolution_map, nil)
  end)
end

--- Merge a pull request
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param opts table|nil Options: merge_method ("merge"|"squash"|"rebase"), commit_title, commit_message
---@param token string GitHub token
---@param callback fun(result: table|nil, err: string|nil)
function M.merge_pr(owner, repo, number, opts, token, callback)
  opts = opts or {}
  local url = string.format("%s/repos/%s/%s/pulls/%d/merge", M.base_url, owner, repo, number)

  vim.schedule(function()
    local result, err = request({
      url = url,
      method = "PUT",
      token = token,
      body = {
        merge_method = opts.merge_method or "merge",
        commit_title = opts.commit_title,
        commit_message = opts.commit_message,
      },
    })

    if err then
      callback(nil, err)
      return
    end

    callback(result and result.data, nil)
  end)
end

--- Resolve a review thread (GraphQL)
---@param thread_id string The node ID of the review thread
---@param token string GitHub token
---@param callback fun(err: string|nil)
function M.resolve_review_thread(thread_id, token, callback)
  vim.schedule(function()
    local query = [[
      mutation($thread_id: ID!) {
        resolveReviewThread(input: {threadId: $thread_id}) {
          clientMutationId
        }
      }
    ]]

    local variables = {
      thread_id = thread_id,
    }

    local _, err = graphql_request(query, variables, token)
    callback(err)
  end)
end

--- Unresolve a review thread (GraphQL)
---@param thread_id string The node ID of the review thread
---@param token string GitHub token
---@param callback fun(err: string|nil)
function M.unresolve_review_thread(thread_id, token, callback)
  vim.schedule(function()
    local query = [[
      mutation($thread_id: ID!) {
        unresolveReviewThread(input: {threadId: $thread_id}) {
          clientMutationId
        }
      }
    ]]

    local variables = {
      thread_id = thread_id,
    }

    local _, err = graphql_request(query, variables, token)
    callback(err)
  end)
end

return M
