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

nvim := "nvim --headless --clean -i NONE -l"

# Run every spec group under Neovim, or the specs whose path contains the pattern
test pattern="":
    {{ nvim }} scripts/test.lua all "{{ pattern }}"

# Run the core specs on the fake host under an interpreter: nvim, luajit, lua5.1, lua5.4 or lua5.5
test-core interpreter="nvim":
    {{ nvim }} scripts/test.lua core "" {{ if interpreter == "nvim" { "" } else { interpreter } }}

# Run the host specs on real processes: nvim, or luajit or lua5.4 with luv
test-hosts interpreter="nvim":
    {{ if interpreter == "nvim" { nvim } else { interpreter } }} scripts/test.lua host

# Clone the pinned Plenary test dependency into .deps/
deps:
    nvim --headless --clean -u NONE -l scripts/deps.lua
