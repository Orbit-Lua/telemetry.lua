-- Run one suite as a child process through the host and collect its result.
--
-- The host delivers output chunks in a normal context. Each stream has its
-- own line splitter, so a partial stderr line never swallows a stdout event.
local protocol = require("telemetry.protocol")
local text = require("telemetry.text")

local M = {}

M.default_timeout = 120000

---@class Telemetry.Observer
---@field event fun(event: Telemetry.Event) Receives each child event.
---@field poll fun() Runs at each wait interval.
---@field cancelled? fun(): boolean Returns true to stop the run.

---@class Telemetry.Capture
---@field lines string[] Output lines in arrival order.
---@field events Telemetry.Event[] Events not yet given to the observer.
---@field started table<string, true> Tests that have no end event yet.
---@field tests Telemetry.TestResult[]

---@param capture Telemetry.Capture
---@return Telemetry.LineSplitter
local function reader(capture)
  return protocol.splitter(function(line)
    local event = protocol.decode(line)

    if event then
      capture.events[#capture.events + 1] = event
    else
      capture.lines[#capture.lines + 1] = line
    end
  end)
end

---@param capture Telemetry.Capture
---@param observer Telemetry.Observer
local function drain(capture, observer)
  local events = capture.events
  capture.events = {}

  for _, event in ipairs(events) do
    -- A name comes from the child. An escape sequence or a newline in it
    -- would break the live view's cursor movement.
    event.name = text.strip(event.name):gsub("%c", " ")

    if event.event == "test_start" then
      capture.started[event.name] = true
    else
      capture.started[event.name] = nil
      capture.tests[#capture.tests + 1] =
        { name = event.name, status = event.status }
    end

    observer.event(event)
  end
end

-- A test with a start event and no end event stopped before it finished,
-- for example through an error in a `before_each` hook.
---@param capture Telemetry.Capture
---@param observer Telemetry.Observer
local function close_started(capture, observer)
  local names = {}
  for name in pairs(capture.started) do
    names[#names + 1] = name
  end
  table.sort(names)

  for _, name in ipairs(names) do
    capture.tests[#capture.tests + 1] = { name = name, status = "error" }
    observer.event({ event = "test_end", name = name, status = "error" })
  end

  capture.started = {}
end

---@param suite Telemetry.Suite
---@return Telemetry.ProcessRequest
local function request(suite)
  local argv = {}
  for index, item in ipairs(suite.argv) do
    argv[index] = tostring(item)
  end

  local env = {}
  for name, value in pairs(suite.env or {}) do
    env[name] = tostring(value)
  end
  env.TELEMETRY_EVENTS = "1"

  return {
    argv = argv,
    cwd = suite.cwd,
    env = env,
    timeout = suite.timeout or M.default_timeout,
  }
end

---@param suite Telemetry.Suite
---@param exit Telemetry.ProcessExit
---@param result Telemetry.SuiteResult
local function classify(suite, exit, result)
  if exit.timed_out then
    local timeout = suite.timeout or M.default_timeout
    result.status = "timeout"
    result.message = string.format("timed out after %d ms", timeout)
  elseif exit.interrupted then
    result.status = "fail"
    result.message = "interrupted"
  elseif result.status == "pass" and suite.check then
    result.message = suite.check(result)
    result.status = result.message and "fail" or "pass"
  end
end

---@param suite Telemetry.Suite
---@param observer Telemetry.Observer
---@param host Telemetry.Host
---@return Telemetry.SuiteResult
---@return boolean interrupted True when Ctrl-C or the observer stopped the suite.
function M.run(suite, observer, host)
  ---@type Telemetry.Capture
  local capture = { lines = {}, events = {}, started = {}, tests = {} }
  local streams = { stdout = reader(capture), stderr = reader(capture) }
  local started = host.clock()

  local exit = host.execute(request(suite), {
    output = function(stream, chunk)
      streams[stream].feed(chunk)
    end,
    poll = function()
      drain(capture, observer)
      observer.poll()
      return observer.cancelled ~= nil and observer.cancelled()
    end,
  })

  streams.stdout.flush()
  streams.stderr.flush()
  if exit.error then
    capture.lines[#capture.lines + 1] = exit.error
  end

  drain(capture, observer)
  close_started(capture, observer)

  ---@type Telemetry.SuiteResult
  local result = {
    name = suite.name,
    -- libuv reports code 0 for a process that a signal ended.
    status = (exit.code == 0 and exit.signal == 0) and "pass" or "fail",
    code = exit.code,
    signal = exit.signal,
    duration = host.clock() - started,
    output = table.concat(capture.lines, "\n"),
    tests = capture.tests,
  }

  classify(suite, exit, result)
  return result, exit.interrupted
end

return M
