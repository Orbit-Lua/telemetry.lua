-- Run one suite as a child process and collect its result.
--
-- The process callbacks run in a fast event context. They only split output
-- into lines and queue events. The wait loop drains the queue in the main
-- context, so observers may call any Neovim function.
local protocol = require("telemetry.protocol")

local M = {}

M.default_timeout = 120000

-- Interval of the wait loop in milliseconds. It bounds the redraw rate.
M.poll_interval = 50

---@class Telemetry.Observer
---@field event fun(event: Telemetry.Event) Receives each child event.
---@field poll fun() Runs at each wait interval.
---@field cancelled? fun(): boolean Returns true to stop the run, as after Ctrl-C.

---@class Telemetry.Capture
---@field lines string[] Output lines in arrival order.
---@field events Telemetry.Event[] Events not yet given to the observer.
---@field started table<string, true> Tests that have no end event yet.
---@field tests Telemetry.TestResult[]

---@class Telemetry.Wait
---@field completed? vim.SystemCompleted
---@field timed_out boolean
---@field interrupted boolean

---@param capture Telemetry.Capture
---@return fun(err?: string, data?: string)
local function reader(capture)
  local splitter = protocol.splitter(function(line)
    local event = protocol.decode(line)

    if event then
      capture.events[#capture.events + 1] = event
    else
      capture.lines[#capture.lines + 1] = line
    end
  end)

  return function(_, data)
    if data then
      splitter.feed(data)
    else
      splitter.flush()
    end
  end
end

---@param capture Telemetry.Capture
---@param observer Telemetry.Observer
local function drain(capture, observer)
  local events = capture.events
  capture.events = {}

  for _, event in ipairs(events) do
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
  local names = vim.tbl_keys(capture.started)
  table.sort(names)

  for _, name in ipairs(names) do
    capture.tests[#capture.tests + 1] = { name = name, status = "error" }
    observer.event({ event = "test_end", name = name, status = "error" })
  end

  capture.started = {}
end

---@param suite Telemetry.Suite
---@param capture Telemetry.Capture
---@param on_exit fun(out: vim.SystemCompleted)
---@return vim.SystemObj
local function spawn(suite, capture, on_exit)
  local env =
    vim.tbl_extend("force", suite.env or {}, { TELEMETRY_EVENTS = "1" })

  return vim.system(suite.argv, {
    cwd = suite.cwd,
    env = env,
    stdout = reader(capture),
    stderr = reader(capture),
  }, on_exit)
end

-- Waits for the process and serves the observer at each interval. Stops the
-- process on a timeout or on Ctrl-C.
---@param process vim.SystemObj
---@param wait Telemetry.Wait
---@param timeout integer
---@param serve fun(): boolean Serves the observer; returns true to cancel.
local function await(process, wait, timeout, serve)
  local deadline = vim.uv.now() + timeout

  local function completed()
    return wait.completed ~= nil
  end

  while not wait.completed do
    local _, status = vim.wait(M.poll_interval, completed)
    local cancelled = serve()

    if status == -2 or cancelled then
      wait.interrupted = true
    elseif vim.uv.now() >= deadline then
      wait.timed_out = true
    end

    if not wait.completed and (wait.interrupted or wait.timed_out) then
      process:kill("sigkill")
      vim.wait(5000, completed)
      return
    end
  end
end

---@param suite Telemetry.Suite
---@param wait Telemetry.Wait
---@param result Telemetry.SuiteResult
local function classify(suite, wait, result)
  if wait.timed_out then
    local timeout = suite.timeout or M.default_timeout
    result.status = "timeout"
    result.message = string.format("timed out after %d ms", timeout)
  elseif wait.interrupted then
    result.status = "fail"
    result.message = "interrupted"
  elseif result.status == "pass" and suite.check then
    result.message = suite.check(result)
    result.status = result.message and "fail" or "pass"
  end
end

---@param suite Telemetry.Suite
---@param observer Telemetry.Observer
---@return Telemetry.SuiteResult
---@return boolean interrupted True when the user pressed Ctrl-C.
function M.run(suite, observer)
  ---@type Telemetry.Capture
  local capture = { lines = {}, events = {}, started = {}, tests = {} }
  ---@type Telemetry.Wait
  local wait = { timed_out = false, interrupted = false }
  local started = vim.uv.hrtime()

  local ok, process = pcall(spawn, suite, capture, function(out)
    wait.completed = out
  end)

  if ok then
    await(process, wait, suite.timeout or M.default_timeout, function()
      drain(capture, observer)
      observer.poll()
      return observer.cancelled ~= nil and observer.cancelled()
    end)
  else
    capture.lines[1] = tostring(process)
  end

  drain(capture, observer)
  close_started(capture, observer)

  local completed = wait.completed or { code = -1, signal = 0 }

  ---@type Telemetry.SuiteResult
  local result = {
    name = suite.name,
    status = completed.code == 0 and "pass" or "fail",
    code = completed.code,
    signal = completed.signal,
    duration = (vim.uv.hrtime() - started) / 1e9,
    output = table.concat(capture.lines, "\n"),
    tests = capture.tests,
  }

  classify(suite, wait, result)
  return result, wait.interrupted
end

return M
