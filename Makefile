# Neodap Development Makefile

.PHONY: help test log play

# Default target
help:
	@echo "Neodap Development Commands"
	@echo ""
	@echo "Usage:"
	@echo "  make test [TARGET] [PATTERN=pattern]  - Run tests"
	@echo "  make log [FILTER=filter]             - Show latest log with optional filter" 
	@echo "  make play                            - Run playground (original)"
	@echo "  make play-lazy                       - Run playground with lazy.nvim"
	@echo "  make lazy-interpreter                - Run lazy.nvim interpreter (for piped code)"
	@echo "  make lazy-interpreter-silent         - Run lazy.nvim interpreter silently"
	@echo ""
	@echo "Examples:"
	@echo "  make test                                    # Run all tests in spec/"
	@echo "  make test spec/core/neodap_core.spec.lua     # Run specific test file"
	@echo "  make test PATTERN=breakpoint_hit             # Run tests matching pattern"
	@echo "  make test spec/breakpoints/ PATTERN=toggle   # Run tests in folder with pattern"
	@echo "  make log                                     # Show latest log"
	@echo "  make log FILTER=ERROR                        # Show only ERROR lines from latest log"
	@echo "  echo 'print(\"Hello\")' | make lazy-interpreter  # Run code with lazy.nvim setup"
	@echo "  cat script.lua | make lazy-interpreter         # Run script with lazy.nvim setup"
	@echo "  cat script.lua | make lazy-interpreter-silent  # Run script silently (no lazy.nvim output)"
	@echo ""
	@echo "Testing with lazy.nvim:"
	@echo "  NEODAP_USE_LAZY=1 make test                 # Use lazy.nvim minit for testing"

# Test command - handles both file/folder and optional pattern
test:
ifdef PATTERN
	@echo "Running tests: $(or $(word 2,$(MAKECMDGOALS)),spec/) with pattern: $(PATTERN)"
	@nix run .#test $(or $(word 2,$(MAKECMDGOALS)),spec/) -- --pattern "$(PATTERN)"
else
	@echo "Running tests: $(or $(word 2,$(MAKECMDGOALS)),spec/)"
	@nix run .#test $(or $(word 2,$(MAKECMDGOALS)),spec/)
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

# Playground command (original)
play:
	@echo "Starting Neodap playground..."
	nix run .#test-nvim

# Enhanced playground with lazy.nvim
play-lazy:
	@echo "Starting Neodap playground with lazy.nvim..."
	nix run .#test-nvim-lazy

# Run lazy.nvim interpreter with piped code
lazy-interpreter:
	@echo "Running lazy.nvim interpreter..."
	@echo "Usage: echo 'print(\"Hello World\")' | make lazy-interpreter"
	@echo "   or: cat script.lua | make lazy-interpreter"
	@./spec/lazy-lua-interpreter.lua

# Run lazy.nvim interpreter silently (suppresses lazy.nvim setup output)
lazy-interpreter-silent:
	@./spec/lazy-lua-interpreter.lua

# Handle additional arguments for test target
%:
	@:
