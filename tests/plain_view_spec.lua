local helpers = require("tests.helpers")
local plain = require("telemetry.view.plain")
local progress = require("telemetry.state")

local failed = helpers.suite_result({
  status = "fail",
  code = 1,
  output = "\27[31mFail\27[0m\t||\touter fails",
})

---@param github string|false
---@return string
local function render(github)
  local out = helpers.fake_terminal({ tty = false, color = false })

  helpers.with_env({ GITHUB_ACTIONS = github }, function()
    local view = plain.new(out)
    local state = progress.new("test", 2)
    view.suite_finished(state, helpers.suite_result({}))
    view.suite_finished(state, failed)
    view.finish(state, {
      title = "test",
      suites = { helpers.suite_result({}), failed },
      passed = 1,
      failed = 1,
      duration = 2,
      interrupted = false,
    })
  end)

  return out.text()
end

describe("plain view", function()
  it("writes lines with no escape sequences", function()
    local text = render(false)

    assert.is_nil(text:find("\27", 1, true))
    assert.truthy(text:find("ok tests/example_spec.lua (1.2s)", 1, true))
    assert.truthy(
      text:find("FAIL tests/example_spec.lua (1.2s) exit=1", 1, true)
    )
    assert.truthy(text:find("Fail\t||\touter fails", 1, true))
    assert.truthy(text:find("1 of 2 test suites passed (2.0s).", 1, true))
    assert.is_nil(text:find("::group::", 1, true))
  end)

  it("folds failure output on GitHub Actions", function()
    local text = render("true")

    assert.truthy(
      text:find("::group::tests/example_spec.lua output\n", 1, true)
    )
    assert.truthy(
      text:find(
        "::endgroup::\n::error::tests/example_spec.lua failed\n",
        1,
        true
      )
    )
  end)
end)
