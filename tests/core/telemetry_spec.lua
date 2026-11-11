local fake = require("tests.support.fake")
local live = require("telemetry.view.live")
local t = require("tests.support.harness")

-- Replace host selection with a fake host for these specs.
local selected
package.loaded["telemetry.host"] = {
  select = function(choice)
    selected = choice
    return assert(fake.current)
  end,
}
local telemetry = require("telemetry")

---@param scripts table<string, Telemetry.FakeScript>
---@param env? table<string, string>
---@return Telemetry.FakeHost
local function use_host(scripts, env)
  fake.current = fake.host(scripts, env)
  return fake.current
end

local quiet = { ok = function() end }

t.test("run returns the counts, the duration and the host name", function()
  local host = use_host({
    ok = function(_, _, self)
      self.now = self.now + 1
    end,
    bad = function()
      return { code = 1 }
    end,
  })
  local out = fake.terminal({ tty = false })
  local result = telemetry.run({
    title = "test",
    host = "nvim",
    terminal = out,
    suites = {
      { name = "one", argv = { "ok" } },
      { name = "two", argv = { "bad" } },
    },
  })

  t.equal(1, result.passed)
  t.equal(1, result.failed)
  t.equal(1, result.duration)
  t.equal("nvim", result.host)
  t.equal(false, result.interrupted)
  t.equal("nvim", selected)
  t.equal(0, host.guarded, "the guard is removed after the run")
  t.contains(out.text(), "1 of 2 test suites passed")
end)

