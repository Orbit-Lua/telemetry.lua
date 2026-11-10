-- Run test suites as child processes and report their progress.
--
-- Usage from a script under `nvim -l`, or under Lua with luv:
--
--   local telemetry = require("telemetry")
--   telemetry.exit(telemetry.run({ title = "test", suites = suites }))
local hosts = require("telemetry.host")
local progress = require("telemetry.state")
local runner = require("telemetry.runner")
local validate = require("telemetry.validate")

local M = {}

-- Exit code after Ctrl-C, as in a shell: 128 plus SIGINT.
M.interrupted_code = 130

-- TELEMETRY_MODE overrides the spec. The auto mode draws the live view only
-- on an interactive terminal outside CI.
---@param spec Telemetry.Spec
---@param out Telemetry.Terminal
---@param getenv fun(name: string): string?
---@return "live"|"plain"
function M.resolve_mode(spec, out, getenv)
  local mode = getenv("TELEMETRY_MODE")

  if not validate.modes[mode] then
    mode = spec.mode or "auto"
  end

  if mode == "auto" then
    local ci = getenv("CI") == "true" or getenv("GITHUB_ACTIONS") == "true"
    return (out.tty and not ci) and "live" or "plain"
  end

  return mode
end

---@param spec Telemetry.Spec
---@param view Telemetry.View
---@param state Telemetry.State
---@param host Telemetry.Host
---@return Telemetry.SuiteResult[] results
---@return boolean interrupted
local function run_suites(spec, view, state, host)
  local results = {}

  ---@type Telemetry.Observer
  local observer = {
    event = function(event)
      progress.apply_event(state, event)
    end,
    poll = function()
      view.update(state)
    end,
  }

  for _, suite in ipairs(spec.suites) do
    -- A stop signal between suites, such as during a check, ends the run
    -- before the next suite starts.
    if host.interrupted() then
      return results, true
    end

    progress.start_suite(state, suite.name)
    view.update(state)

    local result, interrupted = runner.run(suite, observer, host)
    results[#results + 1] = result
    progress.finish_suite(state, result)
    view.suite_finished(state, result)

    if interrupted then
      return results, true
    end
  end

  return results, host.interrupted()
end

---@param out Telemetry.Terminal
local function close(out)
  if out.close then
    out.close()
  end
end

-- Runs the suites in order and reports them. A Lua error restores the
-- terminal before it propagates.
---@param spec Telemetry.Spec
---@return Telemetry.Result
function M.run(spec)
  validate.spec(spec)

  local host = hosts.select(spec.host, os.getenv)
  local out = spec.terminal or host.terminal()
  local mode = M.resolve_mode(spec, out, host.getenv)
  local view = require("telemetry.view." .. mode).new(out, host.getenv)
  local state = progress.new(spec.title, #spec.suites, host.clock)
  local remove_guard = host.guard(view.abort)

  local ok, results, interrupted = xpcall(function()
    return run_suites(spec, view, state, host)
  end, debug.traceback)
  remove_guard()

  if not ok then
    view.abort()
    close(out)
    error(results, 0)
  end

  ---@type Telemetry.Result
  local result = {
    title = spec.title,
    suites = results,
    passed = state.passed,
    failed = state.failed,
    duration = progress.elapsed(state),
    interrupted = interrupted,
    host = host.name,
  }

  view.finish(state, result)
  close(out)
  return result
end

-- Exits the process: 0 when every suite passed, else 1. A run that stopped
-- after Ctrl-C exits with 130. Under Neovim, Ctrl-C can also end the process
-- before this runs, with Neovim's own nonzero code.
---@param result Telemetry.Result
function M.exit(result)
  if result.interrupted then
    os.exit(M.interrupted_code)
  end

  os.exit(result.failed == 0 and 0 or 1)
end

return M
