--- Test mock helpers for raccoon plugin
--- Usage:
---   local mocks = require("tests.helpers.mocks")
---   mocks.mock_curl(responses)
---   -- run tests
---   mocks.restore()
local M = {}

-- Store original functions for restoration
local originals = {}

--- Mock plenary.curl module
--- @param responses table Table mapping URL patterns to response data
--- @return table recorded_requests List of requests made during test
function M.mock_curl(responses)
  local recorded_requests = {}

  -- Store original if we have plenary
  local ok, curl = pcall(require, "plenary.curl")
  if ok then
    originals.curl_get = curl.get
    originals.curl_post = curl.post
    originals.curl_patch = curl.patch
    originals.curl_put = curl.put
    originals.curl_delete = curl.delete
  end

  local function make_mock_request(method)
    return function(opts)
      local url = opts.url or opts[1]
      table.insert(recorded_requests, {
        method = method,
        url = url,
        headers = opts.headers,
        body = opts.body,
      })

      -- Find matching response
      for pattern, response in pairs(responses) do
        if url:match(pattern) then
          if type(response) == "function" then
            return response(opts)
          end
          return response
        end
      end

      -- Default 404 response
      return {
        status = 404,
        body = '{"message": "Not Found"}',
        headers = {},
      }
    end
  end

  if ok then
    curl.get = make_mock_request("GET")
    curl.post = make_mock_request("POST")
    curl.patch = make_mock_request("PATCH")
    curl.put = make_mock_request("PUT")
    curl.delete = make_mock_request("DELETE")
  end

  return recorded_requests
end

--- Mock vim.fn.jobstart for git operations
--- @param responses table Table mapping command patterns to results
--- @return table recorded_commands List of commands executed
function M.mock_jobstart(responses)
  local recorded_commands = {}
  local job_id = 0

  originals.jobstart = vim.fn.jobstart

  vim.fn.jobstart = function(cmd, opts)
    job_id = job_id + 1
    local cmd_str = type(cmd) == "table" and table.concat(cmd, " ") or cmd

    table.insert(recorded_commands, {
      id = job_id,
      cmd = cmd_str,
      opts = opts,
    })

    -- Find matching response
    for pattern, response in pairs(responses) do
      if cmd_str:match(pattern) then
        -- Schedule callback
        vim.schedule(function()
          if opts and opts.on_exit then
            local exit_code = response.exit_code or 0
            opts.on_exit(job_id, exit_code, "exit")
          end
          if opts and opts.on_stdout and response.stdout then
            local lines = type(response.stdout) == "table" and response.stdout or { response.stdout }
            opts.on_stdout(job_id, lines, "stdout")
          end
          if opts and opts.on_stderr and response.stderr then
            local lines = type(response.stderr) == "table" and response.stderr or { response.stderr }
            opts.on_stderr(job_id, lines, "stderr")
          end
        end)
        return job_id
      end
    end

    -- Default success for unmatched commands
    vim.schedule(function()
      if opts and opts.on_exit then
        opts.on_exit(job_id, 0, "exit")
      end
    end)

    return job_id
  end

  return recorded_commands
end

--- Mock vim.notify to capture notifications
--- @return table notifications List of captured notifications
function M.mock_notify()
  local notifications = {}

  originals.notify = vim.notify

  vim.notify = function(msg, level, opts)
    table.insert(notifications, {
      msg = msg,
      level = level,
      opts = opts,
    })
  end

  return notifications
end

--- Mock vim.fn.confirm for user prompts
--- @param response number The response to return (1 = yes, 2 = no, etc.)
function M.mock_confirm(response)
  originals.confirm = vim.fn.confirm

  vim.fn.confirm = function()
    return response
  end
end

--- Mock vim.fn.input for user input
--- @param response string The input to return
function M.mock_input(response)
  originals.input = vim.fn.input

  vim.fn.input = function()
    return response
  end
end

--- Restore all mocked functions
function M.restore()
  -- Restore curl if mocked
  local ok, curl = pcall(require, "plenary.curl")
  if ok then
    if originals.curl_get then
      curl.get = originals.curl_get
    end
    if originals.curl_post then
      curl.post = originals.curl_post
    end
    if originals.curl_patch then
      curl.patch = originals.curl_patch
    end
    if originals.curl_put then
      curl.put = originals.curl_put
    end
    if originals.curl_delete then
      curl.delete = originals.curl_delete
    end
  end

  -- Restore vim functions
  if originals.jobstart then
    vim.fn.jobstart = originals.jobstart
  end
  if originals.notify then
    vim.notify = originals.notify
  end
  if originals.confirm then
    vim.fn.confirm = originals.confirm
  end
  if originals.input then
    vim.fn.input = originals.input
  end

  -- Clear originals
  originals = {}
end

--- Create a mock API response for success
--- @param data table The response body
--- @return table response Mock curl response
function M.api_response(data)
  return {
    status = 200,
    body = vim.fn.json_encode(data),
    headers = {
      ["content-type"] = "application/json",
    },
  }
end

--- Create a mock API error response
--- @param status number HTTP status code
--- @param message string Error message
--- @return table response Mock curl response
function M.api_error(status, message)
  return {
    status = status,
    body = vim.fn.json_encode({ message = message }),
    headers = {
      ["content-type"] = "application/json",
    },
  }
end

--- Create mock PR data
--- @param opts table|nil Optional overrides
--- @return table pr Mock PR object
function M.mock_pr(opts)
  opts = opts or {}
  return {
    id = opts.id or 1,
    number = opts.number or 42,
    title = opts.title or "Test PR",
    body = opts.body or "Test description",
    state = opts.state or "open",
    html_url = opts.html_url or "https://github.com/owner/repo/pull/42",
    user = opts.user or {
      id = 1,
      login = "testuser",
      avatar_url = nil,
    },
    head = opts.head or {
      ref = "feature-branch",
      sha = "abc123def456",
    },
    base = opts.base or {
      ref = "main",
      sha = "def456abc123",
    },
    created_at = opts.created_at or "2026-01-01T00:00:00Z",
    updated_at = opts.updated_at or "2026-01-01T00:00:00Z",
  }
end

--- Create mock file data
--- @param opts table|nil Optional overrides
--- @return table file Mock file object
function M.mock_file(opts)
  opts = opts or {}
  return {
    sha = opts.sha or "abc123",
    filename = opts.filename or "src/main.lua",
    status = opts.status or "modified",
    additions = opts.additions or 10,
    deletions = opts.deletions or 5,
    changes = opts.changes or 15,
    patch = opts.patch or "@@ -1,5 +1,10 @@\n-old line\n+new line",
  }
end

--- Create mock comment data
--- @param opts table|nil Optional overrides
--- @return table comment Mock comment object
function M.mock_comment(opts)
  opts = opts or {}
  return {
    id = opts.id or 999,
    body = opts.body or "Test comment",
    user = opts.user or {
      id = 1,
      login = "reviewer",
      avatar_url = nil,
    },
    path = opts.path or "src/main.lua",
    line = opts.line or 10,
    side = opts.side or "RIGHT",
    commit_id = opts.commit_id or "abc123",
    created_at = opts.created_at or "2026-01-01T00:00:00Z",
    updated_at = opts.updated_at or "2026-01-01T00:00:00Z",
  }
end

return M