t.test("run stops after an interrupted suite", function()
  use_host({
    stop = function(_, sink)
      sink.output("stderr", "interrupted diagnostic\n")
      return { code = -1, interrupted = true }
    end,
    ok = quiet.ok,
  })
  local out = fake.terminal({ color = false })
  local result = telemetry.run({
    title = "test",
    mode = "live",
    terminal = out,
    suites = {
      { name = "one", argv = { "stop" } },
      { name = "two", argv = { "ok" } },
    },
  })

  t.equal(true, result.interrupted)
  t.equal(1, #result.suites)
  t.equal(1, select(2, out.text():gsub("interrupted diagnostic", "")))
  t.contains(out.text(), "interrupted diagnostic\ninterrupted\n0 of 1")
  t.equal(live.show_cursor, out.writes[#out.writes])
end)

t.test(
  "resolve_mode reads TELEMETRY_MODE, then CI, then the terminal",
  function()
    local tty = fake.terminal({ tty = true })
    local pipe = fake.terminal({ tty = false })
    local spec = { title = "test", suites = {} }
    local function env(values)
      return function(name)
        return values[name]
      end
    end

    t.equal("live", telemetry.resolve_mode(spec, tty, env({})))
    t.equal("plain", telemetry.resolve_mode(spec, pipe, env({})))
    t.equal("plain", telemetry.resolve_mode(spec, tty, env({ CI = "true" })))
    t.equal(
      "plain",
      telemetry.resolve_mode(spec, tty, env({ GITHUB_ACTIONS = "true" }))
    )
    t.equal(
      "live",
      telemetry.resolve_mode(spec, pipe, env({ TELEMETRY_MODE = "live" }))
    )
    t.equal(
      "plain",
      telemetry.resolve_mode(spec, tty, env({ TELEMETRY_MODE = "plain" }))
    )
  end
)

t.test(
  "a stop signal between suites ends the run before the next one",
  function()
    local host = use_host({
      signal_in_check = quiet.ok,
      never = function()
        error("the next suite started after the stop signal")
      end,
    })
    local one = {
      name = "one",
      argv = { "signal_in_check" },
      check = function()
        host.stopped = true
      end,
    }
    local result = telemetry.run({
      title = "test",
      terminal = fake.terminal({ tty = false }),
      suites = { one, { name = "two", argv = { "never" } } },
    })
    t.equal(true, result.interrupted)
    t.equal(1, #result.suites)

    host.stopped = false
    local last = telemetry.run({
      title = "test",
      terminal = fake.terminal({ tty = false }),
      suites = { one },
    })
    t.equal(true, last.interrupted, "a stop signal during the last check")
  end
)

t.test("numbers in argv and env become strings, as in vim.system", function()
  local host = use_host({ ok = quiet.ok })
  telemetry.run({
    title = "test",
    terminal = fake.terminal({ tty = false }),
    suites = { { name = "n", argv = { "ok", 5 }, env = { N = 1 } } },
  })

  t.same({ "ok", "5" }, host.requests[1].argv)
  t.equal("1", host.requests[1].env.N)
end)

t.test("run restores the cursor when a suite check raises an error", function()
  for _, reject_diagnostic in ipairs({ false, true }) do
    local host = use_host({
      ok = quiet.ok,
      bad = function(_, sink)
        sink.output("stderr", "earlier diagnostic\n")
        return { code = 1 }
      end,
    })
    local out = fake.terminal()
    local write = out.write
    out.write = function(value)
      if reject_diagnostic and value:find("earlier diagnostic", 1, true) then
        error("abort sink failure")
      end
      write(value)
    end
    local err = t.raises(function()
      telemetry.run({
        title = "test",
        mode = "live",
        terminal = out,
        suites = {
          { name = "earlier failure", argv = { "bad" } },
          {
            name = "check error",
            argv = { "ok" },
            check = function()
              error("broken check")
            end,
          },
        },
      })
    end)

    t.contains(err, "broken check")
    if not reject_diagnostic then
      t.equal(1, select(2, out.text():gsub("earlier diagnostic", "")))
    end
    t.equal(live.show_cursor, out.writes[#out.writes])
    t.equal(0, host.guarded)
  end
end)

t.test(
  "run retains completion order and defers diagnostics past later suites",
  function()
    local out = fake.terminal({ color = false })
    use_host({
      bad = function(_, sink)
        sink.output("stderr", "deferred diagnostic\n")
        return { code = 1 }
      end,
      ok = function(_, sink)
        t.contains(out.text(), "FAIL first (0.0s) exit=1")
        t.equal(nil, out.text():find("deferred diagnostic", 1, true))
        sink.output("stdout", "hidden success output\n")
      end,
    })
    telemetry.run({
      title = "test",
      mode = "live",
      terminal = out,
      suites = {
        { name = "first", argv = { "bad" } },
        { name = "second", argv = { "ok" } },
      },
    })
    local output = out.text()
    local completed = (assert(output:find("ok second (0.0s)", 1, true)))
    local details = (assert(output:find("deferred diagnostic", 1, true)))
    local summary = (assert(output:find("1 of 2 test suites passed", 1, true)))
    t.truthy(completed < details and details < summary)
    t.equal(nil, output:find("hidden success output", 1, true))
  end
)

t.test(
  "diagnostic write errors preserve cleanup and the original error",
  function()
    local host = use_host({
      bad = function(_, sink)
        sink.output("stderr", "diagnostic\n")
        return { code = 1 }
      end,
    })
    local out = fake.terminal({ color = false })
    local write = out.write
    local attempts, closed = 0, false
    out.write = function(value)
      if value:find("diagnostic", 1, true) then
        attempts = attempts + 1
        if attempts == 1 then
          error("diagnostic sink failure")
        end
      end
      write(value)
    end
    out.close = function()
      closed = true
      error("secondary close failure")
    end
    local err = t.raises(function()
      telemetry.run({
        title = "test",
        mode = "live",
        terminal = out,
        suites = { { name = "broken", argv = { "bad" } } },
      })
    end)
    t.equal(1, attempts, "cleanup must not repeat the failed diagnostic write")
    t.contains(err, "diagnostic sink failure")
    t.equal(nil, err:find("secondary close failure", 1, true))
    t.equal(0, host.guarded)
    t.equal(true, closed)
    t.equal(live.show_cursor, out.writes[#out.writes])
  end
)

t.test("run rejects an invalid spec with the field path", function()
  use_host({})
  local cases = {
    { { title = "test", suites = {} }, "spec.suites" },
    {
      { title = "test", suites = { { name = "a", argv = {} } } },
      "spec.suites[1].argv",
    },
    {
      { title = "test", suites = { { name = "a", argv = { false } } } },
      "spec.suites[1].argv[1]",
    },
    {
      {
        title = "test",
        host = "basic",
        suites = { { name = "a", argv = { "x" } } },
      },
      "spec.host",
    },
    {
      {
        title = "test",
        mode = "fancy",
        suites = { { name = "a", argv = { "x" } } },
      },
      "spec.mode",
    },
    {
      {
        title = "test",
        suites = { { name = "a", argv = { "x" }, env = { A = true } } },
      },
      "spec.suites[1].env.A",
    },
    {
      {
        title = "test",
        suites = { { name = "a", argv = { "x" }, timeout = 500.5 } },
      },
      "spec.suites[1].timeout",
    },
  }

  for _, case in ipairs(cases) do
    t.contains(
      t.raises(function()
        telemetry.run(case[1])
      end),
      case[2]
    )
  end
end)

t.finish()
