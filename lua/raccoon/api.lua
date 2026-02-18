---@class RaccoonAPI
---GitHub API client using plenary.curl
local M = {}

local curl = require("plenary.curl")

--- Base URL for GitHub REST API
M.base_url = "https://api.github.com"

--- Base URL for GitHub GraphQL API
M.graphql_url = "https://api.github.com/graphql"

--- Server info (inferred from host)
---@type { is_ghes: boolean }
M.server_info = { is_ghes = false }

--- Cache for viewer login per token (keyed by first 8 chars of token)
local viewer_cache = {}

--- Compute REST and GraphQL base URLs from a GitHub host
---@param host string GitHub host (e.g. "github.com" or "github.mycompany.com")
---@return string base_url, string graphql_url
local function compute_api_urls(host)
  if host == "github.com" then
    return "https://api.github.com", "https://api.github.com/graphql"
  end
  return ("https://%s/api/v3"):format(host), ("https://%s/api/graphql"):format(host)
end

--- Initialize API URLs from a GitHub host
---@param host string GitHub host (e.g. "github.com" or "github.mycompany.com")
function M.init(host)
  M.base_url, M.graphql_url = compute_api_urls(host)
  M.server_info = { is_ghes = (host ~= "github.com") }
end

--- Append GHES version hint to error messages for likely version-related errors
---@param err string Original error message
---@param status number|nil HTTP status code (hint only shown for 404)
---@return string
local function ghes_hint(err, status)
  if M.server_info.is_ghes and status == 404 then
    return err .. " (raccoon requires GHES 3.9+)"
  end
  return err
end

--- Default headers for API requests
---@param token string GitHub token
---@return table
local function default_headers(token)
  return {
    ["Authorization"] = "Bearer " .. token,
    ["Accept"] = "application/vnd.github+json",
    ["User-Agent"] = "raccoon-nvim",
    ["X-GitHub-Api-Version"] = "2022-11-28",
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
    return nil, ghes_hint(string.format("GitHub API error (%d): %s", response.status, message), response.status)
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

--- Get the authenticated user's login for a token
---@param token string GitHub token
---@param callback fun(login: string|nil, err: string|nil)
function M.get_viewer(token, callback)
  local cache_key = token:sub(1, 8)
  if viewer_cache[cache_key] then
    callback(viewer_cache[cache_key], nil)
    return
  end

  vim.schedule(function()
    local url = string.format("%s/user", M.base_url)
    local response, err = request({
      url = url,
      method = "GET",
      token = token,
    })

    if err then
      callback(nil, err)
      return
    end

    local login = response.data and response.data.login
    if not login then
      callback(nil, "Could not determine authenticated user")
      return
    end

    viewer_cache[cache_key] = login
    callback(login, nil)
  end)
end

--- Clear the viewer cache (for testing)
function M.clear_viewer_cache()
  viewer_cache = {}
end

--- Search for open PRs involving the authenticated user
---@param token string GitHub token
---@param username string Authenticated user's login
---@param callback fun(prs: table[]|nil, err: string|nil)
function M.search_user_prs(token, username, callback)
  vim.schedule(function()
    local query = string.format("type:pr state:open involves:%s", username)
    local url = string.format("%s/search/issues?q=%s&sort=updated&order=desc&per_page=100",
      M.base_url, vim.uri_encode(query))

    local response, err = request({
      url = url,
      method = "GET",
      token = token,
    })

    if err then
      callback(nil, err)
      return
    end

    -- Transform search results to match list_prs format
    local prs = {}
    for _, item in ipairs(response.data.items or {}) do
      -- Extract "owner/repo" from repository_url
      local repo_name = item.repository_url and item.repository_url:match("/repos/(.+)$") or "unknown"
      item.base = { repo = { full_name = repo_name } }
      table.insert(prs, item)
    end

    callback(prs, nil)
  end)
end

--- Search for open PRs involving the authenticated user in a specific repo
---@param owner string Repository owner
---@param repo string Repository name
---@param token string GitHub token
---@param username string Authenticated user's login
---@param callback fun(prs: table[]|nil, err: string|nil)
function M.search_repo_prs(owner, repo, token, username, callback)
  vim.schedule(function()
    local query = string.format("type:pr state:open repo:%s/%s involves:%s", owner, repo, username)
    local url = string.format("%s/search/issues?q=%s&sort=updated&order=desc&per_page=100",
      M.base_url, vim.uri_encode(query))

    local response, err = request({
      url = url,
      method = "GET",
      token = token,
    })

    if err then
      callback(nil, err)
      return
    end

    local prs = {}
    local full_name = string.format("%s/%s", owner, repo)
    for _, item in ipairs(response.data.items or {}) do
      item.base = { repo = { full_name = full_name } }
      table.insert(prs, item)
    end

    callback(prs, nil)
  end)
end

--- List open pull requests for a repository (unfiltered)
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

--- Get reviews on a pull request (includes review bodies from bots)
---@param owner string Repository owner
---@param repo string Repository name
---@param number number PR number
---@param token string GitHub token
---@param callback fun(reviews: table[]|nil, err: string|nil)
function M.get_pr_reviews(owner, repo, number, token, callback)
  vim.schedule(function()
    local url = string.format("%s/repos/%s/%s/pulls/%d/reviews?per_page=100", M.base_url, owner, repo, number)
    local reviews, err = fetch_all_pages(url, token)
    callback(reviews, err)
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

--- Parse a GitHub PR URL to extract owner, repo, number, and host.
--- When host is provided, validates the URL against that host.
--- When host is nil, extracts the host from the URL.
---@param url string|nil GitHub PR URL
---@param host string|nil GitHub host to match (nil = extract from URL)
---@return string|nil owner, string|nil repo, number|nil number, string|nil host
function M.parse_pr_url(url, host)
  if not url then
    return nil, nil, nil, nil
  end
  if host then
    local escaped_host = host:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
    local owner, repo, num = url:match(escaped_host .. "/([^/]+)/([^/]+)/pull/(%d+)")
    if owner and repo and num then
      return owner, repo, tonumber(num), host
    end
    return nil, nil, nil, nil
  end
  -- Extract host from URL
  local h, owner, repo, num = url:match("https?://([^/]+)/([^/]+)/([^/]+)/pull/(%d+)")
  if h and owner and repo and num then
    return owner, repo, tonumber(num), h:lower()
  end
  return nil, nil, nil, nil
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
    url = M.graphql_url,
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
    return nil, ghes_hint(string.format("GraphQL API error (%d): %s", response.status, message), response.status)
  end

  local body = vim.json.decode(response.body or "{}")
  if body.errors then
    local err_msg = body.errors[1] and body.errors[1].message or "Unknown GraphQL error"
    return nil, ghes_hint("GraphQL error: " .. err_msg)
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
      if M.server_info.is_ghes then
        callback({}, nil)
        return
      end
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
    if err and M.server_info.is_ghes then
      callback("Thread resolution not supported on this GitHub Enterprise version")
      return
    end
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
    if err and M.server_info.is_ghes then
      callback("Thread resolution not supported on this GitHub Enterprise version")
      return
    end
    callback(err)
  end)
end

return M
