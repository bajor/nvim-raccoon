--- Test loader helper: force-loads modules from CWD to shadow installed plugin copies
local M = {}

--- Reload a module from the current working directory.
--- Clears package.loaded, loads from lua/<mod>.lua, and re-registers the result.
---@param mod string Dot-separated module name (e.g. "raccoon.config")
---@return any result The module's return value
function M.reload_from_cwd(mod)
  package.loaded[mod] = nil
  local cwd = vim.fn.getcwd()
  local path = cwd .. "/lua/" .. mod:gsub("%.", "/") .. ".lua"
  local fn, err = loadfile(path)
  if not fn then error("Failed to load " .. path .. ": " .. tostring(err)) end
  local result = fn()
  package.loaded[mod] = result
  return result
end

return M
