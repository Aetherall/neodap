-- Plugin: Write session output to temp files
-- Writes stdout/stderr to /tmp/dap/session/<id>/{stdout,stderr}

---@class OutputFilesConfig
---@field base_dir? string Base directory (default: /tmp/dap/session)

---Append text to file (preserves exact output including newlines)
---@param path string
---@param text string
local function append_to_file(path, text)
  local file = io.open(path, "a")
  if file then
    file:write(text)
    file:close()
  end
end

---Setup output files plugin
---@param debugger Debugger
---@param config? OutputFilesConfig
return function(debugger, config)
  config = config or {}
  local base_dir = config.base_dir or "/tmp/dap/session"

  debugger:onSession(function(session)
    local session_dir = base_dir .. "/" .. session.id
    local stdout_path = session_dir .. "/stdout"
    local stderr_path = session_dir .. "/stderr"

    -- Create session directory
    vim.fn.mkdir(session_dir, "p")

    -- Clear files at session start
    io.open(stdout_path, "w"):close()
    io.open(stderr_path, "w"):close()

    -- Store paths on session for easy access
    session.output_files = {
      dir = session_dir,
      stdout = stdout_path,
      stderr = stderr_path,
    }

    -- Write output to appropriate file
    session:onOutput(function(output)
      local category = output.category
      local text = output.output or ""

      if category == "stdout" then
        append_to_file(stdout_path, text)
      elseif category == "stderr" then
        append_to_file(stderr_path, text)
      end
    end)
  end)
end
