package.path = package.path .. ";./lua/?.lua;./lua/?/init.lua"
local neostate = require("neostate")


local function test_class()
    print("Testing Class...")

    local MyClass = neostate.Class("MyClass")

    function MyClass:init(val)
        self.value = self:signal(val, "value")
    end

    local instance = MyClass:new(10)

    assert(instance.value:get() == 10, "Initial value should be 10")
    assert(instance._debug_name == "MyClass", "Debug name should be MyClass")

    instance.value:set(20)
    assert(instance.value:get() == 20, "Value should be updated")

    -- Test disposal
    local disposed = false
    instance:on_dispose(function() disposed = true end)

    instance:dispose()
    assert(disposed == true, "Instance should be disposed")
    assert(instance._disposed == true, "Instance _disposed flag should be true")

    print("Class test passed!")
end

local function test_inheritance()
    print("Testing Inheritance...")

    local Base = neostate.Class("Base")
    function Base:base_method() return "base" end

    local Child = neostate.Class("Child", Base)
    function Child:child_method() return "child" end

    local instance = Child:new()

    assert(instance:base_method() == "base", "Should inherit base method")
    assert(instance:child_method() == "child", "Should have child method")
    assert(instance._debug_name == "Child", "Debug name should be Child")

    instance:dispose()
    print("Inheritance test passed!")
end

test_class()
test_inheritance()
