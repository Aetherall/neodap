local M = {}

local function truncate(text, limit)
  if #text > limit then
    return text:sub(1, limit - 3) .. "..."
  end
  return text
end

local function parse_slot(entry)
  if type(entry) == "string" then return entry, {} end
  return entry[1], entry
end

local function setup_highlights()
  local function set(name, opts)
    opts.default = true
    vim.api.nvim_set_hl(0, name, opts)
  end
  -- State
  set("DapStopped", { link = "WarningMsg" })
  set("DapRunning", { link = "DiffAdd" })
  set("DapTerminated", { link = "Comment" })
  set("DapState", { link = "Comment" })
  -- Session / Thread
  set("DapSession", { link = "Type" })
  set("DapThread", { link = "Function" })
  -- Frame
  set("DapFrame", { link = "String" })
  set("DapFrameFocused", { link = "Special" })
  set("DapFrameIndex", { link = "Number" })
  set("DapFrameLabel", { link = "Comment" })
  set("DapFrameSubtle", { link = "Comment" })
  set("DapFrame0", { link = "DapFrame" })
  set("DapFrame1", { link = "DapFrame" })
  set("DapFrame2", { link = "DapFrame" })
  set("DapFrame3", { link = "DapFrame" })
  set("DapFrame4", { link = "DapFrame" })
  -- Source
  set("DapScope", { link = "Keyword" })
  set("DapSource", { link = "Directory" })
  set("DapSourceUser", { link = "Directory" })
  set("DapSourceNormal", { link = "Comment" })
  set("DapSourceInternal", { link = "Comment" })
  -- Variable
  set("DapVarName", { link = "Identifier" })
  set("DapVarType", { link = "Type" })
  set("DapVarValue", { link = "String" })
  -- Breakpoint
  set("DapBreakpointDisabled", { link = "Comment" })
  set("DapBreakpointHit", { link = "WarningMsg" })
  set("DapBreakpointAdjusted", { link = "DiagnosticInfo" })
  set("DapBreakpointVerified", { link = "DiffAdd" })
  set("DapBreakpointUnverified", { link = "Comment" })
  set("DapCondition", { link = "Identifier" })
  set("DapLogMessage", { link = "String" })
  -- Exception filters
  set("DapEnabled", { link = "DiffAdd" })
  set("DapDisabled", { link = "Comment" })
  set("DapFilter", { link = "Identifier" })
  -- Output
  set("DapOutputStdout", { link = "Normal" })
  set("DapOutputStderr", { link = "WarningMsg" })
  set("DapOutputConsole", { link = "Comment" })
  set("DapRepl", { link = "Special" })
  set("DapOutputRepl", { link = "Special" })
  -- Output syntax highlighting (inline preview text)
  set("DapOutputString", { link = "String" })
  set("DapOutputNumber", { link = "Number" })
  set("DapOutputBoolean", { link = "Boolean" })
  set("DapOutputNull", { link = "Constant" })
  set("DapOutputKey", { link = "Identifier" })
  set("DapOutputBrace", { link = "Delimiter" })
  set("DapOutputCollapsed", { link = "Comment" })
  set("DapRepeatBadge", { link = "Number" })
  -- Generic
  set("DapComment", { link = "Comment" })
end

