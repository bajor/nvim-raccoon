.PHONY: install uninstall test test-lua lint mutation mutation-unit

PACK_DIR := $(HOME)/.config/nvim/pack/local/start
PLUGIN_NAME := nvim-raccoon
PYTHON ?= python3
MUTATION ?= 0
MUTATION_SHARDS ?= 1
MUTATION_OPERATORS ?=
MUTATION_OUTPUT_DIR ?= /tmp/raccoon-mutation-$(shell date +%Y%m%d-%H%M%S)

install:
	@echo "Installing $(PLUGIN_NAME)..."
	@mkdir -p $(PACK_DIR)
	@rm -rf $(PACK_DIR)/$(PLUGIN_NAME)
	@ln -s $(CURDIR) $(PACK_DIR)/$(PLUGIN_NAME)
	@echo "Symlinked $(CURDIR) -> $(PACK_DIR)/$(PLUGIN_NAME)"
	@echo "Done! Restart Neovim to load the plugin."

uninstall:
	@echo "Uninstalling $(PLUGIN_NAME)..."
	@rm -rf $(PACK_DIR)/$(PLUGIN_NAME)
	@echo "Done!"

test:
	@echo "Running test suite (mutation: $(if $(filter 1,$(MUTATION)),enabled,disabled))"
	@$(MAKE) test-lua
	@if [ "$(MUTATION)" = "1" ]; then \
		$(MAKE) mutation MUTATION_SHARDS="$(MUTATION_SHARDS)" MUTATION_OPERATORS="$(MUTATION_OPERATORS)"; \
	fi

test-lua:
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

lint:
	luacheck lua/ plugin/

mutation-unit:
	$(PYTHON) -m unittest discover -s tests/mutation -p 'test_*.py'

mutation:
	@echo "Running mutation suite (shards=$(MUTATION_SHARDS), operators=$(if $(strip $(MUTATION_OPERATORS)),$(MUTATION_OPERATORS),all))"
	@$(MAKE) mutation-unit
	$(PYTHON) -m scripts.mutation.run run --shards "$(MUTATION_SHARDS)" --output-dir "$(MUTATION_OUTPUT_DIR)" $(if $(strip $(MUTATION_OPERATORS)),--operators "$(MUTATION_OPERATORS)",)
