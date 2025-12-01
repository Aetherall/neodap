-- Example plugin: Auto-focus leaf sessions
-- This can be loaded by plugin developers or end users

return function(debugger)
    -- Add is_leaf signal to each session
    debugger.sessions:on_added(function(session)
        session.is_leaf = session:signal(true, "is_leaf")

        -- Update is_leaf when children change
        local children = session:children()
        local function update_is_leaf()
            session.is_leaf:set(children:count() == 0)
        end

        children:on_added(update_is_leaf)
        children:on_removed(update_is_leaf)

        -- Auto-focus leaf sessions that have a parent (not bootstrap)
        session.is_leaf:watch(function(is_leaf)
            if is_leaf and session.parent then
                debugger.active_session:set(session)
            end
        end)
    end)
end
