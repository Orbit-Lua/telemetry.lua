-- The core runs under Lua 5.1 to 5.5 and LuaJIT, so only the shared globals
-- are allowed. `unpack` is the Lua 5.1 fallback of `table.unpack`.
std = "min"
read_globals = { "unpack", table = { fields = { "unpack" } } }
cache = true
codes = true
exclude_files = { ".deps/**", ".plans/**" }

files["scripts/**"] = { read_globals = { "arg" } }
files["tests/**"] = { read_globals = { "arg" } }

-- Only the nvim host and the Neovim test glue may use the vim global.
files["lua/telemetry/host/nvim.lua"] = { read_globals = { "vim" } }
files["scripts/deps.lua"] = { read_globals = { "vim" } }
files["tests/fixtures/run.lua"] = { read_globals = { "arg", "vim" } }
files["tests/nvim/**"] = {
  globals = { "vim" },
  read_globals = { "arg", "assert", "describe", "it", "before_each", "after_each" },
}
