local SourceFilePosition  = require('neodap.api.Location.SourceFilePosition')
local SourceFileLine = require('neodap.api.Location.SourceFileLine')
local SourceFile = require('neodap.api.Location.SourceFile')
local SourceIdentifier = require('neodap.api.Location.SourceIdentifier')

-- Create a factory module that exports the create method and backward compatibility
local Location = {}

---Create location from any source type
---@param source api.Source
---@param opts { line?: integer, column?: integer }
---@return api.SourceFilePosition | api.SourceFileLine | api.SourceFile
function Location.fromSource(source, opts)
  local identifier = source:identifier()
  return Location.createWithIdentifier({
    source_identifier = identifier,
    line = opts.line,
    column = opts.column,
  })
end

---NEW: Create location with source identifier
---@param opts { source_identifier: SourceIdentifier, line?: integer, column?: integer }
---@return api.SourceFilePosition | api.SourceFileLine | api.SourceFile
function Location.createWithIdentifier(opts)
  local base_opts = {
    source_identifier = opts.source_identifier,
    line = opts.line,
    column = opts.column
  }
  
  if opts.line and opts.column then
    return SourceFilePosition.createWithIdentifier(base_opts)
  elseif opts.line then
    return SourceFileLine.createWithIdentifier(base_opts)
  else
    return SourceFile.createWithIdentifier(base_opts)
  end
end

---Enhanced create method supporting both path and source_identifier
---@param opts { path?: string, source_identifier?: SourceIdentifier, line?: integer, column?: integer }
---@return api.SourceFilePosition | api.SourceFileLine | api.SourceFile
function Location.create(opts)
  -- Handle new source_identifier parameter
  if opts.source_identifier then
    return Location.createWithIdentifier({
      source_identifier = opts.source_identifier,
      line = opts.line,
      column = opts.column
    })
  end
  
  -- Backward compatibility: path-based creation
  if opts.path then
    if opts.line and opts.column then
      return SourceFilePosition.create({ 
        path = opts.path,
        line = opts.line,
        column = opts.column,
      })
    end

    if opts.line then
      return SourceFileLine.create({
        path = opts.path,
        line = opts.line,
      })
    end

    return SourceFile.create({
      path = opts.path,
    })
  end
  
  error("Location.create requires either 'path' or 'source_identifier'")
end

---Enhanced fromDapBinding supporting both file and virtual sources
---@param dapBinding dap.Breakpoint
---@return api.SourceFilePosition | api.SourceFileLine | api.SourceFile | nil
function Location.fromDapBinding(dapBinding)
  if not dapBinding.source then
    return nil
  end
  
  -- Create source identifier from DAP source
  local success, identifier = pcall(SourceIdentifier.fromDapSource, dapBinding.source)
  if not success then
    return nil -- Cannot identify this source
  end
  
  return Location.createWithIdentifier({
    source_identifier = identifier,
    line = dapBinding.line,
    column = dapBinding.column,
  })
end

---@return api.SourceFilePosition
function Location.fromCursor()
  return SourceFilePosition.fromCursor()
end

-- Backward compatibility - export SourceFile as the previous interface
Location.SourceFile = SourceFilePosition


---@alias api.Location api.SourceFilePosition | api.SourceFileLine | api.SourceFile

return Location