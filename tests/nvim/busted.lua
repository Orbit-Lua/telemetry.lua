-- Run one Plenary spec file in this process and report its tests.
-- Usage: nvim --headless -u tests/nvim/minimal_init.lua -l tests/nvim/busted.lua <spec>
assert(arg[1], "provide a spec file")

local busted = require("plenary.busted")

-- A skipped test hides missing coverage, so it fails the spec.
busted.pending = function()
  error("skipped tests are not allowed", 0)
end
_G.pending = busted.pending

require("telemetry.busted").install()
busted.run(arg[1])
