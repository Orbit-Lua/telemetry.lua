local protocol = require("telemetry.protocol")

---@param env table<string, string>
---@return Telemetry.Event[] events
---@return string output Lines that are not events.
local function run_fixture(env)
  local result = vim
    .system({
      vim.v.progpath,
      "--headless",
      "--noplugin",
      "-i",
      "NONE",
      "-u",
      "tests/nvim/minimal_init.lua",
      "-l",
      "tests/nvim/fixtures/busted_child.lua",
      "tests/nvim/fixtures/busted_cases.lua",
    }, { env = env, text = true })
    :wait(30000)

  local events, output = {}, {}

  for _, line in ipairs(vim.split(result.stdout or "", "\r?\n")) do
    local decoded = protocol.decode(line)

    if decoded then
      events[#events + 1] = decoded
    else
      output[#output + 1] = line
    end
  end

  assert.equal(1, result.code, result.stderr)
  return events, table.concat(output, "\n")
end

describe("busted adapter", function()
  it("reports the start and end of each test", function()
    local events, output = run_fixture({ TELEMETRY_EVENTS = "1" })

    assert.same({
      { event = "test_start", name = "outer inner passes" },
      { event = "test_end", name = "outer inner passes", status = "pass" },
      { event = "test_start", name = "outer fails" },
      { event = "test_end", name = "outer fails", status = "fail" },
    }, events)
    assert.truthy(output:find("fixture failure message", 1, true))
  end)

  it("reports nothing without TELEMETRY_EVENTS", function()
    local events, output = run_fixture({ TELEMETRY_EVENTS = "" })

    assert.same({}, events)
    assert.truthy(output:find("outer fails", 1, true))
  end)
end)
