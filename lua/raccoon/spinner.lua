---@class RaccoonSpinner
---Loading spinner for async operations
local M = {}

local api = vim.api

--- Spinner frames
local frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

--- Active spinners by ID
local spinners = {}

--- Create a new spinner
---@param opts table Options: message, buf (optional)
---@return string id Spinner ID
function M.start(opts)
  opts = opts or {}
  local message = opts.message or "Loading"
  local buf = opts.buf

  local id = tostring(os.time()) .. tostring(math.random(1000))
  local frame_idx = 1

  local function update()
    if not spinners[id] then
      return
    end

    local spinner_text = frames[frame_idx] .. " " .. message .. "..."

    if buf and api.nvim_buf_is_valid(buf) then
      -- Update buffer content
      local modifiable = vim.bo[buf].modifiable
      vim.bo[buf].modifiable = true
      api.nvim_buf_set_lines(buf, 0, 1, false, { "  " .. spinner_text })
      vim.bo[buf].modifiable = modifiable
    else
      -- Echo to command line
      vim.cmd('echo "' .. spinner_text .. '"')
    end

    frame_idx = (frame_idx % #frames) + 1

    -- Schedule next update
    vim.defer_fn(function()
      update()
    end, 80)
  end

  spinners[id] = {
    message = message,
    buf = buf,
  }

  update()
  return id
end

--- Stop a spinner
---@param id string Spinner ID
---@param final_message string|nil Optional final message
function M.stop(id, final_message)
  if not spinners[id] then
    return
  end

  local spinner = spinners[id]
  spinners[id] = nil

  if final_message then
    if spinner.buf and api.nvim_buf_is_valid(spinner.buf) then
      local modifiable = vim.bo[spinner.buf].modifiable
      vim.bo[spinner.buf].modifiable = true
      api.nvim_buf_set_lines(spinner.buf, 0, 1, false, { "  " .. final_message })
      vim.bo[spinner.buf].modifiable = modifiable
    else
      vim.cmd('echo "' .. final_message .. '"')
    end
  else
    vim.cmd('echo ""')
  end
end

--- Check if a spinner is active
---@param id string Spinner ID
---@return boolean
function M.is_active(id)
  return spinners[id] ~= nil
end

--- Stop all spinners
function M.stop_all()
  for id, _ in pairs(spinners) do
    M.stop(id)
  end
end

return M
