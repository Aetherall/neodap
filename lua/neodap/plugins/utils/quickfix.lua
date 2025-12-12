-- Shared quickfix utilities for entity display

local M = {}

local LAYOUTS = {
  Session = { "title", { "state", prefix = " " } },
  Thread = { "title", { "state", prefix = " " }, { "detail", prefix = " " } },
  Frame = { "index", { "title", prefix = " " } },
  Breakpoint = { "icon", { "state", prefix = " " }, { "condition", prefix = " " } },
  Variable = { "title", { "type", prefix = ": " }, { "value", prefix = " = " } },
  Scope = { "title" },
  Source = { "title" },
  ExceptionFilterBinding = { "icon", { "title", prefix = " " }, { "condition", prefix = " " } },
  ExceptionFilter = { "icon", { "title", prefix = " " } },
}

---Convert an entity to a quickfix entry
---@param debugger any Debugger instance
---@param entity any Entity to convert
---@return table entry Quickfix entry
function M.entry(debugger, entity)
  local layout = LAYOUTS[entity:type()]
  local text
  if layout then
    text = debugger:render_text(entity, layout)
  else
    text = string.format("%s: %s", entity:type(), entity.uri:get())
  end

  local entry = {
    user_data = {
      uri = entity.uri:get(),
      id = entity:id(),
      entity_type = entity:type(),
    },
    text = text,
  }

  if type(entity.location) == "function" then
    local loc = entity:location()
    if loc then
      entry.filename = loc.path
      entry.lnum = loc.line or 1
      entry.col = loc.column or 1
    end
  end

  return entry
end

return M
