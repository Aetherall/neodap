# Neodap Development Makefile

.PHONY: help test log play run

# Default target
help:
	@echo "Neodap Development Commands"
	@echo ""
	@echo "Usage:"
	@echo "  make test [TARGET] [PATTERN=pattern]  - Run tests with lazy.nvim"
	@echo "  make log [FILTER=filter]             - Show latest log with optional filter" 
	@echo "  make play                            - Run playground with lazy.nvim"
	@echo "  make run                             - Run lazy.nvim interpreter"
	@echo ""
	@echo "Examples:"
	@echo "  make test                                    # Run all tests in spec/"
	@echo "  make test spec/core/neodap_core.spec.lua     # Run specific test file"
	@echo "  make test PATTERN=breakpoint_hit             # Run tests matching pattern"
	@echo "  make test spec/breakpoints/ PATTERN=toggle   # Run tests in folder with pattern"
	@echo "  make log                                     # Show latest log"
	@echo "  make log FILTER=ERROR                        # Show only ERROR lines from latest log"
	@echo "  echo 'print(\"Hello\")' | make run           # Run piped code"
	@echo "  make run script.lua                          # Run lua file"
	@echo "  ./bin/interpreter.lua 'print(\"Hello\")'    # Run code string (direct)"
	@echo ""
	@echo "Debug mode:"
	@echo "  LAZY_DEBUG=1 make test                      # Show verbose testing output"
	@echo "  echo 'print(\"Hello\")' | LAZY_DEBUG=1 make run  # Show verbose interpreter output"

# Test command - uses lazy.nvim by default
test:
ifdef PATTERN
	@echo "Running tests: $(or $(word 2,$(MAKECMDGOALS)),spec/) with pattern: $(PATTERN)"
	@busted $(or $(word 2,$(MAKECMDGOALS)),spec/) -- --pattern "$(PATTERN)"
else
	@echo "Running tests: $(or $(word 2,$(MAKECMDGOALS)),spec/)"
	@busted $(or $(word 2,$(MAKECMDGOALS)),spec/)
endif

# Log command - show latest log file with optional filter
log:
	@LATEST_LOG=$$(ls -t log/neodap_*.log 2>/dev/null | head -n1); \
	if [ -z "$$LATEST_LOG" ]; then \
		echo "No log files found in log/ directory"; \
		exit 1; \
	fi; \
	echo "Showing log: $$LATEST_LOG"; \
	if [ -n "$(FILTER)" ]; then \
		echo "Filter: $(FILTER)"; \
		grep -i "$(FILTER)" "$$LATEST_LOG" || echo "No matches found for filter: $(FILTER)"; \
	else \
		cat "$$LATEST_LOG"; \
	fi

# INTERACTIVE PLAYGROUND: do not run
play:
	@echo "Starting Neodap playground..."
	@./bin/playground.lua "$(filter-out $@,$(MAKECMDGOALS))"

# INTERACTIVE PLAYGROUND: do not run
play-all:
	@echo "Starting Neodap playground with all.lua playground"
	@./bin/playground.lua lua/playgrounds/all.lua

# Run lazy.nvim interpreter with piped code, string arguments, or files
run:
	@./bin/interpreter.lua "$(filter-out $@,$(MAKECMDGOALS))"


# Handle additional arguments for test target
%:
	@:
