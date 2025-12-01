local neostate = require("neostate")

-- Define a class
local Counter = neostate.Class("Counter")

function Counter:init(start_val)
    -- Create a signal attached to this instance
    self.count = self:signal(start_val or 0, "count")

    -- Create a derived signal (computed)
    self.doubled = self:signal(0, "doubled")

    -- Watch for changes
    self.count:watch(function(val)
        self.doubled:set(val * 2)
    end)
end

function Counter:increment()
    self.count:set(self.count:get() + 1)
end

-- Define a subclass
local ResettableCounter = neostate.Class("ResettableCounter", Counter)

function ResettableCounter:init(start_val)
    -- Call parent constructor (if needed, though Class system doesn't enforce super calls,
    -- but since init is just a method, we should call it if we want parent init logic)
    Counter.init(self, start_val)
end

function ResettableCounter:reset()
    self.count:set(0)
end

-- Usage
print("=== Class Example ===")

local c = ResettableCounter:new(10)

c.count:watch(function(val)
    print("Count is now: " .. val)
end)

c.doubled:watch(function(val)
    print("Doubled is: " .. val)
end)

print("Incrementing...")
c:increment()

print("Resetting...")
c:reset()

print("Disposing...")
c:dispose()

print("Done.")
