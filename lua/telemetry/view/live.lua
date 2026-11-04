-- Fixed view for interactive terminals. A small frame at the bottom shows
-- the progress bar, the running suite and test, and the counts. Each redraw
-- moves the cursor to the frame start and erases the frame, so the screen
-- does not scroll. Failure details print above the frame and stay there.
local progress = require("telemetry.state")
local report = require("telemetry.view.report")
local terminal = require("telemetry.terminal")

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
    terminal.duration(progress.elapsed(state))
  )
  local room = width - vim.fn.strdisplaywidth(state.title .. " " .. tail)
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
    local text =
      string.format("   tests %d passed, %d failed", tests.passed, tests.failed)
    segments[#segments + 1] = { text, "dim" }
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
    terminal.fit(out, progress_segments(state, width), width),
  }

  if state.suite then
    local segments = { { "  " }, { "▶ " .. state.suite, "cyan" } }
    lines[#lines + 1] = terminal.fit(out, segments, width)
  end

  if state.test then
    local segments = { { "    " }, { state.test, "dim" } }
    lines[#lines + 1] = terminal.fit(out, segments, width)
  end

  lines[#lines + 1] = terminal.fit(out, count_segments(state), width)
  return lines
end

---@param out Telemetry.Terminal
---@return Telemetry.View
function M.new(out)
  local height = 0
  local hidden = false

  local function clear()
    if height > 0 then
      out.write(cursor_up(height) .. M.erase_below)
      height = 0
    end
  end

  ---@param lines string[]
  local function write_lines(lines)
    if #lines > 0 then
      out.write(table.concat(lines, "\n") .. "\n")
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
    write_lines(lines)
    height = #lines
  end

  local function suite_finished(state, result)
    if result.status ~= "pass" then
      clear()
      write_lines({ report.suite_line(out, result) })
      write_lines(report.failure_lines(out, result))
    end

    draw(state)
  end

  local function finish(state, result)
    clear()
    write_lines(report.summary_lines(out, state, result))
    out.write(M.show_cursor)
  end

  local function abort()
    clear()
    out.write(M.show_cursor)
  end

  return {
    update = draw,
    suite_finished = suite_finished,
    finish = finish,
    abort = abort,
  }
end

return M
