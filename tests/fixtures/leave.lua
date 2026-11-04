-- Start a run whose suite outlives the parent. The parent then ends during
-- the run: through `:qa!` with "quit", or through a SIGINT from the spec.
-- Usage: nvim --headless -u NONE -l tests/fixtures/leave.lua quit|signal <file>
local repository = assert(vim.env.TELEMETRY_REPOSITORY)
package.path = repository
  .. "/lua/?.lua;"
  .. repository
  .. "/lua/?/init.lua;"
  .. package.path
local telemetry = require("telemetry")

if arg[1] == "quit" then
  vim.defer_fn(function()
    vim.cmd("qa!")
  end, 500)
end

telemetry.exit(telemetry.run({
  title = "leave",
  mode = "live",
  suites = {
    {
      name = "late",
      env = { TELEMETRY_FIXTURE = arg[2] },
      argv = {
        vim.v.progpath,
        "--headless",
        "-u",
        "NONE",
        "-l",
        repository .. "/tests/fixtures/child.lua",
        "late",
      },
    },
  },
}))
