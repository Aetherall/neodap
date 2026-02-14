--- Entity Buffer: URL-bound reactive buffers for entities
---
--- Provides a framework for creating buffers that:
--- - Bind to URLs (not static URIs) for dynamic resolution
--- - Update reactively when the watched entity changes
--- - Handle dirty tracking for editable buffers
--- - Clean up automatically via scoped
---
--- Usage:
---   local entity_buffer = require("neodap.plugins.utils.entity_buffer")
---   entity_buffer.register("dap-var", "Variable", "one", {
---     render = function(bufnr, entity) return entity.value:get() end,
---     submit = function(bufnr, entity, content) entity:setValue(content) end,
---   })

local scoped = require("neodap.scoped")
local log = require("neodap.logger")
local a = require("neodap.async")

local M = {}

-- Registry: scheme -> { entity_type, cardinality, opts }
local registry = {}

-- Active buffers: bufnr -> { scheme, url, options, scope, entity, original_content }
local buffers = {}

-- Debugger instance (set via init)
local debugger = nil

-- Plugin scope (set via init)
local plugin_scope = nil

-- Forward declarations
local validate_result

---Check if the resolved entity has changed (by URI comparison for single, always true for many)
---@param reg table Registration config
---@param old_entity any Previous entity
---@param new_entity any New entity
---@return boolean
local function has_entity_changed(reg, old_entity, new_entity)
  if reg.cardinality == "many" then return true end
  local ok, result = pcall(function()
    local old_uri = old_entity and old_entity.uri and old_entity.uri:get()
    local new_uri = new_entity and new_entity.uri and new_entity.uri:get()
    return old_uri ~= new_uri
  end)
  return not ok or result
end

--------------------------------------------------------------------------------
-- URI Parsing
--------------------------------------------------------------------------------

--- Parse entity buffer URI: scheme://type/url?options or scheme:url?options
---@param uri string Full URI (e.g., "dap://var/@frame/scopes[0]/variables:myVar?closeonsubmit")
---@return string? scheme Full scheme including type (e.g., "dap://var")
---@return string? url The URL part after the scheme
---@return table options Parsed query options
local function parse_uri(uri)
  local scheme, rest

  -- Try URI style first: scheme://type/rest
  scheme, rest = uri:match("^([%w%-]+://[%w%-]+)/(.*)$")

  -- Fall back to simple style: scheme:rest
  if not scheme then
    scheme, rest = uri:match("^([%w%-]+):(.*)$")
  end

  if not scheme or not rest then
    return nil, nil, {}
  end

  -- Split rest into url and options at ?
  local url, options_str = rest:match("^([^?]*)%??(.*)$")
  url = url or rest
  options_str = options_str or ""

  -- Parse options (key or key=value, separated by &)
  local options = {}
  if options_str ~= "" then
    for part in options_str:gmatch("[^&]+") do
      local key, value = part:match("^([^=]+)=?(.*)$")
      if key then
        if value == "" then
          options[key] = true
        elseif value == "true" then
          options[key] = true
        elseif value == "false" then
          options[key] = false
        elseif tonumber(value) then
          options[key] = tonumber(value)
        else
          options[key] = value
        end
      end
    end
  end

  return scheme, url, options
end

--------------------------------------------------------------------------------
-- Buffer State
--------------------------------------------------------------------------------

--- Check if buffer content differs from original
---@param bufnr number
---@return boolean is_dirty
---@return string current_content
local function check_dirty(bufnr)
  local state = buffers[bufnr]
  if not state then return false, "" end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local current = table.concat(lines, "\n")
  local is_dirty = current ~= (state.original_content or "")

  return is_dirty, current
end

