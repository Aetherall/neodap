# Neodap Development Makefile

.PHONY: help test log play run clean-logs

# Default target
help:
	@echo "Neodap Development Commands"
	@echo ""
	@echo "Usage:"
	@echo "  make test [TARGET] [PATTERN=pattern]  - Run tests with lazy.nvim (dirs run each file separately)"
	@echo "  make log [FILTER=filter]             - Show latest numbered log with optional filter (always shows WARN/ERROR/FAIL/CRITICAL)" 
	@echo "  make play                            - Run playground with lazy.nvim"
	@echo "  make run                             - Run lazy.nvim interpreter"
	@echo "  make clean-logs                      - Clean up all numbered log files"
	@echo ""
	@echo "Examples:"
	@echo "  make test                                    # Run all tests in spec/ (each file separately)"
	@echo "  make test spec/core/neodap_core.spec.lua     # Run specific test file"  
	@echo "  make test spec/plugins/                      # Run each plugin spec in separate process"
	@echo "  make test PATTERN=breakpoint_hit             # Run tests matching pattern"
	@echo "  make test spec/breakpoints/ PATTERN=toggle   # Run tests in folder with pattern"
	@echo "  make log                                     # Show the latest numbered log file"
	@echo "  make log FILTER=ERROR                        # Show only ERROR lines + all WARN/ERROR/FAIL/CRITICAL from latest log"
	@echo "  make clean-logs                              # Clean up all numbered log files"
	@echo "  echo 'print(\"Hello\")' | make run           # Run piped code"
	@echo "  make run script.lua                          # Run lua file"
	@echo "  ./bin/interpreter.lua 'print(\"Hello\")'    # Run code string (direct)"
	@echo ""
	@echo "Debug mode:"
	@echo "  LAZY_DEBUG=1 make test                      # Show verbose testing output"
	@echo "  echo 'print(\"Hello\")' | LAZY_DEBUG=1 make run  # Show verbose interpreter output"

# Test command - uses nix busted
test:
	@TARGET="$(or $(word 2,$(MAKECMDGOALS)),spec/)"; \
	if [ -d "$$TARGET" ]; then \
		SPEC_FILES=$$(find "$$TARGET" -name "*.spec.lua" | sort); \
		SPEC_COUNT=$$(echo "$$SPEC_FILES" | wc -l); \
		if [ $$SPEC_COUNT -gt 1 ]; then \
			echo "Found $$SPEC_COUNT spec files in $$TARGET - running each in separate process:"; \
			TOTAL_SUCCESS=0; TOTAL_FAILURE=0; TOTAL_ERROR=0; TOTAL_PENDING=0; \
			for SPEC_FILE in $$SPEC_FILES; do \
				echo ""; \
				echo "========================================"; \
				echo "Running: $$SPEC_FILE"; \
				echo "========================================"; \
				if [ -n "$(PATTERN)" ]; then \
					nix develop --command busted "$$SPEC_FILE" -- --pattern "$(PATTERN)"; \
				else \
					nix develop --command busted "$$SPEC_FILE"; \
				fi; \
				if [ $$? -eq 0 ]; then \
					echo "✓ $$SPEC_FILE - PASSED"; \
				else \
					echo "✗ $$SPEC_FILE - FAILED"; \
				fi; \
			done; \
			echo ""; \
			echo "========================================"; \
			echo "Sequential test execution complete"; \
			echo "========================================"; \
		else \
			if [ -n "$(PATTERN)" ]; then \
				echo "Running tests: $$TARGET with pattern: $(PATTERN)"; \
				nix develop --command busted "$$TARGET" -- --pattern "$(PATTERN)"; \
			else \
				echo "Running tests: $$TARGET"; \
				nix develop --command busted "$$TARGET"; \
			fi; \
		fi; \
	else \
		if [ -n "$(PATTERN)" ]; then \
			echo "Running tests: $$TARGET with pattern: $(PATTERN)"; \
			nix develop --command busted "$$TARGET" -- --pattern "$(PATTERN)"; \
		else \
			echo "Running tests: $$TARGET"; \
			nix develop --command busted "$$TARGET"; \
		fi; \
	fi

# Log command - show the latest numbered log file with optional filter
# When filtering, always include WARN, ERROR, FAIL, and CRITICAL logs
log:
	@LOG_FILE=$$(ls -t log/neodap.*.log 2>/dev/null | head -1); \
	if [ -z "$$LOG_FILE" ]; then \
		echo "No log files found in log/neodap.*.log"; \
		exit 1; \
	fi; \
	echo "Showing latest log: $$LOG_FILE"; \
	if [ -n "$(FILTER)" ]; then \
		echo "Filter: $(FILTER) (always includes WARN/ERROR/FAIL/CRITICAL)"; \
		(grep -i "$(FILTER)" "$$LOG_FILE"; grep -E '\[(WARN|ERROR|FAIL|CRITICAL)\]' "$$LOG_FILE") | sort -u || echo "No matches found for filter: $(FILTER)"; \
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
