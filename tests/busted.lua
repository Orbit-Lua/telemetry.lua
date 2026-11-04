-- Run one Plenary spec file in this process.
-- Usage: nvim --headless -u tests/minimal_init.lua -l tests/busted.lua <spec>
assert(arg[1], "provide a spec file")
require("plenary.busted").run(arg[1])
