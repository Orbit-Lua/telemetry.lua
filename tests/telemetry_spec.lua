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

-- Ends a parent run early and reports whether its child outlived it.
---@param how "quit"|"signal"
---@return vim.SystemCompleted result
---@return boolean survived True when the child wrote its marker file.
local function leave_during_run(how)
  local marker = vim.fn.tempname()
  local process = vim.system({
    vim.v.progpath,
    "--headless",
    "-u",
    "NONE",
    "-l",
    repository .. "/tests/fixtures/leave.lua",
    how,
    marker,
  }, { env = { TELEMETRY_REPOSITORY = repository }, text = true })

  if how == "signal" then
    vim.wait(1000)
    process:kill("sigint")
  end

  local result = process:wait(10000)
  vim.wait(2500)

  local survived = vim.fn.filereadable(marker) == 1
  vim.fn.delete(marker)
  return result, survived
end

describe("telemetry", function()
  it("stops the child and restores the cursor when Neovim exits", function()
    local result, survived = leave_during_run("quit")

    assert.is_false(survived)
    assert.truthy(result.stdout:find("\27[?25h", 1, true), result.stdout)
  end)

  -- Windows has no SIGINT delivery to one process; the user checks Ctrl-C.
  if vim.fn.has("win32") == 0 then
    it("stops the child and restores the cursor after SIGINT", function()
      local result, survived = leave_during_run("signal")

      assert.is_false(survived)
      assert.are_not.equal(0, result.code)
      assert.truthy(result.stdout:find("\27[?25h", 1, true), result.stdout)
    end)
  end

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
