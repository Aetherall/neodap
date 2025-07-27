local Class = require('neodap.tools.class')

---@alias Indexer<T> fun(item: T, position?: integer): string|number|boolean

---@class IndexDefinition<T>
---@field indexer Indexer<T> Function to generate index key
---@field unique boolean true = single value per key, false = multiple values per key

---@class CollectionProps<T, K>
---@field items? T[] Initial items for the collection
---@field indexes table<K, IndexDefinition<T>> Index definitions

---Enhanced Collection with type-safe indexing
---@class (partial) Collection<T, K>: CollectionProps<T, K>
---@field _indexes table<K, table<string|number|boolean, T|T[]>> Index name to key->item(s) mapping
---@field _indexers table<K, Indexer<T>> Index name to key function mapping
---@field _indexDefinitions table<K, IndexDefinition<T>> Index name to definition mapping
---@field new Constructor<CollectionProps<T, K>>

---For specialized collections, use this pattern:
----@class api.BreakpointCollection: Collection<api.Breakpoint>
--- Unique indexes: 'id', 'location_key' (use findBy)
--- Multi indexes: 'source_key' (use whereBy)
local Collection = Class()

---@generic T, K
---@param props CollectionProps<T, K>
---@return Collection<T, K>
function Collection.create(props)
  local instance = Collection:new({
    items = (props and props.items) or {},
    indexes = (props and props.indexes) or {},
  })

  -- Initialize Collection-specific fields
  instance.items = (props and props.items) or {}
  instance._indexes = {}
  instance._indexers = {}
  instance._indexDefinitions = {}

  -- Process index definitions
  if props and props.indexes then
    for name, indexDef in pairs(props.indexes) do
      instance._indexers[name] = indexDef.indexer
      instance._indexDefinitions[name] = indexDef
    end
  end

  -- Build initial indexes
  instance:_rebuildAllIndexes()

  return instance
end

-- Don't override new() - use standard Class pattern
-- Instead, the constructor will call this initialization
function Collection:_initialize(props)
  -- Initialize Collection-specific fields
  self.items = (props and props.items) or {}
  self._indexes = {}
  self._indexers = {}
  self._indexDefinitions = {}

  -- Process index definitions
  if props and props.indexes then
    for name, indexDef in pairs(props.indexes) do
      self._indexers[name] = indexDef.indexer
      self._indexDefinitions[name] = indexDef
    end
  end

  -- Build initial indexes
  self:_rebuildAllIndexes()
end

---@class (partial) Collection<U, K>
---@field _buildIndex fun(self: Collection<U, K>, name: string): void
function Collection:_buildIndex(name)
  local key_function = self._indexers[name]
  local indexDef = self._indexDefinitions[name]
  if not key_function or not indexDef then return end

  self._indexes[name] = {}
  for position, item in ipairs(self.items) do
    local key = key_function(item, position)
    if key ~= nil then
      if indexDef.unique then
        -- Unique index: single item per key
        self._indexes[name][key] = item
      else
        -- Multi-value index: array of items per key
        if not self._indexes[name][key] then
          self._indexes[name][key] = {}
        end
        table.insert(self._indexes[name][key], item)
      end
    end
  end
end

---@class (partial) Collection<U, K>
---@field _rebuildAllIndexes fun(self: Collection<U, K>): void
---Rebuild all indexes based on current items
function Collection:_rebuildAllIndexes()
  ---@diagnostic disable-next-line: param-type-not-match
  for name in pairs(self._indexers) do
    self:_buildIndex(name)
  end
end

---@class (partial) Collection<U, K>
---@field add fun(self: Collection<U, K>, item: U): Collection<U, K>
function Collection:add(item)
  table.insert(self.items, item)

  -- Update indexes with new item
  local position = #self.items
  ---@diagnostic disable-next-line: param-type-not-match
  for name, key_func in pairs(self._indexers) do
    local key = key_func(item, position)
    local indexDef = self._indexDefinitions[name]
    if key ~= nil and indexDef then
      if indexDef.unique then
        -- Unique index: single item per key
        self._indexes[name][key] = item
      else
        -- Multi-value index: array of items per key
        if not self._indexes[name][key] then
          self._indexes[name][key] = {}
        end
        table.insert(self._indexes[name][key], item)
      end
    end
  end

  return self
end

---@class (partial) Collection<U, K>
---@field remove fun(self: Collection<U, K>, item: U): Collection<U, K>
function Collection:remove(item)
  -- Find and remove from items array
  for i, existing in ipairs(self.items) do
    if existing == item then
      table.remove(self.items, i)
      break
    end
  end

  -- Remove from all indexes
  for name, index in pairs(self._indexes) do
    local indexDef = self._indexDefinitions[name]
    if indexDef then
      for key, indexed_value in pairs(index) do
        if indexDef.unique then
          -- Unique index: direct item comparison
          if indexed_value == item then
            index[key] = nil
            break
          end
        else
          -- Multi-value index: remove from array
          if type(indexed_value) == "table" then
            for i, array_item in ipairs(indexed_value) do
              if array_item == item then
                table.remove(indexed_value, i)
                -- Remove key if array is empty
                if #indexed_value == 0 then
                  index[key] = nil
                end
                break
              end
            end
          end
        end
      end
    end
  end

  -- Rebuild position-dependent indexes
  ---@diagnostic disable-next-line: param-type-not-match
  for name, key_func in pairs(self._indexers) do
    ---@diagnostic disable-next-line: param-type-not-match
    local info = debug.getinfo(key_func, "u")
    if info.nparams > 1 then -- Has position parameter
      self:_buildIndex(name)
    end
  end

  return self
