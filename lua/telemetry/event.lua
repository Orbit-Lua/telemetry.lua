-- Report test events from a child process to the telemetry runner.
--
-- The runner sets TELEMETRY_EVENTS=1 in the child environment. Without it,
-- every function here writes nothing, so a spec still runs on its own.
local protocol = require("telemetry.protocol")

local M = {}

---@return boolean
function M.enabled()
  return vim.env.TELEMETRY_EVENTS == "1"
end

---@param event Telemetry.Event
function M.emit(event)
  if not M.enabled() then
    return
  end

  io.stdout:write(protocol.encode(event))
  io.stdout:flush()
end

---@param name string Full test description.
function M.start(name)
  M.emit({ event = "test_start", name = name })
end

---@param name string Full test description.
---@param status Telemetry.TestStatus
function M.finish(name, status)
  M.emit({ event = "test_end", name = name, status = status })
end

-- Runs one test body and reports it. Use it in a spec script that has its
-- own test helper instead of Plenary busted.
---@param name string Full test description.
---@param body fun()
---@return boolean ok
---@return string? err Error message with traceback.
function M.test(name, body)
  M.start(name)
  local ok, err = xpcall(body, debug.traceback)
  M.finish(name, ok and "pass" or "fail")

  return ok, err
end

return M
