local fake = require("tests.support.fake")
local frames = require("tests.support.frames")
local live = require("telemetry.view.live")
local plain = require("telemetry.view.plain")
local progress = require("telemetry.state")
local t = require("tests.support.harness")
local text = require("telemetry.text")

---@param env table<string, string>
---@return fun(name: string): string?
local function getenv(env)
  return function(name)
    return env[name]
  end
end

-- A state 75.5 seconds into a run, with a CJK suite and test name.
---@param total integer
---@return Telemetry.State
local function running_state(total)
  local now = 0
  local state = progress.new("test", total, function()
    return now
  end)
  now = 75.5
  state.done, state.passed, state.failed = 2, 1, 1
  state.tests = { passed = 3, failed = 1 }
  progress.start_suite(state, "tests/中文名稱_spec.lua")
  state.test = "描述 a 很長的測試名稱 that is far wider than the view"
  return state
end

---@param width integer
---@param color boolean
---@return string
local function render_live(width, color)
  local out = fake.terminal({ width = width, color = color })
  local view = live.new(out)
  local state = running_state(4)
  view.update(state)
  view.update(state)
  view.suite_finished(
    state,
    fake.suite_result({
      name = "tests/失敗_spec.lua",
      status = "fail",
      code = 1,
      duration = 61.25,
      output = "\27[31mFail\27[0m line\nsecond",
      tests = { { name = "壞掉 test", status = "error" } },
      message = "timed out",
    })
  )
  view.finish(state, {
    title = "test",
    suites = {
      fake.suite_result({ name = "a" }),
      fake.suite_result({ name = "tests/失敗_spec.lua", status = "fail" }),
    },
    passed = 1,
    failed = 1,
    duration = 125.5,
    interrupted = true,
    host = "nvim",
  })
  return out.text()
end

---@param github boolean
---@return string
local function render_plain(github)
  local out = fake.terminal({ width = 80, tty = false, color = false })
  local view =
    plain.new(out, getenv(github and { GITHUB_ACTIONS = "true" } or {}))
  local state = progress.new("test", 2, os.clock)
  local timed_out = fake.suite_result({
    name = "tests/中文_spec.lua",
    status = "timeout",
    code = -1,
    signal = 9,
    duration = 3,
    output = "\27[31mFail\27[0m\t||\touter",
    tests = { { name = "x", status = "fail" } },
    message = "timed out after 300 ms",
  })
  view.suite_finished(state, fake.suite_result({ name = "tests/ok_spec.lua" }))
  view.suite_finished(state, timed_out)
  state.tests = { passed = 1, failed = 1 }
  view.finish(state, {
    title = "test",
    suites = { fake.suite_result({ name = "a" }), timed_out },
    passed = 1,
    failed = 1,
    duration = 4,
    interrupted = false,
    host = "nvim",
  })
  return out.text()
end

t.test(
  "the live view writes the expected completion and failure frames",
  function()
    t.equal(
      frames.live_40_color,
      render_live(40, true),
      "40 columns with color"
    )
    t.equal(
      frames.live_40_mono,
      render_live(40, false),
      "40 columns without color"
    )
    t.equal(frames.live_24_color, render_live(24, true), "24 columns")
  end
)

t.test("completed suite lines stay above subsequent live frames", function()
  local out = fake.terminal({ color = false })
  local view = live.new(out)
  local state = running_state(3)
  view.update(state)

  for _, status in ipairs({ "pass", "fail", "timeout" }) do
    local before = #out.writes
    view.suite_finished(
      state,
      fake.suite_result({ name = status, status = status })
    )
    t.equal("\27[4F\27[J", out.writes[before + 1])
    local label = status == "pass" and "ok" or status:upper()
    t.equal(label .. " " .. status .. " (1.2s)\n", out.writes[before + 2])
    local drawn = out.writes[before + 3]
    t.contains(drawn, "▶ tests/中文名稱_spec.lua")
    view.update(state)
    t.equal("\27[4F\27[J", out.writes[before + 4])
    t.equal(
      drawn,
      out.writes[before + 5],
      "only the four frame lines are replaced"
    )
  end
end)

