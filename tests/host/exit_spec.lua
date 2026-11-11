-- Exit codes, host exit and Ctrl-C of a whole run, under the host of the
-- interpreter that runs this spec.
local hosts = require("telemetry.host")
local live = require("telemetry.view.live")
local process = require("tests.support.process")
local t = require("tests.support.harness")

local host = hosts.select(nil, os.getenv)

-- Runs the run.lua fixture. `act` runs at each poll with the runner pid
-- once the suite's child and grandchild have written their pids.
---@param mode string
---@param pidfile? string
---@param act? fun(runner: integer)
---@return Telemetry.ProcessExit exit
---@return string stdout
local function run_fixture(mode, pidfile, act)
  local stdout = {}
  local exit = host.execute({
    argv = process.fixture("run.lua", mode, pidfile),
    env = { TELEMETRY_MODE = "" },
    timeout = 60000,
  }, {
    output = function(stream, chunk)
      if stream == "stdout" then
        stdout[#stdout + 1] = chunk
      end
    end,
    poll = function()
      local runner = pidfile and process.read_pids(pidfile .. ".runner")[1]
      if act and runner and #process.read_pids(pidfile) == 2 then
        act(runner)
        act = nil
      end
      return false
    end,
  })

  return exit, table.concat(stdout)
end

-- Checks that the suite's child and grandchild are gone.
---@param pidfile string
local function assert_stopped(pidfile)
  local pids = process.read_pids(pidfile)
  os.remove(pidfile)
  os.remove(pidfile .. ".runner")

  t.equal(2, #pids, "the suite wrote its pids")
  for _, pid in ipairs(pids) do
    t.equal(false, process.alive(pid), "pid " .. pid .. " survived")
  end
end

t.test("exit returns 0 when every suite passes and 1 otherwise", function()
  local passed, passed_out = run_fixture("pass")
  local failed, failed_out = run_fixture("fail")

  t.equal(0, passed.code, passed_out)
  t.equal(1, failed.code, failed_out)
  t.contains(failed_out, "out")
end)

if host.name == "nvim" then
  t.test(
    "Neovim exit stops the suite's group and restores the cursor",
    function()
      local pidfile = process.tempname()
      local _, stdout = run_fixture("quit", pidfile)

      assert_stopped(pidfile)
      t.contains(stdout, live.show_cursor)
      local running = (assert(stdout:find("▶ quit", 1, true)))
      local diagnostic = (assert(stdout:find("out", running, true)))
      local restored = (assert(stdout:find(live.show_cursor, diagnostic, true)))
      t.truthy(running < diagnostic and diagnostic < restored)
      t.equal(1, select(2, stdout:gsub("out", "")))
      t.contains(stdout:sub(running, diagnostic), "\27[3F\27[JFAIL fail")
    end
  )
end

-- A signal that arrives during blocking work, such as a check, reaches its
-- handler only when the loop runs. The run must still end before suite two.
if not process.windows then
  t.test(
    "a stop signal during a check ends the run before the next suite",
    function()
      local marker = process.tempname()
      local exit = run_fixture("between", marker)
      local started = io.open(marker, "r")
      os.remove(marker)

      t.truthy(exit.code ~= 0, "exit code " .. exit.code)
      t.equal(nil, started, "the next suite started")
      if started then
        started:close()
      end
    end
  )
end

-- A terminal sends Ctrl-C to its foreground group. The runner is detached
-- here, so its group gets SIGINT and the suite's own group does not.
-- `kill` and a closed terminal send SIGTERM and SIGHUP to the runner alone.
if not process.windows then
  for _, signal in ipairs({ "sigint", "sigterm", "sighup" }) do
    local name = signal:upper()

    t.test(
      name .. " stops the suite's group and restores the cursor",
      function()
        local pidfile = process.tempname()
        local exit, stdout = run_fixture("hold", pidfile, function(runner)
          process.uv.kill(signal == "sigint" and -runner or runner, signal)
        end)

        assert_stopped(pidfile)
        t.contains(stdout, live.show_cursor)
        if host.name == "luv" then
          t.equal(130, exit.code)
        else
          t.truthy(exit.code ~= 0, "exit code " .. exit.code)
        end
      end
    )
  end
end

t.finish()
