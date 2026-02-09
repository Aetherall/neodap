-- Plugin: Unified :Dap command router
-- Routes subcommands to Dap<Command> user commands
--
-- Usage:
--   :Dap list breakpoints                    - delegates to :DapList
--   :Dap continue                            - delegates to :DapContinue
--   :Dap step into                           - delegates to :DapStep into

local quickfix = require("neodap.plugins.utils.quickfix")
local log = require("neodap.logger")

---@param debugger neodap.entities.Debugger
---@return table api Plugin API
return function(debugger)
  local api = {}

  -- Re-export for backwards compatibility
  function api.to_quickfix(entity)
    return quickfix.entry(debugger, entity)
  end

  -- ============================================================================
  -- Quickfix Entity Resolution
  -- ============================================================================

  ---Get the URI for the current quickfix entry
  ---Works during :cdo iteration by reading user_data from current quickfix item
  ---@return string? uri Entity URI or nil
  function api.current_uri()
    local qf = vim.fn.getqflist({ idx = 0 })
    if qf.idx == 0 then
      return nil
    end

    local items = vim.fn.getqflist()
    local item = items[qf.idx]

    if item and item.user_data and item.user_data.uri then
      return item.user_data.uri
    end

    return nil
  end

  ---Resolve a URI to an entity
  ---Delegates to debugger:query for centralized lookup
  ---@param uri_string string URI to resolve
  ---@return any? entity Entity or nil
  function api.resolve_uri(uri_string)
    return debugger:query(uri_string)
  end

  -- ============================================================================
  -- User Command (Router)
  -- ============================================================================

  ---Check if a user command exists
  ---@param name string Command name
  ---@return boolean
  local function command_exists(name)
    return vim.fn.exists(":" .. name) == 2
  end

  ---Convert subcommand to PascalCase for Dap<Command> lookup
  ---@param subcommand string e.g., "jump", "stepin", "run-to-cursor"
  ---@return string e.g., "Jump", "Stepin", "RunToCursor"
  local function to_pascal_case(subcommand)
    -- Handle kebab-case: "run-to-cursor" -> "RunToCursor"
    -- Handle lowercase: "jump" -> "Jump"
    return subcommand:gsub("^%l", string.upper):gsub("%-(%l)", function(c)
      return c:upper()
    end)
  end

  vim.api.nvim_create_user_command("Dap", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local subcommand = args[1]

    if not subcommand then
      log:error("Dap: Missing subcommand")
      return
    end

    -- Get optional arguments (everything after subcommand)
    local rest_args = table.concat(vim.list_slice(args, 2), " ")

    -- Try to delegate to Dap<Command> (e.g., "list" -> "DapList", "jump" -> "DapJump")
    local pascal_name = to_pascal_case(subcommand)
    local dap_command = "Dap" .. pascal_name

    if command_exists(dap_command) then
      vim.cmd(dap_command .. " " .. rest_args)
      return
    end

    log:error("Dap: Unknown subcommand", { subcommand = subcommand })
  end, {
    nargs = "+",
    desc = "DAP command router (delegates to Dap<Command>)",
    complete = function(arglead, cmdline)
      local args = vim.split(cmdline, "%s+", { trimempty = true })

      -- Complete subcommand
      if #args <= 2 then
        local subcommands = {}

        -- Find all Dap* commands and add them as subcommands
        local all_commands = vim.api.nvim_get_commands({})
        for name, _ in pairs(all_commands) do
          local sub = name:match("^Dap(%u.*)$")
          if sub then
            -- Convert PascalCase to lowercase for completion
            local simple = sub:lower()
            if not vim.tbl_contains(subcommands, simple) then
              table.insert(subcommands, simple)
            end
          end
        end

        return vim.tbl_filter(function(cmd)
          return cmd:match("^" .. vim.pesc(arglead))
        end, subcommands)
      end

      return {}
    end,
  })

  -- Cleanup function
  function api.cleanup()
    pcall(vim.api.nvim_del_user_command, "Dap")
  end

  return api
end
