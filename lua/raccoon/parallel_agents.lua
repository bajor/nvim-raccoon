---@class RaccoonParallelAgents
---Fire-and-forget parallel agent dispatch from commit viewer
local M = {}

local config = require("raccoon.config")
local windows = require("raccoon.windows")

--- Active agents: array of {job_id, task_name}
local agents = {}
local suppress_exit_notifications = false
local kill_in_progress = false

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
---@param cmd_template string Command template containing <PROMPT> placeholder
---@param prompt string The assembled prompt
---@return string final_cmd
function M.build_command(cmd_template, prompt)
  local escaped = vim.fn.shellescape(prompt)
  local placeholder = '<PROMPT>'
  local pos = cmd_template:find(placeholder, 1, true)
  if not pos then return cmd_template end
  return cmd_template:sub(1, pos - 1) .. escaped .. cmd_template:sub(pos + #placeholder)
end

--- Get the number of currently running agents
---@return number
function M.get_running_count()
  return #agents
end

--- Open a floating window for task input, call on_submit with the text
---@param on_submit fun(task_text: string)
---@param view_state? table Optional state table; sets state.popup_win while open
---@param popup_width? number Desired popup width (clamped to terminal)
local function open_task_input(on_submit, view_state, popup_width)
  local shortcuts = config.load_shortcuts()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"

  local width = math.min(popup_width or 70, vim.o.columns - 4)
  local height = 5
  local row = 1
  local col = math.floor((vim.o.columns - width) / 2)

  local save_key = config.is_enabled(shortcuts.comment_save) and shortcuts.comment_save or "<leader>s"
  local close_key = shortcuts.close
  local title = string.format(" Agent Task (%s=send, %s=cancel) ", save_key, close_key)

  -- Set truthy sentinel before open_win so the WinEnter focus lock sees it
  -- (open_win fires WinEnter synchronously before we can assign the real handle)
  if view_state then view_state.popup_win = -1 end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    zindex = 200,
  })
  windows.mark(win)

  if view_state then view_state.popup_win = win end

  vim.cmd("startinsert")

  local buf_opts = { buffer = buf, noremap = true, silent = true }

  local function close()
    if view_state then view_state.popup_win = nil end
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local text = vim.fn.trim(table.concat(lines, "\n"))
    close()
    if text == "" then
      vim.notify("Agent dispatch cancelled: no task provided", vim.log.levels.INFO)
      return
    end
    on_submit(text)
  end

  if config.is_enabled(shortcuts.comment_save) then
    vim.keymap.set("n", shortcuts.comment_save, submit, buf_opts)
  end
  vim.keymap.set("n", shortcuts.close, close, buf_opts)
  vim.keymap.set("i", shortcuts.close, close, buf_opts)
end

--- Dispatch an agent process
---@param opts table {repo_path, commit_sha, commit_message, filename, visual_lines, line_start, line_end, view_state}
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

  if not pa_cfg.command:find('<PROMPT>', 1, true) then
    vim.notify('Parallel agents: command must contain <PROMPT> placeholder', vim.log.levels.WARN)
    return
  end

  local has_claude = pa_cfg.command:find("claude", 1, true)
  local has_skip_perms = pa_cfg.command:find("%-%-dangerously%-skip%-permissions")
  local has_allowed_tools = pa_cfg.command:find("%-%-allowedTools")
  if has_claude and not has_skip_perms and not has_allowed_tools then
    vim.notify(
      "Parallel agents: claude command lacks permission flags.\n"
        .. "Use --dangerously-skip-permissions or --allowedTools"
        .. " so background agents don't hang on prompts.",
      vim.log.levels.WARN
    )
    return
  end

  local get_input = M._open_task_input or open_task_input
  get_input(function(task_text)
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

    local stderr_lines = {}

    -- Redirect stdin from /dev/null so the child process doesn't hang waiting for input
    local job_id = vim.fn.jobstart({ "sh", "-c", final_cmd .. " </dev/null" }, {
      cwd = opts.repo_path,
      on_stderr = function(_, data)
        if data then
          for _, line in ipairs(data) do
            if line ~= "" then table.insert(stderr_lines, line) end
          end
        end
      end,
      on_exit = function(id, exit_code)
        vim.schedule(function()
          for i, agent in ipairs(agents) do
            if agent.job_id == id then
              table.remove(agents, i)
              break
            end
          end

          if suppress_exit_notifications then
            return
          end

          local level = exit_code == 0 and vim.log.levels.INFO or vim.log.levels.WARN
          local msg = string.format("Agent finished (exit %d): %s", exit_code, task_text)
          if exit_code ~= 0 and #stderr_lines > 0 then
            msg = msg .. "\n" .. table.concat(stderr_lines, "\n")
          end
          vim.notify(msg, level)
        end)
      end,
    })

    if job_id > 0 then
      table.insert(agents, { job_id = job_id, task_name = task_text })
      vim.notify(string.format("Agent dispatched: %s (%d running)", task_text, #agents))
    elseif job_id == 0 then
      vim.notify("Failed to start agent: invalid command arguments", vim.log.levels.ERROR)
    else
      vim.notify("Failed to start agent: command not executable", vim.log.levels.ERROR)
    end
  end, opts.view_state, pa_cfg.popup_width)
end

--- Kill all running agent jobs and clear tracker.
--- Best effort: continues on individual failures.
---@return table summary {requested: number, stopped: number, errors: string[], in_progress?: boolean}
function M.kill_all()
  if kill_in_progress then
    return { requested = 0, stopped = 0, errors = {}, in_progress = true }
  end

  kill_in_progress = true
  suppress_exit_notifications = true

  local running = agents
  agents = {}

  local stopped = 0
  local errors = {}

  local ok, err = xpcall(function()
    for _, agent in ipairs(running) do
      local stop_ok, result = pcall(vim.fn.jobstop, agent.job_id)
      if not stop_ok then
        table.insert(errors, string.format("job %s: %s", tostring(agent.job_id), tostring(result)))
      elseif result == 1 then
        stopped = stopped + 1
      elseif result ~= 0 and result ~= -1 then
        table.insert(errors, string.format("job %s: unexpected jobstop result %s", tostring(agent.job_id), tostring(result)))
      end
    end
  end, debug.traceback)

  suppress_exit_notifications = false
  kill_in_progress = false

  if not ok then
    table.insert(errors, "kill_all failed: " .. tostring(err))
  end

  return {
    requested = #running,
    stopped = stopped,
    errors = errors,
  }
end

---@private
M._get_agents = function() return agents end
---@private
M._reset_agents = function() agents = {} end

return M
