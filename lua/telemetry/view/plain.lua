-- Line-based view for pipes and CI logs: one line per suite, the full output
-- of each failed suite, and a summary. It writes no cursor control or color.
-- On GitHub Actions it folds failure output into groups and adds annotations.
local report = require("telemetry.view.report")

local M = {}

---@param out Telemetry.Terminal
---@param lines string[]
local function write_lines(out, lines)
  if #lines > 0 then
    out.write(table.concat(lines, "\n") .. "\n")
  end
end

---@param out Telemetry.Terminal
---@return Telemetry.View
function M.new(out)
  local github = vim.env.GITHUB_ACTIONS == "true"

  local function suite_finished(_, result)
    write_lines(out, { report.suite_line(out, result) })

    if result.status == "pass" then
      return
    end

    local details = report.failure_lines(out, result)

    if github then
      table.insert(details, 1, "::group::" .. result.name .. " output")
      details[#details + 1] = "::endgroup::"
      details[#details + 1] = "::error::" .. result.name .. " failed"
    end

    write_lines(out, details)
  end

  local function finish(state, result)
    write_lines(out, report.summary_lines(out, state, result))
  end

  return {
    update = function() end,
    suite_finished = suite_finished,
    finish = finish,
    abort = function() end,
  }
end

return M