--- Install presentation registry methods on debugger instance
--- Safe to call multiple times (idempotent)
---@param debugger table The debugger to extend
function M.install(debugger)
  -- Guard against double-installation
  -- Use rawget/rawset because neograph returns Signals for any key access
  if rawget(debugger, "_presentation_installed") then return end
  rawset(debugger, "_presentation_installed", true)

  setup_highlights()

  local components = {} -- { [name] = { [entity_type] = fn } }
  local actions = {} -- { [name] = { [entity_type] = fn } }

  --- Register a component renderer for a (name, entity_type) pair
  ---@param name string Component name
  ---@param entity_type string Entity type name
  ---@param fn fun(entity: table): {text: string, hl?: string}|nil
  function debugger:register_component(name, entity_type, fn)
    if not components[name] then components[name] = {} end
    components[name][entity_type] = fn
  end

  --- Register an action handler for a (name, entity_type) pair
  ---@param name string Action name
  ---@param entity_type string Entity type name
  ---@param fn fun(entity: table, ctx?: table): any
  function debugger:register_action(name, entity_type, fn)
    if not actions[name] then actions[name] = {} end
    actions[name][entity_type] = fn
  end

  --- Get a single component segment for an entity
  ---@param name string Component name
  ---@param entity table Entity instance
  ---@return {text: string, hl?: string}|nil
  function debugger:component(name, entity)
    local by_type = components[name]
    if not by_type then return nil end
    local fn = by_type[entity:type()]
    if not fn then return nil end
    return fn(entity)
  end

  --- Get all component segments for an entity
  ---@param entity table Entity instance
  ---@return table<string, {text: string, hl?: string}>
  function debugger:components(entity)
    local etype = entity:type()
    local result = {}
    for name, by_type in pairs(components) do
      local fn = by_type[etype]
      if fn then
        local segment = fn(entity)
        if segment then
          result[name] = segment
        end
      end
    end
    return result
  end

  --- Dispatch an action on an entity
  ---@param name string Action name
  ---@param entity table Entity instance
  ---@param ctx? table Optional context
  ---@return any
  function debugger:action(name, entity, ctx)
    local by_type = actions[name]
    if not by_type then return nil end
    local fn = by_type[entity:type()]
    if not fn then
      -- Show a brief hint when the action exists but not for this entity type
      local available = vim.tbl_keys(by_type)
      if #available > 0 then
        local E = require("neodap.error")
        E.report(E.warn(string.format(
          "'%s' is not available for %s (works on: %s)",
          name, entity:type(), table.concat(available, ", ")
        )))
      end
      return nil
    end
    return fn(entity, ctx)
  end

  --- List action names available for an entity
  ---@param entity table Entity instance
  ---@return string[]
  function debugger:actions_for(entity)
    local etype = entity:type()
    local result = {}
    for name, by_type in pairs(actions) do
      if by_type[etype] then
        result[#result + 1] = name
      end
    end
    table.sort(result)
    return result
  end

  --- Render an entity using a layout, returning segments
  ---
  --- Layout slots support these options:
  ---   prefix    string   Text to prepend (rendered as decoration)
  ---   suffix    string   Text to append (rendered as decoration)
  ---   truncate  number   Max text length (adds "..." if exceeded)
  ---   cursor    boolean  Mark segment as cursor anchor
  ---   align     string   "right" to render as right-aligned virtual text
  ---   hl        string   Override the component's highlight group
  ---   pad_left  number   Spaces to insert before this slot
  ---   pad_right number   Spaces to insert after this slot
  ---
  ---@param entity table Entity instance
  ---@param layout table Layout slots
  ---@return table[] segments { text, hl?, cursor?, decoration?, right_align? }
  function debugger:render(entity, layout)
    local segments = {}
    for _, entry in ipairs(layout) do
      local slot, opts = parse_slot(entry)
      local result = self:component(slot, entity)
      if result then
        local right_align = opts.align == "right" or nil
        local hl_override = opts.hl

        -- Padding before
        if opts.pad_left and opts.pad_left > 0 then
          segments[#segments + 1] = { text = string.rep(" ", opts.pad_left), decoration = true, right_align = right_align }
        end

        if opts.prefix then
          segments[#segments + 1] = { text = opts.prefix, decoration = true, right_align = right_align }
        end
        -- Components can return { segments = { {text, hl}, ... } } for multi-highlight
        if result.segments then
          local remaining = opts.truncate
          for i, seg in ipairs(result.segments) do
            local text = seg.text
            if remaining then
              if #text >= remaining then
                -- This segment exceeds the limit — truncate and stop
                text = truncate(text, remaining)
                segments[#segments + 1] = {
                  text = text,
                  hl = hl_override or seg.hl,
                  cursor = (i == 1 and opts.cursor) or nil,
                  right_align = right_align,
                }
                break
              end
              remaining = remaining - #text
            end
            segments[#segments + 1] = {
              text = text,
              hl = hl_override or seg.hl,
              cursor = (i == 1 and opts.cursor) or nil,
              right_align = right_align,
            }
          end
        else
          local text = result.text
          if opts.truncate and #text > opts.truncate then
            text = truncate(text, opts.truncate)
          end
          segments[#segments + 1] = {
            text = text,
            hl = hl_override or result.hl,
            cursor = opts.cursor or nil,
            right_align = right_align,
          }
        end
        if opts.suffix then
          segments[#segments + 1] = { text = opts.suffix, decoration = true, right_align = right_align }
        end

        -- Padding after
        if opts.pad_right and opts.pad_right > 0 then
          segments[#segments + 1] = { text = string.rep(" ", opts.pad_right), decoration = true, right_align = right_align }
        end
      end
    end
    return segments
  end

  --- Render an entity to plain text using a layout
  ---@param entity table Entity instance
  ---@param layout table Layout slots
  ---@return string
  function debugger:render_text(entity, layout)
    local parts = {}
    for _, seg in ipairs(self:render(entity, layout)) do
      parts[#parts + 1] = seg.text
    end
    return table.concat(parts)
  end

  -- Register default components and actions
  require("neodap.presentation.components").register(debugger)
  require("neodap.presentation.actions").register(debugger)
end

return M
