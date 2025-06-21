---@class api.ContentAccessTrait
local ContentAccessTrait = {}

---@return boolean
---@return_cast self api.ContentAccessImpl
function ContentAccessTrait:hasContent()
  ---@cast self api.BaseSource
  return self.ref.sourceReference and self.ref.sourceReference > 0 or
      self.ref.path and self.ref.path ~= ''
end

---@class api.ContentAccessImpl: api.BaseSource
local ContentAccessImpl = {}

function ContentAccessImpl:content()
  ---@cast self api.BaseSource

  if self._content then
    return self._content
  end

  local args = {}
  if self.ref.sourceReference and self.ref.sourceReference > 0 then
    args.sourceReference = self.ref.sourceReference
  elseif self.ref.path then
    args.source = { path = self.ref.path, sourceReference = self.ref.sourceReference }
  else
    return nil
  end

  -- Sources are session-level, no threadId needed
  local response = self.session.ref.calls:source(args):wait()

  if response and response.content then
    self._content = response.content
    return self._content
  end

  return nil
end

function ContentAccessImpl:clearContentCache()
  ---@cast self api.BaseSource
  self._content = nil
end

function ContentAccessTrait.extend(target)
  for k, v in pairs(ContentAccessTrait) do
    target[k] = v
  end

  for k, v in pairs(ContentAccessImpl) do
    target[k] = v
  end

  return target
end

return ContentAccessTrait
