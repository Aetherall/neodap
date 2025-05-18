#!/usr/bin/env -S nvim -u NONE -U NONE -N -i NONE -V1 --headless -c "source .vscode/debug.lua"

if os.getenv("DEBUG") == "true" then
  require("lldebugger").start()
end

print(loadfile(os.getenv("FILE"))())

coroutine.create(function()
  for line in io.lines() do
    local fn, err = loadstring(line)
    if fn then
      local result = fn()
      if result then
        print(result)
      end
      return result
    elseif err then
      io.stderr:write(err)
    end
  end
end)