--- Get current content from buffer
---@param bufnr number
---@return string
local function get_content(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

--- Set buffer content
---@param bufnr number
---@param content string|string[]
local function set_content(bufnr, content)
  local lines
  if type(content) == "string" then
    lines = vim.split(content, "\n")
  else
    lines = content
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
end

--------------------------------------------------------------------------------
-- Rendering
--------------------------------------------------------------------------------

--- Render entity to buffer
---@param bufnr number
---@param reg table Registration config
---@param entity any Entity or array of entities
---@param is_initial boolean Whether this is initial render
local function render_buffer(bufnr, reg, entity, is_initial)
  local state = buffers[bufnr]
  if not state then return end

  -- Call render
  local content = reg.opts.render(bufnr, entity)
  if content == nil then
    content = ""
  end

  -- Set content
  set_content(bufnr, content)

  -- Store as original for dirty tracking
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  state.original_content = table.concat(lines, "\n")
  state.entity = entity

  -- Mark as not modified
  vim.bo[bufnr].modified = false
end

--- Handle entity change (URL resolved to different entity)
---@param bufnr number
---@param reg table Registration config
---@param new_entity any New entity
---@param old_entity any Previous entity
local function handle_entity_change(bufnr, reg, new_entity, old_entity)
  local is_dirty = check_dirty(bufnr)
  local policy = reg.opts.on_change or "skip_if_dirty"

  local should_update = false

  if type(policy) == "function" then
    should_update = policy(bufnr, old_entity, new_entity, is_dirty)
  elseif policy == "always" then
    should_update = true
  elseif policy == "skip_if_dirty" then
    should_update = not is_dirty
  elseif policy == "prompt" then
    if is_dirty then
      -- TODO: implement prompt
      should_update = false
    else
      should_update = true
    end
  end

  if should_update then
    render_buffer(bufnr, reg, new_entity, false)
  end
end

--------------------------------------------------------------------------------
-- Buffer Setup
--------------------------------------------------------------------------------

--- Setup buffer for entity
---@param bufnr number
---@param scheme string
---@param url string
---@param options table Parsed URL options
---@param reg table Registration config
local function setup_buffer(bufnr, scheme, url, options, reg)
  -- Default buffer options
  vim.bo[bufnr].buftype = reg.opts.submit and "acwrite" or "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true

  -- Create buffer scope for cleanup
  local buffer_scope = scoped.createScope(plugin_scope)

  -- Store state
  buffers[bufnr] = {
    scheme = scheme,
    url = url,
    options = options,
    scope = buffer_scope,
    entity = nil,
    original_content = "",
  }

  -- Watch URL for entity resolution
  local watch = debugger:watch(url)
  if not watch then
    set_content(bufnr, { "-- Error: Could not watch URL", "-- " .. url })
    vim.bo[bufnr].modifiable = false
    return
  end

  -- Get initial watched result
  local result = watch:get()

  -- Subscribe to changes for an entity
  local function setup_subscription(initial_entity)
    scoped.withScope(buffer_scope, function()
      local prev_entity = initial_entity
      watch:use(function(new_result)
        local function apply_change(new_entity)
          if not has_entity_changed(reg, prev_entity, new_entity) then return end
          handle_entity_change(bufnr, reg, new_entity, prev_entity)
          prev_entity = new_entity
        end

        if reg.opts.resolve then
          a.run(function()
            return reg.opts.resolve(new_result, options)
          end, function(err, new_entity)
            vim.schedule(function()
              if not vim.api.nvim_buf_is_valid(bufnr) then return end
              if err then return end
              apply_change(new_entity)
            end)
          end)
        else
          vim.schedule(function()
            if not vim.api.nvim_buf_is_valid(bufnr) then return end
            local new_entity, err = validate_result(new_result, reg)
            if err then return end
            apply_change(new_entity)
          end)
        end
      end)
    end)
  end

  -- Helper to complete buffer setup after entity is resolved
  local function complete_setup(entity)
    -- Final validation for resolved entity
    if entity == nil and not reg.opts.optional then
      set_content(bufnr, { "-- Error: Entity resolved to nil", "-- URL: " .. url })
      vim.bo[bufnr].modifiable = false
      if watch.dispose then watch:dispose() end
      return
    end

    -- Initial render
    render_buffer(bufnr, reg, entity, true)

    -- Call setup if provided
    if reg.opts.setup then
      reg.opts.setup(bufnr, entity, options)
    end

    -- Make read-only if no submit handler
    if not reg.opts.submit then
      vim.bo[bufnr].modifiable = false
    end

    -- Setup subscription for future changes
    setup_subscription(entity)
  end

  -- Apply resolve transform if provided
  if reg.opts.resolve then
    -- Show loading state
    set_content(bufnr, { "-- Loading..." })
    vim.bo[bufnr].modifiable = false

    -- Run resolve async (supports both sync and async resolve functions)
    a.run(function()
      return reg.opts.resolve(result, options)
    end, function(err, entity)
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(bufnr) then return end
        vim.bo[bufnr].modifiable = true

        if err then
          -- Split error message by newlines and prefix each line
          local err_str = tostring(err)
          local err_lines = { "-- Error resolving entity:" }
          for line in err_str:gmatch("[^\n]+") do
            table.insert(err_lines, "-- " .. line)
          end
          set_content(bufnr, err_lines)
          vim.bo[bufnr].modifiable = false
          if watch.dispose then watch:dispose() end
          return
        end

        complete_setup(entity)
      end)
    end)
  else
    -- Validate entity type and cardinality (only when no custom resolve)
    local entity, validation_error = validate_result(result, reg)
    if validation_error then
      set_content(bufnr, { "-- Error: " .. validation_error, "-- URL: " .. url })
      vim.bo[bufnr].modifiable = false
      if watch.dispose then watch:dispose() end
      return
    end

    complete_setup(entity)
  end

  -- Setup submit handler for editable buffers
  if reg.opts.submit then
    vim.api.nvim_create_autocmd("BufWriteCmd", {
      buffer = bufnr,
      callback = function()
        M.submit(bufnr)
        vim.bo[bufnr].modified = false
      end,
    })
  end
