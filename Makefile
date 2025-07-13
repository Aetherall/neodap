# Neodap Development Makefile

.PHONY: help test log play

# Default target
help:
	@echo "Neodap Development Commands"
	@echo ""
	@echo "Usage:"
	@echo "  make test [TARGET] [PATTERN=pattern]  - Run tests"
	@echo "  make log [FILTER=filter]             - Show latest log with optional filter" 
	@echo "  make play                            - Run playground"
	@echo ""
	@echo "Examples:"
	@echo "  make test                                    # Run all tests in spec/"
	@echo "  make test spec/core/neodap_core.spec.lua     # Run specific test file"
	@echo "  make test PATTERN=breakpoint_hit             # Run tests matching pattern"
	@echo "  make test spec/breakpoints/ PATTERN=toggle   # Run tests in folder with pattern"
	@echo "  make log                                     # Show latest log"
	@echo "  make log FILTER=ERROR                        # Show only ERROR lines from latest log"

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

# Playground command
play:
	@echo "Starting Neodap playground..."
	nix run .#test-nvim

# Handle additional arguments for test target
%:
	@:
