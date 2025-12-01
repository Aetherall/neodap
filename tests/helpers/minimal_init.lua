local vim = vim
vim.opt.rtp:append(".")

-- Add tests directory to package path
-- Get the directory where this init file is located
local init_path = debug.getinfo(1, "S").source:sub(2)  -- Remove '@' prefix
local helpers_dir = vim.fn.fnamemodify(init_path, ":h")   -- tests/helpers
local tests_dir = vim.fn.fnamemodify(helpers_dir, ":h")   -- tests

-- Add helpers directory to package.path so test_helpers can be required
package.path = helpers_dir .. "/?.lua;" .. package.path

-- Preload test_helpers module
local test_helpers_path = helpers_dir .. "/test_helpers.lua"
if vim.fn.filereadable(test_helpers_path) == 1 then
  package.preload["test_helpers"] = function()
    return dofile(test_helpers_path)
  end
  io.stderr:write("Preloaded test_helpers from: " .. test_helpers_path .. "\n")
else
  io.stderr:write("Warning: test_helpers.lua not found at: " .. test_helpers_path .. "\n")
end

-- Check if plenary is already in RTP (e.g. from Nix wrapper)
local ok, _ = pcall(require, "plenary")
if not ok then
  -- Fallback for local development without Nix
  vim.opt.rtp:append("../plenary.nvim")
  ok, _ = pcall(require, "plenary")
end

if ok then
  io.stderr:write("Plenary loaded successfully\n")
else
  io.stderr:write("Failed to load Plenary\n")
end
