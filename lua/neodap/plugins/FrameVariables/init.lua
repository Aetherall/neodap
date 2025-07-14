local nio = require("nio")

local name = "FrameVariables"
return {
  name = name,
  description = "Plugin to display frame variables in Neo-tree",
  ---@param api Api
  plugin = function(api)
    local current_frame = nil
    local neotree_available = false
    local source_registered = false
    local cleanup_functions = {}  -- Store cleanup functions for event handlers
    local plugin_destroyed = false  -- Flag to prevent handlers from running after destruction
    local current_variables_buffer = nil  -- Store the current variables buffer for API access
    
    -- Debug: Track plugin initialization (can be removed in production)
    local instance_id = tostring(api):sub(-8)  -- Last 8 chars of API instance for tracking

    -- Neo-tree source definition
    local source = {
      name = "neodap-variables",
      display_name = "Variables",
    }

    -- Convert variable to Neo-tree node format
    local function variable_to_node(var, parent_id)
      local node = {
        id = parent_id and (parent_id .. "." .. var.ref.name) or var.ref.name,
        name = var.ref.name,
        type = "variable",
        extra = {
          value = var.ref.value,
          type = var.ref.type,
          evaluateName = var.ref.evaluateName,
        },
      }

      -- Add value to display
      if var.ref.value then
        node.name = string.format("%s = %s", var.ref.name, var.ref.value)
      end

      -- Check if variable has children
      if var.ref.variablesReference and var.ref.variablesReference > 0 then
        node.has_children = true
        node.children = {}
      end
      
      return node
    end

    -- Get children for a node
    source.get_items = nio.create(function(_, parent_id, callback)
      if not current_frame then
        callback({})
        return
      end

      if not parent_id then
        -- Root level - show scopes
        local scopes = current_frame:scopes()
        if not scopes then
          callback({})
          return
        end

        local nodes = {}
        for _, scope in ipairs(scopes) do
          local node = {
            id = "scope_" .. tostring(scope.ref.variablesReference),
            name = scope.ref.name,
            type = "scope",
            has_children = true,
            children = {},
            extra = {
              expensive = scope.ref.expensive,
              variablesReference = scope.ref.variablesReference,
            },
          }
          table.insert(nodes, node)
        end

        callback(nodes)
      else
        -- Get variables for scope or nested variable
        local variablesReference

        if parent_id:match("^scope_") then
          -- This is a scope
          variablesReference = tonumber(parent_id:sub(7))
        else
          -- This is a nested variable - find it
          -- local parts = vim.split(parent_id, ".", { plain = true })
          -- For now, we'll need to implement proper variable reference tracking
          -- This is a simplified version
          callback({})
          return
        end

        if variablesReference then
          local variables = current_frame:variables(variablesReference)
          if variables then
            local nodes = {}
            for _, var in ipairs(variables) do
              table.insert(nodes, variable_to_node(var, parent_id))
            end
            callback(nodes)
          else
            callback({})
          end
        else
          callback({})
        end
      end
    end, 1)

    -- Refresh Neo-tree when frame changes
    local function refresh_neotree()
      if not neotree_available then return end
      
      vim.schedule(function()
        local ok, manager = pcall(require, "neo-tree.sources.manager")
        if ok and manager then
          local state = manager.get_state("neodap-variables")
          if state and state.tree then
            -- Refresh the tree
            manager.refresh("neodap-variables")
          end
        end
      end)
    end

    -- Try to register Neo-tree source when plugin loads
    local function try_register_neotree()
      if source_registered then return end
      
      local ok, neotree = pcall(require, "neo-tree")
      if ok then
        neotree_available = true
        
        -- Get current sources or use defaults
        local current_sources = vim.g.neo_tree_sources or { "filesystem", "buffers", "git_status" }
        if not vim.tbl_contains(current_sources, "neodap-variables") then
          table.insert(current_sources, "neodap-variables")
        end
        
        neotree.setup({
          sources = current_sources,
          neodap_variables = {
            window = {
              mappings = {
                ["<cr>"] = "toggle_node",
                ["<space>"] = "toggle_node",
              },
            },
          },
        })

        -- Register our source
        local manager_ok, manager = pcall(require, "neo-tree.sources.manager")
        if manager_ok and manager.register then
          manager.register(source)
          source_registered = true
        end
      end
    end
    
    -- Try to register on load
    vim.schedule(try_register_neotree)

    -- Hook into debugging session
    local cleanup_session = api:onSession(function(session)
      -- current_session = session

      local cleanup_thread = session:onThread(function(thread)
        -- current_thread = thread

        local cleanup_stopped = thread:onStopped(function()
          if plugin_destroyed then
            return
          end
          
            
            local stack = thread:stack()
            if not stack then
              return
            end

            current_frame = stack:top()
            if current_frame then
              refresh_neotree()
            end
        end, { name = name .. ".onStopped" })
        
        table.insert(cleanup_functions, cleanup_stopped)

        local cleanup_continued = thread:onContinued(function()
          if plugin_destroyed then
            return
          end
          
          current_frame = nil
          refresh_neotree()
        end, { name = name .. ".onContinued" })
        
        table.insert(cleanup_functions, cleanup_continued)
      end, { name = name .. ".onThread" })
      
      table.insert(cleanup_functions, cleanup_thread)

      local cleanup_terminated = session:onTerminated(function()
        if plugin_destroyed then
          return
        end
        
        -- current_session = nil
        -- current_thread = nil
        current_frame = nil
        refresh_neotree()
      end, { name = name .. ".onTerminated" })
      
      table.insert(cleanup_functions, cleanup_terminated)
    end, { name = name .. ".onSession" })
    
    table.insert(cleanup_functions, cleanup_session)

    -- Command to open the variables window
    -- Check if command already exists (from previous plugin instance)
    if vim.api.nvim_get_commands({})["NeodapVariables"] then
      vim.api.nvim_del_user_command("NeodapVariables")
    end
    vim.api.nvim_create_user_command("NeodapVariables", function()
      if neotree_available then
        vim.cmd("Neotree neodap-variables")
      else
        vim.notify("Neo-tree is not installed. Please install neo-tree.nvim to use this feature.", vim.log.levels.WARN)
      end
    end, {})
    
    -- Interactive tree-like variables display
    local function create_variables_tree()
      if not current_frame then
        vim.notify("No active debugging frame", vim.log.levels.INFO)
        return
      end
      
      nio.run(function()
        -- Tree state
        local expanded = {}
        local tree_data = {}
        local line_to_data = {}
        local variables_cache = {}
        
        -- Function to check if a variable should be lazy evaluated
        local function is_lazy_variable(var_ref)
          return var_ref.presentationHint and 
                 (var_ref.presentationHint.lazy or 
                  var_ref.presentationHint.attributes and 
                  vim.tbl_contains(var_ref.presentationHint.attributes, "lazy"))
        end
        
        -- Function to evaluate a lazy variable using variables() call like VSCode
        local function resolve_lazy_variable(var_entry)
          if not var_entry.ref.variablesReference or var_entry.ref.variablesReference == 0 then
            return nil
          end
          
          local success, resolved_vars = pcall(function()
            return current_frame:variables(var_entry.ref.variablesReference)
          end)
          
          if success and resolved_vars and #resolved_vars == 1 then
            -- Return the resolved variable reference (like VSCode does)
            return resolved_vars[1].ref
          end
          return nil
        end
        
        -- Pre-fetch all variables for expanded nodes (async)
        local function fetch_variables()
          return nio.run(function()
            variables_cache = {}
            
            local scopes = current_frame:scopes()
            if scopes then
              for _, scope in ipairs(scopes) do
                local scope_id = "scope_" .. scope.ref.variablesReference
                if expanded[scope_id] then
                  variables_cache[scope_id] = scope:variables()
                  
                  -- Fetch nested variables and resolve lazy variables
                  if variables_cache[scope_id] then
                    for _, var in ipairs(variables_cache[scope_id]) do
                      local var_id = scope_id .. "_" .. var.ref.name
                      
                      -- Resolve lazy variables during fetch phase
                      if is_lazy_variable(var.ref) then
                        local resolved_ref = resolve_lazy_variable(var)
                        if resolved_ref then
                          -- Update the cached variable with resolved data
                          var.ref = resolved_ref
                        end
                      end
                      
                      if expanded[var_id] and var.ref.variablesReference and var.ref.variablesReference > 0 then
                        variables_cache[var_id] = current_frame:variables(var.ref.variablesReference)
                      end
                    end
                  end
                end
              end
            end
          end)
        end
        
        -- Legacy function to evaluate a lazy variable using evaluate() call
        local function evaluate_lazy_variable(var_entry)
          if not var_entry.ref.evaluateName then
            return nil
          end
          
          local success, result = pcall(function()
            return current_frame.stack.thread.session.ref.calls:evaluate({
              expression = var_entry.ref.evaluateName,
              frameId = current_frame.ref.id,
              threadId = current_frame.stack.thread.id,
              context = "watch"
            }):wait()
          end)
          
          if success and result then
            return result.result
          end
          return nil
        end
        
        -- Build tree structure (sync function, uses cached data)
        local function build_tree(scopes)
          tree_data = {}
          line_to_data = {}
          local lines = {}
          local highlights = {} -- Store highlight information
          
          -- Function to get highlight group based on variable type
          local function get_highlight_group(var_type, var_value)
            if not var_type then return nil end
            
            local type_lower = var_type:lower()
            if type_lower:match("function") then
              return "@function"
            elseif type_lower:match("string") then
              return "@string"
            elseif type_lower:match("number") or type_lower:match("integer") or type_lower:match("float") then
              return "@number"
            elseif type_lower:match("boolean") then
              return "@boolean"
            elseif type_lower:match("class") or (type_lower:match("object") and var_value and tostring(var_value):match("class")) then
              return "@type.definition"
            elseif type_lower:match("object") then
              return "@type"
            elseif type_lower:match("array") then
              return "@constructor"
            elseif type_lower:match("null") or type_lower:match("undefined") then
              return "@constant.builtin"
            else
              return "@variable"
            end
          end
          
          if scopes then
            for _, scope in ipairs(scopes) do
              local scope_id = "scope_" .. scope.ref.variablesReference
              local scope_entry = {
                id = scope_id,
                type = "scope",
                name = scope.ref.name,
                ref = scope.ref,
                indent = 0,
              }
              table.insert(tree_data, scope_entry)
              
              -- Build display line
              local prefix = expanded[scope_id] and "▼ " or "▶ "
              local line = prefix .. scope.ref.name
              table.insert(lines, line)
              line_to_data[#lines] = scope_entry
              
              -- Show variables if expanded
              if expanded[scope_id] and variables_cache[scope_id] then
                local variables = variables_cache[scope_id]
                  for _, var in ipairs(variables) do
                    local var_id = scope_id .. "_" .. var.ref.name
                    local var_entry = {
                      id = var_id,
                      type = "variable",
                      name = var.ref.name,
                      ref = var.ref,
                      indent = 1,
                      parent_id = scope_id,
                    }
                    table.insert(tree_data, var_entry)
                  
                  -- Build display line
                  local var_prefix = "  "
                  local can_expand = (var.ref.variablesReference and var.ref.variablesReference > 0) or is_lazy
                  if can_expand then
                    var_prefix = var_prefix .. (expanded[var_id] and "▼ " or "▶ ")
                  else
                    var_prefix = var_prefix .. "  "
                  end
                  
                  local value = ""
                  local type_str = ""
                  
                  -- Check if this is a lazy variable (already resolved in fetch phase)
                  local is_lazy = is_lazy_variable(var.ref)
                  
                  if is_lazy and not var.ref.value then
                    -- Show lazy indicator for unresolved lazy variables
                    value = " <lazy>"
                    type_str = " : " .. (var.ref.type or "unknown")
                  elseif var.ref.type then
                    -- Show only type for functions, objects, and other complex types
                    if var.ref.type:match("function") then
                      -- Extract function signature
                      if var.ref.value then
                        local val = tostring(var.ref.value)
                        -- Try to extract function signature
                        local signature = val:match("function[^{]*") or val:match("([^{]*){")
                        if signature then
                          -- Clean up the signature
                          signature = signature:gsub("\\n", " "):gsub("\\t", " "):gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
                          -- Remove "function" keyword if present
                          signature = signature:gsub("^function%s*", "")
                          
                          -- Extract just the parameters part
                          local params = signature:match("%(.*%)") or "()"
                          -- Always use the variable name from the debugger + extracted params
                          value = params
                        else
                          value = "()"
                        end
                      else
                        value = "()"
                      end
                    elseif var.ref.type:match("class") or (var.ref.type:match("object") and var.ref.value and tostring(var.ref.value):match("class")) then
                      -- Extract class name and show as ClassName { }
                      if var.ref.value then
                        local val = tostring(var.ref.value)
                        local class_name = val:match("class%s+([%w_]+)") or var.ref.name
                        value = class_name .. " { }"
                      else
                        value = var.ref.name .. " { }"
                      end
                    elseif var.ref.type:match("object") or var.ref.type:match("Object") then
                      value = "{ }"
                    elseif var.ref.type:match("Array") then
                      -- Show array with length if possible
                      if var.ref.value then
                        local val = tostring(var.ref.value)
                        local length = val:match("length:(%d+)") or val:match("%[([%d,]+)%]")
                        if length then
                          value = "[ " .. (length:match("(%d+)") or "...") .. " items ]"
                        else
                          value = "[ ]"
                        end
                      else
                        value = "[ ]"
                      end
                    elseif var.ref.value then
                      -- For primitive types, show the value
                      local val = tostring(var.ref.value):gsub("[\n\r]", "\\n"):gsub("\t", "\\t")
                      if #val > 50 then
                        val = val:sub(1, 50) .. "..."
                      end
                      value = " = " .. val
                    end
                  elseif var.ref.value then
                    -- No type info, just show value
                    local val = tostring(var.ref.value):gsub("[\n\r]", "\\n"):gsub("\t", "\\t")
                    if #val > 50 then
                      val = val:sub(1, 50) .. "..."
                    end
                    value = " = " .. val
                  end
                  
                  local line = var_prefix .. var.ref.name .. value .. type_str
                  table.insert(lines, line)
                  line_to_data[#lines] = var_entry
                  
                  -- Store highlight information for this line
                  local hl_group = get_highlight_group(var.ref.type, var.ref.value)
                  if hl_group then
                    -- Calculate the position of the variable name in the line
                    local name_start = #var_prefix
                    local name_end = name_start + #var.ref.name
                    table.insert(highlights, {
                      line = #lines - 1, -- 0-indexed
                      col_start = name_start,
                      col_end = name_end,
                      hl_group = hl_group
                    })
                  end
                  
                  -- Show nested variables if expanded
                  if expanded[var_id] and variables_cache[var_id] then
                    local nested_vars = variables_cache[var_id]
                    for _, nested_var in ipairs(nested_vars) do
                      local nested_id = var_id .. "_" .. nested_var.name
                      local nested_entry = {
                        id = nested_id,
                        type = "variable",
                        name = nested_var.name,
                        ref = nested_var,
                        indent = 2,
                        parent_id = var_id,
                      }
                      table.insert(tree_data, nested_entry)
                      
                      -- Build display line  
                      local nested_prefix = "    "
                      if nested_var.variablesReference and nested_var.variablesReference > 0 then
                        nested_prefix = nested_prefix .. (expanded[nested_id] and "▼ " or "▶ ")
                      else
                        nested_prefix = nested_prefix .. "  "
                      end
                      
                      local nested_value = ""
                      local nested_type_str = ""
                      
                      -- Check if this is a lazy nested variable
                      local nested_is_lazy = is_lazy_variable(nested_var)
                      
                      if nested_is_lazy and not nested_var.value then
                        -- Show lazy indicator
                        nested_value = " <lazy>"
                        nested_type_str = " : " .. (nested_var.type or "unknown")
                      elseif nested_var.type then
                        -- Show only type for functions, objects, and other complex types
                        if nested_var.type:match("function") then
                          -- Extract function signature
                          if nested_var.value then
                            local val = tostring(nested_var.value)
                            -- Try to extract function signature
                            local signature = val:match("function[^{]*") or val:match("([^{]*){")
                            if signature then
                              -- Clean up the signature
                              signature = signature:gsub("\\n", " "):gsub("\\t", " "):gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
                              -- Remove "function" keyword if present
                              signature = signature:gsub("^function%s*", "")
                              
                              -- Extract just the parameters part
                              local params = signature:match("%(.*%)") or "()"
                              -- Always use the variable name from the debugger + extracted params
                              nested_value = params
                              
                              -- Truncate if too long for nested display
                              if #nested_value > 35 then
                                nested_value = nested_value:sub(1, 35) .. "...)"
                              end
                            else
                              nested_value = "()"
                            end
                          else
                            nested_value = "()"
                          end
                        elseif nested_var.type:match("class") or (nested_var.type:match("object") and nested_var.value and tostring(nested_var.value):match("class")) then
                          -- Extract class name and show as ClassName { }
                          if nested_var.value then
                            local val = tostring(nested_var.value)
                            local class_name = val:match("class%s+([%w_]+)") or nested_var.name
                            nested_value = class_name .. " { }"
                          else
                            nested_value = nested_var.name .. " { }"
                          end
                        elseif nested_var.type:match("object") or nested_var.type:match("Object") then
                          nested_value = "{ }"
                        elseif nested_var.type:match("Array") then
                          -- Show array with length if possible
                          if nested_var.value then
                            local val = tostring(nested_var.value)
                            local length = val:match("length:(%d+)") or val:match("%[([%d,]+)%]")
                            if length then
                              nested_value = "[ " .. (length:match("(%d+)") or "...") .. " items ]"
                            else
                              nested_value = "[ ]"
                            end
                          else
                            nested_value = "[ ]"
                          end
                        elseif nested_var.value then
                          -- For primitive types, show the value
                          local val = tostring(nested_var.value):gsub("[\n\r]", "\\n"):gsub("\t", "\\t")
                          if #val > 40 then
                            val = val:sub(1, 40) .. "..."
                          end
                          nested_value = " = " .. val
                        end
                      elseif nested_var.value then
                        -- No type info, just show value
                        local val = tostring(nested_var.value):gsub("[\n\r]", "\\n"):gsub("\t", "\\t")
                        if #val > 40 then
                          val = val:sub(1, 40) .. "..."
                        end
                        nested_value = " = " .. val
                      end
                      
                      local line = nested_prefix .. nested_var.name .. nested_value .. nested_type_str
                      table.insert(lines, line)
                      line_to_data[#lines] = nested_entry
                      
                      -- Store highlight information for nested variable
                      local nested_hl_group = get_highlight_group(nested_var.type, nested_var.value)
                      if nested_hl_group then
                        local nested_name_start = #nested_prefix
                        local nested_name_end = nested_name_start + #nested_var.name
                        table.insert(highlights, {
                          line = #lines - 1, -- 0-indexed
                          col_start = nested_name_start,
                          col_end = nested_name_end,
                          hl_group = nested_hl_group
                        })
                      end
                    end
                  end
                end
              end
            end
          end
          
          return lines, highlights
        end
        
        -- Initial fetch
        local scopes = current_frame:scopes()
        
        -- Auto-expand all non-expensive scopes by default
        if scopes then
          for _, scope in ipairs(scopes) do
            local scope_id = "scope_" .. scope.ref.variablesReference
            if not scope.ref.expensive then
              expanded[scope_id] = true
            end
          end
        end
        
        fetch_variables():wait()
        local lines, highlights = build_tree(scopes)
        
        vim.schedule(function()
          -- Create buffer
          local buf = vim.api.nvim_create_buf(false, true)
          current_variables_buffer = buf  -- Store buffer for API access
          vim.bo[buf].modifiable = false
          vim.bo[buf].buftype = "nofile"
          vim.bo[buf].filetype = "neodap-variables"
          
          -- Function to refresh display
          local function refresh_display()
            nio.run(function()
              fetch_variables():wait()
              lines, highlights = build_tree(scopes)
              vim.schedule(function()
                vim.bo[buf].modifiable = true
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                vim.bo[buf].modifiable = false
                
                -- Clear existing highlights and apply new ones
                vim.api.nvim_buf_clear_namespace(buf, -1, 0, -1)
                for _, hl in ipairs(highlights) do
                  vim.api.nvim_buf_add_highlight(buf, -1, hl.hl_group, hl.line, hl.col_start, hl.col_end)
                end
              end)
            end)
          end
          
          -- Initial display (we already have lines from above)
          vim.bo[buf].modifiable = true
          vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
          vim.bo[buf].modifiable = false
          
          -- Apply initial syntax highlighting
          for _, hl in ipairs(highlights) do
            vim.api.nvim_buf_add_highlight(buf, -1, hl.hl_group, hl.line, hl.col_start, hl.col_end)
          end
          
          -- Calculate window size
          local width = math.min(100, vim.o.columns - 4)
          -- Make the window much taller - use most of the screen height
          local height = math.min(vim.o.lines - 6, math.max(20, #lines + 2))
          
          -- Create main window (left side)
          local main_width = math.min(60, vim.o.columns / 2 - 2)
          local main_col = math.floor((vim.o.columns - main_width * 2 - 4) / 2)
          
          local win = vim.api.nvim_open_win(buf, true, {
            relative = "editor",
            width = main_width,
            height = height,
            col = main_col,
            row = math.floor((vim.o.lines - height) / 2),
            style = "minimal",
            border = "rounded",
            title = " Frame Variables ",
            title_pos = "center",
          })
          
          -- Create preview buffer and window (right side)
          local preview_buf = vim.api.nvim_create_buf(false, true)
          vim.bo[preview_buf].modifiable = false
          vim.bo[preview_buf].buftype = "nofile"
          
          local preview_win = vim.api.nvim_open_win(preview_buf, false, {
            relative = "editor",
            width = main_width,
            height = height,
            col = main_col + main_width + 2,
            row = math.floor((vim.o.lines - height) / 2),
            style = "minimal",
            border = "rounded",
            title = " Preview ",
            title_pos = "center",
          })
          
          -- Function to update preview
          local function update_preview()
            local cursor_line = vim.api.nvim_win_get_cursor(win)[1]
            local data = line_to_data[cursor_line]
            
            local preview_lines = {}
            
            if data and data.type == "variable" and data.ref then
              -- Always use JavaScript-style comments for metadata
              table.insert(preview_lines, "// Variable: " .. (data.ref.name or "?"))
              table.insert(preview_lines, "// Type: " .. (data.ref.type or "unknown"))
              if data.ref.evaluateName then
                table.insert(preview_lines, "// Expression: " .. data.ref.evaluateName)
              end
              table.insert(preview_lines, "")
              
              if data.ref.value ~= nil then
                local value = tostring(data.ref.value)
                
                -- Format the value
                value = value:gsub("\\n", "\n")
                value = value:gsub("\\t", "  ")
                value = value:gsub("\\r", "")
                
                -- Determine how to display the value
                if data.ref.type and data.ref.type:match("function") then
                  -- Function - display as is
                  for line in value:gmatch("[^\n]+") do
                    table.insert(preview_lines, line)
                  end
                elseif data.ref.type and data.ref.type:match("string") then
                  -- String - wrap in quotes if it's not already
                  if not value:match("^['\"]") then
                    value = '"' .. value:gsub('"', '\\"') .. '"'
                  end
                  -- Handle multi-line strings
                  if value:match("\n") then
                    table.insert(preview_lines, "`")
                    for line in value:gmatch("[^\n]+") do
                      table.insert(preview_lines, line)
                    end
                    table.insert(preview_lines, "`")
                  else
                    table.insert(preview_lines, value)
                  end
                elseif data.ref.type and (data.ref.type:match("number") or data.ref.type:match("boolean")) then
                  -- Numbers and booleans - display as is
                  table.insert(preview_lines, value)
                elseif value == "null" or value == "undefined" then
                  -- Null/undefined - display as is
                  table.insert(preview_lines, value)
                else
                  -- Objects/Arrays/Other - try to format nicely
                  if value:match("\n") then
                    -- Multi-line - probably already formatted
                    for line in value:gmatch("[^\n]+") do
                      table.insert(preview_lines, line)
                    end
                  else
                    -- Single line - might need wrapping
                    local max_width = main_width - 4
                    while #value > 0 do
                      local chunk = value:sub(1, max_width)
                      table.insert(preview_lines, chunk)
                      value = value:sub(max_width + 1)
                    end
                  end
                end
              else
                -- Value is nil
                table.insert(preview_lines, "undefined")
              end
              
              -- Add variable reference info
              if data.ref.variablesReference and data.ref.variablesReference > 0 then
                table.insert(preview_lines, "")
                table.insert(preview_lines, "// This variable has child properties.")
                table.insert(preview_lines, "// Press Enter to expand in the tree view.")
              end
            elseif data and data.type == "scope" then
              -- Scope info - also in JavaScript style
              table.insert(preview_lines, "// Scope: " .. (data.ref.name or "?"))
              table.insert(preview_lines, "//")
              table.insert(preview_lines, "// Press Enter to expand this scope")
              table.insert(preview_lines, "// and see its variables.")
              
              if data.ref.expensive then
                table.insert(preview_lines, "//")
                table.insert(preview_lines, "// Note: This scope is marked as")
                table.insert(preview_lines, "// 'expensive' by the debugger.")
              end
            else
              -- No selection - help text in JavaScript comments
              table.insert(preview_lines, "// Select a variable to preview its value.")
              table.insert(preview_lines, "//")
              table.insert(preview_lines, "// Keyboard shortcuts:")
              table.insert(preview_lines, "//   Enter/Space - Expand/collapse node")
              table.insert(preview_lines, "//   e - Edit variable value in preview pane")
              table.insert(preview_lines, "//   l - Evaluate lazy variable")
              table.insert(preview_lines, "//   E - Expand all nodes")
              table.insert(preview_lines, "//   C - Collapse all nodes")
              table.insert(preview_lines, "//   y - Copy variable value")
              table.insert(preview_lines, "//   ? - Show this help")
              table.insert(preview_lines, "//   q/Esc - Close windows")
            end
            
            -- Update preview buffer
            vim.bo[preview_buf].modifiable = true
            vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, preview_lines)
            vim.bo[preview_buf].modifiable = false
            
            -- Always use JavaScript syntax highlighting for consistency
            vim.bo[preview_buf].filetype = "javascript"
          end
          
          -- Initial preview
          update_preview()
          
          -- Update preview on cursor move
          vim.api.nvim_create_autocmd("CursorMoved", {
            buffer = buf,
            callback = update_preview,
          })
          
          -- Set up keymaps
          local opts = { noremap = true, silent = true, buffer = buf }
          
          -- Toggle expansion
          vim.keymap.set("n", "<CR>", function()
            local line = vim.api.nvim_win_get_cursor(win)[1]
            local data = line_to_data[line]
            if data then
              local can_expand = false
              
              if data.type == "scope" then
                can_expand = true
              elseif data.type == "variable" then
                local is_lazy = is_lazy_variable(data.ref)
                can_expand = (data.ref.variablesReference and data.ref.variablesReference > 0) or is_lazy
              end
              
              if can_expand then
                expanded[data.id] = not expanded[data.id]
                local current_line = vim.api.nvim_win_get_cursor(win)[1]
                refresh_display()
                -- Restore cursor position
                vim.api.nvim_win_set_cursor(win, {current_line, 0})
                update_preview()
              end
            end
          end, opts)
          
          -- Also allow space to toggle
          vim.keymap.set("n", "<Space>", function()
            local line = vim.api.nvim_win_get_cursor(win)[1]
            local data = line_to_data[line]
            if data then
              local can_expand = false
              
              if data.type == "scope" then
                can_expand = true
              elseif data.type == "variable" then
                local is_lazy = is_lazy_variable(data.ref)
                can_expand = (data.ref.variablesReference and data.ref.variablesReference > 0) or is_lazy
              end
              
              if can_expand then
                expanded[data.id] = not expanded[data.id]
                local current_line = vim.api.nvim_win_get_cursor(win)[1]
                refresh_display()
                vim.api.nvim_win_set_cursor(win, {current_line, 0})
                update_preview()
              end
            end
          end, opts)
          
          -- Close windows
          local function close_windows()
            vim.api.nvim_win_close(preview_win, true)
            vim.api.nvim_win_close(win, true)
          end
          
          vim.keymap.set("n", "q", close_windows, opts)
          vim.keymap.set("n", "<Esc>", close_windows, opts)
          
          -- Edit variable value in preview pane
          local edit_mode = false
          local editing_data = nil
          local original_preview_content = nil
          
          local function enter_edit_mode(data)
            edit_mode = true
            editing_data = data
            
            -- Store original preview content
            original_preview_content = vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false)
            
            -- Create edit content
            local edit_lines = {}
            table.insert(edit_lines, "// Editing: " .. data.ref.name)
            table.insert(edit_lines, "// Type: " .. (data.ref.type or "unknown"))
            table.insert(edit_lines, "// Press <C-s> to save, <Esc> to cancel")
            table.insert(edit_lines, "")
            
            -- Add current value for editing
            local current_value = data.ref.value and tostring(data.ref.value) or ""
            current_value = current_value:gsub("\\n", "\n")
            current_value = current_value:gsub("\\t", "  ")
            current_value = current_value:gsub("\\r", "")
            
            if current_value:match("\n") then
              -- Multi-line value
              for line in current_value:gmatch("[^\n]+") do
                table.insert(edit_lines, line)
              end
            else
              table.insert(edit_lines, current_value)
            end
            
            -- Set up edit buffer
            vim.bo[preview_buf].modifiable = true
            vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, edit_lines)
            vim.bo[preview_buf].filetype = "javascript"
            
            -- Move cursor to start of value (after comments)
            vim.api.nvim_win_set_cursor(preview_win, {5, 0})
            
            -- Focus the preview window for editing
            vim.api.nvim_set_current_win(preview_win)
          end
          
          local function exit_edit_mode(save)
            if not edit_mode then return end
            
            if save and editing_data then
              -- Get the edited content (skip comment lines)
              local all_lines = vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false)
              local value_lines = {}
              local in_value = false
              
              for i, line in ipairs(all_lines) do
                if i > 4 then -- Skip the first 4 comment/header lines
                  table.insert(value_lines, line)
                end
              end
              
              local new_value = table.concat(value_lines, "\n")
              
              -- Trim trailing newlines
              new_value = new_value:gsub("\n+$", "")
              
              if new_value ~= (editing_data.ref.value and tostring(editing_data.ref.value) or "") then
                -- Use setVariable DAP request to update the value
                nio.run(function()
                  local success, err = pcall(function()
                    -- Find the parent scope's variables reference
                    local parent_ref = nil
                    if editing_data.parent_id then
                      if editing_data.parent_id:match("^scope_") then
                        -- Direct child of scope
                        parent_ref = tonumber(editing_data.parent_id:match("scope_(%d+)"))
                      else
                        -- Nested variable - find the parent variable's reference
                        for _, tree_item in ipairs(tree_data) do
                          if tree_item.id == editing_data.parent_id and tree_item.ref.variablesReference then
                            parent_ref = tree_item.ref.variablesReference
                            break
                          end
                        end
                      end
                    end
                    
                    if not parent_ref then
                      error("Could not determine parent scope for variable")
                    end
                    
                    local response = current_frame.stack.thread.session.ref.calls:setVariable({
                      variablesReference = parent_ref,
                      name = editing_data.ref.name,
                      value = new_value,
                      threadId = current_frame.stack.thread.id,
                    }):wait()
                    
                    if response and response.value then
                      vim.schedule(function()
                        vim.notify("Variable updated: " .. editing_data.ref.name .. " = " .. response.value, vim.log.levels.INFO)
                        -- Refresh the display to show new value
                        refresh_display()
                      end)
                    end
                  end)
                  
                  if not success then
                    vim.schedule(function()
                      vim.notify("Failed to update variable: " .. (err or "unknown error"), vim.log.levels.ERROR)
                    end)
                  end
                end)
              end
            end
            
            -- Reset state
            edit_mode = false
            editing_data = nil
            
            -- Restore preview content
            vim.bo[preview_buf].modifiable = true
            if original_preview_content then
              vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, original_preview_content)
            end
            vim.bo[preview_buf].modifiable = false
            
            -- Return focus to main window
            vim.api.nvim_set_current_win(win)
            
            -- Update preview
            update_preview()
          end
          
          vim.keymap.set("n", "e", function()
            local line = vim.api.nvim_win_get_cursor(win)[1]
            local data = line_to_data[line]
            if data and data.type == "variable" and data.ref then
              enter_edit_mode(data)
            else
              vim.notify("Select a variable to edit", vim.log.levels.WARN)
            end
          end, opts)
          
          -- Evaluate lazy variable
          vim.keymap.set("n", "l", function()
            local line = vim.api.nvim_win_get_cursor(win)[1]
            local data = line_to_data[line]
            if data and data.type == "variable" and data.ref then
              local is_lazy = is_lazy_variable(data.ref)
              if is_lazy then
                nio.run(function()
                  vim.schedule(function()
                    vim.notify("Evaluating lazy variable...", vim.log.levels.INFO)
                  end)
                  
                  local result = evaluate_lazy_variable(data)
                  if result then
                    -- Update the variable with the evaluated result
                    data.ref.value = result.value
                    data.ref.type = result.type or data.ref.type
                    data.ref.presentationHint = result.presentationHint
                    data.ref.variablesReference = result.variablesReference or 0
                    
                    -- If the evaluated result has children, we need to clear the cache
                    -- so it gets re-fetched with the new variablesReference
                    if data.ref.variablesReference and data.ref.variablesReference > 0 then
                      -- Clear any existing cache for this variable
                      variables_cache[data.id] = nil
                      
                      -- If this variable is expanded, we need to fetch its children
                      if expanded[data.id] then
                        -- Re-fetch the children with the new variablesReference
                        local success, children = pcall(function()
                          return current_frame:variables(data.ref.variablesReference)
                        end)
                        
                        if success and children then
                          variables_cache[data.id] = children
                        end
                      end
                    end
                    
                    vim.schedule(function()
                      vim.notify("Lazy variable evaluated", vim.log.levels.INFO)
                      refresh_display()
                      update_preview()
                    end)
                  else
                    vim.schedule(function()
                      vim.notify("Failed to evaluate lazy variable", vim.log.levels.ERROR)
                    end)
                  end
                end)
              else
                vim.notify("Variable is not lazy", vim.log.levels.INFO)
              end
            else
              vim.notify("Select a lazy variable to evaluate", vim.log.levels.WARN)
            end
          end, opts)
          
          -- Expand all (moved to uppercase E)
          vim.keymap.set("n", "E", function()
            for _, data in ipairs(tree_data) do
              if data.type == "scope" or 
                 (data.type == "variable" and data.ref.variablesReference and data.ref.variablesReference > 0) then
                expanded[data.id] = true
              end
            end
            refresh_display()
            update_preview()
          end, opts)
          
          -- Collapse all
          vim.keymap.set("n", "C", function()
            expanded = {}
            refresh_display()
            update_preview()
          end, opts)
          
          -- Copy value to clipboard
          vim.keymap.set("n", "y", function()
            local line = vim.api.nvim_win_get_cursor(win)[1]
            local data = line_to_data[line]
            if data and data.type == "variable" and data.ref.value then
              vim.fn.setreg("+", tostring(data.ref.value))
              vim.notify("Value copied to clipboard", vim.log.levels.INFO)
            end
          end, opts)
          
          -- Set up preview window keybindings for edit mode
          local preview_opts = { noremap = true, silent = true, buffer = preview_buf }
          
          -- Save changes in edit mode
          vim.keymap.set("n", "<C-s>", function()
            if edit_mode then
              exit_edit_mode(true)
            end
          end, preview_opts)
          
          vim.keymap.set("i", "<C-s>", function()
            if edit_mode then
              vim.cmd("stopinsert")
              exit_edit_mode(true)
            end
          end, preview_opts)
          
          -- Cancel edit mode
          vim.keymap.set("n", "<Esc>", function()
            if edit_mode then
              exit_edit_mode(false)
            else
              close_windows()
            end
          end, preview_opts)
          
          -- Show help
          vim.keymap.set("n", "?", function()
            vim.notify([[Frame Variables Help:
Enter/Space - Expand/collapse node
e - Edit variable value in preview pane
l - Evaluate lazy variable
E - Expand all
C - Collapse all  
y - Copy variable value to clipboard
q/Esc - Close window

Edit Mode (in preview):
<C-s> - Save changes
<Esc> - Cancel editing]], vim.log.levels.INFO)
          end, opts)
        end)
      end)
    end
    
    -- Also provide a command to show variables in a floating window as a fallback
    -- Check if command already exists (from previous plugin instance)
    local existing_cmd = vim.api.nvim_get_commands({})["NeodapVariablesFloat"]
    if existing_cmd then
      print("[FrameVariables] WARNING: NeodapVariablesFloat command already exists!")
      -- Delete the old command before creating new one
      vim.api.nvim_del_user_command("NeodapVariablesFloat")
    end
    vim.api.nvim_create_user_command("NeodapVariablesFloat", create_variables_tree, {})

    -- Cleanup function
    local function destroy()
      -- Set destroyed flag to prevent handlers from running
      plugin_destroyed = true
      
      -- Clean up all event handlers
      for _, cleanup in ipairs(cleanup_functions) do
        pcall(cleanup)
      end
      cleanup_functions = {}
      
      -- Delete user commands
      pcall(vim.api.nvim_del_user_command, "NeodapVariables")
      pcall(vim.api.nvim_del_user_command, "NeodapVariablesFloat")
      
      -- Clear frame and buffer references
      current_frame = nil
      current_variables_buffer = nil
    end
    
    return {
      refresh = refresh_neotree,
      get_current_frame = function() return current_frame end,
      get_variables_buffer = function() return current_variables_buffer end,
      try_register_neotree = try_register_neotree,
      destroy = destroy,
    }
  end
}