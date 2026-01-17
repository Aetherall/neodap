-- Test bootstrap: sets up lazy.nvim and loads mini.test

-- Disable swap files (prevents stale swap for "-f" arg parsed as filename)
vim.o.swapfile = false

local root = vim.fn.fnamemodify("./.tests", ":p")
local pid = vim.fn.getpid()

-- Watchdog: crash after timeout to avoid hanging tests
-- Set NEODAP_TEST_TIMEOUT=0 to disable, or to a number for custom timeout
local watchdog_timeout = tonumber(vim.env.NEODAP_TEST_TIMEOUT) or 60000
if watchdog_timeout > 0 then
  local watchdog = vim.uv.new_timer()
  watchdog:start(watchdog_timeout, 0, function()
    io.stderr:write(string.format("\n\nWATCHDOG: Test timeout after %ds, forcing exit\n", watchdog_timeout / 1000))
    os.exit(124)
  end)
end

-- Set stdpaths to use per-process directories to avoid parallel test conflicts
for _, name in ipairs({ "config", "data", "state", "cache" }) do
  vim.env[("XDG_%s_HOME"):format(name:upper())] = root .. "/" .. pid .. "/" .. name
end

-- Shared treesitter install directory (persistent across test runs)
local ts_install_dir = root .. "/treesitter"

-- Setup treesitter parsers from nix if available
local function setup_treesitter_parsers()
  local parser_dir = ts_install_dir .. "/parser"
  vim.fn.mkdir(parser_dir, "p")

  local parsers = {
    { env = "TS_PARSER_PYTHON", name = "python.so" },
    { env = "TS_PARSER_JAVASCRIPT", name = "javascript.so" },
    { env = "TS_PARSER_TYPESCRIPT", name = "typescript.so" },
    { env = "TS_PARSER_LUA", name = "lua.so" },
  }

  for _, p in ipairs(parsers) do
    local src = vim.env[p.env]
    local dst = parser_dir .. "/" .. p.name
    if src and vim.uv.fs_stat(src) and not vim.uv.fs_stat(dst) then
      vim.uv.fs_symlink(src, dst)
    end
  end

  -- Add to runtimepath so vim.treesitter can find parsers
  vim.opt.runtimepath:prepend(ts_install_dir)
end
setup_treesitter_parsers()

-- Bootstrap lazy.nvim (shared across all test processes)
local lazypath = root .. "/plugins/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    lazypath,
  })
end
vim.opt.runtimepath:prepend(lazypath)

-- Install plugins
-- Note: neograph is vendored in lua/neograph/, no external dependency needed
require("lazy").setup({
  {
    "echasnovski/mini.test",
    lazy = false,
  },
  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    config = function()
      -- Parsers are provided by nix and symlinked in setup_treesitter_parsers()
      require("nvim-treesitter.config").setup({ install_dir = ts_install_dir })
      -- Add runtime directory to rtp for queries (locals.scm, etc.)
      vim.opt.runtimepath:append(root .. "/plugins/nvim-treesitter/runtime")
    end,
  },
  {
    "nvim-neotest/neotest",
    lazy = false,
    dependencies = {
      "nvim-neotest/nvim-nio",
      "nvim-lua/plenary.nvim",
      "antoinemadec/FixCursorHold.nvim",
      "nvim-neotest/neotest-python",
      "nvim-neotest/neotest-jest",
    },
  },
  {
    "stevearc/overseer.nvim",
    lazy = false,
    config = function()
      require("overseer").setup({
        -- Minimal setup for tests
        strategy = "jobstart",
        templates = { "builtin", "vscode" },
      })
    end,
  },
}, {
  root = root .. "/plugins",
  defaults = { lazy = true },
  install = { colorscheme = {} },
  ui = { enabled = false },
  change_detection = { enabled = false },
  checker = { enabled = false },
  rocks = { enabled = false },
  pkg = { enabled = false },
  headless = {
    process = false,
    log = false,
    task = false,
    colors = false,
  },
})

-- Setup mini.test
require("mini.test").setup()

-- Add neodap to runtimepath
vim.opt.runtimepath:prepend(vim.fn.fnamemodify(".", ":p"))

-- Add tests to package.path for helper modules
local cwd = vim.fn.getcwd()
package.path = cwd .. "/tests/?.lua;" .. package.path
package.path = cwd .. "/tests/?/init.lua;" .. package.path
