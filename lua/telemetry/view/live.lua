-- Fixed view for interactive terminals. A small frame at the bottom shows
-- the progress bar, the running suite and test, and the counts. Each redraw
-- replaces only the frame. Completed suite lines stay above it. Failure
-- details print when the run finishes or aborts.
local progress = require("telemetry.state")
local report = require("telemetry.view.report")
local text = require("telemetry.text")

local M = {}

M.hide_cursor = "\27[?25l"
M.show_cursor = "\27[?25h"

-- Erases from the cursor to the end of the screen.
M.erase_below = "\27[J"

M.max_bar_width = 24

---@param count integer
---@return string
local function cursor_up(count)
  return string.format("\27[%dF", count)
end

---@param state Telemetry.State
---@param width integer Columns for the whole line.
---@return Telemetry.Segment[]
local function progress_segments(state, width)
  local tail = string.format(
    " %d/%d  %s",
    state.done,
    state.total,
    text.duration(progress.elapsed(state))
  )
  local room = width - text.width(state.title .. " " .. tail)
  local bar = math.max(math.min(room, M.max_bar_width), 0)
  local filled = state.total == 0 and bar
    or math.floor(bar * state.done / state.total)

  return {
    { state.title, "bold" },
    { " " },
    { string.rep("█", filled), state.failed == 0 and "green" or "red" },
    { string.rep("░", bar - filled), "dim" },
    { tail },
  }
end

---@param state Telemetry.State
---@return Telemetry.Segment[]
local function count_segments(state)
  local segments = {
    { "  " },
    { state.passed .. " passed", "green" },
    { "  " },
    { state.failed .. " failed", state.failed == 0 and "dim" or "red" },
  }

  local tests = state.tests
  if tests.passed + tests.failed > 0 then
    local counts =
      string.format("   tests %d passed, %d failed", tests.passed, tests.failed)
    segments[#segments + 1] = { counts, "dim" }
  end

  return segments
end

-- Builds the frame lines. Each line fits in the width minus one column, so
-- that no line wraps and breaks the cursor movement.
---@param out Telemetry.Terminal
---@param state Telemetry.State
---@return string[]
local function frame(out, state)
  local width = math.max(out.width() - 1, 1)
  local lines = {
    text.fit(out, progress_segments(state, width), width),
  }

  if state.suite then
    local segments = { { "  " }, { "▶ " .. state.suite, "cyan" } }
    lines[#lines + 1] = text.fit(out, segments, width)
  end

  if state.test then
    local segments = { { "    " }, { state.test, "dim" } }
    lines[#lines + 1] = text.fit(out, segments, width)
  end

  lines[#lines + 1] = text.fit(out, count_segments(state), width)
  return lines
end

---@param out Telemetry.Terminal
---@param lines string[]
local function write_lines(out, lines)
  if #lines > 0 then
    out.write(table.concat(lines, "\n") .. "\n")
  end
end

---@param out Telemetry.Terminal
---@return fun(result: Telemetry.SuiteResult) defer
---@return fun() emit
local function failure_reporter(out)
  ---@type Telemetry.SuiteResult[]
  local pending = {}
  local next_failure = 1

  return function(result)
    pending[#pending + 1] = result
  end, function()
    while next_failure <= #pending do
      local result = pending[next_failure]
      -- Consume before writing: abort must not repeat a partially written block.
      next_failure = next_failure + 1
      write_lines(out, { report.suite_line(out, result) })
      write_lines(out, report.failure_lines(out, result))
    end
    pending, next_failure = {}, 1
  end
end

---@param out Telemetry.Terminal
---@param clear fun()
---@param emit fun()
local function abort(out, clear, emit)
  local ok, err = pcall(function()
    clear()
    emit()
  end)
  out.write(M.show_cursor)
  if not ok then
    error(err, 0)
  end
end

---@param out Telemetry.Terminal
---@return Telemetry.View
function M.new(out)
  local height = 0
  local hidden = false
  local defer, emit = failure_reporter(out)

  local function clear()
    if height > 0 then
      out.write(cursor_up(height) .. M.erase_below)
      height = 0
    end
  end

  ---@param state Telemetry.State
  local function draw(state)
    if not hidden then
      out.write(M.hide_cursor)
      hidden = true
    end

    local lines = frame(out, state)
    clear()
    write_lines(out, lines)
    height = #lines
  end

  ---@param state Telemetry.State
  ---@param result Telemetry.SuiteResult
  local function suite_finished(state, result)
    if result.status ~= "pass" then
      defer(result)
    end
    clear()
    write_lines(out, { report.suite_line(out, result) })
    draw(state)
  end

  ---@param state Telemetry.State
  ---@param result Telemetry.Result
  local function finish(state, result)
    clear()
    emit()
    write_lines(out, report.summary_lines(out, state, result))
    out.write(M.show_cursor)
  end

  return {
    update = draw,
    suite_finished = suite_finished,
    finish = finish,
    abort = function()
      abort(out, clear, emit)
    end,
  }
end

return M
