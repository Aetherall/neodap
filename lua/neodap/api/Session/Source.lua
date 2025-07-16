local Class = require('neodap.tools.class')
local Logger = require('neodap.tools.logger')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')
local Location = require("neodap.api.Location")

---@class api.SourceProps
---@field id SourceIdentifier
---@field session api.Session
---@field ref dap.Source
---@field _content string? -- Cached content

---@class api.Source: api.SourceProps
---@field new Constructor<api.SourceProps>
local Source = Class()

---Create a source instance
---@param session api.Session
---@param source dap.Source
---@return api.Source
function Source.instanciate(session, source)
  local instance = Source:new({
    id = SourceIdentifier.fromDapSource(source, session),
    session = session,
    ref = source,
    _identifier = nil, -- Lazy-loaded
    _content = nil     -- Lazy-loaded
  })
  return instance
end

function Source:location()
  return Location.fromSource(self, {})
end

-- Core Type Checking Methods

---Check if this is a virtual source (has sourceReference > 0)
---@return boolean
function Source:isVirtual()
  return self.ref.sourceReference and self.ref.sourceReference > 0
end

---Check if this is a file source (no sourceReference, has path)
---@return boolean
function Source:isFile()
  return not self:isVirtual() and self.ref.path and self.ref.path ~= ''
end

-- REMOVED: Source:bufnr() - session-scoped objects cannot manage persistent buffers
-- Use location:manifests(session) instead for proper lifecycle management

---Get filename for display
---@return string
function Source:filename()
  if self:isFile() and self.ref.path then
    return vim.fn.fnamemodify(self.ref.path, ':t')
  else
    return self.ref.name or 'unnamed'
  end
end

---Get string representation
---@return string
function Source:toString()
  return string.format("Source(%s)", self.id:toString())
end

-- Content Access (Internal Use)

---Get content for this source
---@return string?
function Source:content()
  if self._content then
    return self._content
  end
  
  if self:isVirtual() then
    self._content = self:_getDapContent()
  elseif self:isFile() then
    self._content = self:_getFileContent()
  end
  
  return self._content
end

-- Legacy DAP Methods (for backward compatibility)

---Check if this source matches DAP checksums
---@param checksums dap.Checksum[]
---@return boolean
function Source:matchesChecksums(checksums)
  if not checksums or #checksums == 0 then
    return true
  end
  
  local content = self:content()
  if not content then
    return false
  end
  
  for _, checksum in ipairs(checksums) do
    if checksum.algorithm == 'MD5' then
      if vim.fn.md5(content) == checksum.checksum then
        return true
      end
    elseif checksum.algorithm == 'SHA1' then
      if vim.fn.sha1(content) == checksum.checksum then
        return true
      end
    elseif checksum.algorithm == 'SHA256' then
      if vim.fn.sha256(content) == checksum.checksum then
        return true
      end
    end
  end
  
  return false
end

---Get file content by reading from filesystem
---@return string?
function Source:_getFileContent()
  local log = Logger.get("API:Source")
  
  if not self.ref.path or self.ref.path == '' then
    log:warn("Source: No path available for file content")
    return nil
  end
  
  local path = vim.fn.fnamemodify(self.ref.path, ':p')
  
  if vim.fn.filereadable(path) == 0 then
    log:warn("Source: File not readable:", path)
    return nil
  end
  
  local ok, content = pcall(function()
    local lines = vim.fn.readfile(path)
    return table.concat(lines, '\n')
  end)
  
  if not ok then
    log:error("Source: Failed to read file:", path, content)
    return nil
  end
  
  return content
end

---Get virtual content via DAP source request
---@return string?
function Source:_getDapContent()
  local log = Logger.get("API:Source")
  
  if not self.ref.sourceReference or self.ref.sourceReference <= 0 then
    log:warn("Source: No sourceReference for DAP content")
    return nil
  end
  
  log:debug("Source: Requesting DAP content for sourceReference:", self.ref.sourceReference)
  
  local ok, result = pcall(function()
    return self.session.ref.calls:source({
      source = self.ref,
      sourceReference = self.ref.sourceReference
    }):wait()
  end)
  
  if not ok then
    log:error("Source: DAP source request failed:", result)
    return nil
  end
  
  if not result or not result.content then
    log:warn("Source: DAP returned no content for sourceReference:", self.ref.sourceReference)
    return nil
  end
  
  return result.content
end


---@param opts { line?: integer }
---@return fun(): api.Location?
function Source:breakpointLocations(opts)
  local line = opts.line or 1

  local result = self.session.ref.calls:breakpointLocations({
    source = self.ref,
    line = line,
  }):wait()

  if not result or not result.breakpoints then
    return function() return nil end
  end

  local index = 0
    return function()
      index = index + 1
      if index > #result.breakpoints then
        return nil
      end
      local loc = result.breakpoints[index]
      if not loc then
        return nil
      end
      return Location.fromSource(self, loc)
    end
end

return Source