end

--- Validate result matches expected type and cardinality
---@param result any Query result
---@param reg table Registration config
---@return any entity Valid entity or array
---@return string? error Error message if validation failed
validate_result = function(result, reg)
  if result == nil then
    if reg.opts.optional then
      return nil, nil -- Allow nil when optional
    end
    return nil, "URL resolved to nil"
  end

  if reg.cardinality == "one" then
    -- Expect single entity
    local entity = result
    if type(result) == "table" and result[1] and not result._id then
      -- Array - take first
      entity = result[1]
    end

    if not entity or not entity._id then
      if reg.opts.optional then
        return nil, nil -- Allow nil when optional
      end
      return nil, "Expected single entity"
    end

    -- Type check
    if reg.entity_type and entity:type() ~= reg.entity_type then
      return nil, string.format("Expected %s, got %s", reg.entity_type, entity:type())
    end

    return entity, nil

  else -- "many"
    -- Expect array of entities
    local entities = result
    if type(result) == "table" and result._id then
      -- Single entity - wrap in array
      entities = { result }
    end

    if type(entities) ~= "table" then
      return nil, "Expected array of entities"
    end

    -- Type check each
    if reg.entity_type then
      for i, entity in ipairs(entities) do
        if entity:type() ~= reg.entity_type then
          return nil, string.format("Entity %d: expected %s, got %s", i, reg.entity_type, entity:type())
        end
      end
    end

    return entities, nil
  end
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

--- Cleanup buffer state
---@param bufnr number
local function cleanup_buffer(bufnr)
  local state = buffers[bufnr]
  if not state then return end

  -- Call cleanup if provided
  local reg = registry[state.scheme]
  if reg and reg.opts.cleanup then
    pcall(reg.opts.cleanup, bufnr)
  end

  -- Cancel scope (cleans up watch subscription)
  if state.scope then
    state.scope:cancel()
  end

  buffers[bufnr] = nil
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Initialize entity_buffer with debugger instance
--- Safe to call multiple times (idempotent)
---@param dbg table Debugger instance
function M.init(dbg)
  -- Guard against double-initialization with same debugger
  if debugger == dbg then return end

  debugger = dbg
  plugin_scope = scoped.current()

  -- Create augroup for all entity buffers
  local group = vim.api.nvim_create_augroup("neodap-entity-buffer", { clear = true })

  -- Cleanup on buffer wipeout
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    callback = function(opts)
      if buffers[opts.buf] then
        cleanup_buffer(opts.buf)
      end
    end,
  })
end

