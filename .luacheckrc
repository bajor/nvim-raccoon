-- Luacheck configuration for nvim-raccoon
std = "luajit"

globals = { "vim" }

read_globals = {
  "describe",
  "it",
  "before_each",
  "after_each",
  "assert",
  "pending",
}

include_files = {
  "lua/**/*.lua",
  "plugin/**/*.lua",
  "tests/**/*.lua",
}

-- Enable dead code detection
unused = true
unused_args = true
unused_secondaries = true

-- Allow underscore-prefixed args to be unused (Lua convention)
ignore = { "212/_.*" }
