BFCTL ?= bfctl

.PHONY: help backup info ports diff

help:
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z_-]+:.*## /{printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

ports: ## List connected Betaflight FCs
	@$(BFCTL) ports

info: ## Print connected FC's metadata
	@$(BFCTL) info

backup: ## Pull config from connected FC into <craft>.txt
	@craft=$$($(BFCTL) info -json | jq -r '.craft_name' | tr '[:upper:]' '[:lower:]'); \
	test -n "$$craft" -a "$$craft" != "null" || { echo "no craft name found"; exit 1; }; \
	$(BFCTL) dump > "$$craft.txt"; \
	echo "wrote $$craft.txt"

diff: ## Show diff between connected FC and its tracked file
	@craft=$$($(BFCTL) info -json | jq -r '.craft_name' | tr '[:upper:]' '[:lower:]'); \
	test -f "$$craft.txt" || { echo "no tracked file for $$craft"; exit 1; }; \
	$(BFCTL) dump | diff -u "$$craft.txt" - || true
