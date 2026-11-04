local runner = require("telemetry.runner")

local repository = vim.fn.getcwd()

---@param mode string
---@param fields? table Extra suite fields.
---@return Telemetry.Suite
local function suite(mode, fields)
  local argv = {
    vim.v.progpath,
    "--headless",
    "-u",
    "NONE",
    "-l",
    repository .. "/tests/fixtures/child.lua",
    mode,
  }
  local env = { TELEMETRY_REPOSITORY = repository }

  return vim.tbl_extend(
    "force",
    { name = mode, argv = argv, env = env },
    fields or {}
  )
end

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

describe("runner", function()
  it("separates events from output and passes a zero exit", function()
    local observer, events = recorder()
    local result = runner.run(suite("pass"), observer)

    assert.equal("pass", result.status)
    assert.equal(0, result.code)
    assert.same({ { name = "first", status = "pass" } }, result.tests)
    assert.equal(2, #events)

    for _, line in ipairs({ "before", "after", "on stderr" }) do
      assert.truthy(result.output:find(line, 1, true), line)
    end

    assert.is_nil(result.output:find("\30", 1, true))
  end)

  it("fails a nonzero exit and keeps its output", function()
    local result = runner.run(suite("fail"), recorder())

    assert.equal("fail", result.status)
    assert.equal(3, result.code)
    assert.equal("broken output", result.output)
  end)

  it("reports a started test without an end as an error", function()
    local observer, events = recorder()
    local result = runner.run(suite("unfinished"), observer)

    assert.same({ { name = "never ends", status = "error" } }, result.tests)
    assert.same(
      { event = "test_end", name = "never ends", status = "error" },
      events[#events]
    )
  end)

  it("stops a suite at its timeout", function()
    local started = vim.uv.hrtime()
    local result = runner.run(suite("sleep", { timeout = 300 }), recorder())

    assert.equal("timeout", result.status)
    assert.equal("timed out after 300 ms", result.message)
    assert.is_true((vim.uv.hrtime() - started) / 1e9 < 5)
  end)

  it("stops the child when the observer cancels the run", function()
    local observer = recorder()
    observer.cancelled = function()
      return true
    end

    local started = vim.uv.hrtime()
    local result, interrupted = runner.run(suite("sleep"), observer)

    assert.is_true(interrupted)
    assert.equal("fail", result.status)
    assert.equal("interrupted", result.message)
    assert.is_true((vim.uv.hrtime() - started) / 1e9 < 5)
  end)

  it("applies env and cwd, then runs check", function()
    local seen
    local result = runner.run(
      suite("environment", {
        cwd = repository .. "/tests",
        env = { TELEMETRY_REPOSITORY = repository, TELEMETRY_FIXTURE = "set" },
        check = function(completed)
          seen = completed.output
          return "check rejected the suite"
        end,
      }),
      recorder()
    )

    assert.equal("set\ntests", seen)
    assert.equal("fail", result.status)
    assert.equal("check rejected the suite", result.message)
  end)

  it("fails a suite whose command cannot start", function()
    local result = runner.run(
      { name = "missing", argv = { "telemetry-missing-executable" } },
      recorder()
    )

    assert.equal("fail", result.status)
    assert.truthy(result.output:find("telemetry-missing-executable", 1, true))
  end)
end)
