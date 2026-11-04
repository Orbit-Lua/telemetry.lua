-- Child process for the runner spec. The first argument selects a behavior.
-- Usage: nvim --headless -u NONE -l tests/fixtures/child.lua <mode>
local repository = assert(vim.env.TELEMETRY_REPOSITORY)
package.path = repository .. "/lua/?.lua;" .. package.path
local event = require("telemetry.event")

---@type table<string, fun()>
local modes = {
  pass = function()
    io.stdout:write("before\n")
    event.test("first", function() end)
    io.stderr:write("on stderr\n")
    io.stdout:write("after")
  end,

  fail = function()
    io.stdout:write("broken output\n")
    os.exit(3)
  end,

  unfinished = function()
    event.start("never ends")
    os.exit(1)
  end,

  sleep = function()
    vim.uv.sleep(10000)
  end,

  -- Writes a file after two seconds, unless the runner stops it first.
  late = function()
    io.stdout:write("started\n")
    io.stdout:flush()
    vim.uv.sleep(2000)
    vim.fn.writefile({ "survived" }, vim.env.TELEMETRY_FIXTURE)
  end,

  environment = function()
    io.stdout:write(vim.env.TELEMETRY_FIXTURE .. "\n")
    io.stdout:write(vim.fs.basename(vim.fn.getcwd()) .. "\n")
  end,
}

assert(modes[arg[1]], "unknown mode: " .. tostring(arg[1]))()
