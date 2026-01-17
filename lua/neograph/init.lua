--[[
  neograph-native: A reactive in-memory graph database for Lua

  MATERIALIZED DERIVED EDGES VERSION

  Key insight: Reference and collection rollups are materialized as actual edges
  at write time. This makes the query layer completely agnostic - it just iterates
  edges without needing to know whether they're real edges or derived from rollups.

  - Real edges: stored in graph.edges[id][edge_name], have skip list indexes
  - Derived edges: stored in graph.edges[id][rollup_name], NO skip list (just arrays)
  - Property rollups: still computed/cached as before (stored in node_data)

  Derived edges are maintained reactively:
  - On link to base edge: check if target belongs in derived edge
  - On unlink from base edge: remove from derived edge if present
  - On property change: re-evaluate membership in derived edges
--]]

local neo = {}

-- Sentinel value for explicitly setting properties to nil
neo.NIL = setmetatable({}, { __tostring = function() return "neo.NIL" end })

--============================================================================
-- HELPERS
--============================================================================

local function copy_array(arr)
  local new = {}
  for i, v in ipairs(arr) do new[i] = v end
  return new
end

local function copy_array_append(arr, val)
  local new = copy_array(arr)
  new[#new + 1] = val
  return new
end

local function array_remove(arr, val)
  for i, v in ipairs(arr) do
    if v == val then table.remove(arr, i); return true end
  end
  return false
end

local function array_contains(arr, val)
  for _, v in ipairs(arr) do
    if v == val then return true end
  end
  return false
end

local function type_index_key(type_name, idx_name)
  return type_name .. ":" .. (idx_name or "default")
end

local function edge_index_key(type_name, edge_name, idx_name)
  return type_name .. ":" .. edge_name .. ":" .. (idx_name or "default")
end

--============================================================================
-- ROLLUP STRATEGY TABLE
--============================================================================

local RollupStrategy = {
  count = {
    compute = function(iter, prop, node_data, rdef)
      local c = 0
      for _ in iter do c = c + 1 end
      return c
    end,
    add = function(old) return (old or 0) + 1 end,
    sub = function(old) return (old or 0) - 1 end,
  },

  sum = {
    compute = function(iter, prop, node_data, rdef)
      local s = 0
      for tgt_id in iter do
        local data = node_data[tgt_id]
        if data and data[prop] then s = s + data[prop] end
      end
      return s
    end,
    add = function(old, val) return (old or 0) + (val or 0) end,
    sub = function(old, val) return (old or 0) - (val or 0) end,
  },

  avg = {
    compute = function(iter, prop, node_data, rdef)
      local sum, count = 0, 0
      for tgt_id in iter do
        local data = node_data[tgt_id]
        if data and data[prop] ~= nil then
          sum = sum + data[prop]
          count = count + 1
        end
      end
      return count > 0 and (sum / count) or nil
    end,
  },

  min = {
    compute = function(iter, prop, node_data, rdef)
      local min_val = nil
      for tgt_id in iter do
        local data = node_data[tgt_id]
        if data and data[prop] ~= nil then
          if min_val == nil or data[prop] < min_val then min_val = data[prop] end
        end
      end
      return min_val
    end,
    add = function(old, val)
      if val == nil then return old end
      return (old == nil) and val or math.min(old, val)
    end,
    rescan_on_unlink = function(old, val)
      return val ~= nil and old ~= nil and val <= old
    end,
  },

  max = {
    compute = function(iter, prop, node_data, rdef)
      local max_val = nil
      for tgt_id in iter do
        local data = node_data[tgt_id]
        if data and data[prop] ~= nil then
          if max_val == nil or data[prop] > max_val then max_val = data[prop] end
        end
      end
      return max_val
    end,
    add = function(old, val)
      if val == nil then return old end
      return (old == nil) and val or math.max(old, val)
    end,
    rescan_on_unlink = function(old, val)
      return val ~= nil and old ~= nil and val >= old
    end,
  },

  first = {
    compute = function(iter, prop, node_data, rdef)
      local first_id = iter()
      if first_id then
        local data = node_data[first_id]
        return data and data[prop]
      end
      return nil
    end,
  },

  last = {
    compute = function(iter, prop, node_data, rdef)
      local last_val = nil
      for tgt_id in iter do
        local data = node_data[tgt_id]
        if data then last_val = data[prop] end
      end
      return last_val
    end,
  },

  any = {
    compute = function(iter, prop, node_data, rdef)
      for tgt_id in iter do
        if not prop then return true end
        local data = node_data[tgt_id]
        if data and data[prop] then return true end
      end
      return false
    end,
    add = function(old, val, tgt, rdef)
      if old then return true end
      local prop_val = rdef.property and val or true
      return prop_val and true or false
    end,
    rescan_on_unlink = function(old, val, tgt, rdef)
      if not old then return false end
      local prop_val = rdef.property and val or true
      return prop_val and true or false
    end,
  },

  all = {
    compute = function(iter, prop, node_data, rdef)
      local has_any = false
      for tgt_id in iter do
        has_any = true
        if prop then
          local data = node_data[tgt_id]
          if not data or not data[prop] then return false end
        end
      end
      return has_any
    end,
  },
}

--============================================================================
-- INDEXED SKIP LIST
--============================================================================

local MAX_LEVEL = 18
local random = math.random

local function indexed_skiplist(compare)
  local head = {}
  local level = 1
  local count = 0
  local update = {}
  local update_pos = {}

  for i = 1, MAX_LEVEL do
    head[i] = nil
    head[-i] = 0
  end

  local function rand_level()
    local lvl = 1
    while random() < 0.5 and lvl < MAX_LEVEL do lvl = lvl + 1 end
    return lvl
  end

  local function insert(value)
    local x = head
    local pos = 0

    for i = level, 1, -1 do
      while x[i] and compare(x[i].v, value) < 0 do
        pos = pos + (x[-i] or 1)
        x = x[i]
      end
      update[i] = x
      update_pos[i] = pos
    end

    local nxt = x[1]
    if nxt and compare(nxt.v, value) == 0 then
      return nil
    end

    local nlvl = rand_level()
    if nlvl > level then
      for i = level + 1, nlvl do
        update[i] = head
        update_pos[i] = 0
        head[-i] = count + 1
      end
      level = nlvl
    end

    local node = { v = value }

    for i = 1, nlvl do
      node[i] = update[i][i]
      update[i][i] = node
      local old_span = update[i][-i] or 1
      local before = pos - update_pos[i]
      node[-i] = old_span - before
      update[i][-i] = before + 1
    end

    for i = nlvl + 1, level do
      update[i][-i] = (update[i][-i] or 0) + 1
    end

    count = count + 1
    return pos + 1
  end

  local function remove(value)
    local x = head
    local pos = 0

    for i = level, 1, -1 do
      while x[i] and compare(x[i].v, value) < 0 do
        pos = pos + (x[-i] or 1)
        x = x[i]
      end
      update[i] = x
      update_pos[i] = pos
    end

    local target = x[1]
    if not target or compare(target.v, value) ~= 0 then
      return nil
    end

    local removed_pos = pos + 1
    local target_height = 0

    for i = 1, level do
      if update[i][i] ~= target then break end
      target_height = i
      update[i][i] = target[i]
      update[i][-i] = (update[i][-i] or 1) + (target[-i] or 1) - 1
    end

    for i = target_height + 1, level do
      update[i][-i] = (update[i][-i] or 1) - 1
    end

    while level > 1 and not head[level] do
      head[-level] = 0
      level = level - 1
    end

    count = count - 1
    return removed_pos
  end

  local function iter()
    return coroutine.wrap(function()
      local x = head[1]
      while x do
        coroutine.yield(x.v)
        x = x[1]
      end
    end)
  end

  local function iter_from(start_pos)
    return coroutine.wrap(function()
      if start_pos < 1 or start_pos > count then return end
      local x = head
      local pos = 0
      for i = level, 1, -1 do
        while x[i] and pos + (x[-i] or 1) < start_pos do
          pos = pos + (x[-i] or 1)
          x = x[i]
        end
      end
      x = x[1]
      while x do
        coroutine.yield(x.v)
        x = x[1]
      end
    end)
  end

  local function seek(target_pos)
    if target_pos < 1 or target_pos > count then return nil end
    local x = head
    local pos = 0
    for i = level, 1, -1 do
      while x[i] and pos + (x[-i] or 1) <= target_pos do
        pos = pos + (x[-i] or 1)
        x = x[i]
      end
      if pos == target_pos then return x end
    end
    return nil
  end

  local function rank(value)
    local x = head
    local pos = 0
    for i = level, 1, -1 do
      while x[i] and compare(x[i].v, value) < 0 do
        pos = pos + (x[-i] or 1)
        x = x[i]
      end
    end
    local nxt = x[1]
    if nxt and compare(nxt.v, value) == 0 then
      return pos + 1
    end
    return nil
  end

  local function rank_lower_bound(lower_bound)
    local x = head
    local pos = 0
    for i = level, 1, -1 do
      while x[i] and compare(x[i].v, lower_bound) < 0 do
        pos = pos + (x[-i] or 1)
        x = x[i]
      end
    end
    return pos + 1
  end

  local function contains(value)
    local x = head
    for i = level, 1, -1 do
      while x[i] and compare(x[i].v, value) < 0 do
        x = x[i]
      end
    end
    local nxt = x[1]
    return nxt and compare(nxt.v, value) == 0
  end

  return {
    insert = insert,
    remove = remove,
    iter = iter,
    iter_from = iter_from,
    seek = seek,
    rank = rank,
    rank_lower_bound = rank_lower_bound,
    contains = contains,
    count = function() return count end,
  }
end

--============================================================================
-- COMPARATORS
--============================================================================

local function compare_values(a, b, dir)
  if a == b then return 0 end
  if a == nil then return dir == "asc" and 1 or -1 end
  if b == nil then return dir == "asc" and -1 or 1 end
  if type(a) == "boolean" then a = a and 1 or 0 end
  if type(b) == "boolean" then b = b and 1 or 0 end
  if a < b then return dir == "asc" and -1 or 1 end
  return dir == "asc" and 1 or -1
end

local function make_comparator(fields, get_node)
  if not fields or #fields == 0 then
    return function(a, b)
      if a < b then return -1 end
      if a > b then return 1 end
      return 0
    end
  end

  return function(a, b)
    local na, nb = get_node(a), get_node(b)
    if not na and not nb then return a < b and -1 or (a > b and 1 or 0) end
    if not na then return 1 end
    if not nb then return -1 end

    for _, f in ipairs(fields) do
      local c = compare_values(na[f.name], nb[f.name], f.dir or "asc")
      if c ~= 0 then return c end
    end
    if a < b then return -1 end
    if a > b then return 1 end
    return 0
  end
end

local function make_edge_comparator(fields)
  local num_fields = fields and #fields or 0
  return function(a, b)
    -- Compare parent first
    if a.parent < b.parent then return -1 end
    if a.parent > b.parent then return 1 end

    -- Compare denormalized field values stored in _f array
    if num_fields > 0 then
      local af, bf = a._f, b._f
      if af and bf then
        -- Compare up to the shorter array length for prefix seeking
        -- Missing values in partial _f array (for seeking) are treated as -infinity
        local af_len, bf_len = #af, #bf
        for i = 1, num_fields do
          local av, bv = af[i], bf[i]
          -- Handle partial _f arrays: missing elements are -infinity (less than anything)
          if i > af_len and i <= bf_len then
            return -1  -- a's prefix ends here, a < b
          elseif i > bf_len and i <= af_len then
            return 1   -- b's prefix ends here, b < a
          elseif i <= af_len and i <= bf_len then
            local c = compare_values(av, bv, fields[i].dir or "asc")
            if c ~= 0 then return c end
          end
        end
      elseif af and not bf then
        return 1   -- a has fields, b is a lower bound probe without fields
      elseif bf and not af then
        return -1  -- b has fields, a is a lower bound probe without fields
      end
    end

    -- Compare child id last (tiebreaker)
    if a.child < b.child then return -1 end
    if a.child > b.child then return 1 end
    return 0
  end
end

-- Build edge index entry with denormalized field values
local function make_edge_entry(parent_id, child_id, idx_fields, child_data)
  local entry = { parent = parent_id, child = child_id }
  if idx_fields and #idx_fields > 0 and child_data then
    local f = {}
    for i, field in ipairs(idx_fields) do
      f[i] = child_data[field.name]
    end
    entry._f = f
  end
  return entry
end

--============================================================================
-- INDEX COVERAGE
--============================================================================

local function find_covering_index(tdef, filters, sort)
  filters = filters or {}
  local indexes = tdef.indexes or {}

  for _, idx in ipairs(indexes) do
    local fields = idx.fields or {}
    local field_idx = 1
    local valid = true

    for _, f in ipairs(filters) do
      if f.op == "eq" or f.op == nil then
        if field_idx > #fields or fields[field_idx].name ~= f.field then
          valid = false
          break
        end
        field_idx = field_idx + 1
      end
    end

    if valid then
      local has_range = false
      for _, f in ipairs(filters) do
        if f.op and f.op ~= "eq" then
          if has_range then valid = false; break end
          if field_idx > #fields or fields[field_idx].name ~= f.field then
            valid = false; break
          end
          if sort and sort.field == f.field then
            local idx_dir = fields[field_idx].dir or "asc"
            if idx_dir ~= (sort.dir or "asc") then valid = false; break end
          end
          has_range = true
        end
      end

      if valid and sort and not has_range then
        if field_idx > #fields or fields[field_idx].name ~= sort.field then
          valid = false
        else
          local idx_dir = fields[field_idx].dir or "asc"
          if idx_dir ~= (sort.dir or "asc") then valid = false end
        end
      end
    end

    if valid then return idx end
  end

  local filter_desc = {}
  for _, f in ipairs(filters) do
    filter_desc[#filter_desc + 1] = f.field .. " " .. (f.op or "eq")
  end
  return nil, "No index covers query [" .. table.concat(filter_desc, ", ") .. "]"
end

--============================================================================
-- FILTER EVALUATION
--============================================================================

local function node_matches_filters(node_or_data, filters, graph)
  if not filters or #filters == 0 then return true end

  local data = node_or_data
  if graph and rawget(node_or_data, "_id") then
    data = graph._node_data[rawget(node_or_data, "_id")]
  end
  if not data then return false end

  for _, f in ipairs(filters) do
    local val = data[f.field]
    local op = f.op or "eq"

    if op == "eq" then
      if val ~= f.value then return false end
    elseif op == "gt" then
      if val == nil or val <= f.value then return false end
    elseif op == "gte" then
      if val == nil or val < f.value then return false end
    elseif op == "lt" then
      if val == nil or val >= f.value then return false end
    elseif op == "lte" then
      if val == nil or val > f.value then return false end
    end
  end
  return true
end

--============================================================================
-- SIGNAL
--============================================================================

local Signal = {}
Signal.__index = Signal

function Signal.new(graph, node_id, prop_name)
  return setmetatable({
    _graph = graph,
    _node_id = node_id,
    _prop_name = prop_name,
  }, Signal)
end

function Signal:get()
  local data = self._graph._node_data[self._node_id]
  return data and data[self._prop_name]
end

function Signal:set(value)
  self._graph:update(self._node_id, { [self._prop_name] = value })
end

function Signal:use(effect)
  local current = self:get()
  local cleanup = effect(current, nil)

  local prop_name = self._prop_name
  local unsub = self._graph:watch(self._node_id, {
    on_change = function(id, prop, new_val, old_val)
      if prop == prop_name then
        if cleanup then
          local ok, err = pcall(cleanup)
          if not ok then print("Signal cleanup error:", err) end
        end
        cleanup = effect(new_val, old_val)
      end
    end
  })

  return function()
    unsub()
    if cleanup then
      local ok, err = pcall(cleanup)
      if not ok then print("Signal cleanup error:", err) end
    end
  end
end

--============================================================================
-- EDGE HANDLE
--============================================================================

local EdgeHandle = {}
EdgeHandle.__index = EdgeHandle

function EdgeHandle.new(graph, node_id, edge_name, filter_opts)
  return setmetatable({
    _graph = graph,
    _node_id = node_id,
    _edge_name = edge_name,
    _filters = filter_opts and filter_opts.filters,
    _index_name = filter_opts and filter_opts.index_name,
    _is_derived = filter_opts and filter_opts.is_derived,
  }, EdgeHandle)
end

function EdgeHandle:filter(opts)
  opts = opts or {}
  local graph = self._graph
  local src = graph.nodes[self._node_id]
  if not src then return self end

  local tdef = graph.types[src._type]
  local edef = graph:_get_edge_def(tdef, self._edge_name)
  if not edef then return self end

  -- Derived edges don't support additional filtering at this level
  if edef.is_derived then
    error("Cannot filter derived edge '" .. self._edge_name .. "' - use base edge instead")
  end

  local query_filters = {}
  if opts.filters then
    for _, f in ipairs(opts.filters) do
      query_filters[#query_filters + 1] = f
    end
  end
  if opts.sort then
    query_filters[#query_filters + 1] = { field = opts.sort.field, op = "gte", value = "" }
  end

  local edge_indexes = edef.indexes or {{ name = "default", fields = {} }}
  local idx, err = find_covering_index({ indexes = edge_indexes }, query_filters, opts.sort)
  if not idx then
    error("EdgeHandle:filter - " .. err)
  end

  return EdgeHandle.new(graph, self._node_id, self._edge_name, {
    filters = opts.filters,
    index_name = idx.name or "default",
  })
end

function EdgeHandle:iter()
  local graph = self._graph
  local node_id = self._node_id
  local edge_name = self._edge_name
  local filters = self._filters
  local index_name = self._index_name

  return coroutine.wrap(function()
    for tgt_id in graph:targets_iter(node_id, edge_name, nil, index_name, filters) do
      coroutine.yield(graph:get(tgt_id))
    end
  end)
end

function EdgeHandle:link(target)
  -- Check if this is a derived edge
  local src = self._graph.nodes[self._node_id]
  if src then
    local edef = self._graph.edge_defs[src._type .. ":" .. self._edge_name]
    if edef and edef.is_derived then
      error("Cannot link on derived edge '" .. self._edge_name .. "' - it is read-only")
    end
  end

  local tgt_id = type(target) == "table" and target._id or target
  return self._graph:link(self._node_id, self._edge_name, tgt_id)
end

function EdgeHandle:unlink(target)
  -- Check if this is a derived edge
  local src = self._graph.nodes[self._node_id]
  if src then
    local edef = self._graph.edge_defs[src._type .. ":" .. self._edge_name]
    if edef and edef.is_derived then
      error("Cannot unlink on derived edge '" .. self._edge_name .. "' - it is read-only")
    end
  end

  local tgt_id = type(target) == "table" and target._id or target
  return self._graph:unlink(self._node_id, self._edge_name, tgt_id)
end

function EdgeHandle:count()
  if not self._filters then
    return self._graph:targets_count(self._node_id, self._edge_name)
  end
  local n = 0
  for _ in self:iter() do
    n = n + 1
  end
  return n
end

function EdgeHandle:onLink(callback)
  local filters = self._filters
  local graph = self._graph
  if not filters then
    return graph:_subscribe_edge(self._node_id, self._edge_name, "link", callback)
  end
  return graph:_subscribe_edge(self._node_id, self._edge_name, "link", function(node)
    local node_data = graph._node_data[node._id]
    if node_matches_filters(node_data, filters) then
      callback(node)
    end
  end)
end

function EdgeHandle:onUnlink(callback)
  local filters = self._filters
  local graph = self._graph
  if not filters then
    return graph:_subscribe_edge(self._node_id, self._edge_name, "unlink", callback)
  end
  return graph:_subscribe_edge(self._node_id, self._edge_name, "unlink", function(node)
    local node_data = graph._node_data[node._id]
    if node_matches_filters(node_data, filters) then
      callback(node)
    end
  end)
end

function EdgeHandle:each(effect)
  local cleanups = {}
  local watchers = {}
  local graph = self._graph
  local filters = self._filters

  local function run_cleanup(node_id)
    local cleanup = cleanups[node_id]
    if cleanup then
      local ok, err = pcall(cleanup)
      if not ok then print("EdgeHandle:each cleanup error:", err) end
      cleanups[node_id] = nil
    end
  end

  local function run_effect(node)
    local cleanup = effect(node)
    if cleanup then
      cleanups[node._id] = cleanup
    end
  end

  local function watch_node(node_id)
    if watchers[node_id] then return end
    watchers[node_id] = graph:watch(node_id, {
      on_change = function(id, prop)
        local node_data = graph._node_data[id]
        local node = graph:get(id)
        local now_matches = node_matches_filters(node_data, filters)
        local was_in = cleanups[id] ~= nil

        if now_matches and not was_in then
          run_effect(node)
        elseif not now_matches and was_in then
          run_cleanup(id)
        end
      end
    })
  end

  local function unwatch_node(node_id)
    if watchers[node_id] then
      watchers[node_id]()
      watchers[node_id] = nil
    end
  end

  for node in self:iter() do
    run_effect(node)
    if filters then
      watch_node(node._id)
    end
  end

  local unsub_link = graph:_subscribe_edge(self._node_id, self._edge_name, "link", function(node)
    if filters then
      watch_node(node._id)
      local node_data = graph._node_data[node._id]
      if node_matches_filters(node_data, filters) then
        run_effect(node)
      end
    else
      run_effect(node)
    end
  end)

  local unsub_unlink = graph:_subscribe_edge(self._node_id, self._edge_name, "unlink", function(node)
    run_cleanup(node._id)
    if filters then
      unwatch_node(node._id)
    end
  end)

  return function()
    unsub_link()
    unsub_unlink()
    for node_id in pairs(watchers) do
      unwatch_node(node_id)
    end
    for _, cleanup in pairs(cleanups) do
      local ok, err = pcall(cleanup)
      if not ok then print("EdgeHandle:each cleanup error:", err) end
    end
  end
end

--============================================================================
-- PROPERTY ROLLUP (Signal-like for computed values)
--============================================================================

local PropertyRollup = {}
PropertyRollup.__index = PropertyRollup

function PropertyRollup.new(graph, node_id, rdef)
  return setmetatable({
    _graph = graph,
    _node_id = node_id,
    _rdef = rdef,
  }, PropertyRollup)
end

function PropertyRollup:_compute()
  return self._graph:_compute_property_rollup(self._node_id, self._rdef)
end

function PropertyRollup:get()
  return self:_compute()
end

function PropertyRollup:use(effect)
  local graph = self._graph
  local rdef = self._rdef
  local node_id = self._node_id

  local current = self:_compute()
  local cleanup = effect(current)
  local last_value = current

  local function recompute()
    local new_value = self:_compute()
    if new_value ~= last_value then
      if cleanup then
        local ok, err = pcall(cleanup)
        if not ok then print("PropertyRollup cleanup error:", err) end
      end
      last_value = new_value
      cleanup = effect(new_value)
    end
  end

  local unsub_link = graph:_subscribe_edge(node_id, rdef.edge, "link", recompute)
  local unsub_unlink = graph:_subscribe_edge(node_id, rdef.edge, "unlink", recompute)

  local target_unsubs = {}
  local unsub_target_link, unsub_target_unlink
  if rdef.property or rdef.filters then
    for tgt_id in graph:targets_iter(node_id, rdef.edge) do
      target_unsubs[tgt_id] = graph:watch(tgt_id, { on_change = recompute })
    end

    unsub_target_link = graph:_subscribe_edge(node_id, rdef.edge, "link", function(node)
      target_unsubs[node._id] = graph:watch(node._id, { on_change = recompute })
    end)

    unsub_target_unlink = graph:_subscribe_edge(node_id, rdef.edge, "unlink", function(node)
      if target_unsubs[node._id] then
        target_unsubs[node._id]()
        target_unsubs[node._id] = nil
      end
    end)
  end

  return function()
    unsub_link()
    unsub_unlink()
    if unsub_target_link then unsub_target_link() end
    if unsub_target_unlink then unsub_target_unlink() end
    for _, unsub in pairs(target_unsubs) do unsub() end
    if cleanup then
      local ok, err = pcall(cleanup)
      if not ok then print("PropertyRollup cleanup error:", err) end
    end
  end
end

--============================================================================
-- REFERENCE SIGNAL (Signal-like for single-target reference rollup)
-- Now backed by a derived edge with 0-1 elements
--============================================================================

local ReferenceSignal = {}
ReferenceSignal.__index = ReferenceSignal

function ReferenceSignal.new(graph, node_id, rdef)
  return setmetatable({
    _graph = graph,
    _node_id = node_id,
    _rdef = rdef,
  }, ReferenceSignal)
end

function ReferenceSignal:get()
  -- Derived edge is stored in graph.edges[id][rdef.name]
  local targets = self._graph.edges[self._node_id]
  local derived = targets and targets[self._rdef.name]
  if derived and #derived > 0 then
    return self._graph:get(derived[1])
  end
  return nil
end

function ReferenceSignal:set()
  error("Cannot set reference rollup - it is computed from edge '" .. self._rdef.edge .. "'")
end

function ReferenceSignal:use(effect)
  local graph = self._graph
  local rdef = self._rdef
  local node_id = self._node_id
  local derived_edge_name = rdef.name

  local current_node = self:get()
  local cleanup = effect(current_node)

  -- Subscribe to the derived edge's link/unlink events
  local unsub_link = graph:_subscribe_edge(node_id, derived_edge_name, "link", function(node)
    if cleanup then
      local ok, err = pcall(cleanup)
      if not ok then print("ReferenceSignal use cleanup error:", err) end
    end
    cleanup = effect(node)
  end)

  local unsub_unlink = graph:_subscribe_edge(node_id, derived_edge_name, "unlink", function(node)
    if cleanup then
      local ok, err = pcall(cleanup)
      if not ok then print("ReferenceSignal use cleanup error:", err) end
    end
    -- After unlink, check if there's a new reference
    local new_node = self:get()
    cleanup = effect(new_node)
  end)

  return function()
    unsub_link()
    unsub_unlink()
    if cleanup then
      local ok, err = pcall(cleanup)
      if not ok then print("ReferenceSignal use cleanup error:", err) end
    end
  end
end

--============================================================================
-- NODE PROXY
--============================================================================

local function is_edge(graph, type_name, key)
  local edef = graph.edge_defs[type_name .. ":" .. key]
  return edef ~= nil
end

local function get_rollup_def(graph, type_name, key)
  local tdef = graph.types[type_name]
  if not tdef or not tdef.rollups then return nil end
  for _, rdef in ipairs(tdef.rollups) do
    if rdef.name == key then return rdef end
  end
  return nil
end

local function get_or_create_edge_handle(graph, id, key, opts)
  graph._edge_handles[id] = graph._edge_handles[id] or {}
  if not graph._edge_handles[id][key] then
    graph._edge_handles[id][key] = EdgeHandle.new(graph, id, key, opts)
  end
  return graph._edge_handles[id][key]
end

local function get_or_create_signal(graph, id, key)
  graph._signals[id] = graph._signals[id] or {}
  if not graph._signals[id][key] then
    graph._signals[id][key] = Signal.new(graph, id, key)
  end
  return graph._signals[id][key]
end

local function get_or_create_rollup_handle(graph, id, key, rdef)
  graph._edge_handles[id] = graph._edge_handles[id] or {}
  if not graph._edge_handles[id][key] then
    if rdef.kind == "property" then
      graph._edge_handles[id][key] = PropertyRollup.new(graph, id, rdef)
    elseif rdef.kind == "reference" then
      graph._edge_handles[id][key] = ReferenceSignal.new(graph, id, rdef)
    elseif rdef.kind == "collection" then
      -- Collection rollups are now actual derived edges
      graph._edge_handles[id][key] = EdgeHandle.new(graph, id, key, { is_derived = true })
    end
  end
  return graph._edge_handles[id][key]
end

local function setup_node_metatable(graph, node, id, type_name, user_mt)
  local mt = {
    __index = function(self, key)
      if key == "_graph" then return graph end
      if key == "_id" then return id end
      if key == "_type" then return type_name end

      if user_mt and user_mt.__index then
        local idx = user_mt.__index
        local val
        if type(idx) == "table" then
          val = idx[key]
        elseif type(idx) == "function" then
          val = idx(self, key)
        end
        if val ~= nil then return val end
      end

      -- Check for rollup first (they shadow edges if same name)
      local rdef = get_rollup_def(graph, type_name, key)
      if rdef then
        if rdef.kind == "property" then
          -- Property rollups are stored in _node_data, use Signal for cached read
          return get_or_create_signal(graph, id, key)
        else
          -- Reference and collection rollups use special handles
          return get_or_create_rollup_handle(graph, id, key, rdef)
        end
      end

      if is_edge(graph, type_name, key) then
        return get_or_create_edge_handle(graph, id, key)
      end

      return get_or_create_signal(graph, id, key)
    end,

    __eq = function(a, b)
      return type(a) == "table" and type(b) == "table" and a._id == b._id
    end,

    __tostring = function(self)
      return "Node<" .. type_name .. ">#" .. id
    end,
  }

  return setmetatable(node, mt)
end

--============================================================================
-- SCHEMA PARSING (flat format)
--============================================================================

-- Rollup type keywords
local ROLLUP_TYPES = {
  count = "property",
  sum = "property",
  avg = "property",
  min = "property",
  max = "property",
  first = "property",
  last = "property",
  any = "property",
  all = "property",
  reference = "reference",
  collection = "collection",
}

local function parse_schema(schema)
  local types = {}

  for type_name, type_def in pairs(schema) do
    local tdef = {
      name = type_name,
      properties = {},
      edges = {},
      indexes = {},
      rollups = {},
    }

    for field_name, field_def in pairs(type_def) do
      if field_name == "__indexes" then
        -- Type-level indexes
        tdef.indexes = field_def

      elseif type(field_def) == "string" then
        -- Property: name = "string" | "number" | "bool"
        table.insert(tdef.properties, { name = field_name, type = field_def })

      elseif type(field_def) == "table" and field_def.type then
        local ftype = field_def.type

        if ftype == "edge" then
          -- Edge definition
          local edef = {
            name = field_name,
            target = field_def.target,
            reverse = field_def.reverse,
            indexes = field_def.__indexes or {{ name = "default", fields = {} }},
          }
          table.insert(tdef.edges, edef)

        elseif ROLLUP_TYPES[ftype] then
          -- Rollup definition
          local kind = ROLLUP_TYPES[ftype]
          local rdef = {
            name = field_name,
            kind = kind,
            edge = field_def.edge,
          }

          -- Property rollup specific
          if kind == "property" then
            rdef.compute = ftype
            rdef.property = field_def.property
          end

          -- Reference rollup specific
          if kind == "reference" then
            rdef.sort = field_def.sort
          end

          -- Collection rollup specific (same as reference)
          if kind == "collection" then
            rdef.sort = field_def.sort
          end

          -- Common: filters
          if field_def.filter then
            -- Convert { state = "stopped" } to {{ field = "state", value = "stopped" }}
            rdef.filters = {}
            for k, v in pairs(field_def.filter) do
              table.insert(rdef.filters, { field = k, value = v })
            end
          elseif field_def.filters then
            rdef.filters = field_def.filters
          end

          table.insert(tdef.rollups, rdef)
        end
      end
    end

    types[#types + 1] = tdef
  end

  return { types = types }
end

--============================================================================
-- GRAPH CREATION
--============================================================================

neo.Graph = {}

function neo.create(schema)
  -- Parse flat schema format to internal format
  schema = parse_schema(schema)
  local graph = {
    nodes = {},
    _node_data = {},
    next_id = 1,
    types = {},
    indexes = {},
    edges = {},
    edge_indexes = {},
    edge_defs = {},
    type_edges = {},  -- Cached list of edge names per type (real + derived)
    edge_field_deps = {},
    edge_counts = {},
    reverse = {},
    views = setmetatable({}, { __mode = "v" }),
    watchers = {},
    edge_subs = {},
    _edge_handles = {},
    _signals = {},
    rollup_defs = {},
    rollup_edge_deps = {},
    rollup_prop_deps = {},
    -- DERIVED EDGES: maps (src_type, edge_name) -> list of derived edges that depend on it
    derived_edge_deps = {},
    -- DERIVED PROP DEPS: property changes that affect derived edges
    derived_prop_deps = {},
  }

  for _, tdef in ipairs(schema.types or {}) do
    graph.types[tdef.name] = tdef

    for _, idx in ipairs(tdef.indexes or {}) do
      local key = type_index_key(tdef.name, idx.name)
      local cmp = make_comparator(idx.fields, function(id) return graph._node_data[id] end)
      graph.indexes[key] = indexed_skiplist(cmp)
    end

    for _, edef in ipairs(tdef.edges or {}) do
      local edge_indexes = edef.indexes or {{ name = "default", fields = {} }}
      for _, idx in ipairs(edge_indexes) do
        local key = edge_index_key(tdef.name, edef.name, idx.name)
        local cmp = make_edge_comparator(idx.fields)
        graph.edge_indexes[key] = indexed_skiplist(cmp)

        local target_type = edef.target
        for _, field in ipairs(idx.fields or {}) do
          graph.edge_field_deps[target_type] = graph.edge_field_deps[target_type] or {}
          graph.edge_field_deps[target_type][field.name] = graph.edge_field_deps[target_type][field.name] or {}
          table.insert(graph.edge_field_deps[target_type][field.name], {
            type_name = tdef.name,
            edge_name = edef.name,
            idx_name = idx.name or "default",
            reverse = edef.reverse,
            idx_fields = idx.fields,
          })
        end
      end
      graph.edge_defs[tdef.name .. ":" .. edef.name] = edef
      graph.type_edges[tdef.name] = graph.type_edges[tdef.name] or {}
      table.insert(graph.type_edges[tdef.name], edef.name)
    end

    -- Process rollups
    graph.rollup_defs[tdef.name] = graph.rollup_defs[tdef.name] or {}
    graph.rollup_edge_deps[tdef.name] = graph.rollup_edge_deps[tdef.name] or {}
    graph.derived_edge_deps[tdef.name] = graph.derived_edge_deps[tdef.name] or {}

    for _, rdef in ipairs(tdef.rollups or {}) do
      rdef._src_type = tdef.name

      if rdef.filters or rdef.sort then
        local edef = graph.edge_defs[tdef.name .. ":" .. rdef.edge]
        if edef then
          local edge_indexes = edef.indexes or {{ name = "default", fields = {} }}

          local query_filters = {}
          if rdef.filters then
            for _, f in ipairs(rdef.filters) do
              query_filters[#query_filters + 1] = f
            end
          end
          if rdef.sort then
            query_filters[#query_filters + 1] = { field = rdef.sort.field, op = "gte", value = "" }
          end

          local idx, err = find_covering_index({ indexes = edge_indexes }, query_filters, rdef.sort)
          if not idx then
            error("Rollup '" .. rdef.name .. "' on " .. tdef.name .. "." .. rdef.edge .. ": " .. err)
          end
          rdef._index_name = idx.name or "default"
        else
          rdef._index_name = "default"
        end
      else
        rdef._index_name = "default"
      end

      graph.rollup_defs[tdef.name][rdef.name] = rdef
      graph.rollup_edge_deps[tdef.name][rdef.edge] = graph.rollup_edge_deps[tdef.name][rdef.edge] or {}
      table.insert(graph.rollup_edge_deps[tdef.name][rdef.edge], rdef)

      -- Register DERIVED EDGES for reference and collection rollups
      if rdef.kind == "reference" or rdef.kind == "collection" then
        local edef = graph.edge_defs[tdef.name .. ":" .. rdef.edge]
        local target_type = edef and edef.target or "unknown"

        -- Register derived edge in edge_defs (NO skip list index)
        graph.edge_defs[tdef.name .. ":" .. rdef.name] = {
          name = rdef.name,
          target = target_type,
          is_derived = true,
          base_edge = rdef.edge,
          rdef = rdef,
        }
        table.insert(graph.type_edges[tdef.name], rdef.name)

        -- Track dependency: when base edge changes, update this derived edge
        graph.derived_edge_deps[tdef.name][rdef.edge] = graph.derived_edge_deps[tdef.name][rdef.edge] or {}
        table.insert(graph.derived_edge_deps[tdef.name][rdef.edge], rdef)

        -- Track property dependencies for derived edges
        if rdef.filters or rdef.sort then
          graph.derived_prop_deps[target_type] = graph.derived_prop_deps[target_type] or {}

          for _, f in ipairs(rdef.filters or {}) do
            graph.derived_prop_deps[target_type][f.field] = graph.derived_prop_deps[target_type][f.field] or {}
            table.insert(graph.derived_prop_deps[target_type][f.field], {
              src_type = tdef.name,
              base_edge = rdef.edge,
              rdef = rdef,
            })
          end

          if rdef.sort then
            graph.derived_prop_deps[target_type][rdef.sort.field] = graph.derived_prop_deps[target_type][rdef.sort.field] or {}
            table.insert(graph.derived_prop_deps[target_type][rdef.sort.field], {
              src_type = tdef.name,
              base_edge = rdef.edge,
              rdef = rdef,
            })
          end
        end
      end

      -- Property rollup prop deps (for incremental updates)
      if rdef.kind == "property" and (rdef.property or rdef.filters or rdef.sort) then
        local edef = graph.edge_defs[tdef.name .. ":" .. rdef.edge]
        if edef then
          local target_type = edef.target
          graph.rollup_prop_deps[target_type] = graph.rollup_prop_deps[target_type] or {}

          if rdef.property then
            graph.rollup_prop_deps[target_type][rdef.property] = graph.rollup_prop_deps[target_type][rdef.property] or {}
            table.insert(graph.rollup_prop_deps[target_type][rdef.property], {
              src_type = tdef.name,
              edge_name = rdef.edge,
              rdef = rdef,
            })
          end

          for _, f in ipairs(rdef.filters or {}) do
            graph.rollup_prop_deps[target_type][f.field] = graph.rollup_prop_deps[target_type][f.field] or {}
            table.insert(graph.rollup_prop_deps[target_type][f.field], {
              src_type = tdef.name,
              edge_name = rdef.edge,
              rdef = rdef,
            })
          end

          if rdef.sort then
            graph.rollup_prop_deps[target_type][rdef.sort.field] = graph.rollup_prop_deps[target_type][rdef.sort.field] or {}
            table.insert(graph.rollup_prop_deps[target_type][rdef.sort.field], {
              src_type = tdef.name,
              edge_name = rdef.edge,
              rdef = rdef,
            })
          end
        end
      end
    end
  end

  return setmetatable(graph, { __index = neo.Graph })
end

--============================================================================
-- VIEW NOTIFICATION HELPER
--============================================================================

function neo.Graph:_notify_views(type_filter, method, ...)
  for _, view in pairs(self.views) do
    if not type_filter or type_filter == view.type then
      view[method](view, ...)
    end
  end
end

--============================================================================
-- EDGE SUBSCRIPTION
--============================================================================

function neo.Graph:_subscribe_edge(node_id, edge_name, event, callback)
  if not self.edge_subs[node_id] then
    self.edge_subs[node_id] = {}
  end
  if not self.edge_subs[node_id][edge_name] then
    self.edge_subs[node_id][edge_name] = { link = {}, unlink = {} }
  end

  table.insert(self.edge_subs[node_id][edge_name][event], callback)

  local subs = self.edge_subs[node_id][edge_name][event]
  return function()
    array_remove(subs, callback)
  end
end

function neo.Graph:_notify_edge_subs(node_id, edge_name, event, target_id)
  local node_subs = self.edge_subs[node_id]
  if not node_subs then return end
  local edge_subs = node_subs[edge_name]
  if not edge_subs then return end
  local callbacks = edge_subs[event]
  if not callbacks then return end

  local target_node = self:get(target_id)
  for _, cb in ipairs(callbacks) do
    local ok, err = pcall(cb, target_node)
    if not ok then
      print("Edge callback error:", err)
    end
  end
end

--============================================================================
-- DERIVED EDGE MAINTENANCE
-- These functions maintain derived edges (reference/collection rollups)
-- at write time, so the query layer can treat them as regular edges.
--============================================================================

-- Find the best candidate for a reference rollup (first item after sort)
function neo.Graph:_find_reference_target(src_id, rdef)
  local base_edge = rdef.edge
  local iter = self:targets_iter(src_id, base_edge, nil, rdef._index_name, rdef.filters)
  return iter()  -- First matching target
end

-- Update derived edges when a link is added to the base edge
function neo.Graph:_update_derived_edges_on_link(src_id, base_edge, tgt_id)
  local src = self.nodes[src_id]
  if not src then return end

  local deps = self.derived_edge_deps[src._type]
  if not deps then return end

  local rdefs = deps[base_edge]
  if not rdefs then return end

  local tgt_data = self._node_data[tgt_id]

  for _, rdef in ipairs(rdefs) do
    local derived_edge_name = rdef.name

    -- Initialize derived edge array if needed
    self.edges[src_id][derived_edge_name] = self.edges[src_id][derived_edge_name] or {}
    local derived = self.edges[src_id][derived_edge_name]

    if rdef.kind == "collection" then
      -- Collection: add if target matches filters
      local matches = not rdef.filters or node_matches_filters(tgt_data, rdef.filters)
      if matches and not array_contains(derived, tgt_id) then
        table.insert(derived, tgt_id)
        self.edge_counts[src_id][derived_edge_name] = (self.edge_counts[src_id][derived_edge_name] or 0) + 1
        self:_notify_edge_subs(src_id, derived_edge_name, "link", tgt_id)
      end

    elseif rdef.kind == "reference" then
      -- Reference: find the new best candidate
      local new_ref = self:_find_reference_target(src_id, rdef)
      local old_ref = derived[1]

      if new_ref ~= old_ref then
        -- Remove old reference
        if old_ref then
          derived[1] = nil
          self.edge_counts[src_id][derived_edge_name] = 0
          self:_notify_edge_subs(src_id, derived_edge_name, "unlink", old_ref)
        end
        -- Add new reference
        if new_ref then
          derived[1] = new_ref
          self.edge_counts[src_id][derived_edge_name] = 1
          self:_notify_edge_subs(src_id, derived_edge_name, "link", new_ref)
        end
      end
    end
  end
end

-- Update derived edges when a link is removed from the base edge
function neo.Graph:_update_derived_edges_on_unlink(src_id, base_edge, tgt_id)
  local src = self.nodes[src_id]
  if not src then return end

  local deps = self.derived_edge_deps[src._type]
  if not deps then return end

  local rdefs = deps[base_edge]
  if not rdefs then return end

  for _, rdef in ipairs(rdefs) do
    local derived_edge_name = rdef.name
    local derived = self.edges[src_id] and self.edges[src_id][derived_edge_name]
    if derived then
      if rdef.kind == "collection" then
        -- Collection: remove if present
        if array_remove(derived, tgt_id) then
          self.edge_counts[src_id][derived_edge_name] = math.max(0, (self.edge_counts[src_id][derived_edge_name] or 1) - 1)
          self:_notify_edge_subs(src_id, derived_edge_name, "unlink", tgt_id)
        end

      elseif rdef.kind == "reference" then
        -- Reference: if we removed the current reference, find new one
        local old_ref = derived[1]
        if old_ref == tgt_id then
          derived[1] = nil
          self.edge_counts[src_id][derived_edge_name] = 0
          self:_notify_edge_subs(src_id, derived_edge_name, "unlink", tgt_id)

          -- Find new reference
          local new_ref = self:_find_reference_target(src_id, rdef)
          if new_ref then
            derived[1] = new_ref
            self.edge_counts[src_id][derived_edge_name] = 1
            self:_notify_edge_subs(src_id, derived_edge_name, "link", new_ref)
          end
        end
      end
    end
  end
end

-- Update derived edges when a target's property changes (for filter/sort reevaluation)
function neo.Graph:_update_derived_edges_for_prop(tgt_id, prop_name, old_val, new_val)
  local tgt = self.nodes[tgt_id]
  if not tgt then return end

  local deps = self.derived_prop_deps[tgt._type]
  if not deps then return end

  local prop_deps = deps[prop_name]
  if not prop_deps then return end

  local tgt_data = self._node_data[tgt_id]

  for _, dep in ipairs(prop_deps) do
    local rdef = dep.rdef
    local reverse_edge = self.edge_defs[dep.src_type .. ":" .. dep.base_edge]
    if reverse_edge and reverse_edge.reverse then
      -- Find all sources that have this target linked
      local sources = self.reverse[tgt_id] and self.reverse[tgt_id][reverse_edge.reverse]
      if sources then
        for _, src_id in ipairs(sources) do
          local src = self.nodes[src_id]
          if src and src._type == dep.src_type then
            local derived_edge_name = rdef.name
            local derived = self.edges[src_id] and self.edges[src_id][derived_edge_name]
            if not derived then
              self.edges[src_id][derived_edge_name] = {}
              derived = self.edges[src_id][derived_edge_name]
            end

            if rdef.kind == "collection" then
              -- Check if membership changed
              tgt_data[prop_name] = old_val
              local was_member = not rdef.filters or node_matches_filters(tgt_data, rdef.filters)
              tgt_data[prop_name] = new_val
              local is_member = not rdef.filters or node_matches_filters(tgt_data, rdef.filters)

              if was_member and not is_member then
                -- Left collection
                if array_remove(derived, tgt_id) then
                  self.edge_counts[src_id][derived_edge_name] = math.max(0, (self.edge_counts[src_id][derived_edge_name] or 1) - 1)
                  self:_notify_edge_subs(src_id, derived_edge_name, "unlink", tgt_id)
                end
              elseif not was_member and is_member then
                -- Joined collection
                if not array_contains(derived, tgt_id) then
                  table.insert(derived, tgt_id)
                  self.edge_counts[src_id][derived_edge_name] = (self.edge_counts[src_id][derived_edge_name] or 0) + 1
                  self:_notify_edge_subs(src_id, derived_edge_name, "link", tgt_id)
                end
              end

            elseif rdef.kind == "reference" then
              -- Reference might change if sort field changed
              local old_ref = derived[1]
              local new_ref = self:_find_reference_target(src_id, rdef)

              if new_ref ~= old_ref then
                if old_ref then
                  derived[1] = nil
                  self.edge_counts[src_id][derived_edge_name] = 0
                  self:_notify_edge_subs(src_id, derived_edge_name, "unlink", old_ref)
                end
                if new_ref then
                  derived[1] = new_ref
                  self.edge_counts[src_id][derived_edge_name] = 1
                  self:_notify_edge_subs(src_id, derived_edge_name, "link", new_ref)
                end
              end
            end
          end
        end
      end
    end
  end
end

--============================================================================
-- PROPERTY ROLLUP COMPUTATION
--============================================================================

function neo.Graph:_compute_property_rollup(node_id, rdef)
  local strategy = RollupStrategy[rdef.compute]
  if not strategy then return nil end

  local iter = self:targets_iter(node_id, rdef.edge, nil, rdef._index_name, rdef.filters)
  return strategy.compute(iter, rdef.property, self._node_data, rdef)
end

function neo.Graph:_init_rollups(node_id, type_name)
  local rollups = self.rollup_defs[type_name]
  if not rollups then return end

  local data = self._node_data[node_id]
  for name, rdef in pairs(rollups) do
    if rdef.kind == "property" then
      data[name] = self:_compute_property_rollup(node_id, rdef)
    end
    -- Reference/collection rollups: derived edges initialized in insert
  end
end

function neo.Graph:_init_derived_edges(node_id, type_name)
  local rollups = self.rollup_defs[type_name]
  if not rollups then return end

  for name, rdef in pairs(rollups) do
    if rdef.kind == "reference" or rdef.kind == "collection" then
      self.edges[node_id][name] = {}
      self.edge_counts[node_id][name] = 0
    end
  end
end

function neo.Graph:_update_rollups_for_edge(node_id, edge_name, is_link, tgt_id)
  local node = self.nodes[node_id]
  if not node then return end

  local deps = self.rollup_edge_deps[node._type]
  if not deps then return end

  local rollups = deps[edge_name]
  if not rollups then return end

  local tgt_data = self._node_data[tgt_id]
  local node_data = self._node_data[node_id]

  for _, rdef in ipairs(rollups) do
    if rdef.kind == "property" then
      local old_rollup = node_data[rdef.name]
      local new_rollup = old_rollup

      local matches_filter = true
      if rdef.filters and tgt_data then
        matches_filter = node_matches_filters(tgt_data, rdef.filters)
      end

      if matches_filter then
        local strategy = RollupStrategy[rdef.compute]
        local prop_val = tgt_data and tgt_data[rdef.property]

        if is_link then
          if strategy and strategy.add then
            new_rollup = strategy.add(old_rollup, prop_val, tgt_data, rdef)
          else
            new_rollup = self:_compute_property_rollup(node_id, rdef)
          end
        else
          if strategy and strategy.rescan_on_unlink then
            if strategy.rescan_on_unlink(old_rollup, prop_val, tgt_data, rdef) then
              new_rollup = self:_compute_property_rollup(node_id, rdef)
            end
          elseif strategy and strategy.sub then
            new_rollup = strategy.sub(old_rollup, prop_val, tgt_data, rdef)
          else
            new_rollup = self:_compute_property_rollup(node_id, rdef)
          end
        end
      end

      if old_rollup ~= new_rollup then
        node_data[rdef.name] = new_rollup
        self:_on_prop_change(node_id, rdef.name, new_rollup, old_rollup)
      end
    end
  end
end

function neo.Graph:_update_rollups_for_prop(target_id, prop_name, old_prop_val, new_prop_val)
  local target = self.nodes[target_id]
  if not target then return end

  local target_data = self._node_data[target_id]
  local deps = self.rollup_prop_deps[target._type]
  if not deps then return end

  local prop_deps = deps[prop_name]
  if not prop_deps then return end

  for _, dep in ipairs(prop_deps) do
    local rdef = dep.rdef
    local reverse_name = self.edge_defs[dep.src_type .. ":" .. dep.edge_name]
    if reverse_name and reverse_name.reverse then
      local sources = self.reverse[target_id] and self.reverse[target_id][reverse_name.reverse]
      if sources then
        for _, src_id in ipairs(sources) do
          local src = self.nodes[src_id]
          local src_data = self._node_data[src_id]
          if src and src._type == dep.src_type and rdef.kind == "property" then
            -- Check if this prop change affects filter matching
            local is_filter_field = false
            if rdef.filters then
              for _, f in ipairs(rdef.filters) do
                if f.field == prop_name then
                  is_filter_field = true
                  break
                end
              end
            end

            local new_matches = not rdef.filters or node_matches_filters(target_data, rdef.filters)
            local old_matches = new_matches  -- Default: same as new

            -- If this prop is a filter field, compute old match status with old value
            if is_filter_field and rdef.filters then
              -- Build old_data with old prop value for filter check
              local old_data = {}
              for k, v in pairs(target_data) do old_data[k] = v end
              old_data[prop_name] = old_prop_val
              old_matches = node_matches_filters(old_data, rdef.filters)
            end

            local old_rollup = src_data[rdef.name]
            local new_rollup = old_rollup

            if old_matches and not new_matches then
              -- Was matching, no longer matches: decrement
              local strategy = RollupStrategy[rdef.compute]
              if strategy and strategy.sub then
                local prop_val = target_data and target_data[rdef.property]
                new_rollup = strategy.sub(old_rollup, prop_val, target_data, rdef)
              else
                new_rollup = self:_compute_property_rollup(src_id, rdef)
              end
            elseif not old_matches and new_matches then
              -- Wasn't matching, now matches: increment
              local strategy = RollupStrategy[rdef.compute]
              if strategy and strategy.add then
                local prop_val = target_data and target_data[rdef.property]
                new_rollup = strategy.add(old_rollup, prop_val, target_data, rdef)
              else
                new_rollup = self:_compute_property_rollup(src_id, rdef)
              end
            elseif new_matches then
              -- Still matches: update value if needed
              local compute = rdef.compute

              if rdef.property == prop_name then
                if compute == "sum" then
                  local old_v = old_prop_val or 0
                  local new_v = new_prop_val or 0
                  new_rollup = (old_rollup or 0) - old_v + new_v

                elseif compute == "max" then
                  if new_prop_val ~= nil and (old_rollup == nil or new_prop_val > old_rollup) then
                    new_rollup = new_prop_val
                  elseif old_prop_val ~= nil and old_rollup ~= nil and old_prop_val >= old_rollup then
                    new_rollup = self:_compute_property_rollup(src_id, rdef)
                  end

                elseif compute == "min" then
                  if new_prop_val ~= nil and (old_rollup == nil or new_prop_val < old_rollup) then
                    new_rollup = new_prop_val
                  elseif old_prop_val ~= nil and old_rollup ~= nil and old_prop_val <= old_rollup then
                    new_rollup = self:_compute_property_rollup(src_id, rdef)
                  end

                else
                  new_rollup = self:_compute_property_rollup(src_id, rdef)
                end
              else
                new_rollup = self:_compute_property_rollup(src_id, rdef)
              end
            end

            if old_rollup ~= new_rollup then
              src_data[rdef.name] = new_rollup
              self:_on_prop_change(src_id, rdef.name, new_rollup, old_rollup)
            end
          end
        end
      end
    end
  end
end

--============================================================================
-- CRUD
--============================================================================

function neo.Graph:insert(type_name, props)
  local tdef = self.types[type_name]
  if not tdef then error("Unknown type: " .. type_name) end

  local id = self.next_id
  self.next_id = id + 1

  local user_mt = getmetatable(props)

  local data = {}
  for k, v in pairs(props or {}) do
    data[k] = v
  end
  self._node_data[id] = data

  local node = {}
  rawset(node, "_id", id)
  rawset(node, "_type", type_name)

  setup_node_metatable(self, node, id, type_name, user_mt)

  self.nodes[id] = node

  self.edges[id] = {}
  self.edge_counts[id] = {}

  -- Initialize derived edges for reference/collection rollups
  self:_init_derived_edges(id, type_name)

  self:_init_rollups(id, type_name)

  for _, idx in ipairs(tdef.indexes or {}) do
    self.indexes[type_index_key(type_name, idx.name)].insert(id)
  end

  self:_notify_views(type_name, "_on_insert", node)

  return node
end

function neo.Graph:update(id, props)
  local node = self.nodes[id]
  if not node then return nil end

  local data = self._node_data[id]

  for k, v in pairs(props) do
    if v == neo.NIL then
      v = nil
    end
    local old = data[k]
    if old ~= v then
      data[k] = v
      self:_on_prop_change(id, k, v, old)
    end
  end

  return self:get(id)
end

function neo.Graph:clear_prop(id, prop_name)
  local node = self.nodes[id]
  if not node then return nil end

  local data = self._node_data[id]
  local old = data[prop_name]
  if old ~= nil then
    data[prop_name] = nil
    self:_on_prop_change(id, prop_name, nil, old)
  end

  return self:get(id)
end

function neo.Graph:_on_prop_change(id, prop, new_val, old_val)
  local node = self.nodes[id]
  if not node then return end

  local data = self._node_data[id]
  local tdef = self.types[node._type]
  if not tdef then return end

  for _, idx in ipairs(tdef.indexes or {}) do
    for _, f in ipairs(idx.fields or {}) do
      if f.name == prop then
        local sl = self.indexes[type_index_key(node._type, idx.name)]
        data[prop] = old_val
        sl.remove(id)
        data[prop] = new_val
        sl.insert(id)
        break
      end
    end
  end

  self:_resort_edges(id, prop, new_val, old_val)
  self:_notify_views(node._type, "_on_change", node, prop, new_val, old_val)

  self:_update_rollups_for_prop(id, prop, old_val, new_val)
  self:_update_derived_edges_for_prop(id, prop, old_val, new_val)

  local node_watchers = self.watchers[id]
  if node_watchers then
    for _, cb in ipairs(node_watchers) do
      cb(id, prop, new_val, old_val)
    end
  end
end

function neo.Graph:_resort_edges(tgt_id, prop, new_val, old_val)
  local tgt = self.nodes[tgt_id]
  if not tgt then return end

  local tgt_data = self._node_data[tgt_id]
  local type_deps = self.edge_field_deps[tgt._type]
  if not type_deps then return end

  local prop_deps = type_deps[prop]
  if not prop_deps then return end

  for _, dep in ipairs(prop_deps) do
    local edge_sl = self.edge_indexes[edge_index_key(dep.type_name, dep.edge_name, dep.idx_name)]
    if edge_sl then
      local idx_fields = dep.idx_fields
      for _, src_id in ipairs(self:sources(tgt_id, dep.reverse)) do
        -- Build old entry with old field values for removal
        local old_data = {}
        for k, v in pairs(tgt_data) do old_data[k] = v end
        old_data[prop] = old_val
        local old_entry = make_edge_entry(src_id, tgt_id, idx_fields, old_data)
        edge_sl.remove(old_entry)

        -- Build new entry with new field values for insertion
        local new_entry = make_edge_entry(src_id, tgt_id, idx_fields, tgt_data)
        edge_sl.insert(new_entry)
      end
    end
  end
end

function neo.Graph:delete(id)
  local node = self.nodes[id]
  if not node then return false end

  for edge_name, targets in pairs(self.edges[id] or {}) do
    -- Skip derived edges, they'll be cleaned up automatically
    local edef = self.edge_defs[node._type .. ":" .. edge_name]
    if not edef or not edef.is_derived then
      for i = #targets, 1, -1 do
        self:unlink(id, edge_name, targets[i])
      end
    end
  end

  local tdef = self.types[node._type]
  if tdef then
    for _, idx in ipairs(tdef.indexes or {}) do
      self.indexes[type_index_key(node._type, idx.name)].remove(id)
    end
  end

  self:_notify_views(node._type, "_on_delete", node)

  self.nodes[id] = nil
  self._node_data[id] = nil
  self.edges[id] = nil
  self.edge_counts[id] = nil
  self.reverse[id] = nil
  self.watchers[id] = nil
  self.edge_subs[id] = nil
  self._edge_handles[id] = nil
  self._signals[id] = nil

  return true
end

function neo.Graph:get(id)
  return self.nodes[id]
end

--============================================================================
-- EDGES
--============================================================================

function neo.Graph:_get_edge_def(tdef, edge_name)
  return self.edge_defs[tdef.name .. ":" .. edge_name]
end

function neo.Graph:link(src_id, edge_name, tgt_id)
  local src = self.nodes[src_id]
  local tgt = self.nodes[tgt_id]
  if not src or not tgt then return false end

  local tdef = self.types[src._type]
  local edef = tdef and self:_get_edge_def(tdef, edge_name)
  if not edef then return false end

  -- Cannot link on derived edges
  if edef.is_derived then return false end

  local tgt_data = self._node_data[tgt_id]
  local src_data = self._node_data[src_id]

  -- Check if edge already exists (use default index which has no fields)
  local default_entry = make_edge_entry(src_id, tgt_id, nil, nil)
  local default_sl = self.edge_indexes[edge_index_key(src._type, edge_name, "default")]
  if default_sl and default_sl.contains(default_entry) then return false end

  if edef.reverse then
    local rev_default_entry = make_edge_entry(tgt_id, src_id, nil, nil)
    local tgt_tdef = self.types[tgt._type]
    local rev_edef = tgt_tdef and self:_get_edge_def(tgt_tdef, edef.reverse)
    if rev_edef then
      local rev_sl = self.edge_indexes[edge_index_key(tgt._type, edef.reverse, "default")]
      if rev_sl and rev_sl.contains(rev_default_entry) then return false end
    end
  end

  -- Insert into all indexes with denormalized field values
  for _, idx in ipairs(edef.indexes or {{ name = "default", fields = {} }}) do
    local sl = self.edge_indexes[edge_index_key(src._type, edge_name, idx.name)]
    if sl then
      local entry = make_edge_entry(src_id, tgt_id, idx.fields, tgt_data)
      sl.insert(entry)
    end
  end

  self.edges[src_id][edge_name] = self.edges[src_id][edge_name] or {}
  table.insert(self.edges[src_id][edge_name], tgt_id)
  self.edge_counts[src_id][edge_name] = (self.edge_counts[src_id][edge_name] or 0) + 1

  if edef.reverse then
    self.reverse[tgt_id] = self.reverse[tgt_id] or {}
    self.reverse[tgt_id][edef.reverse] = self.reverse[tgt_id][edef.reverse] or {}
    table.insert(self.reverse[tgt_id][edef.reverse], src_id)

    local tgt_tdef = self.types[tgt._type]
    local rev_edef = tgt_tdef and self:_get_edge_def(tgt_tdef, edef.reverse)
    if rev_edef then
      -- Insert into all reverse edge indexes with denormalized field values
      for _, idx in ipairs(rev_edef.indexes or {{ name = "default", fields = {} }}) do
        local sl = self.edge_indexes[edge_index_key(tgt._type, edef.reverse, idx.name)]
        if sl then
          local rev_entry = make_edge_entry(tgt_id, src_id, idx.fields, src_data)
          sl.insert(rev_entry)
        end
      end
      self.edges[tgt_id][edef.reverse] = self.edges[tgt_id][edef.reverse] or {}
      table.insert(self.edges[tgt_id][edef.reverse], src_id)
      self.edge_counts[tgt_id][edef.reverse] = (self.edge_counts[tgt_id][edef.reverse] or 0) + 1
    end
  end

  -- Update property rollups
  self:_update_rollups_for_edge(src_id, edge_name, true, tgt_id)

  -- Update derived edges (reference/collection rollups)
  self:_update_derived_edges_on_link(src_id, edge_name, tgt_id)

  -- Also update derived edges on target for reverse edge
  if edef.reverse then
    self:_update_derived_edges_on_link(tgt_id, edef.reverse, src_id)
  end

  self:_notify_views(nil, "_on_link", src_id, edge_name, tgt_id)
  self:_notify_edge_subs(src_id, edge_name, "link", tgt_id)

  if edef.reverse then
    self:_notify_edge_subs(tgt_id, edef.reverse, "link", src_id)
  end

  return true
end

function neo.Graph:unlink(src_id, edge_name, tgt_id)
  local src = self.nodes[src_id]
  if not src then return false end

  local tdef = self.types[src._type]
  local edef = tdef and self:_get_edge_def(tdef, edge_name)
  if not edef then return false end

  -- Cannot unlink on derived edges
  if edef.is_derived then return false end

  local tgt_data = self._node_data[tgt_id]
  local src_data = self._node_data[src_id]

  -- Check if edge exists (use default index which has no fields)
  local default_entry = make_edge_entry(src_id, tgt_id, nil, nil)
  local default_sl = self.edge_indexes[edge_index_key(src._type, edge_name, "default")]
  if default_sl and not default_sl.contains(default_entry) then return false end

  -- Remove from all indexes with denormalized field values
  for _, idx in ipairs(edef.indexes or {{ name = "default", fields = {} }}) do
    local sl = self.edge_indexes[edge_index_key(src._type, edge_name, idx.name)]
    if sl then
      local entry = make_edge_entry(src_id, tgt_id, idx.fields, tgt_data)
      sl.remove(entry)
    end
  end

  local targets = self.edges[src_id] and self.edges[src_id][edge_name]
  if targets then array_remove(targets, tgt_id) end

  if self.edge_counts[src_id][edge_name] then
    self.edge_counts[src_id][edge_name] = self.edge_counts[src_id][edge_name] - 1
    if self.edge_counts[src_id][edge_name] <= 0 then
      self.edge_counts[src_id][edge_name] = nil
    end
  end

  if edef.reverse then
    local sources = self.reverse[tgt_id] and self.reverse[tgt_id][edef.reverse]
    if sources then array_remove(sources, src_id) end

    local tgt = self.nodes[tgt_id]
    if tgt then
      local tgt_tdef = self.types[tgt._type]
      local rev_edef = tgt_tdef and self:_get_edge_def(tgt_tdef, edef.reverse)
      if rev_edef then
        -- Remove from all reverse edge indexes with denormalized field values
        for _, idx in ipairs(rev_edef.indexes or {{ name = "default", fields = {} }}) do
          local sl = self.edge_indexes[edge_index_key(tgt._type, edef.reverse, idx.name)]
          if sl then
            local rev_entry = make_edge_entry(tgt_id, src_id, idx.fields, src_data)
            sl.remove(rev_entry)
          end
        end
        local rev_targets = self.edges[tgt_id] and self.edges[tgt_id][edef.reverse]
        if rev_targets then array_remove(rev_targets, src_id) end
        if self.edge_counts[tgt_id] and self.edge_counts[tgt_id][edef.reverse] then
          self.edge_counts[tgt_id][edef.reverse] = self.edge_counts[tgt_id][edef.reverse] - 1
          if self.edge_counts[tgt_id][edef.reverse] <= 0 then
            self.edge_counts[tgt_id][edef.reverse] = nil
          end
        end
      end
    end
  end

  -- Update property rollups
  self:_update_rollups_for_edge(src_id, edge_name, false, tgt_id)

  -- Update derived edges (reference/collection rollups)
  self:_update_derived_edges_on_unlink(src_id, edge_name, tgt_id)

  -- Also update derived edges on target for reverse edge
  if edef.reverse then
    self:_update_derived_edges_on_unlink(tgt_id, edef.reverse, src_id)
  end

  self:_notify_views(nil, "_on_unlink", src_id, edge_name, tgt_id)
  self:_notify_edge_subs(src_id, edge_name, "unlink", tgt_id)

  if edef.reverse then
    self:_notify_edge_subs(tgt_id, edef.reverse, "unlink", src_id)
  end

  return true
end

function neo.Graph:targets(id, edge_name)
  return self.edges[id] and self.edges[id][edge_name] or {}
end

function neo.Graph:sources(id, edge_name)
  return self.reverse[id] and self.reverse[id][edge_name] or {}
end

function neo.Graph:targets_count(id, edge_name)
  return self.edge_counts[id] and self.edge_counts[id][edge_name] or 0
end

function neo.Graph:targets_iter(id, edge_name, offset, index_name, filters)
  local src = self.nodes[id]
  if not src then return function() end end

  -- Check if this is a derived edge
  local edef = self.edge_defs[src._type .. ":" .. edge_name]
  if edef and edef.is_derived then
    -- Derived edges: just iterate the array directly (no skip list)
    local targets = self.edges[id] and self.edges[id][edge_name] or {}
    local i = offset or 0
    if not filters then
      return function()
        i = i + 1
        return targets[i]
      end
    end
    local node_data = self._node_data
    return function()
      while true do
        i = i + 1
        local tgt_id = targets[i]
        if not tgt_id then return nil end
        if node_matches_filters(node_data[tgt_id], filters) then
          return tgt_id
        end
      end
    end
  end

  -- Regular edge: use skip list index
  local edge_sl = self.edge_indexes[edge_index_key(src._type, edge_name, index_name or "default")]

  if not edge_sl then
    local targets = self.edges[id] and self.edges[id][edge_name]
    if not targets or #targets == 0 then
      targets = self.reverse[id] and self.reverse[id][edge_name] or {}
    end
    local i = offset or 0
    if not filters then
      return function()
        i = i + 1
        return targets[i]
      end
    end
    local node_data = self._node_data
    return function()
      while true do
        i = i + 1
        local tgt_id = targets[i]
        if not tgt_id then return nil end
        if node_matches_filters(node_data[tgt_id], filters) then
          return tgt_id
        end
      end
    end
  end

  local parent_id = id
  local node_data = self._node_data

  -- Get index fields for this index
  local idx_fields = nil
  if edef and filters then
    for _, idx in ipairs(edef.indexes or {}) do
      if (idx.name or "default") == (index_name or "default") then
        idx_fields = idx.fields
        break
      end
    end
  end

  -- Build equality prefix from filters matching index field order
  local eq_prefix = {}
  local eq_values = {}  -- Values for seeking
  if idx_fields and filters then
    for i, idx_field in ipairs(idx_fields) do
      local found = false
      for _, f in ipairs(filters) do
        if f.field == idx_field.name and (f.op == "eq" or f.op == nil) then
          eq_prefix[#eq_prefix + 1] = { field = f.field, value = f.value, idx = i }
          eq_values[i] = f.value
          found = true
          break
        end
      end
      if not found then break end  -- Stop at first non-equality field
    end
  end

  -- Build lower_bound with equality prefix values for proper index seeking
  local lower_bound = { parent = id, child = 0 }
  if #eq_values > 0 then
    lower_bound._f = eq_values  -- Seek directly to matching prefix
  end

  local first_pos = edge_sl.rank_lower_bound(lower_bound)
  local target_pos = first_pos + (offset or 0)

  return coroutine.wrap(function()
    for entry in edge_sl.iter_from(target_pos) do
      if entry.parent ~= parent_id then break end

      -- Check equality prefix from the entry's denormalized fields (fast)
      if #eq_prefix > 0 and entry._f then
        local prefix_match = true
        for _, eq in ipairs(eq_prefix) do
          if entry._f[eq.idx] ~= eq.value then
            prefix_match = false
            break
          end
        end
        if not prefix_match then
          break  -- Past the matching range, stop
        end
      end

      -- Apply full filter check (for non-indexed filters)
      local child_data = node_data[entry.child]
      if child_data and (not filters or node_matches_filters(child_data, filters)) then
        coroutine.yield(entry.child)
      end
    end
  end)
end

function neo.Graph:has_edge(src_id, edge_name, tgt_id)
  local src = self.nodes[src_id]
  if not src then return false end

  -- Check if derived edge
  local edef = self.edge_defs[src._type .. ":" .. edge_name]
  if edef and edef.is_derived then
    local targets = self.edges[src_id] and self.edges[src_id][edge_name]
    return targets and array_contains(targets, tgt_id)
  end

  local edge_sl = self.edge_indexes[edge_index_key(src._type, edge_name, "default")]
  if edge_sl then
    return edge_sl.contains({ parent = src_id, child = tgt_id })
  end

  local targets = self.edges[src_id] and self.edges[src_id][edge_name]
  if targets then
    for _, t in ipairs(targets) do
      if t == tgt_id then return true end
    end
  end
  return false
end

--============================================================================
-- PATH UTILITIES
--============================================================================

local function path_to_key(path)
  if #path == 1 then return tostring(path[1]) end
  local parts = {}
  for i, v in ipairs(path) do
    parts[i] = tostring(v)
  end
  return table.concat(parts, ":")
end

local function path_key_to_path(path_key)
  local path = {}
  local is_id = true
  for part in path_key:gmatch("[^:]+") do
    if is_id then
      path[#path + 1] = tonumber(part)
    else
      path[#path + 1] = part
    end
    is_id = not is_id
  end
  return path
end

--============================================================================
-- EDGE CONFIGURATION
--============================================================================

local function normalize_edge_config(graph, source_type, edges)
  if not edges then return nil end

  local tdef = graph.types[source_type]
  if not tdef then return nil end

  local config = {}
  for edge_name, cfg in pairs(edges) do
    -- Check if this is a valid edge (real or derived)
    local edef = graph.edge_defs[source_type .. ":" .. edge_name]
    if not edef then
      error("Unknown edge '" .. edge_name .. "' on type '" .. source_type .. "'")
    end

    local target_type = edef.target
    local normalized = {}

    if cfg == true then
      -- Trackable but not eager
    elseif type(cfg) == "table" then
      normalized.eager = cfg.eager or false
      normalized.inline = cfg.inline or false
      normalized.recursive = cfg.recursive or false
      normalized.skip = cfg.skip or 0
      normalized.take = cfg.take

      if cfg.filters or cfg.sort then
        -- For derived edges, we don't support additional filters/sort at view level
        if edef.is_derived then
          error("Cannot apply filters/sort to derived edge '" .. edge_name .. "' in view")
        end

        local query_filters = {}
        local has_range_on_sort_field = false
        if cfg.filters then
          for _, f in ipairs(cfg.filters) do
            query_filters[#query_filters + 1] = f
            if cfg.sort and f.field == cfg.sort.field and f.op and f.op ~= "eq" then
              has_range_on_sort_field = true
            end
          end
        end
        if cfg.sort then
          normalized.sort = cfg.sort
          if not has_range_on_sort_field then
            query_filters[#query_filters + 1] = { field = cfg.sort.field, op = "gte", value = "" }
          end
        end

        local edge_indexes = edef.indexes or {{ name = "default", fields = {} }}
        local idx, err = find_covering_index({ indexes = edge_indexes }, query_filters, normalized.sort)
        if not idx then
          error("Edge '" .. edge_name .. "': " .. err)
        end
        normalized.filters = cfg.filters
        normalized.index_name = idx.name or "default"
      end

      if cfg.edges then
        normalized.edges = normalize_edge_config(graph, target_type, cfg.edges)
      end
    end

    normalized._is_derived = edef.is_derived

    config[edge_name] = normalized
  end
  return config
end

local function get_config_for_edge(edge_tree, edge_path, edge_name)
  if not edge_tree then return nil end

  if #edge_path == 0 then
    return edge_tree[edge_name]
  end

  local last_edge = edge_path[#edge_path]

  local node = edge_tree[edge_path[1]]
  if not node then return nil end

  for i = 2, #edge_path do
    if not node or not node.edges then break end
    node = node.edges[edge_path[i]]
    if node and node.recursive and edge_path[i] == edge_name then
      return node
    end
  end

  if last_edge == edge_name and node then
    return node
  end

  if node and node.edges then
    return node.edges[edge_name]
  end

  return nil
end

local function check_edge_flag(flag, node)
  if type(flag) == "function" then return flag(node) end
  return flag == true
end

local function check_edge_config(edge_tree, edge_path, edge_name, flag_name, parent_node)
  local cfg = get_config_for_edge(edge_tree, edge_path, edge_name)
  if not cfg then return false end
  return check_edge_flag(cfg[flag_name], parent_node)
end

--============================================================================
-- CHILD ITERATOR HELPER
-- Now simplified since derived edges are stored as regular edges
--============================================================================

local function make_child_iterator(graph, parent_id, edge_name, edge_cfg)
  local edge_filters = edge_cfg and edge_cfg.filters
  local index_name = edge_cfg and edge_cfg.index_name
  local skip = edge_cfg and edge_cfg.skip or 0
  local take = edge_cfg and edge_cfg.take

  -- For derived edges (reference rollups), limit take to 1
  local parent_node = graph.nodes[parent_id]
  if parent_node then
    local edef = graph.edge_defs[parent_node._type .. ":" .. edge_name]
    if edef and edef.is_derived and edef.rdef and edef.rdef.kind == "reference" then
      if take == nil or take > 1 then
        take = 1
      end
    end
  end

  local base_iter = graph:targets_iter(parent_id, edge_name, nil, index_name, edge_filters)

  if skip == 0 and take == nil then
    return base_iter
  end

  local skipped = 0
  local taken = 0
  return function()
    while true do
      local child_id = base_iter()
      if child_id == nil then return nil end

      if skipped < skip then
        skipped = skipped + 1
      else
        if take ~= nil and taken >= take then
          return nil
        end
        taken = taken + 1
        return child_id
      end
    end
  end
end

local function count_children_with_cursor(graph, parent_id, edge_name, edge_cfg)
  local total = graph:targets_count(parent_id, edge_name)

  -- For reference rollups, max is 1
  local parent_node = graph.nodes[parent_id]
  if parent_node then
    local edef = graph.edge_defs[parent_node._type .. ":" .. edge_name]
    if edef and edef.is_derived and edef.rdef and edef.rdef.kind == "reference" then
      if total > 1 then total = 1 end
    end
  end

  local skip = edge_cfg and edge_cfg.skip or 0
  local take = edge_cfg and edge_cfg.take

  local after_skip = total - skip
  if after_skip < 0 then after_skip = 0 end

  if take ~= nil and after_skip > take then
    return take
  end
  return after_skip
end

--============================================================================
-- VIEWS (Virtualized Range Strategy)
--============================================================================

neo.View = {}

function neo.Graph:view(query_def, opts)
  opts = opts or {}

  local tdef = self.types[query_def.type]
  if not tdef then error("Unknown type: " .. query_def.type) end

  local idx, err = find_covering_index(tdef, query_def.filters)
  if not idx then error(err) end

  local view = {
    graph = self,
    type = query_def.type,
    filters = query_def.filters or {},
    index_name = idx.name or "default",
    index_key = type_index_key(query_def.type, idx.name),
    offset = opts.offset or 0,
    limit = opts.limit or 50,
    callbacks = opts.callbacks or {},
    edge_tree = normalize_edge_config(self, query_def.type, query_def.edges),

    expansions = {},
    expanded_at = {},

    _root_count = nil,
    _expansion_size = 0,

    node_watchers = {},
    edge_watchers = {},

    _viewport_cache = nil,
    _viewport_dirty = true,

    _initializing = true,
  }

  self.views[view] = view
  local view_mt = setmetatable(view, { __index = neo.View })

  view_mt:_initialize_roots()

  view_mt._initializing = false

  return view_mt
end

function neo.View:_initialize_roots()
  local count = 0
  local sl = self.graph.indexes[self.index_key]
  local on_enter = self.callbacks.on_enter
  local roots_to_expand = {}

  if #self.filters == 0 then
    self._root_count = sl.count()
    local pos = 0
    for id in sl.iter() do
      pos = pos + 1
      self:_subscribe_node(id)
      if on_enter then
        local node = self.graph:get(id)
        on_enter(node, pos, nil, nil)
      end
      roots_to_expand[#roots_to_expand + 1] = id
    end
  else
    local pos = 0
    for id in sl.iter() do
      local raw_node = self.graph.nodes[id]
      if raw_node and node_matches_filters(raw_node, self.filters, self.graph) then
        count = count + 1
        pos = pos + 1
        self:_subscribe_node(id)
        if on_enter then
          local node = self.graph:get(id)
          on_enter(node, pos, nil, nil)
        end
        roots_to_expand[#roots_to_expand + 1] = id
      end
    end
    self._root_count = count
  end

  for _, root_id in ipairs(roots_to_expand) do
    local root_node = self.graph.nodes[root_id]
    if root_node then
      local path_key = tostring(root_id)
      local available_edges = self:_get_available_edges(root_node._type)
      for _, edge_name in ipairs(available_edges) do
        if check_edge_config(self.edge_tree, {}, edge_name, "eager", root_node) then
          -- _expand now fires on_expand internally with context
          self:_expand(path_key, edge_name, { eager = true })
        end
      end
    end
  end
end

-- Get available edges for a type (real edges + derived edges from rollups)
function neo.View:_get_available_edges(type_name)
  return self.graph.type_edges[type_name] or {}
end

function neo.View:_compute_root_count()
  local count = 0
  local sl = self.graph.indexes[self.index_key]
  if #self.filters == 0 then
    self._root_count = sl.count()
    return
  end
  for id in sl.iter() do
    local node = self.graph.nodes[id]
    if node and node_matches_filters(node, self.filters, self.graph) then
      count = count + 1
    end
  end
  self._root_count = count
end

function neo.View:visible_total()
  if not self._root_count then self:_compute_root_count() end
  return self._root_count + self._expansion_size
end

--============================================================================
-- VIRTUALIZED OFFSET CALCULATION
--============================================================================

function neo.View:_expansion_size_at(path_key)
  local exp = self.expansions[path_key]
  if not exp then return 0 end

  local total = 0
  local graph = self.graph
  local parent_id = self:_path_key_to_id(path_key)
  local parent_node = parent_id and graph.nodes[parent_id]

  for edge_name, edge_exp in pairs(exp) do
    local edge_path = self:_path_key_to_edge_path(path_key)
    table.insert(edge_path, edge_name)
    local is_inline = check_edge_config(self.edge_tree, edge_path, edge_name, "inline", parent_node)

    if is_inline then
      local cfg = get_config_for_edge(self.edge_tree, edge_path, edge_name)
      for child_id in make_child_iterator(graph, parent_id, edge_name, cfg) do
        local child_path_key = path_key .. ":" .. edge_name .. ":" .. child_id
        total = total + self:_expansion_size_at(child_path_key)
      end
    else
      total = total + edge_exp.count
      total = total + self:_nested_expansion_size(path_key, edge_name)
    end
  end
  return total
end

function neo.View:_nested_expansion_size(parent_path_key, edge_name)
  local prefix = parent_path_key .. ":" .. edge_name .. ":"
  local total = 0

  for child_path_key in pairs(self.expanded_at) do
    if child_path_key:sub(1, #prefix) == prefix then
      local child_exp = self.expansions[child_path_key]
      if child_exp then
        for _, edge_exp in pairs(child_exp) do
          total = total + edge_exp.count
        end
      end
    end
  end

  return total
end

function neo.View:_resolve_position(virtual_pos)
  if virtual_pos < 1 then return nil end

  local graph = self.graph
  local sl = graph.indexes[self.index_key]
  local root_pos = 0

  for root_id in sl.iter() do
    local root = graph.nodes[root_id]
    if root and node_matches_filters(root, self.filters, self.graph) then
      root_pos = root_pos + 1

      if root_pos == virtual_pos then
        return root_id, tostring(root_id), 0, nil
      end

      local path_key = tostring(root_id)
      local exp_size = self:_expansion_size_at(path_key)

      if virtual_pos <= root_pos + exp_size then
        local offset_in_subtree = virtual_pos - root_pos
        return self:_resolve_subtree_position(path_key, offset_in_subtree, 0, root)
      end

      root_pos = root_pos + exp_size
    end
  end

  return nil
end

function neo.View:_resolve_subtree_position(parent_path_key, offset, parent_depth, parent_node)
  local exp = self.expansions[parent_path_key]
  if not exp then return nil end

  local pos = 0
  local graph = self.graph

  local edge_names = {}
  for edge_name in pairs(exp) do edge_names[#edge_names + 1] = edge_name end
  table.sort(edge_names)

  for _, edge_name in ipairs(edge_names) do
    local edge_exp = exp[edge_name]
    local edge_path = self:_path_key_to_edge_path(parent_path_key)
    table.insert(edge_path, edge_name)
    local cfg = get_config_for_edge(self.edge_tree, edge_path, edge_name)
    local is_inline = check_edge_config(self.edge_tree, edge_path, edge_name, "inline", parent_node)
    local child_depth = is_inline and parent_depth or (parent_depth + 1)

    local parent_id = self:_path_key_to_id(parent_path_key)

    for child_id in make_child_iterator(graph, parent_id, edge_name, cfg) do
      local child_path_key = parent_path_key .. ":" .. edge_name .. ":" .. child_id
      local child_node = graph.nodes[child_id]

      if is_inline then
        local child_exp_size = self:_expansion_size_at(child_path_key)
        if child_exp_size > 0 and offset <= pos + child_exp_size then
          return self:_resolve_subtree_position(child_path_key, offset - pos, child_depth, child_node)
        end
        pos = pos + child_exp_size
      else
        pos = pos + 1
        if pos == offset then
          return child_id, child_path_key, child_depth, edge_name
        end

        local child_exp_size = self:_expansion_size_at(child_path_key)
        if offset <= pos + child_exp_size then
          return self:_resolve_subtree_position(child_path_key, offset - pos, child_depth, child_node)
        end

        pos = pos + child_exp_size
      end

      if pos >= offset then break end
    end
  end

  return nil
end

--============================================================================
-- NODE/EDGE SUBSCRIPTIONS
--============================================================================

function neo.View:_subscribe_node(node_id)
  if self.node_watchers[node_id] then
    self.node_watchers[node_id].ref_count = self.node_watchers[node_id].ref_count + 1
    return
  end

  local view = self
  local unsub = self.graph:watch(node_id, {
    on_change = function(id, prop, new_val, old_val)
      view:_on_node_change(id, prop, new_val, old_val)
    end
  })

  self.node_watchers[node_id] = { unsub = unsub, ref_count = 1 }
end

function neo.View:_unsubscribe_node(node_id)
  local watcher = self.node_watchers[node_id]
  if not watcher then return end

  watcher.ref_count = watcher.ref_count - 1
  if watcher.ref_count <= 0 then
    watcher.unsub()
    self.node_watchers[node_id] = nil
  end
end

function neo.View:_subscribe_edge(path_key, edge_name, parent_id)
  local key = path_key .. ":" .. edge_name
  if self.edge_watchers[key] then return end

  -- Subscribe directly to the edge (works for both real and derived edges)
  local view = self
  local unsub_link = self.graph:_subscribe_edge(parent_id, edge_name, "link", function(child)
    view:_on_edge_link(path_key, edge_name, child._id)
  end)
  local unsub_unlink = self.graph:_subscribe_edge(parent_id, edge_name, "unlink", function(child)
    view:_on_edge_unlink(path_key, edge_name, child._id)
  end)

  self.edge_watchers[key] = function()
    unsub_link()
    unsub_unlink()
  end
end

function neo.View:_unsubscribe_edge(path_key, edge_name)
  local key = path_key .. ":" .. edge_name
  local unsub = self.edge_watchers[key]
  if unsub then
    unsub()
    self.edge_watchers[key] = nil
  end
end

function neo.View:_on_node_change(node_id, prop, new_val, old_val)
  local cb = self.callbacks.on_change
  if not cb then return end

  local node = self.graph:get(node_id)
  if not node then return end

  local watcher = self.node_watchers[node_id]
  local ref_count = watcher and watcher.ref_count or 1

  for _ = 1, ref_count do
    cb(node, prop, new_val, old_val)
  end
end

function neo.View:_on_edge_link(parent_path_key, edge_name, child_id)
  local exp = self.expansions[parent_path_key]
  if not exp or not exp[edge_name] then return end

  local edge_path = self:_path_key_to_edge_path(parent_path_key)
  table.insert(edge_path, edge_name)
  local cfg = get_config_for_edge(self.edge_tree, edge_path, edge_name)

  local child_data = self.graph._node_data[child_id]
  if not child_data then return end

  if cfg and cfg.filters then
    if not node_matches_filters(child_data, cfg.filters) then
      return
    end
  end

  local parent_id = self:_path_key_to_id(parent_path_key)
  local parent_node = parent_id and self.graph.nodes[parent_id]

  local is_inline = check_edge_config(self.edge_tree, edge_path, edge_name, "inline", parent_node)

  exp[edge_name].count = exp[edge_name].count + 1

  if not is_inline then
    self._expansion_size = self._expansion_size + 1
  end

  self._viewport_dirty = true

  self:_subscribe_node(child_id)

  if not self._initializing and not is_inline then
    local cb = self.callbacks.on_enter
    if cb then
      local child_node = self.graph:get(child_id)
      if child_node then
        cb(child_node, nil, edge_name, parent_id)
      end
    end
  end

  local child_node = self.graph.nodes[child_id]
  if child_node then
    local child_path_key = parent_path_key .. ":" .. edge_name .. ":" .. child_id
    local child_edge_path = self:_path_key_to_edge_path(child_path_key)
    local available_edges = self:_get_available_edges(child_node._type)
    for _, edef_name in ipairs(available_edges) do
      if check_edge_config(self.edge_tree, child_edge_path, edef_name, "eager", child_node) then
        self:_expand(child_path_key, edef_name, { eager = true })
      end
    end
  end
end

function neo.View:_on_edge_unlink(parent_path_key, edge_name, child_id)
  local exp = self.expansions[parent_path_key]
  if not exp or not exp[edge_name] then return end

  local child_path_key = parent_path_key .. ":" .. edge_name .. ":" .. child_id
  self:_collapse_all_at(child_path_key)

  local parent_id = self:_path_key_to_id(parent_path_key)
  local parent_node = parent_id and self.graph.nodes[parent_id]

  local edge_path = self:_path_key_to_edge_path(parent_path_key)
  table.insert(edge_path, edge_name)
  local is_inline = check_edge_config(self.edge_tree, edge_path, edge_name, "inline", parent_node)

  exp[edge_name].count = math.max(0, exp[edge_name].count - 1)

  if not is_inline then
    self._expansion_size = math.max(0, self._expansion_size - 1)
  end

  self:_unsubscribe_node(child_id)

  self._viewport_dirty = true

  if not self._initializing and not is_inline then
    local cb = self.callbacks.on_leave
    if cb then
      local child_node = self.graph:get(child_id)
      if child_node then
        cb(child_node, edge_name, parent_id)
      end
    end
  end
end

--============================================================================
-- VIEW EXPANSION
--============================================================================

function neo.View:_is_expanded(path_key, edge_name)
  local exp = self.expansions[path_key]
  return exp and exp[edge_name] ~= nil
end

function neo.View:_expand(path_key, edge_name, context)
  local exp = self.expansions[path_key]
  if exp and exp[edge_name] then
    return false
  end

  local parent_id = self:_path_key_to_id(path_key)
  if not parent_id then return false end

  local parent_node = self.graph.nodes[parent_id]
  if not parent_node then return false end

  local edge_path = self:_path_key_to_edge_path(path_key)
  table.insert(edge_path, edge_name)
  local cfg = get_config_for_edge(self.edge_tree, edge_path, edge_name)

  local child_count = count_children_with_cursor(self.graph, parent_id, edge_name, cfg)

  if not exp then
    self.expansions[path_key] = {}
    exp = self.expansions[path_key]
  end

  exp[edge_name] = {
    count = child_count,
    index_name = cfg and cfg.index_name or "default",
  }

  local is_inline = check_edge_config(self.edge_tree, edge_path, edge_name, "inline", parent_node)

  if not is_inline then
    self._expansion_size = self._expansion_size + child_count
  end

  self.expanded_at[path_key] = true

  self:_subscribe_edge(path_key, edge_name, parent_id)

  -- Fire on_expand callback with context
  local cb = self.callbacks.on_expand
  if cb then
    local node_proxy = self.graph:get(parent_id)
    if node_proxy then
      cb(node_proxy, edge_name, {
        eager = context and context.eager or false,
        path_key = path_key,
        inline = is_inline,
      })
    end
  end

  local depth = self:_path_key_depth(path_key)
  local child_depth = is_inline and depth or (depth + 1)

  for child_id in make_child_iterator(self.graph, parent_id, edge_name, cfg) do
    local child_path_key = path_key .. ":" .. edge_name .. ":" .. child_id
    self:_subscribe_node(child_id)

    if not is_inline then
      local cb_enter = self.callbacks.on_enter
      if cb_enter then
        local child_node = self.graph:get(child_id)
        if child_node then
          cb_enter(child_node, nil, edge_name, parent_id)
        end
      end
    end

    local child_node = self.graph.nodes[child_id]
    if child_node then
      local cep = self:_path_key_to_edge_path(child_path_key)
      local available_edges = self:_get_available_edges(child_node._type)
      for _, edef_name in ipairs(available_edges) do
        if check_edge_config(self.edge_tree, cep, edef_name, "eager", child_node) then
          self:_expand(child_path_key, edef_name, { eager = true })
        end
      end
    end
  end

  self._viewport_dirty = true

  return true
end

function neo.View:_path_key_depth(path_key)
  local depth = 0
  for _ in path_key:gmatch(":") do
    depth = depth + 1
  end
  return depth / 2
end

function neo.View:_collapse(path_key, edge_name)
  local exp = self.expansions[path_key]
  if not exp or not exp[edge_name] then return false end

  local parent_id = self:_path_key_to_id(path_key)
  local parent_node = parent_id and self.graph.nodes[parent_id]
  local edge_path = self:_path_key_to_edge_path(path_key)
  table.insert(edge_path, edge_name)
  local cfg = get_config_for_edge(self.edge_tree, edge_path, edge_name)

  local is_inline = check_edge_config(self.edge_tree, edge_path, edge_name, "inline", parent_node)

  -- Fire on_collapse callback with context
  local cb = self.callbacks.on_collapse
  if cb and parent_id then
    local node_proxy = self.graph:get(parent_id)
    if node_proxy then
      cb(node_proxy, edge_name, {
        path_key = path_key,
        inline = is_inline,
      })
    end
  end

  local prefix = path_key .. ":" .. edge_name .. ":"
  for child_path_key in pairs(self.expanded_at) do
    if child_path_key:sub(1, #prefix) == prefix then
      self:_collapse_all_at(child_path_key)
    end
  end

  if parent_id then
    for child_id in make_child_iterator(self.graph, parent_id, edge_name, cfg) do
      self:_unsubscribe_node(child_id)

      if not is_inline then
        local cb = self.callbacks.on_leave
        if cb then
          local child_node = self.graph:get(child_id)
          if child_node then
            cb(child_node, edge_name, parent_id)
          end
        end
      end
    end
  end

  if not is_inline then
    self._expansion_size = self._expansion_size - exp[edge_name].count
  end

  if parent_id then
    self:_unsubscribe_edge(path_key, edge_name)
  end

  exp[edge_name] = nil

  if not next(exp) then
    self.expansions[path_key] = nil
    self.expanded_at[path_key] = nil
  end

  self._viewport_dirty = true

  return true
end

function neo.View:_collapse_all_at(path_key)
  local exp = self.expansions[path_key]
  if not exp then return end

  local edges_to_collapse = {}
  for edge_name in pairs(exp) do
    edges_to_collapse[#edges_to_collapse + 1] = edge_name
  end

  for _, edge_name in ipairs(edges_to_collapse) do
    self:_collapse(path_key, edge_name)
  end
end

function neo.View:_clear_expansion_matching(pattern)
  local to_remove = {}
  for key in pairs(self.expansions) do
    if key:find(pattern) then
      to_remove[#to_remove + 1] = key
    end
  end
  for _, key in ipairs(to_remove) do
    self:_collapse_all_at(key)
  end
end

--============================================================================
-- PATH KEY UTILITIES
--============================================================================

function neo.View:_path_key_to_id(path_key)
  local last_id = path_key:match(":(%d+)$") or path_key:match("^(%d+)$")
  return last_id and tonumber(last_id)
end

function neo.View:_path_key_to_edge_path(path_key)
  local edge_path = {}
  for edge in path_key:gmatch(":([^:]+):%d+") do
    table.insert(edge_path, edge)
  end
  return edge_path
end

function neo.View:_edges_at_path(path_key)
  local edge_path = self:_path_key_to_edge_path(path_key)
  local node = self.edge_tree

  for _, edge in ipairs(edge_path) do
    if not node or not node[edge] then return {} end
    node = node[edge].edges
  end

  local edges = {}
  if node then
    for edge_name, cfg in pairs(node) do
      if type(cfg) == "table" then
        table.insert(edges, edge_name)
      end
    end
  end
  return edges
end

--============================================================================
-- VIEW CLEANUP
--============================================================================

function neo.View:destroy()
  for _, watcher in pairs(self.node_watchers) do
    watcher.unsub()
  end
  self.node_watchers = {}

  for _, unsub in pairs(self.edge_watchers) do
    unsub()
  end
  self.edge_watchers = {}

  self.expansions = {}
  self.expanded_at = {}
  self._expansion_size = 0
  self._root_count = nil

  self.graph.views[self] = nil
end

function neo.View:on(event, callback)
  local cb_key = "on_" .. event

  if not self._dynamic_callbacks then
    self._dynamic_callbacks = {}
  end
  if not self._dynamic_callbacks[cb_key] then
    self._dynamic_callbacks[cb_key] = {}

    local original = self.callbacks[cb_key]
    self.callbacks[cb_key] = function(...)
      if original then pcall(original, ...) end
      for _, cb in ipairs(self._dynamic_callbacks[cb_key]) do
        pcall(cb, ...)
      end
    end
  end

  table.insert(self._dynamic_callbacks[cb_key], callback)

  return function()
    if not self._dynamic_callbacks or not self._dynamic_callbacks[cb_key] then return end
    for i, cb in ipairs(self._dynamic_callbacks[cb_key]) do
      if cb == callback then
        table.remove(self._dynamic_callbacks[cb_key], i)
        break
      end
    end
  end
end

--============================================================================
-- ITEM
--============================================================================

neo.Item = {}

function neo.Item:expand(edge_name)
  self._view:expand(self.id, edge_name)
end

function neo.Item:collapse(edge_name)
  self._view:collapse(self.id, edge_name)
end

function neo.Item:is_expanded(edge_name)
  return self._view:_is_expanded(path_to_key(self._path), edge_name)
end

function neo.Item:toggle(edge_name)
  if edge_name then
    if self:is_expanded(edge_name) then
      self:collapse(edge_name)
    else
      self:expand(edge_name)
    end
  else
    local edges = self._view:_edges_at_path(path_to_key(self._path))
    -- Check if all edges are expanded
    local all_expanded = true
    for _, e in ipairs(edges) do
      if not self:is_expanded(e) then
        all_expanded = false
        break
      end
    end
    if all_expanded then
      -- All expanded -> collapse all
      for _, e in ipairs(edges) do
        self:collapse(e)
      end
    else
      -- Some collapsed -> expand all non-expanded
      for _, e in ipairs(edges) do
        if not self:is_expanded(e) then
          self:expand(e)
        end
      end
    end
  end
end

function neo.Item:any_expanded()
  local edges = self._view:_edges_at_path(path_to_key(self._path))
  for _, e in ipairs(edges) do
    if self:is_expanded(e) then return true end
  end
  return false
end

function neo.Item:child_count(edge_name)
  return self._view.graph:targets_count(self.id, edge_name)
end

--============================================================================
-- VIEW METHODS
--============================================================================

function neo.View:expand(id, edge_name)
  local path_key = self:_find_path_to(id)
  if not path_key then return false end
  -- Pass eager = false for manual expansions; _expand fires on_expand internally
  return self:_expand(path_key, edge_name, { eager = false })
end

function neo.View:collapse(id, edge_name)
  local path_key = self:_find_path_to(id)
  if not path_key then return false end
  -- _collapse fires on_collapse internally with context
  return self:_collapse(path_key, edge_name)
end

function neo.View:_find_path_to(target_id)
  local node = self.graph.nodes[target_id]
  if not node then return nil end

  if node._type == self.type and node_matches_filters(node, self.filters, self.graph) then
    return tostring(target_id)
  end

  local target_str = tostring(target_id)
  for parent_path_key, edges in pairs(self.expansions) do
    for edge_name, _ in pairs(edges) do
      local parent_id = self:_path_key_to_id(parent_path_key)
      if parent_id then
        local targets = self.graph.edges[parent_id] and self.graph.edges[parent_id][edge_name]
        if targets then
          for _, tgt_id in ipairs(targets) do
            if tgt_id == target_id then
              return parent_path_key .. ":" .. edge_name .. ":" .. target_str
            end
          end
        end
        local reverse_targets = self.graph.reverse[parent_id] and self.graph.reverse[parent_id][edge_name]
        if reverse_targets then
          for _, tgt_id in ipairs(reverse_targets) do
            if tgt_id == target_id then
              return parent_path_key .. ":" .. edge_name .. ":" .. target_str
            end
          end
        end
      end
    end
  end

  return nil
end

function neo.View:scroll(offset)
  if self.offset ~= offset then
    self.offset = offset
    self._viewport_dirty = true
  end
end

function neo.View:total()
  local sl = self.graph.indexes[self.index_key]
  if #self.filters == 0 then return sl.count() end

  local count = 0
  for id in sl.iter() do
    local node = self.graph.nodes[id]
    if node and node_matches_filters(node, self.filters, self.graph) then
      count = count + 1
    end
  end
  return count
end

function neo.View:seek(position)
  local node_id = self:_resolve_position(position)
  if node_id then
    return self.graph:get(node_id)
  end
  return nil
end

function neo.View:position_of(node_id)
  local node = self.graph.nodes[node_id]
  if not node or node._type ~= self.type then return nil end
  if not node_matches_filters(node, self.filters, self.graph) then return nil end
  return self.graph.indexes[self.index_key].rank(node_id)
end

function neo.View:collect()
  local items = {}
  for item in self:items() do
    items[#items + 1] = item
  end
  return items
end

--============================================================================
-- ITEMS ITERATOR
--============================================================================

function neo.View:items()
  local view = self
  local graph = self.graph

  return coroutine.wrap(function()
    local start_pos = view.offset + 1
    local end_pos = view.offset + view.limit
    local total = view:visible_total()

    if end_pos > total then end_pos = total end

    for virtual_pos = start_pos, end_pos do
      local node_id, path_key, depth, edge_name = view:_resolve_position(virtual_pos)
      if node_id then
        local raw_node = graph.nodes[node_id]
        if raw_node then
          local item = setmetatable({
            id = node_id,
            node = graph:get(node_id),
            depth = depth,
            edge = edge_name,
            _view = view,
            _path = path_key_to_path(path_key),
          }, { __index = neo.Item })

          coroutine.yield(item)
        end
      end
    end
  end)
end

--============================================================================
-- VIEW REACTIVE HOOKS
--============================================================================

function neo.View:_on_insert(node)
  if node_matches_filters(node, self.filters, self.graph) then
    self._root_count = nil
    self._viewport_dirty = true

    self:_subscribe_node(node._id)

    if not self._initializing then
      local cb = self.callbacks.on_enter
      if cb then
        local pos = self:_compute_virtual_position(tostring(node._id))
        cb(node, pos, nil, nil)
      end
    end
  end
end

function neo.View:_compute_virtual_position(target_path_key)
  local target_id = self:_path_key_to_id(target_path_key)
  if not target_id then return nil end

  local graph = self.graph
  local sl = graph.indexes[self.index_key]
  local pos = 0

  for root_id in sl.iter() do
    local root = graph.nodes[root_id]
    if root and node_matches_filters(root, self.filters, self.graph) then
      pos = pos + 1

      if root_id == target_id then
        return pos
      end

      local path_key = tostring(root_id)
      pos = pos + self:_expansion_size_at(path_key)
    end
  end

  return nil
end

function neo.View:_on_delete(node)
  local path_key = tostring(node._id)

  self:_collapse_all_at(path_key)

  local id_str = tostring(node._id)
  self:_clear_expansion_matching(":" .. id_str .. ":")
  self:_clear_expansion_matching(":" .. id_str .. "$")

  self._root_count = nil
  self._viewport_dirty = true

  if not self._initializing then
    local cb = self.callbacks.on_leave
    if cb then
      cb(node, nil, nil)
    end
  end
end

function neo.View:_on_change(node, prop, new_val, old_val)
  local dominated_by_filter = false
  for _, f in ipairs(self.filters) do
    if f.field == prop then
      dominated_by_filter = true
      break
    end
  end

  if dominated_by_filter then
    local is_in = node_matches_filters(node, self.filters, self.graph)
    node[prop] = old_val
    local was_in_before = node_matches_filters(node, self.filters, self.graph)
    node[prop] = new_val

    local path_key = tostring(node._id)

    if was_in_before and not is_in then
      self:_collapse_all_at(path_key)
      self._root_count = nil
      self._viewport_dirty = true

      if not self._initializing then
        local cb = self.callbacks.on_leave
        if cb then cb(node, nil, nil) end
      end
    elseif not was_in_before and is_in then
      self._root_count = nil
      self._viewport_dirty = true

      if not self._initializing then
        local cb = self.callbacks.on_enter
        if cb then cb(node, nil, nil, nil) end
      end
    end
  end
end

function neo.View:_on_link(src_id, edge_name, tgt_id)
  -- Handled by edge subscriptions
end

function neo.View:_on_unlink(src_id, edge_name, tgt_id)
  self:_clear_expansion_matching(":" .. edge_name .. ":" .. tgt_id)
end

--============================================================================
-- WATCH
--============================================================================

function neo.Graph:watch(id, callbacks)
  if not self.nodes[id] then return function() end end

  self.watchers[id] = self.watchers[id] or {}
  local cb = callbacks.on_change
  if cb then
    table.insert(self.watchers[id], cb)
  end

  return function()
    local watchers = self.watchers[id]
    if watchers then array_remove(watchers, cb) end
  end
end

return neo
