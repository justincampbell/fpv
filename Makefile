BFCTL ?= bfctl
CONFIGS := $(wildcard drones/*/diff.txt)

# MSP codes worth saving alongside the dump — static identity/config that
# `diff all` doesn't cover (board, build, mode names ↔ permanent IDs, mode
# ranges as the FC sees them). Telemetry codes are deliberately excluded.
MSP_CODES := 1 2 3 4 5 10 34 116 117 119

# Prerequisites are serialized: MSP must precede any CLI-mode op (bfctl
# diff/dump leave the FC in CLI mode, blocking subsequent MSP queries).
.NOTPARALLEL:

.PHONY: help test switches \
        fc-ports fc-info fc-diff fc-msp fc-dump fc-diff-save fc-backup \
        radio-backup t8l-backup

help:
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z0-9_-]+:.*## /{printf "  %-14s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

switches: ## Print cross-drone switch table (drones × switches) as markdown
	@bin/switches

test: ## Run rules/*.bats against every drones/*/diff.txt
	@command -v bats >/dev/null || { echo "bats not found. install: brew install bats-core"; exit 1; }
	@status=0; \
	for config in $(CONFIGS); do \
		echo ""; \
		echo "=== $$config ==="; \
		CONFIG="$(CURDIR)/$$config" bats rules/ || status=1; \
	done; \
	exit $$status

# === FC (Betaflight flight controller, over USB) ===

fc-ports: ## List connected Betaflight FCs
	@$(BFCTL) ports

fc-info: ## Print connected FC's metadata
	@$(BFCTL) info

fc-diff: ## Diff connected FC vs. its tracked diff.txt
	@craft=$$($(BFCTL) craft) || exit; \
	test -f "drones/$$craft/diff.txt" || { echo "no tracked file for $$craft"; exit 1; }; \
	$(BFCTL) diff | diff -u "drones/$$craft/diff.txt" - || true

fc-msp: ## Write drones/<craft>/msp.json from connected FC
	@craft=$$($(BFCTL) craft) || exit; \
	dir="drones/$$craft"; \
	mkdir -p "$$dir"; \
	$(BFCTL) msp --json $(MSP_CODES) > "$$dir/msp.json"; \
	echo "wrote $$dir/msp.json"

fc-diff-save: ## Write drones/<craft>/diff.txt from connected FC
	@craft=$$($(BFCTL) craft) || exit; \
	dir="drones/$$craft"; \
	mkdir -p "$$dir"; \
	$(BFCTL) backup -out "$$dir/diff.txt" >/dev/null; \
	echo "wrote $$dir/diff.txt"

fc-dump: ## Write drones/<craft>/dump.txt from connected FC
	@craft=$$($(BFCTL) craft) || exit; \
	dir="drones/$$craft"; \
	mkdir -p "$$dir"; \
	$(BFCTL) dump > "$$dir/dump.txt"; \
	echo "wrote $$dir/dump.txt"

fc-backup: fc-msp fc-dump fc-diff-save ## Pull MSP + dump + diff from connected FC

# === Radio (EdgeTX transmitter, over USB mass storage) ===

radio-backup: ## Copy radio configs from mounted SD card to radios/<name>/
	@set -e; \
	sd=""; for v in /Volumes/*; do \
		test -f "$$v/edgetx.sdcard.target" && sd="$$v" && break; \
	done; \
	test -n "$$sd" || { echo "no EdgeTX SD card mounted under /Volumes/"; exit 1; }; \
	name=$$(awk '/^board:/{print $$2; exit}' "$$sd/RADIO/radio.yml" | tr -d '\r'); \
	test -n "$$name" || { echo "could not derive radio name from $$sd/RADIO/radio.yml"; exit 1; }; \
	dir="radios/$$name"; \
	mkdir -p "$$dir"; \
	rsync -rt --delete --exclude='._*' --exclude='README.txt' \
		"$$sd/MODELS/" "$$dir/MODELS/"; \
	rsync -rt --delete --exclude='._*' --exclude='README.txt' \
		"$$sd/RADIO/" "$$dir/RADIO/"; \
	install -m 644 "$$sd/edgetx.sdcard.target" "$$sd/edgetx.sdcard.version" "$$dir/"; \
	find "$$dir/MODELS" "$$dir/RADIO" -type d -exec chmod 755 {} +; \
	find "$$dir/MODELS" "$$dir/RADIO" -type f -exec chmod 644 {} +; \
	echo "wrote $$dir/"

t8l-backup: ## Pull T8L config over USB (radio must be in M+power management mode)
	@command -v rmt8l >/dev/null || { \
		echo "rmt8l not installed. See https://github.com/justincampbell/rmt8l"; exit 1; }
	@rmt8l backup --out-dir radios/t8l
