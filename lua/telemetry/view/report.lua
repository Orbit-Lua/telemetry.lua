-- Text blocks that both views print: suite lines, failure details and the
-- final summary. Each function returns lines without newlines.
local text = require("telemetry.text")

local M = {}

---@type table<Telemetry.SuiteStatus, { label: string, style: "green"|"red"|"yellow" }>
local labels = {
  pass = { label = "ok", style = "green" },
  fail = { label = "FAIL", style = "red" },
  timeout = { label = "TIMEOUT", style = "yellow" },
}

---@param out Telemetry.Terminal
---@param result Telemetry.SuiteResult
---@return string
function M.suite_line(out, result)
  local label = labels[result.status]
  local line = string.format(
    "%s %s (%s)",
    text.paint(out, label.style, label.label),
    result.name,
    text.duration(result.duration)
  )

  if result.status ~= "pass" and result.code ~= 0 then
    line = line .. string.format(" exit=%d", result.code)
  end

  if result.signal ~= 0 then
    line = line .. string.format(" signal=%d", result.signal)
  end

  return line
end

-- Lines that explain a failed suite: its full output, its failed tests and
-- the reason that the exit code does not give.
---@param out Telemetry.Terminal
---@param result Telemetry.SuiteResult
---@return string[]
function M.failure_lines(out, result)
  local output = out.color and result.output or text.strip(result.output)
  local lines = output == "" and {} or text.lines(output)

  for _, test in ipairs(result.tests) do
    if test.status ~= "pass" then
      local mark = text.paint(out, "red", test.status)
      lines[#lines + 1] = string.format("  %s: %s", mark, test.name)
    end
  end

  if result.message then
    lines[#lines + 1] = text.paint(out, "red", result.message)
  end

  return lines
end

---@param out Telemetry.Terminal
---@param state Telemetry.State
---@param result Telemetry.Result
---@return string[]
function M.summary_lines(out, state, result)
  local style = result.failed == 0 and "green" or "red"
  local lines = {
    text.paint(
      out,
      style,
      string.format(
        "%d of %d %s suites passed (%s).",
        result.passed,
        #result.suites,
        result.title,
        text.duration(result.duration)
      )
    ),
  }

  local tests = state.tests
  if tests.passed + tests.failed > 0 then
    lines[#lines + 1] =
      string.format("Tests: %d passed, %d failed.", tests.passed, tests.failed)
  end

  local failed = {}
  for _, suite in ipairs(result.suites) do
    if suite.status ~= "pass" then
      failed[#failed + 1] = suite.name
    end
  end

  if #failed > 0 then
    lines[#lines + 1] = "Failed: " .. table.concat(failed, ", ")
  end

  if result.interrupted then
    lines[#lines + 1] = text.paint(out, "yellow", "Interrupted.")
  end

  return lines
end

return M
