---@class RaccoonParallelAgents
---Fire-and-forget parallel agent dispatch from commit viewer
local M = {}

local config = require("raccoon.config")

--- Active agents: array of {job_id, task_name}
local agents = {}

--- Build the prompt string from dispatch opts and user task text
---@param opts table Dispatch context
---@param task_text string User-entered task description
---@return string prompt
function M.build_prompt(opts, task_text)
  local parts = { task_text }

  if opts.visual_lines and #opts.visual_lines > 0 then
    local ft = vim.filetype.match({ filename = opts.filename }) or ""
    table.insert(parts, string.format(
      "\nSelected code from %s, lines %d-%d:\n```%s\n%s\n```",
      opts.filename, opts.line_start, opts.line_end, ft,
      table.concat(opts.visual_lines, "\n")
    ))
  end

  local sha_short = opts.commit_sha and opts.commit_sha:sub(1, 8) or ""
  local msg = opts.commit_message or ""
  if sha_short ~= "" or msg ~= "" then
    table.insert(parts, string.format("\nCommit: %s — %s", sha_short, msg))
  end

  local suffix = opts.suffix_prompt or ""
  if suffix ~= "" then
    table.insert(parts, "\n" .. suffix)
  end

  return table.concat(parts, "\n")
end

--- Build the final shell command by replacing the placeholder
---@param cmd_template string Command template containing "your task"
---@param prompt string The assembled prompt
---@return string final_cmd
function M.build_command(cmd_template, prompt)
  local escaped = vim.fn.shellescape(prompt)
  local placeholder = '"your task"'
  local pos = cmd_template:find(placeholder, 1, true)
  if not pos then return cmd_template end
  return cmd_template:sub(1, pos - 1) .. escaped .. cmd_template:sub(pos + #placeholder)
end

--- Get the number of currently running agents
---@return number
function M.get_running_count()
  return #agents
end

--- Dispatch an agent process
---@param opts table {repo_path, commit_sha, commit_message, filename, visual_lines, line_start, line_end}
function M.dispatch(opts)
  local pa_cfg = config.load_parallel_agents()

  if not pa_cfg.enabled then
    vim.notify("Parallel agents: not enabled in config", vim.log.levels.WARN)
    return
  end

  if pa_cfg.command == "" then
    vim.notify("Parallel agents: configure 'command' in parallel_agents config", vim.log.levels.WARN)
    return
  end

  if not pa_cfg.command:find('"your task"', 1, true) then
    vim.notify('Parallel agents: command must contain "your task" placeholder', vim.log.levels.WARN)
    return
  end

  vim.ui.input({ prompt = "Agent task: " }, function(task_text)
    if not task_text or task_text == "" then return end

    local prompt = M.build_prompt({
      commit_sha = opts.commit_sha,
      commit_message = opts.commit_message,
      filename = opts.filename,
      visual_lines = opts.visual_lines,
      line_start = opts.line_start,
      line_end = opts.line_end,
      suffix_prompt = pa_cfg.suffix_prompt,
    }, task_text)

    local final_cmd = M.build_command(pa_cfg.command, prompt)

    local job_id = vim.fn.jobstart({ "sh", "-c", final_cmd }, {
      cwd = opts.repo_path,
      on_exit = function(id, exit_code)
        vim.schedule(function()
          for i, agent in ipairs(agents) do
            if agent.job_id == id then
              table.remove(agents, i)
              break
            end
          end
          local level = exit_code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
          vim.notify(
            string.format("Agent finished (exit %d): %s", exit_code, task_text),
            level
          )
        end)
      end,
    })

    if job_id > 0 then
      table.insert(agents, { job_id = job_id, task_name = task_text })
      vim.notify(string.format("Agent dispatched: %s (%d running)", task_text, #agents))
    else
      vim.notify("Failed to start agent process", vim.log.levels.ERROR)
    end
  end)
end

---@private
M._get_agents = function() return agents end
---@private
M._reset_agents = function() agents = {} end

return M
