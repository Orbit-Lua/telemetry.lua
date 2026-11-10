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

t.test("the live view writes the frames of the previous release", function()
  t.equal(frames.live_40_color, render_live(40, true), "40 columns with color")
  t.equal(
    frames.live_40_mono,
    render_live(40, false),
    "40 columns without color"
  )
  t.equal(frames.live_24_color, render_live(24, true), "24 columns")
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
