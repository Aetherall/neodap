local Class = require('neodap.tools.class')
local ContentAccessTrait = require('neodap.api.Session.Source.traits.ContentAccessTrait')
-- Location dependency removed - use dependency injection instead
local nio = require('nio')
local Logger = require("neodap.tools.logger")

---@class api.BaseSourceProps
---@field type 'file' | 'virtual' | 'generic'
---@field session api.Session
---@field ref dap.Source
---@field _content string | nil

---@class (partial) api.BaseSource: api.BaseSourceProps, api.ContentAccessTrait
---@field new Constructor<api.BaseSourceProps>
local BaseSource = ContentAccessTrait.extend(Class())

-- Legacy type checking methods removed - use source.type directly

---Create a unique identifier for this source, or nil if unidentifiable
---@return string | nil
function BaseSource:identifier()
  return self.dap_identifier(self.ref)
end

---Check if this source is identifiable
---@return boolean
function BaseSource:isIdentifiable()
  return self:identifier() ~= nil
end

---Check if this source matches a LoadedSource event
---@param loaded_source dap.Source
---@return boolean
function BaseSource:matchesLoadedSource(loaded_source)
  -- Can't match if we're not identifiable
  if not self:isIdentifiable() then
    return false
  end

  -- Match by sourceReference first (most reliable)
  if self.ref.sourceReference and loaded_source.sourceReference then
    return self.ref.sourceReference == loaded_source.sourceReference
  end

  -- Match by path for file sources
  if self.ref.path and loaded_source.path then
    return self.ref.path == loaded_source.path
  end

  -- Match by name as fallback
  if self.ref.name and loaded_source.name then
    return self.ref.name == loaded_source.name
  end

  return false
end

function BaseSource:matchesChecksums(checksums)
  if not self.ref.checksums then
    return false
  end

  if not checksums or #checksums == 0 then
    error("No checksums provided to match against source")
  end

  if #checksums ~= #self.ref.checksums then
    return false
  end

  -- Check if all checksums match
  for _, ref_checksum in ipairs(self.ref.checksums) do
    local found = false
    for _, checksum in ipairs(checksums) do
      if ref_checksum.algorithm == checksum.algorithm and ref_checksum.checksum == checksum.checksum then
        found = true
        break
      end
    end
    if not found then
      return false
    end
  end

  return true
end

---@param other api.BaseSource
function BaseSource:is(other)
  if not other or not other.ref then
    error("Other source must be a valid Source instance")
  end

  if self.ref.sourceReference and other.ref.sourceReference then
    return self.ref.sourceReference == other.ref.sourceReference
  end

  if self.ref.path and other.ref.path then
    return self.ref.path == other.ref.path
  end

  return false
end

---@param other api.BaseSource
function BaseSource:equals(other)
  if not self:is(other) then
    return false
  end

  if not self.ref.checksums and not other.ref.checksums then
    return true
  end

  if not self.ref.checksums or not other.ref.checksums then
    return false
  end

  return other:matchesChecksums(self.ref.checksums)
end

function BaseSource:toString()
  return self.ref.name or 'unnamed'
end

---@param dap dap.Source
function BaseSource.dap_identifier(dap)
  -- Priority order for identification:
  -- 1. path (for file sources)
  if dap.path and dap.path ~= '' then
    return string.format("path:%s", dap.path)
  end

  -- 2. sourceReference (most reliable for virtual sources)
  if dap.sourceReference and dap.sourceReference > 0 then
    return string.format("ref:%d", dap.sourceReference)
  end


  -- 3. name as fallback
  if dap.name and dap.name ~= '' then
    return string.format("name:%s", dap.name)
  end

  -- Return nil for unidentifiable sources instead of throwing
  return nil
end

---@return number | nil
function BaseSource:bufnr()
  if self.type == 'file' then
    return vim.uri_to_bufnr(vim.uri_from_fname(self.ref.path))
  elseif self.type == 'virtual' then
    -- Virtual source buffer handling (synchronous)
    ---@cast self api.VirtualSource
    return self:bufnr()
  else
    -- Generic sources have no buffer
    return nil
  end
end

-- ---@return api.FileSourceBreakpoint
-- function BaseSource:addBreakpoint(opts)
--   local log = Logger.get()
--   log:info("BaseSource:addBreakpoint - Adding breakpoint to source:", self:identifier(), "opts:", opts)
  
--   local location = Location.SourceFile.fromSource(self, opts)
--   log:debug("BaseSource:addBreakpoint - Created location:", location)
  
--   local BreakpointManager = require("neodap.plugins.BreakpointManager")
--   local breakpoint_service = BreakpointManager.for_api(self.session.api)
--   local breakpoint = breakpoint_service:addBreakpoint(location)
--   log:info("BaseSource:addBreakpoint - Breakpoint created with ID:", breakpoint.id)
  
--   return breakpoint
-- end

return BaseSource