--- Register an entity buffer scheme
---@param scheme string URI scheme (e.g., "dap-var")
---@param entity_type string Expected entity type (e.g., "Variable")
---@param cardinality "one"|"many" Expected cardinality
---@param opts table Configuration options
---  - render: function(bufnr, entity) -> string  Required. Render entity to buffer content
---  - submit: function(bufnr, entity, content)   Optional. Handle content submission
---  - setup: function(bufnr, entity, options)    Optional. Setup buffer keymaps etc.
---  - cleanup: function(bufnr)                   Optional. Cleanup on buffer wipeout
---  - resolve: function(watched, options) -> entity  Optional. Transform watched entity
---  - on_change: "always"|"skip_if_dirty"|"prompt"|function  Optional. Default: "skip_if_dirty"
---  - optional: boolean                          Optional. Allow nil entity
function M.register(scheme, entity_type, cardinality, opts)
  assert(scheme, "scheme is required")
  assert(cardinality == "one" or cardinality == "many", "cardinality must be 'one' or 'many'")
  assert(opts.render, "render function is required")

  registry[scheme] = {
    entity_type = entity_type,
    cardinality = cardinality,
    opts = opts,
  }

  -- Create autocmd for this scheme
  -- Replace special chars in scheme for augroup name
  local group_name = "neodap-entity-buffer-" .. scheme:gsub("[:/]", "-")
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })

  -- Use /* for URI-style schemes (dap://var), :* for simple schemes (dap-var)
  local pattern = scheme:find("://") and (scheme .. "/*") or (scheme .. ":*")

  vim.api.nvim_create_autocmd("BufReadCmd", {
    pattern = pattern,
    group = group,
    callback = function(ev)
      local bufnr = ev.buf
      local uri = ev.file

      local parsed_scheme, url, options = parse_uri(uri)
      if not parsed_scheme or parsed_scheme ~= scheme then
        log:error("entity_buffer: invalid URI", { uri = uri })
        return
      end

      local ok, err = pcall(setup_buffer, bufnr, scheme, url, options, registry[scheme])
      if not ok then
        vim.bo[bufnr].modifiable = true
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
          "-- entity_buffer error:",
          "-- " .. tostring(err),
        })
        vim.bo[bufnr].modifiable = false
      end
    end,
  })
end

--- Submit buffer content (for editable buffers)
---@param bufnr? number Buffer number (default: current)
function M.submit(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffers[bufnr]
  if not state then return end

  local reg = registry[state.scheme]
  if not reg or not reg.opts.submit then
    log:warn("entity_buffer: buffer is not editable")
    return
  end

  local is_dirty, content = check_dirty(bufnr)
  if not is_dirty then
    log:info("entity_buffer: no changes to submit")
    return
  end

  local entity = state.entity
  if not entity then
    log:error("entity_buffer: no entity bound")
    return
  end

  -- Call submit
  local ok, err = pcall(reg.opts.submit, bufnr, entity, content)
  if ok then
    -- Update original content
    state.original_content = content
    vim.bo[bufnr].modified = false

    -- Close if option set
    if state.options.closeonsubmit then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  else
    log:error("entity_buffer: submit failed", { error = tostring(err) })
  end
end

--- Get entity bound to buffer
---@param bufnr? number Buffer number (default: current)
---@return any? entity
function M.get_entity(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffers[bufnr]
  return state and state.entity
end

--- Get URL bound to buffer
---@param bufnr? number Buffer number (default: current)
---@return string? url
function M.get_url(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffers[bufnr]
  return state and state.url
end

--- Check if buffer has unsaved changes
---@param bufnr? number Buffer number (default: current)
---@return boolean
function M.is_dirty(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local is_dirty = check_dirty(bufnr)
  return is_dirty
end

--- Reset buffer to original content
---@param bufnr? number Buffer number (default: current)
function M.reset(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = buffers[bufnr]
  if not state then return end

  set_content(bufnr, state.original_content)
  vim.bo[bufnr].modified = false
end

--- Get the render function for a scheme (for preview handler delegation)
---@param scheme string URI scheme (e.g., "dap://source/")
---@return function? render The render function, or nil if scheme not registered
function M.get_renderer(scheme)
  local reg = registry[scheme]
  return reg and reg.opts.render
end

--- Get the setup function for a scheme (for preview handler delegation)
---@param scheme string URI scheme (e.g., "dap://source/")
---@return function? setup The setup function, or nil if not provided
function M.get_setup(scheme)
  local reg = registry[scheme]
  return reg and reg.opts.setup
end

return M
