.PHONY: devinstall test lint

PLUGGED_DIR := $(HOME)/.vim/plugged
PLUGIN_NAME := nvim-raccoon

devinstall:
	@echo "Installing $(PLUGIN_NAME) for development..."
	@mkdir -p $(PLUGGED_DIR)
	@rm -f $(PLUGGED_DIR)/$(PLUGIN_NAME)
	@ln -s $(CURDIR) $(PLUGGED_DIR)/$(PLUGIN_NAME)
	@echo "Symlinked $(CURDIR) -> $(PLUGGED_DIR)/$(PLUGIN_NAME)"
	@echo "Done! Restart Neovim to load the plugin."

test:
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/ {minimal_init = 'tests/minimal_init.lua'}"

lint:
	luacheck lua/ plugin/
