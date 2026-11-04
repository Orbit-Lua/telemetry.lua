-- Progress of one run: suite counts and the running suite and test. The views
-- read this state; only the run loop in init.lua changes it.
local M = {}

---@class Telemetry.TestCounts
---@field passed integer
---@field failed integer Tests with status "fail" or "error".

---@class Telemetry.State
---@field title string
---@field total integer Suites in the run.
---@field done integer Finished suites.
---@field passed integer Passed suites.
---@field failed integer Failed or timed-out suites.
---@field tests Telemetry.TestCounts Tests across all suites.
---@field suite? string Running suite.
---@field test? string Running test of the running suite.
---@field started integer Start time from `vim.uv.hrtime()`.

---@param title string
---@param total integer
---@return Telemetry.State
function M.new(title, total)
  return {
    title = title,
    total = total,
    done = 0,
    passed = 0,
    failed = 0,
    tests = { passed = 0, failed = 0 },
    started = vim.uv.hrtime(),
  }
end

---@param state Telemetry.State
---@param name string
function M.start_suite(state, name)
  state.suite = name
  state.test = nil
end

---@param state Telemetry.State
---@param event Telemetry.Event
function M.apply_event(state, event)
  if event.event == "test_start" then
    state.test = event.name
    return
  end

  state.test = nil

  if event.status == "pass" then
    state.tests.passed = state.tests.passed + 1
  else
    state.tests.failed = state.tests.failed + 1
  end
end

---@param state Telemetry.State
---@param result Telemetry.SuiteResult
function M.finish_suite(state, result)
  state.done = state.done + 1
  state.suite = nil
  state.test = nil

  if result.status == "pass" then
    state.passed = state.passed + 1
  else
    state.failed = state.failed + 1
  end
end

---@param state Telemetry.State
---@return number seconds
function M.elapsed(state)
  return (vim.uv.hrtime() - state.started) / 1e9
end

return M
