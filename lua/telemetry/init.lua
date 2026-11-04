-- Run test suites as Neovim subprocesses and report their progress.
--
-- Usage from a headless script:
--
--   local telemetry = require("telemetry")
--   telemetry.exit(telemetry.run({ title = "test", suites = suites }))
local progress = require("telemetry.state")
local runner = require("telemetry.runner")
local terminal = require("telemetry.terminal")

local M = {}

---@type table<Telemetry.Mode, true>
local modes = { auto = true, live = true, plain = true }

-- Exit code after Ctrl-C, as in a shell: 128 plus SIGINT.
M.interrupted_code = 130

---@param spec Telemetry.Spec
local function validate(spec)
  vim.validate("spec", spec, "table")
  vim.validate("spec.title", spec.title, "string")
  vim.validate("spec.suites", spec.suites, function(suites)
    return type(suites) == "table" and #suites > 0
  end, "a non-empty list")
  vim.validate("spec.mode", spec.mode, function(mode)
    return mode == nil or modes[mode] == true
  end, "auto, live or plain")

  for index, suite in ipairs(spec.suites) do
    local path = string.format("spec.suites[%d]", index)
    vim.validate(path .. ".name", suite.name, "string")
    vim.validate(path .. ".argv", suite.argv, "table")
    vim.validate(path .. ".cwd", suite.cwd, "string", true)
    vim.validate(path .. ".env", suite.env, "table", true)
    vim.validate(path .. ".timeout", suite.timeout, "number", true)
    vim.validate(path .. ".check", suite.check, "function", true)
  end
end

-- TELEMETRY_MODE overrides the spec. The auto mode draws the live view only
-- on an interactive terminal outside CI.
---@param spec Telemetry.Spec
---@param out Telemetry.Terminal
---@return "live"|"plain"
function M.resolve_mode(spec, out)
  local mode = vim.env.TELEMETRY_MODE

  if not modes[mode] then
    mode = spec.mode or "auto"
  end

  if mode == "auto" then
    local ci = vim.env.CI == "true" or vim.env.GITHUB_ACTIONS == "true"
    return (out.tty and not ci) and "live" or "plain"
  end

  return mode
end

---@param mode "live"|"plain"
---@param out Telemetry.Terminal
---@return Telemetry.View
local function create_view(mode, out)
  return require("telemetry.view." .. mode).new(out)
end

-- Starts a Ctrl-C handler. Returns a function that reports a press and a
-- function that stops the handler.
---@return fun(): boolean pressed
---@return fun() stop
local function watch_interrupt()
  local pressed = false
  local signal = vim.uv.new_signal()

  if not signal then
    return function()
      return false
    end, function() end
  end

  signal:start("sigint", function()
    pressed = true
  end)

  return function()
    return pressed
  end, function()
    signal:stop()
    signal:close()
  end
end

---@class Telemetry.Running
---@field process? vim.SystemObj Process of the running suite.

-- Neovim may end the process itself on Ctrl-C ("Caught deadly signal").
-- It still runs VimLeavePre, so the hook stops the running child and
-- restores the terminal. Returns a function that removes the hook.
---@param view Telemetry.View
---@param running Telemetry.Running
---@return fun() remove
local function guard_exit(view, running)
  local group = vim.api.nvim_create_augroup("telemetry.run", { clear = true })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      if running.process then
        pcall(running.process.kill, running.process, "sigkill")
      end

      view.abort()
    end,
  })

  return function()
    vim.api.nvim_del_augroup_by_id(group)
  end
end

---@param spec Telemetry.Spec
---@param view Telemetry.View
---@param state Telemetry.State
---@param cancelled fun(): boolean
---@param running Telemetry.Running
---@return Telemetry.SuiteResult[] results
---@return boolean interrupted
local function run_suites(spec, view, state, cancelled, running)
  local results = {}

  ---@type Telemetry.Observer
  local observer = {
    event = function(event)
      progress.apply_event(state, event)
    end,
    poll = function()
      view.update(state)
    end,
    cancelled = cancelled,
    spawned = function(process)
      running.process = process
    end,
  }

  for _, suite in ipairs(spec.suites) do
    progress.start_suite(state, suite.name)
    view.update(state)

    local result, interrupted = runner.run(suite, observer)
    results[#results + 1] = result
    progress.finish_suite(state, result)
    view.suite_finished(state, result)

    if interrupted then
      return results, true
    end
  end

  return results, false
end

-- Runs the suites in order and reports them. A Lua error restores the
-- terminal before it propagates.
---@param spec Telemetry.Spec
---@return Telemetry.Result
function M.run(spec)
  validate(spec)

  local out = spec.terminal or terminal.stdout()
  local view = create_view(M.resolve_mode(spec, out), out)
  local state = progress.new(spec.title, #spec.suites)
  local cancelled, stop_watch = watch_interrupt()
  ---@type Telemetry.Running
  local running = {}
  local remove_guard = guard_exit(view, running)

  local ok, results, interrupted =
    xpcall(run_suites, debug.traceback, spec, view, state, cancelled, running)
  stop_watch()
  remove_guard()

  if not ok then
    view.abort()
    if out.close then
      out.close()
    end
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
  }

  view.finish(state, result)
  if out.close then
    out.close()
  end

  return result
end

-- Exits the process: 0 when every suite passed, else 1. A run that telemetry
-- itself stopped after Ctrl-C exits with 130. Neovim can also end the process
-- on Ctrl-C before this runs; see guard_exit.
---@param result Telemetry.Result
function M.exit(result)
  if result.interrupted then
    os.exit(M.interrupted_code)
  end

  os.exit(result.failed == 0 and 0 or 1)
end

return M
