BFCTL ?= bfctl
CONFIGS := $(wildcard drones/*/diff.txt)

# MSP codes worth saving alongside the dump — static identity/config that
# `diff all` doesn't cover (board, build, mode names ↔ permanent IDs, mode
# ranges as the FC sees them). Telemetry codes are deliberately excluded.
MSP_CODES := 1 2 3 4 5 10 34 116 117 119

.PHONY: help backup info ports diff test msp

help:
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z_-]+:.*## /{printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

test: ## Run rules/*.bats against every drones/*/diff.txt
	@command -v bats >/dev/null || { echo "bats not found. install: brew install bats-core"; exit 1; }
	@status=0; \
	for config in $(CONFIGS); do \
		echo ""; \
		echo "=== $$config ==="; \
		CONFIG="$(CURDIR)/$$config" bats rules/ || status=1; \
	done; \
	exit $$status

ports: ## List connected Betaflight FCs
	@$(BFCTL) ports

info: ## Print connected FC's metadata
	@$(BFCTL) info

backup: ## Pull MSP snapshot + diff + dump from connected FC into drones/<craft>/
	@craft=$$($(BFCTL) craft) || exit; \
	dir="drones/$$craft"; \
	mkdir -p "$$dir"; \
	$(BFCTL) msp --json $(MSP_CODES) > "$$dir/msp.json"; \
	echo "wrote $$dir/msp.json"; \
	$(BFCTL) backup -out "$$dir/diff.txt" >/dev/null; \
	echo "wrote $$dir/diff.txt"; \
	$(BFCTL) dump > "$$dir/dump.txt"; \
	echo "wrote $$dir/dump.txt"

msp: ## Save selected MSP codes to drones/<craft>/msp.json
	@craft=$$($(BFCTL) craft) || exit; \
	dir="drones/$$craft"; \
	mkdir -p "$$dir"; \
	$(BFCTL) msp --json $(MSP_CODES) > "$$dir/msp.json"; \
	echo "wrote $$dir/msp.json"

diff: ## Diff connected FC vs. its tracked file
	@craft=$$($(BFCTL) craft) || exit; \
	test -f "drones/$$craft/diff.txt" || { echo "no tracked file for $$craft"; exit 1; }; \
	$(BFCTL) diff | diff -u "drones/$$craft/diff.txt" - || true
