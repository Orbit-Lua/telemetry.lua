local helpers = require("tests.helpers")
local live = require("telemetry.view.live")
local progress = require("telemetry.state")
local terminal = require("telemetry.terminal")

---@param text string
---@return string[]
local function screen_lines(text)
  local plain = terminal.strip(text)
  return vim.split(plain, "\n", { trimempty = true })
end

describe("live view", function()
  it("redraws in place and fits every line in the width", function()
    local out = helpers.fake_terminal({ width = 40 })
    local view = live.new(out)
    local state = progress.new("test", 4)
    progress.start_suite(
      state,
      "tests/a_very_long_suite_name_that_wraps_spec.lua"
    )
    state.test = "describes a test name that is far wider than forty columns"

    view.update(state)
    local first = #out.writes
    view.update(state)
    local redraw = table.concat(out.writes, "", first + 1)

    assert.equal(live.hide_cursor, out.writes[1])
    assert.equal(1, select(2, out.text():gsub("%?25l", "")))
    assert.equal("\27[4F" .. live.erase_below, redraw:sub(1, 7))

    for _, line in ipairs(screen_lines(redraw:sub(8))) do
      assert.is_true(vim.fn.strdisplaywidth(line) <= 39, line)
    end
  end)

  it("prints failure output above the frame and keeps it", function()
    local out = helpers.fake_terminal()
    local view = live.new(out)
    local state = progress.new("test", 2)
    view.update(state)

    local result = helpers.suite_result({
      status = "fail",
      code = 1,
      output = "assertion output",
      tests = { { name = "outer fails", status = "fail" } },
    })
    progress.finish_suite(state, result)
    local mark = #out.writes
    view.suite_finished(state, result)

    local text = terminal.strip(table.concat(out.writes, "", mark + 1))
    local failure = text:find("FAIL tests/example_spec.lua", 1, true)
    local output = text:find("assertion output", 1, true)
    local frame = text:find("test ", output, true)

    assert.truthy(failure and output and frame)
    assert.truthy(text:find("fail: outer fails", 1, true))
    assert.truthy(failure < output and output < frame)
  end)

  it("shows the cursor after finish and after abort", function()
    for _, close in ipairs({ "finish", "abort" }) do
      local out = helpers.fake_terminal()
      local view = live.new(out)
      local state = progress.new("test", 1)
      view.update(state)

      view[close](state, {
        title = "test",
        suites = {},
        passed = 0,
        failed = 0,
        duration = 0,
        interrupted = false,
      })

      assert.equal(live.show_cursor, out.writes[#out.writes], close)
    end
  end)

  it("writes no color without color support", function()
    local out = helpers.fake_terminal({ color = false })
    local view = live.new(out)
    local state = progress.new("test", 1)
    view.update(state)

    assert.is_nil(out.text():find("\27%[%d+m"))
  end)
end)
