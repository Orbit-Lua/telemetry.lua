local fake = require("tests.support.fake")
local protocol = require("telemetry.protocol")
local runner = require("telemetry.runner")
local t = require("tests.support.harness")

---@return Telemetry.Observer observer
---@return Telemetry.Event[] events
local function recorder()
  local events = {}
  local observer = {
    event = function(event)
      events[#events + 1] = event
    end,
    poll = function() end,
  }

  return observer, events
end

---@param name string
---@param fields? table<string, any>
---@return Telemetry.Suite
local function suite(name, fields)
  local result = { name = name, argv = { name, "--flag" } }
  for key, value in pairs(fields or {}) do
    result[key] = value
  end
  return result
end

local host = fake.host({
  -- A partial stderr line, an event line on stdout, then the stderr rest.
  pass = function(_, sink)
    sink.output("stdout", "before\n")
    sink.output("stderr", "err-")
    sink.output(
      "stdout",
      protocol.encode({ event = "test_start", name = "first" })
    )
    sink.poll()
    sink.output(
      "stdout",
      protocol.encode({ event = "test_end", name = "first", status = "pass" })
    )
    sink.output("stderr", "part\n")
    sink.output("stdout", "after")
  end,
  fail = function(_, sink)
    sink.output("stdout", "broken output\n")
    return { code = 3 }
  end,
  unfinished = function(_, sink)
    sink.output(
      "stdout",
      protocol.encode({ event = "test_start", name = "never ends" })
    )
    return { code = 1 }
  end,
  slow = function(_, _, self)
    self.now = self.now + 2
    return { code = -1, signal = 15, timed_out = true }
  end,
  cancel = function(_, sink)
    return { code = -1, interrupted = sink.poll() }
  end,
  unsafe = function(_, sink)
    sink.output(
      "stdout",
      protocol.encode({
        event = "test_end",
        name = "a\nb\27[31mc",
        status = "pass",
      })
    )
  end,
  crashed = function()
    return { code = 0, signal = 11 }
  end,
  missing = function()
    return { code = -1, error = "cannot start missing: ENOENT" }
  end,
})

t.test("runner separates events from output on each stream", function()
  local observer, events = recorder()
  local result = runner.run(suite("pass"), observer, host)

  t.equal("pass", result.status)
  t.same({ { name = "first", status = "pass" } }, result.tests)
  t.equal(2, #events)
  t.equal("before\nerr-part\nafter", result.output)
end)

t.test("runner passes argv, cwd, env and the timeout to the host", function()
  runner.run(
    suite("pass", { cwd = "/work dir", env = { A = "1" }, timeout = 300 }),
    recorder(),
    host
  )
  local request = host.requests[#host.requests]

  t.same({ "pass", "--flag" }, request.argv)
  t.equal("/work dir", request.cwd)
  t.same({ A = "1", TELEMETRY_EVENTS = "1" }, request.env)
  t.equal(300, request.timeout)
  runner.run(suite("pass"), recorder(), host)
  t.equal(runner.default_timeout, host.requests[#host.requests].timeout)
end)

t.test("runner fails a nonzero exit and keeps its output", function()
  local result = runner.run(suite("fail"), recorder(), host)

  t.equal("fail", result.status)
  t.equal(3, result.code)
  t.equal("broken output", result.output)
end)

t.test("runner reports a started test without an end as an error", function()
  local observer, events = recorder()
  local result = runner.run(suite("unfinished"), observer, host)

  t.same({ { name = "never ends", status = "error" } }, result.tests)
  t.same(
    { event = "test_end", name = "never ends", status = "error" },
    events[#events]
  )
end)

t.test(
  "runner classifies a timeout and measures with the host clock",
  function()
    local result =
      runner.run(suite("slow", { timeout = 300 }), recorder(), host)

    t.equal("timeout", result.status)
    t.equal("timed out after 300 ms", result.message)
    t.equal(2, result.duration)
    t.equal(15, result.signal)
  end
)

t.test("runner cancels through the observer", function()
  local observer = recorder()
  observer.cancelled = function()
    return true
  end
  local result, interrupted = runner.run(suite("cancel"), observer, host)

  t.equal(true, interrupted)
  t.equal("fail", result.status)
  t.equal("interrupted", result.message)
end)

t.test("runner runs check after a zero exit only", function()
  local seen
  local result = runner.run(
    suite("pass", {
      check = function(completed)
        seen = completed.output
        return "check rejected the suite"
      end,
    }),
    recorder(),
    host
  )

  t.equal("before\nerr-part\nafter", seen)
  t.equal("fail", result.status)
  t.equal("check rejected the suite", result.message)
end)

t.test("runner removes control characters from child test names", function()
  local result = runner.run(suite("unsafe"), recorder(), host)

  t.same({ { name = "a bc", status = "pass" } }, result.tests)
end)

t.test("runner fails a suite that a signal ended", function()
  local result = runner.run(suite("crashed"), recorder(), host)

  t.equal("fail", result.status)
  t.equal(11, result.signal)
end)

t.test("runner fails a suite whose command cannot start", function()
  local result = runner.run(suite("missing"), recorder(), host)

  t.equal("fail", result.status)
  t.equal(-1, result.code)
  t.contains(result.output, "missing")
end)

t.finish()
