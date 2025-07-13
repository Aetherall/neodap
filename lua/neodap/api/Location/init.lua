local SourceFilePosition  = require('neodap.api.Location.SourceFilePosition')
local SourceFileLine = require('neodap.api.Location.SourceFileLine')
local SourceFile = require('neodap.api.Location.SourceFile')

-- Create a factory module that exports the create method and backward compatibility
local Location = {}

---@param source api.FileSource
---@param opts { line?: integer, column?: integer }
---@return api.SourceFilePosition | api.SourceFileLine | api.SourceFile
function Location.fromSource(source, opts)
  return Location.create({
    path = source:absolutePath(),
    line = opts.line,
    column = opts.column,
  })
end

---@param opts { path: string, line?: integer, column?: integer }
---@return api.SourceFilePosition | api.SourceFileLine | api.SourceFile
function Location.create(opts)
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

---@param dapBinding dap.Breakpoint
---@return api.SourceFilePosition | api.SourceFileLine | api.SourceFile | nil
function Location.fromDapBinding(dapBinding)
  if not dapBinding.source or not dapBinding.source.path or not dapBinding.line then
    return nil
  end

  return Location.create({
    path = dapBinding.source.path,
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

return Location