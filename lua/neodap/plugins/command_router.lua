-- Plugin: Unified :Dap command router
-- Routes subcommands to Dap<Command> user commands
--
-- Usage:
--   :Dap list breakpoints                    - delegates to :DapList
--   :Dap continue                            - delegates to :DapContinue
--   :Dap step into                           - delegates to :DapStep into

local quickfix = require("neodap.plugins.utils.quickfix")
local log = require("neodap.logger")
local E = require("neodap.error")

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

  ---Convert PascalCase suffix to kebab-case subcommand for display/completion
  ---@param pascal string e.g., "RunToCursor", "TerminateAll"
  ---@return string e.g., "run-to-cursor", "terminate-all"
  local function to_kebab_case(pascal)
    return pascal:gsub("(%u)", function(c) return "-" .. c:lower() end):sub(2)
  end

  ---Convert subcommand to PascalCase for Dap<Command> lookup
  ---@param subcommand string e.g., "jump", "step-in", "run-to-cursor"
  ---@return string e.g., "Jump", "StepIn", "RunToCursor"
  local function to_pascal_case(subcommand)
    -- Handle kebab-case: "run-to-cursor" -> "RunToCursor"
    -- Handle lowercase: "jump" -> "Jump"
    return subcommand:gsub("^%l", string.upper):gsub("%-(%l)", function(c)
      return c:upper()
    end)
  end

  E.create_command("Dap", function(opts)
    local args = vim.split(opts.args, "%s+", { trimempty = true })
    local subcommand = args[1]

    if not subcommand then
      error(E.warn("Dap: Missing subcommand"), 0)
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

    error(E.warn("Dap: Unknown subcommand '" .. subcommand .. "'"), 0)
  end, {
    nargs = "+",
    desc = "DAP command router (delegates to Dap<Command>)",
    complete = function(arglead, cmdline)
      local args = vim.split(cmdline, "%s+", { trimempty = true })
      local has_trailing_space = cmdline:match("%s$") ~= nil

      -- Still typing the subcommand (e.g. ":Dap ope" or ":Dap ")
      local completing_subcommand = #args < 2 or (#args == 2 and not has_trailing_space)

      if completing_subcommand then
        local subcommands = {}

        -- Find all Dap* commands and add them as subcommands
        local all_commands = vim.api.nvim_get_commands({})
        for name, _ in pairs(all_commands) do
          local sub = name:match("^Dap(%u.*)$")
          if sub then
            -- Convert PascalCase to kebab-case so the round-trip through
            -- to_pascal_case preserves word boundaries:
            -- "RunToCursor" -> "run-to-cursor" -> "RunToCursor"
            local kebab = to_kebab_case(sub)
            if not vim.tbl_contains(subcommands, kebab) then
              table.insert(subcommands, kebab)
            end
          end
        end

        return vim.tbl_filter(function(cmd)
          return cmd:match("^" .. vim.pesc(arglead))
        end, subcommands)
      end

      -- Subcommand is complete — delegate to the target command's completer
      local subcommand = args[2]
      if subcommand then
        local pascal_name = to_pascal_case(subcommand)
        local dap_command = "Dap" .. pascal_name
        local completer = E._completers[dap_command]
        if completer then
          -- Rebuild cmdline as if the user typed `:DapOpen vsplit con...`
          local rest = table.concat(vim.list_slice(args, 3), " ")
          local trailing_space = has_trailing_space and " " or ""
          local delegate_cmdline = dap_command .. " " .. rest .. trailing_space
          return completer(arglead, delegate_cmdline)
        end
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
