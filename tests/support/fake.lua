-- Fakes for the core specs: a recording terminal, a scripted host and
-- suite results.
local M = {}

---@class Telemetry.FakeTerminal: Telemetry.Terminal
---@field writes string[] Every write, in order.
---@field text fun(): string All writes joined.

---@param fields? { width?: integer, tty?: boolean, color?: boolean }
---@return Telemetry.FakeTerminal
function M.terminal(fields)
  fields = fields or {}
  local writes = {}

  return {
    writes = writes,
    text = function()
      return table.concat(writes)
    end,
    write = function(text)
      writes[#writes + 1] = text
    end,
    width = function()
      return fields.width or 40
    end,
    tty = fields.tty ~= false,
    color = fields.color ~= false,
  }
end

-- A fake process: it feeds the sink and returns its exit fields.
---@alias Telemetry.FakeScript fun(request: Telemetry.ProcessRequest, sink: Telemetry.ProcessSink, host: table): table?

---@class Telemetry.FakeHost: Telemetry.Host
---@field env table<string, string> Variables that getenv returns.
---@field now number Seconds that clock returns.
---@field requests Telemetry.ProcessRequest[] Every execute request.
---@field scripts table<string, Telemetry.FakeScript> Behavior by argv[1].
---@field guarded integer Active guards.
---@field stopped boolean What interrupted returns; a script sets it.

-- A host whose processes are Lua functions, selected by argv[1]. A script
-- returns an exit, or nil for a zero exit.
---@param scripts table<string, Telemetry.FakeScript>
---@param env? table<string, string>
---@return Telemetry.FakeHost
function M.host(scripts, env)
  local host
  host = {
    name = "nvim",
    env = env or {},
    now = 0,
    requests = {},
    scripts = scripts,
    guarded = 0,
    getenv = function(name)
      return host.env[name]
    end,
    clock = function()
      return host.now
    end,
    terminal = function()
      return M.terminal()
    end,
    execute = function(request, sink)
      host.requests[#host.requests + 1] = request
      local script = assert(host.scripts[request.argv[1]], request.argv[1])
      local exit = script(request, sink, host) or {}
      exit.code = exit.code or 0
      exit.signal = exit.signal or 0
      exit.timed_out = exit.timed_out == true
      exit.interrupted = exit.interrupted == true
      return exit
    end,
    stopped = false,
    interrupted = function()
      return host.stopped
    end,
    guard = function()
      host.guarded = host.guarded + 1
      return function()
        host.guarded = host.guarded - 1
      end
    end,
  }

  return host
end

---@param fields table<string, any> Fields that replace the passing defaults.
---@return Telemetry.SuiteResult
function M.suite_result(fields)
  local result = {
    name = "tests/example_spec.lua",
    status = "pass",
    code = 0,
    signal = 0,
    duration = 1.25,
    output = "",
    tests = {},
  }

  for key, value in pairs(fields) do
    result[key] = value
  end

  return result
end

return M