end

---@class (partial) Collection<U, K>
---@field first fun(self: Collection<U, K>): U?
function Collection:first()
  return self.items[1]
end

---@class (partial) Collection<U, K>
---@field last fun(self: Collection<U, K>): U?
function Collection:last()
  return self.items[#self.items]
end

---@class (partial) Collection<U, K>
---@field at fun(self: Collection<U, K>, index: integer): U?
function Collection:at(index)
  return self.items[index]
end

---@class (partial) Collection<U, K>
---@field getBy fun(self: Collection<U, K>, index_name: K, key: string|number|boolean): U?
function Collection:getBy(index_name, key)
  local index = self._indexes[index_name]
  local indexDef = self._indexDefinitions[index_name]
  if not index or not indexDef then
    return nil
  end

  local indexed_value = index[key]
  if not indexed_value then
    return nil
  end

  if indexDef.unique then
    -- Unique index: return the item directly
    return indexed_value
  else
    -- Multi-value index: return first item for backward compatibility
    return type(indexed_value) == "table" and indexed_value[1] or nil
  end
end

---@class (partial) Collection<U, K>
---@field getByAny fun(self: Collection<U, K>, index_name: K, keys: (string|number|boolean)[]): Collection<U, K>
function Collection:getByAny(index_name, keys)
  local result = self:createEmpty()
  local index = self._indexes[index_name]
  local indexDef = self._indexDefinitions[index_name]
  if not index or not indexDef then return result end

  for _, key in ipairs(keys) do
    local indexed_value = index[key]
    if indexed_value then
      if indexDef.unique then
        -- Unique index: add single item
        result:add(indexed_value)
      else
        -- Multi-value index: add all items from array
        if type(indexed_value) == "table" then
          for _, item in ipairs(indexed_value) do
            result:add(item)
          end
        end
      end
    end
  end

  return result
end

---@class (partial) Collection<U, K>
---@field getAllBy fun(self: Collection<U, K>, index_name: K, key: string|number|boolean): Collection<U, K>
function Collection:getAllBy(index_name, key)
  local result = self:createEmpty()
  local index = self._indexes[index_name]
  local indexDef = self._indexDefinitions[index_name]
  if not index or not indexDef then return result end

  local indexed_value = index[key]
  if not indexed_value then return result end

  if indexDef.unique then
    -- Unique index: add single item
    result:add(indexed_value)
  else
    -- Multi-value index: add all items from array
    if type(indexed_value) == "table" then
      for _, item in ipairs(indexed_value) do
        result:add(item)
      end
    end
  end

  return result
end

---@class (partial) Collection<U, K>
---@field findBy fun(self: Collection<U, K>, index_name: K, key: string|number|boolean): U?
function Collection:findBy(index_name, key)
  local indexDef = self._indexDefinitions[index_name]
  if not indexDef then
    error(string.format("Index '%s' not found", index_name))
  end
  if not indexDef.unique then
    error(string.format("findBy() requires unique index, but '%s' is multi-value. Use whereBy() instead.", index_name))
  end
  return self:getBy(index_name, key)
end

---@class (partial) Collection<U, K>
---@field whereBy fun(self: Collection<U, K>, index_name: K, key: string|number|boolean): Collection<U, K>
function Collection:whereBy(index_name, key)
  local indexDef = self._indexDefinitions[index_name]
  if not indexDef then
    error(string.format("Index '%s' not found", index_name))
  end
  if indexDef.unique then
    error(string.format("whereBy() requires multi-value index, but '%s' is unique. Use findBy() instead.", index_name))
  end
  return self:getAllBy(index_name, key)
end

---@class (partial) Collection<U, K>
---@field filter fun(self: Collection<U, K>, predicate: fun(item: U, position?: integer): boolean): Collection<U, K>
function Collection:filter(predicate)
  local filtered = self:createEmpty()
  for position, item in ipairs(self.items) do
    if predicate(item, position) then
      filtered:add(item)
    end
  end
  return filtered
end

---@class (partial) Collection<U, K>
---@field filterBy fun(self: Collection<U, K>, key_function: fun(item: U): any, key: any): Collection<U, K>
function Collection:filterBy(key_function, key)
  return self:filter(function(item)
    return key_function(item) == key
  end)
end

---@generic G
---@class (partial) Collection<U, K>
---@field groupBy fun(self: Collection<U, K>, key_function: fun(item: U): G): fun(): G?, Collection<U, K>
function Collection:groupBy(key_function)
  local groups = {}

  -- Build groups
  for item in self:each() do
    local key = key_function(item)
    if key ~= nil then
      if not groups[key] then
        groups[key] = self:createEmpty()
      end
      groups[key]:add(item)
    end
  end

  -- Return iterator
  local keys = vim.tbl_keys(groups)
  local index = 0

  return function()
    index = index + 1
    if index > #keys then
      return nil, nil
    end
    local key = keys[index]
    return key, groups[key]
  end
end

---@generic T
---@class (partial) Collection<U, K>
---@field map fun(self: Collection<U, K>, transform_function: fun(item: U, position?: integer): T): Collection<T, any>
function Collection:map(transform_function)
  local mapped = self:createEmpty()
  for position, item in ipairs(self.items) do
    mapped:add(transform_function(item, position))
  end
  return mapped
end

---@class (partial) Collection<U>
---@field each fun(self: Collection<U>): fun(): U?, integer?
function Collection:each()
  local index = 0
  return function()
    index = index + 1
    if index > #self.items then
      return nil, nil
    end
    return self.items[index], index
  end
end

---@param callback fun(item: any, position?: integer): any
---@return Collection Self for chaining
function Collection:forEach(callback)
  for position, item in ipairs(self.items) do
    callback(item, position)
  end
  return self
end

---@class (partial) Collection<U, K>
---@field toArray fun(self: Collection<U, K>): U[]
function Collection:toArray()
  return vim.tbl_map(function(item) return item end, self.items)
end

---@class (partial) Collection<U>
---@field count fun(self: Collection<U>): integer
function Collection:count()
  return #self.items
end

---@class (partial) Collection<U>
---@field isEmpty fun(self: Collection<U>): boolean
function Collection:isEmpty()
  return #self.items == 0
end

---@return boolean True if collection has items
function Collection:isNotEmpty()
  return #self.items > 0
end

---@class (partial) Collection<U, K>
---@field createEmpty fun(self: Collection<U, K>): Collection<U, K>
function Collection:createEmpty()
  -- Create a deep copy of index definitions
  local indexes_copy = {}
  ---@diagnostic disable-next-line: param-type-not-match
  for name, indexDef in pairs(self._indexDefinitions) do
    indexes_copy[name] = indexDef
  end

  return Collection.create({
    indexes = indexes_copy
  })
end

---@class (partial) Collection<U>
---@field clear fun(self: Collection<U>): Collection<U>
---@return Collection<U>
function Collection:clear()
  ---@type U[]
  self.items = {}
  ---@type table<K, table<string|number|boolean, U>>
  self._indexes = {}
  self:_rebuildAllIndexes()
  return self
end

---@class (partial) Collection<U, K>
---@field find fun(self: Collection<U, K>, predicate: fun(item: U): boolean): U?
function Collection:find(predicate)
  for _, item in ipairs(self.items) do
    if predicate(item) then
      return item
    end
  end
  return nil
end

---@class (partial) Collection<U>
---@field any fun(predicate: fun(item: U): boolean): boolean
function Collection:any(predicate)
  return self:find(predicate) ~= nil
end

---@class (partial) Collection<U>
---@field all fun(self: Collection<U>, predicate: fun(item: U): boolean): boolean
function Collection:all(predicate)
  for _, item in ipairs(self.items) do
    if not predicate(item) then
      return false
    end
  end
  return true
end

---@class (partial) Collection<U>
---@field indexOf fun(self: Collection<U>, predicate_or_item: U|fun(item: U): boolean): integer?
function Collection:indexOf(predicate_or_item)
  for i, item in ipairs(self.items) do
    if type(predicate_or_item) == "function" then
      if predicate_or_item(item) then
        return i
      end
    else
      if item == predicate_or_item then
        return i
      end
    end
  end
  return nil
end

---@class (partial) Collection<U, K>
---@field removeWhere fun(self: Collection<U, K>, predicate: fun(item: U): boolean): integer
function Collection:removeWhere(predicate)
  local removed = 0

  -- Remove from items array (iterate backwards to maintain indices)
  for i = #self.items, 1, -1 do
    if predicate(self.items[i]) then
      table.remove(self.items, i)
      removed = removed + 1
    end
  end

  -- Rebuild all indexes after removal
  if removed > 0 then
    self:_rebuildAllIndexes()
  end

  return removed
end

---@class (partial) Collection<U, K>
---@field removeBy fun(self: Collection<U, K>, index_name: K, key: any): U?
function Collection:removeBy(index_name, key)
  return self:removeWhere(function(item)
    local index = self._indexes[index_name]
    return index and index[key] == item
  end)
end

---@class (partial) Collection<U, K>
---@field eachWhere fun(self: Collection<U, K>, predicate: fun(item: U): boolean): fun(): U?, integer?
function Collection:eachWhere(predicate)
  local index = 0
  return function()
    while true do
      index = index + 1
      if index > #self.items then
        return nil, nil
      end
      local item = self.items[index]
      if predicate(item) then
        return item, index
      end
    end
  end
end

return Collection
