-- DerivedSignal: wraps a source signal and transforms the value
local DerivedSignal = {}
DerivedSignal.__index = DerivedSignal

function DerivedSignal.new(source, transform)
  return setmetatable({ _source = source, _transform = transform }, DerivedSignal)
end

function DerivedSignal:get()
  local raw = self._source:get()
  if raw == nil then return nil end
  return self._transform(raw)
end

function DerivedSignal:onChange(callback)
  local transform = self._transform
  return self._source:onChange(function(new_raw, old_raw)
    local new_val = new_raw and transform(new_raw) or nil
    local old_val = old_raw and transform(old_raw) or nil
    callback(new_val, old_val)
  end)
end

function DerivedSignal:use(effect)
  local cleanup, unsubscribed = nil, false

  local function runCleanup()
    if cleanup then
      pcall(cleanup); cleanup = nil
    end
  end

  local ok, result = pcall(effect, self:get())
  if ok and type(result) == "function" then cleanup = result end

  local unsubscribe = self:onChange(function(new_val)
    if unsubscribed then return end
    runCleanup()
    local ok2, result2 = pcall(effect, new_val)
    if ok2 and type(result2) == "function" then cleanup = result2 end
  end)

  return function()
    if unsubscribed then return end
    unsubscribed = true
    runCleanup()
    unsubscribe()
  end
end

function DerivedSignal:iter()
  local entity, done = self:get(), false
  return function()
    if not done and entity then
      done = true; return entity
    end
  end
end

return DerivedSignal
