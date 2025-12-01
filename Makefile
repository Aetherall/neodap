# Test runner with optional directory filter
# Usage:
#   make test              - Run all tests
#   make test neostate     - Run tests/neostate/
#   make test sdk-source   - Run tests/neodap/sdk-source/
#   make test plugins      - Run tests/neodap/plugins/

# Capture arguments after 'test'
TESTDIR := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
# Turn them into do-nothing targets
$(eval $(TESTDIR):;@:)

test:
ifeq ($(TESTDIR),)
	@echo "Running all tests..."
	@nvim --headless -u tests/helpers/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/ { minimal_init = 'tests/helpers/minimal_init.lua' }"
else ifeq ($(TESTDIR),neostate)
	@echo "Running tests in tests/neostate/..."
	@nvim --headless -u tests/helpers/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/neostate/ { minimal_init = 'tests/helpers/minimal_init.lua' }"
else ifeq ($(TESTDIR),treewindow)
	@echo "Running tests in tests/neostate/treewindow/..."
	@nvim --headless -u tests/helpers/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/neostate/treewindow/ { minimal_init = 'tests/helpers/minimal_init.lua' }"
else ifeq ($(TESTDIR),dap-client)
	@echo "Running tests in tests/dap-client/..."
	@nvim --headless -u tests/helpers/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/dap-client/ { minimal_init = 'tests/helpers/minimal_init.lua' }"
else
	@echo "Running tests in tests/neodap/$(TESTDIR)/..."
	@nvim --headless -u tests/helpers/minimal_init.lua \
		-c "PlenaryBustedDirectory tests/neodap/$(TESTDIR)/ { minimal_init = 'tests/helpers/minimal_init.lua' }"
endif

.PHONY: test
