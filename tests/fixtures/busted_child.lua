-- Run a fixture spec with the telemetry busted adapter installed.
require("telemetry.busted").install()
require("plenary.busted").run(arg[1])
