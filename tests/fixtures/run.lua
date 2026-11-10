-- Run one fixture suite through telemetry, then exit with its status.
-- Usage: <lua> tests/fixtures/run.lua pass|fail|hold|quit|between [file]
--
-- hold and quit write this runner's pid to <pidfile>.runner and run a suite
-- whose child and grandchild write their pids to <pidfile>. quit then ends
-- Neovim with `:qa!` during the suite. between sends SIGTERM to this runner
-- from the first suite's check; the second suite would create <file>.
local interpreter = require("tests.support.interpreter")
local telemetry = require("telemetry")

local mode, pidfile = arg[1], arg[2]
local fixture = arg[0]:gsub("run%.lua$", "process.lua")

---@param ... string
---@return string[]
local function process(...)
  local argv = interpreter.command()
  argv[#argv + 1] = fixture

  for _, value in ipairs({ ... }) do
    argv[#argv + 1] = value
  end

  return argv
end

local suites = {
  pass = { name = "pass", argv = process("exit", "0") },
  fail = { name = "fail", argv = process("exit", "3") },
}

if mode == "hold" or mode == "quit" then
  local file = assert(io.open(pidfile .. ".runner", "w"))
  file:write(string.format("%d", math.floor(interpreter.uv().os_getpid())))
  file:close()
  suites[mode] = { name = mode, argv = process("hold", pidfile) }
end

if mode == "between" then
  local uv = interpreter.uv()
  local first = { name = "first", argv = process("exit", "0") }
  first.check = function()
    uv.kill(uv.os_getpid(), "sigterm")
    uv.sleep(200)
  end
  suites.between = first
  suites.second = { name = "second", argv = process("touch", pidfile) }
end

if mode == "quit" then
  vim.defer_fn(function()
    vim.cmd("qa!")
  end, 1000)
end

local spec = {
  title = "fixture",
  mode = pidfile and "live" or "plain",
  suites = { (assert(suites[mode], mode)), suites.second },
}
telemetry.exit(telemetry.run(spec))
