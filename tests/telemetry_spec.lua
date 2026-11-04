local helpers = require("tests.helpers")
local telemetry = require("telemetry")

local repository = vim.fn.getcwd()

---@param mode string Child fixture mode.
---@return vim.SystemCompleted
local function run_exit_fixture(mode)
  return vim
    .system({
      vim.v.progpath,
      "--headless",
      "-u",
      "NONE",
      "-l",
      repository .. "/tests/fixtures/exit.lua",
      mode,
    }, { env = { TELEMETRY_REPOSITORY = repository }, text = true })
    :wait(30000)
end

describe("telemetry", function()
  it("exits 0 when every suite passes and 1 otherwise", function()
    local passed = run_exit_fixture("pass")
    local failed = run_exit_fixture("fail")

    assert.equal(0, passed.code, passed.stdout)
    assert.equal(1, failed.code, failed.stdout)
    assert.truthy(failed.stdout:find("broken output", 1, true))
  end)

  it("selects the mode from TELEMETRY_MODE, then the terminal", function()
    local tty = helpers.fake_terminal({ tty = true })
    local pipe = helpers.fake_terminal({ tty = false })
    local spec = { title = "test", suites = {} }

    helpers.with_env(
      { TELEMETRY_MODE = false, CI = false, GITHUB_ACTIONS = false },
      function()
        assert.equal("live", telemetry.resolve_mode(spec, tty))
        assert.equal("plain", telemetry.resolve_mode(spec, pipe))
      end
    )

    helpers.with_env({ TELEMETRY_MODE = false, CI = "true" }, function()
      assert.equal("plain", telemetry.resolve_mode(spec, tty))
    end)

    helpers.with_env({ TELEMETRY_MODE = "live" }, function()
      assert.equal("live", telemetry.resolve_mode(spec, pipe))
    end)

    helpers.with_env({ TELEMETRY_MODE = "plain" }, function()
      assert.equal("plain", telemetry.resolve_mode(spec, tty))
    end)
  end)

  it("restores the cursor when a suite check raises an error", function()
    local out = helpers.fake_terminal()
    local ok, err = pcall(telemetry.run, {
      title = "test",
      mode = "live",
      terminal = out,
      suites = {
        {
          name = "check error",
          argv = { vim.v.progpath, "--headless", "-u", "NONE", "-c", "qa!" },
          check = function()
            error("broken check")
          end,
        },
      },
    })

    assert.is_false(ok)
    assert.truthy(tostring(err):find("broken check", 1, true))
    assert.equal("\27[?25h", out.writes[#out.writes])
  end)

  it("rejects an empty suite list with the field path", function()
    local ok, err = pcall(telemetry.run, { title = "test", suites = {} })

    assert.is_false(ok)
    assert.truthy(tostring(err):find("spec.suites", 1, true))
  end)
end)
