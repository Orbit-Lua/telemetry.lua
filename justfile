set shell := ["sh", "-cu"]
set windows-shell := ["cmd.exe", "/d", "/c"]

lua_paths := "lua tests scripts"

# Check formatting and lint, then run the specs
all: fmt-check lint test

# Rewrite Lua formatting
fmt:
    stylua {{ lua_paths }} --config-path=.stylua.toml

# Check formatting without rewriting
fmt-check:
    stylua --check {{ lua_paths }} --config-path=.stylua.toml

# Run Luacheck
lint:
    luacheck {{ lua_paths }}

# Run the specs, or the specs whose path contains the pattern
test pattern="":
    nvim --headless --clean -i NONE -l scripts/test.lua {{ pattern }}

# Clone the pinned Plenary test dependency into .deps/
deps:
    nvim --headless --clean -u NONE -l scripts/deps.lua
