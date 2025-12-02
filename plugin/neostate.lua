-- Neostate plugin setup
-- Ensures lua modules are findable regardless of cwd

-- Get the plugin's root directory (parent of plugin/)
local plugin_dir = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":h:h")
local lua_dir = plugin_dir .. "/lua"

-- Add to package.path with absolute paths
if not package.path:find(lua_dir, 1, true) then
  package.path = lua_dir .. "/?.lua;" .. lua_dir .. "/?/init.lua;" .. package.path
end
