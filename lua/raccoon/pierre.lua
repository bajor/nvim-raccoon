local M = {}

local cache = {}

local defaults = {
  provider = "auto",
  timeout_ms = 200,
  command = nil,
  inline_word_diff = true,
}

local function cfg()
  local core = require("raccoon")
  return vim.tbl_deep_extend("force", defaults, (core.config or {}).diff_renderer or {})
end

function M.is_enabled()
  local provider = cfg().provider
  return provider == "auto" or provider == "pierre"
end

local function default_command()
  local script = vim.api.nvim_get_runtime_file("scripts/pierre_render.mjs", false)[1]
  if not script then
    return nil
  end
  return { "node", script }
end

local function normalize_reviewable(plan)
  local reviewable = {}
  if type(plan.reviewable) == "table" then
    for key, line in pairs(plan.reviewable) do
      if type(line) == "number" then
        reviewable[line] = true
      elseif type(key) == "number" and line == true then
        reviewable[key] = true
      end
    end
  end
  plan.reviewable = reviewable
end

local function validate_plan(plan)
  if type(plan) ~= "table" or plan.version ~= 1 then
    return false
  end

  for _, key in ipairs({ "hunks", "added", "deleted", "reviewable" }) do
    if plan[key] ~= nil and type(plan[key]) ~= "table" then
      return false
    end
    plan[key] = plan[key] or {}
  end
  if plan.inline_add ~= nil and type(plan.inline_add) ~= "table" then
    return false
  end
  plan.inline_add = plan.inline_add or {}

  normalize_reviewable(plan)
  return true
end

function M.render_patch(patch, filename)
  if not M.is_enabled() or type(patch) ~= "string" or patch == "" then
    return nil, "disabled"
  end

  local key = (filename or "") .. "\0" .. patch
  if cache[key] then
    return cache[key], nil
  end

  local c = cfg()
  local cmd = c.command or default_command()
  if type(cmd) ~= "table" or not cmd[1] then
    return nil, "missing command"
  end
  if type(vim.system) ~= "function" then
    return nil, "missing vim.system"
  end

  local payload = vim.json.encode({
    patch = patch,
    filename = filename,
    inline_word_diff = c.inline_word_diff ~= false,
  })

  local ok, job_or_err = pcall(vim.system, cmd, { text = true, stdin = payload })
  if not ok then
    return nil, tostring(job_or_err)
  end

  local wait_ok, result = pcall(function()
    return job_or_err:wait(c.timeout_ms)
  end)
  if not wait_ok then
    return nil, tostring(result)
  end
  if result == nil then
    return nil, "timeout"
  end
  if result.code ~= 0 then
    local stderr = result.stderr or ""
    return nil, stderr ~= "" and stderr or ("exit " .. tostring(result.code))
  end

  local decode_ok, decoded = pcall(vim.json.decode, result.stdout or "")
  if not decode_ok or not validate_plan(decoded) then
    return nil, "invalid json"
  end

  cache[key] = decoded
  return decoded, nil
end

return M
