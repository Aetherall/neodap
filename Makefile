.PHONY: test test-seq test-file test-file-seq test-unit test-integration test-plugins test-dap-lua test-update-screenshots check clean

# Run ALL tests (single command runs everything)
# Test structure:
#   tests/unit/           - Unit tests (no debug adapter needed)
#   tests/integration/    - Integration tests (Python + JavaScript adapters)
#     core/               - Session, Thread, Frame entity tests
#     url/                - URL query and URI resolution tests
#     context/            - Context and focus tests
#     plugins/            - Plugin tests (auto_context, dap_jump, etc.)
#     multi_session/      - Multi-session behavior tests
#   tests/neodap/         - Additional plugin tests
#   tests/dap-lua/        - Transport layer tests
test:
	NEODAP_TEST_TIMEOUT=0 nvim --headless -u tests/init.lua -c "luafile tests/parallel.lua"

# Sequential test runner (original, slower)
test-seq:
	nvim --headless -u tests/init.lua -c "lua MiniTest.run({ collect = { find_files = function() return vim.tbl_filter(function(f) return not f:match('init.lua') and not f:match('helpers/') and not f:match('parallel.lua') end, vim.fn.globpath('tests', '**/*.lua', false, true)) end } })"

# Run single test file (parallel)
test-file:
	NEODAP_TEST_TIMEOUT=0 nvim --headless -u tests/init.lua -c "luafile tests/parallel.lua" -- -f $(FILE)

# Run single test file (sequential)
test-file-seq:
	nvim --headless -u tests/init.lua -c "lua MiniTest.run_file('$(FILE)')"

# Run only unit tests (fast, no debug adapter needed)
test-unit:
	NEODAP_TEST_TIMEOUT=0 nvim --headless -u tests/init.lua -c "luafile tests/parallel.lua" -- -f unit/

# Run only dap-lua transport tests
test-dap-lua:
	nvim --headless -u tests/init.lua -c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.globpath('tests/dap-lua', '**/*.lua', false, true) end } })"

# Run only integration tests (with all adapters)
test-integration:
	nvim --headless -u tests/init.lua -c "lua MiniTest.run({ collect = { find_files = function() return vim.fn.globpath('tests/neodap/integration', '**/*.lua', false, true) end } })"

# Run only plugin tests
test-plugins:
	nvim --headless -u tests/init.lua -c "lua MiniTest.run({ collect = { find_files = function() return vim.tbl_filter(function(f) return not f:match('/dap/') end, vim.fn.globpath('tests/neodap/plugins', '**/*.lua', false, true)) end } })"

# Update reference screenshots (delete and re-run)
test-update-screenshots:
	rm -rf tests/screenshots/*
	$(MAKE) test-plugins

check:
	emmylua_check --ignore ".tests/**" .

clean:
	rm -rf .tests/
