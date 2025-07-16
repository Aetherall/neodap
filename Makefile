# Neodap Development Makefile

.PHONY: help test log play run clean-logs

# Default target
help:
	@echo "Neodap Development Commands"
	@echo ""
	@echo "Usage:"
	@echo "  make test [TARGET] [PATTERN=pattern]  - Run tests with lazy.nvim"
	@echo "  make log [FILTER=filter]             - Show latest log with optional filter" 
	@echo "  make play                            - Run playground with lazy.nvim"
	@echo "  make run                             - Run lazy.nvim interpreter"
	@echo "  make clean-logs                      - Clean up old numbered log files"
	@echo ""
	@echo "Examples:"
	@echo "  make test                                    # Run all tests in spec/"
	@echo "  make test spec/core/neodap_core.spec.lua     # Run specific test file"
	@echo "  make test PATTERN=breakpoint_hit             # Run tests matching pattern"
	@echo "  make test spec/breakpoints/ PATTERN=toggle   # Run tests in folder with pattern"
	@echo "  make log                                     # Show the log file"
	@echo "  make log FILTER=ERROR                        # Show only ERROR lines from log file"
	@echo "  make clean-logs                              # Clean up old numbered log files"
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

# Log command - show the single shared log file with optional filter
log:
	@LOG_FILE="log/neodap.log"; \
	if [ ! -f "$$LOG_FILE" ]; then \
		echo "No log file found: $$LOG_FILE"; \
		exit 1; \
	fi; \
	echo "Showing log: $$LOG_FILE"; \
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

# Clean up old numbered log files (keep the single neodap.log)
clean-logs:
	@echo "Cleaning up old numbered log files..."
	@rm -f log/neodap_*.log
	@echo "Done. Kept log/neodap.log"

# Handle additional arguments for test target
%:
	@:
