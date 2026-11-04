-- Run one fixture suite through telemetry and exit with its status.
-- Usage: nvim --headless -u NONE -l tests/fixtures/exit.lua <child mode>
local repository = assert(vim.env.TELEMETRY_REPOSITORY)
package.path = repository
  .. "/lua/?.lua;"
  .. repository
  .. "/lua/?/init.lua;"
  .. package.path
local telemetry = require("telemetry")

telemetry.exit(telemetry.run({
  title = "fixture",
  mode = "plain",
  suites = {
    {
      name = arg[1],
      argv = {
        vim.v.progpath,
        "--headless",
        "-u",
        "NONE",
        "-l",
        repository .. "/tests/fixtures/child.lua",
        arg[1],
      },
    },
  },
}))
