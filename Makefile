BFCTL ?= bfctl
PORT_ARG := $(if $(PORT),-port $(PORT),)

.PHONY: help backup info ports diff

help:
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z_-]+:.*## /{printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

ports: ## List connected Betaflight FCs
	@$(BFCTL) ports

info: ## Print connected FC's metadata (PORT=... optional)
	@$(BFCTL) info $(PORT_ARG)

backup: ## Pull config into <craft>.txt (PORT=... optional)
	@dump=$$($(BFCTL) dump $(PORT_ARG)); \
	craft=$$(echo "$$dump" | awk -F': *' '/^# name:/ { print tolower($$2); exit }'); \
	test -n "$$craft" || { echo "no craft name found in dump (set 'name' in Configurator)"; exit 1; }; \
	echo "$$dump" > "$$craft.txt"; \
	echo "wrote $$craft.txt"

diff: ## Diff connected FC vs. its tracked file (PORT=... optional)
	@dump=$$($(BFCTL) dump $(PORT_ARG)); \
	craft=$$(echo "$$dump" | awk -F': *' '/^# name:/ { print tolower($$2); exit }'); \
	test -f "$$craft.txt" || { echo "no tracked file for $$craft"; exit 1; }; \
	echo "$$dump" | diff -u "$$craft.txt" - || true