t.test(
  "live failures are labeled and deferred until before the summary",
  function()
    local out = fake.terminal({ color = false })
    local view = live.new(out)
    local state = running_state(3)
    local results = {
      fake.suite_result({
        name = "broken",
        status = "fail",
        code = 1,
        output = "first diagnostic",
        tests = { { name = "bad case", status = "fail" } },
      }),
      fake.suite_result({
        name = "slow",
        status = "timeout",
        code = -1,
        output = "second diagnostic",
        message = "timed out",
      }),
      fake.suite_result({ name = "good", output = "hidden success output" }),
    }
    for _, result in ipairs(results) do
      view.suite_finished(state, result)
    end
    local before = out.text()
    t.equal(nil, before:find("diagnostic", 1, true))
    t.equal(nil, before:find("bad case", 1, true))
    t.equal(nil, before:find("timed out", 1, true))
    view.finish(state, {
      title = "test",
      suites = results,
      passed = 1,
      failed = 2,
      duration = 4,
      interrupted = false,
      host = "nvim",
    })
    local final = out.text():sub(#before + 1)
    t.contains(
      final,
      "\27[4F\27[JFAIL broken (1.2s) exit=1\nfirst diagnostic\n  fail: bad case\n"
    )
    t.contains(
      final,
      "TIMEOUT slow (1.2s) exit=-1\nsecond diagnostic\ntimed out\n1 of 3"
    )
    t.equal(nil, out.text():find("hidden success output", 1, true))
    t.equal(1, select(2, out.text():gsub("first diagnostic", "")))
    t.equal(1, select(2, out.text():gsub("second diagnostic", "")))
  end
)

t.test("abort emits deferred failures once across repeated cleanup", function()
  local out = fake.terminal({ color = false })
  local view = live.new(out)
  local state = running_state(1)
  view.suite_finished(
    state,
    fake.suite_result({ status = "fail", output = "diagnostic" })
  )
  t.equal(nil, out.text():find("diagnostic", 1, true))
  view.abort()
  t.contains(
    out.text(),
    "\27[4F\27[JFAIL tests/example_spec.lua (1.2s)\ndiagnostic\n"
  )
  view.abort()
  view.finish(state, {
    title = "test",
    suites = {},
    passed = 0,
    failed = 0,
    duration = 0,
    interrupted = true,
    host = "nvim",
  })
  t.equal(1, select(2, out.text():gsub("diagnostic", "")))
  t.equal(live.show_cursor, out.writes[#out.writes])
end)

t.test("the plain view writes the lines of the previous release", function()
  t.equal(frames.plain, render_plain(false), "outside GitHub Actions")
  t.equal(frames.plain_github, render_plain(true), "on GitHub Actions")
end)

t.test("each live frame line fits in the width minus one column", function()
  local out = fake.terminal({ width = 40 })
  live.new(out).update(running_state(4))

  for _, line in ipairs(text.lines(text.strip(out.text()))) do
    t.truthy(text.width(line) <= 39, line)
  end
end)

t.test("the live view shows the cursor after finish and after abort", function()
  for _, close in ipairs({ "finish", "abort" }) do
    local out = fake.terminal()
    local view = live.new(out)
    local state = running_state(1)
    view.update(state)
    view[close](state, {
      title = "test",
      suites = {},
      passed = 0,
      failed = 0,
      duration = 0,
      interrupted = false,
      host = "nvim",
    })

    t.equal(live.show_cursor, out.writes[#out.writes], close)
  end
end)

t.test("the plain view writes no escape sequences", function()
  t.equal(nil, render_plain(false):find("\27", 1, true))
end)

t.finish()
