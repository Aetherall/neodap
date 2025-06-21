---@class api.RangedScopeTrait
local RangedScopeTrait = {}

---@return boolean
---@return_cast self api.RangedScopeImpl
function RangedScopeTrait:hasRange()
  ---@cast self api.Scope
  if self.ref.line and self.ref.endLine then
    return true
  end
  return false
end

---@return api.RangedScopeImpl|nil
function RangedScopeTrait:isRanged()
  return self:hasRange() and self
end

---@class api.RangedScopeImpl: api.Scope
local RangedScopeImpl = {}

function RangedScopeTrait.extend(target)
  -- Apply the trait to the target, which is expected to be a class
  -- It will add all the methods from RangedScopeTrait and RangedScope to the target,
  -- but will type it as RangedScopeTrait only.
  -- This allows instances of the target not to expose the trait methods until they are explicitly casted.

  for k, v in pairs(RangedScopeTrait) do
    target[k] = v
  end

  for k, v in pairs(RangedScopeImpl) do
    target[k] = v
  end

  return target
end

---@return [integer, integer], [integer, integer]
function RangedScopeImpl:region()
  ---@cast self api.Scope

  local start = { self.ref.line or 1, self.ref.column or 1 }
  local finish = { self.ref.endLine or start[1], self.ref.endColumn or start[2] }
  return start, finish
end

---Check if a given line is within this scope's range
---@param line integer
---@return boolean
function RangedScopeImpl:containsLine(line)
  local start, finish = self:region()
  return line >= start[1] and line <= finish[1]
end

---Check if a given position is within this scope's range
---@param line integer
---@param column integer
---@return boolean
function RangedScopeImpl:containsPosition(line, column)
  local start, finish = self:region()

  if line < start[1] or line > finish[1] then
    return false
  end

  if line == start[1] and column < start[2] then
    return false
  end

  if line == finish[1] and column > finish[2] then
    return false
  end

  return true
end

function RangedScopeImpl:rangeLinkSuffix()
  local start, finish = self:region()
  return string.format("%d:%d-%d:%d", start[1], start[2], finish[1], finish[2])
end

RangedScopeTrait.Impl = RangedScopeImpl

return RangedScopeTrait
