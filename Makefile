.PHONY: install uninstall test lint

PACK_DIR := $(HOME)/.config/nvim/pack/local/start
PLUGIN_NAME := nvim-raccoon

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
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

lint:
	luacheck lua/ plugin/
