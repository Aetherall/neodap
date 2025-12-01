return function(neostate)
    ---@class Class
    ---@field new fun(...): any
    local ClassHelpers = {}

    function ClassHelpers:signal(initial, name)
        local s = neostate.Signal(initial, name)
        s:set_parent(self)
        return s
    end

    function ClassHelpers:list(name)
        local l = neostate.List(name)
        l:set_parent(self)
        return l
    end

    function ClassHelpers:collection(name)
        local c = neostate.Collection(name)
        c:set_parent(self)
        return c
    end

    function ClassHelpers:set(name)
        local s = neostate.Set(name)
        s:set_parent(self)
        return s
    end

    function ClassHelpers:disposable(obj)
        if obj and obj.set_parent then
            obj:set_parent(self)
        end
        return obj
    end

    function ClassHelpers:computed(fn, deps, name)
        local c = neostate.computed(fn, deps, name)
        c:set_parent(self)
        return c
    end

    ---Define a new class
    ---@param name string Debug name for the class
    ---@param base? table Base class to inherit from
    ---@return table
    local function Class(name, base)
        local c = {}

        -- Inheritance
        if base then
            setmetatable(c, { __index = base })
        end

        -- Prototype for instances
        c.__index = c
        c._class_name = name

        -- Constructor
        function c:new(...)
            local instance = setmetatable({}, c)

            -- Initialize Disposable trait
            -- We pass explicit_parent=nil so it doesn't auto-attach to context yet?
            -- Or maybe we want it to?
            -- neostate.Disposable(target, parent, name)
            -- If we are creating a class instance, we probably want standard Disposable behavior.
            neostate.Disposable(instance, nil, name)

            -- Inject helpers if not present (or we can put them in 'c'?)
            -- Putting them in 'c' is better for memory, but 'c' is the class.
            -- Let's put them in 'c' if they are not there.
            for k, v in pairs(ClassHelpers) do
                if not c[k] then
                    c[k] = v
                end
            end

            if instance.init then
                instance:init(...)
            end

            return instance
        end

        -- Allow calling ClassName(...) to create instance
        setmetatable(c, {
            __call = function(_, ...) return c:new(...) end,
            __index = base -- Allow accessing base class static members
        })

        return c
    end

    return Class
end
