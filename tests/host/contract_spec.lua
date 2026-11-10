-- The host contract against real child processes, under the host of the
-- interpreter that runs this spec.
local hosts = require("telemetry.host")
local process = require("tests.support.process")
local protocol = require("telemetry.protocol")
local runner = require("telemetry.runner")
local t = require("tests.support.harness")
local uv_host = require("telemetry.host.uv")

local host = hosts.select(nil, os.getenv)
local uv = process.uv

---@return Telemetry.Observer
local function observer()
  return { event = function() end, poll = function() end }
end

---@param name string
---@param argv string[]
---@param fields? table<string, any>
---@return Telemetry.SuiteResult result
---@return boolean interrupted
---@return number seconds
local function run(name, argv, fields)
  local suite = { name = name, argv = argv }
  for key, value in pairs(fields or {}) do
    suite[key] = value
  end

  local started = host.clock()
  local result, interrupted =
    runner.run(suite, fields and fields.observer or observer(), host)
  return result, interrupted, host.clock() - started
end

-- Runs a request on the host and records each output chunk.
---@param argv string[]
---@param env? table<string, string>
---@return Telemetry.ProcessExit exit
---@return { [1]: string, [2]: string }[] chunks
local function execute(argv, env)
  local chunks = {}
  local exit = host.execute({ argv = argv, env = env or {}, timeout = 30000 }, {
    output = function(stream, chunk)
      chunks[#chunks + 1] = { stream, chunk }
    end,
    poll = function()
      return false
    end,
  })

  return exit, chunks
end

t.test("the host reports exit codes and output", function()
  local passed = run("exit 0", process.fixture("process.lua", "exit", "0"))
  local failed = run("exit 3", process.fixture("process.lua", "exit", "3"))

  t.equal("pass", passed.status)
  t.equal(0, passed.code)
  t.equal("fail", failed.status)
  t.equal(3, failed.code)
  t.equal("out", failed.output)
end)

t.test("the host reports a command that cannot start", function()
  local result = run("missing", { "telemetry-missing-executable" })

  t.equal("fail", result.status)
  t.equal(-1, result.code)
  t.contains(result.output, "telemetry-missing-executable")
end)

t.test("the host keeps output order and separates the streams", function()
  local exit, chunks = execute(process.fixture("process.lua", "order"))
  -- A pipe may split one write into several chunks, so join the chunks of
  -- each run of one stream. Windows children write "\r\n" in text mode.
  local runs = {}
  for _, chunk in ipairs(chunks) do
    local last = runs[#runs]
    if last and last[1] == chunk[1] then
      last[2] = last[2] .. chunk[2]
    else
      runs[#runs + 1] = { chunk[1], chunk[2] }
    end
  end

  local seen = {}
  for _, item in ipairs(runs) do
    seen[#seen + 1] = item[1] .. ":" .. item[2]:gsub("\r\n", "\n")
  end

  t.equal(0, exit.code)
  t.equal("stdout:a\n stderr:b\n stdout:c\n", table.concat(seen, " "))
end)

t.test("a partial stderr line does not swallow a stdout event", function()
  local result = run("split", process.fixture("process.lua", "split"))

  t.same({ { name = "first", status = "pass" } }, result.tests)
  t.equal("err-part", result.output)
  t.equal(nil, result.output:find(protocol.prefix, 1, true))
end)

t.test("the host inherits the environment and adds variables", function()
  local path = os.getenv("PATH")
  local extended = path .. (process.windows and ";" or ":") .. "telemetry-extra"
  local argv = process.fixture(
    "process.lua",
    "env",
    "PATH",
    "TELEMETRY_ADDED",
    "TELEMETRY_EVENTS"
  )
  local result =
    run("env", argv, { env = { PATH = extended, TELEMETRY_ADDED = "set" } })
  local child_path, rest = result.output:match("^PATH=([^\n]*)\n(.*)$")

  -- Neovim on Windows appends its own bin directory to PATH at startup.
  t.equal(extended, child_path and child_path:sub(1, #extended), "PATH")
  t.equal("TELEMETRY_ADDED=set\nTELEMETRY_EVENTS=1", rest)
end)

t.test("the host runs in a cwd with spaces and quotes", function()
  local name = process.windows and "telemetry cwd 'quoted' XXXXXX"
    or "telemetry cwd 'quoted' \"double\" XXXXXX"
  local directory = assert(uv.fs_mkdtemp(uv.os_tmpdir() .. "/" .. name))
  local result =
    run("cwd", process.fixture("process.lua", "cwd"), { cwd = directory })
  uv.fs_rmdir(directory)

  t.equal("pass", result.status, result.output)
  t.equal(
    uv.fs_realpath(uv.os_tmpdir())
      .. (process.windows and "\\" or "/")
      .. directory:match("[^/\\]+$"),
    result.output
  )
end)

t.test("the host reports events from the child", function()
  local result = run("events", process.fixture("process.lua", "events"))
  local expected = {
    { name = "passes", status = "pass" },
    { name = "fails", status = "fail" },
  }

  t.same(expected, result.tests)
end)

t.test("a timeout starts when the suite starts, after idle work", function()
  -- Busy work leaves the libuv loop time stale.
  local started = os.clock()
  while os.clock() - started < 1.5 do
  end

  local result =
    run("nap", process.fixture("process.lua", "nap", "500"), { timeout = 1500 })
  t.equal("pass", result.status, result.message)
end)

-- A grandchild that holds the pipes must not keep a stopped suite running.
---@param label string
---@param mode string
---@param fields table<string, any>
local function check_group_stop(label, mode, fields)
  local pidfile = process.tempname()
  local result, interrupted, seconds =
    run(mode, process.fixture("process.lua", mode, pidfile), fields)
  local pids = process.read_pids(pidfile)
  os.remove(pidfile)

  t.equal(2, #pids, label .. ": the fixture wrote its pids")
  t.truthy(
    seconds < uv_host.kill_grace / 1000 + 5,
    label .. ": stopped in time"
  )
  for _, pid in ipairs(pids) do
    t.equal(false, process.alive(pid), label .. ": pid " .. pid .. " survived")
  end

  return result, interrupted
end

t.test("a timeout stops the child and its grandchild", function()
  local result = check_group_stop("timeout", "hold", { timeout = 1000 })

  t.equal("timeout", result.status)
  t.equal("timed out after 1000 ms", result.message)
end)

t.test("a cancel stops the child and its grandchild", function()
  local polls = 0
  local cancelling = observer()
  cancelling.cancelled = function()
    polls = polls + 1
    return polls > 20
  end
  local result, interrupted =
    check_group_stop("cancel", "hold", { observer = cancelling })

  t.equal(true, interrupted)
  t.equal("interrupted", result.message)
end)

if not process.windows then
  t.test("the whole group gets the grace period after SIGTERM", function()
    local pidfile, marker = process.tempname(), process.tempname()
    local result = run(
      "trap",
      process.fixture("process.lua", "trap", pidfile, marker),
      { timeout = 1000 }
    )
    local file = io.open(marker, "r")
    os.remove(pidfile)
    os.remove(marker)

    t.equal("timeout", result.status)
    t.truthy(file, "the grandchild's SIGTERM trap did not finish")
    if file then
      file:close()
    end
  end)

  t.test("SIGKILL stops a grandchild that ignores SIGTERM", function()
    local result = check_group_stop("stubborn", "stubborn", { timeout = 1000 })
    t.equal("timeout", result.status)
  end)
end

t.finish()
