# Neodap Development Makefile

.PHONY: help test log play run clean-logs

# Default target
help:
	@echo "Neodap Development Commands"
	@echo ""
	@echo "Usage:"
	@echo "  make test [TARGET] [PATTERN=pattern]  - Run tests with lazy.nvim"
	@echo "  make log [FILTER=filter]             - Show latest numbered log with optional filter" 
	@echo "  make play                            - Run playground with lazy.nvim"
	@echo "  make run                             - Run lazy.nvim interpreter"
	@echo "  make clean-logs                      - Clean up all numbered log files"
	@echo ""
	@echo "Examples:"
	@echo "  make test                                    # Run all tests in spec/"
	@echo "  make test spec/core/neodap_core.spec.lua     # Run specific test file"
	@echo "  make test PATTERN=breakpoint_hit             # Run tests matching pattern"
	@echo "  make test spec/breakpoints/ PATTERN=toggle   # Run tests in folder with pattern"
	@echo "  make log                                     # Show the latest numbered log file"
	@echo "  make log FILTER=ERROR                        # Show only ERROR lines from latest log"
	@echo "  make clean-logs                              # Clean up all numbered log files"
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

# Log command - show the latest numbered log file with optional filter
log:
	@LOG_FILE=$$(ls -t log/neodap.*.log 2>/dev/null | head -1); \
	if [ -z "$$LOG_FILE" ]; then \
		echo "No log files found in log/neodap.*.log"; \
		exit 1; \
	fi; \
	echo "Showing latest log: $$LOG_FILE"; \
	if [ -n "$(FILTER)" ]; then \
		echo "Filter: $(FILTER)"; \
		grep -i "$(FILTER)" "$$LOG_FILE" || echo "No matches found for filter: $(FILTER)"; \
	else \
		cat "$$LOG_FILE"; \
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

# Clean up all numbered log files
clean-logs:
	@echo "Cleaning up numbered log files..."
	@rm -f log/neodap.*.log
	@echo "Done. Removed all log/neodap.*.log files"

# Handle additional arguments for test target
%:
	@:
