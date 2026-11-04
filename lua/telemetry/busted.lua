-- Report Plenary busted tests to the telemetry runner.
--
-- Call install() after Plenary loads and before the spec file runs. It wraps
-- `describe` to track the description path and `it` to report each test.
-- Plenary still catches each failure and prints its own message.
local event = require("telemetry.event")

local M = {}

local installed = false

---@param busted table Plenary busted module.
---@param stack string[] Description path of the running block.
local function wrap_describe(busted, stack)
  for _, field in ipairs({ "describe", "inner_describe" }) do
    local original = busted[field]

    busted[field] = function(desc, body)
      stack[#stack + 1] = desc
      original(desc, body)
      stack[#stack] = nil
    end
  end

  _G.describe = busted.describe
end

---@param busted table Plenary busted module.
---@param stack string[] Description path of the running block.
local function wrap_it(busted, stack)
  local original = busted.it

  busted.it = function(desc, body)
    local name =
      table.concat(vim.list_extend(vim.list_slice(stack), { desc }), " ")
    local passed = false

    event.start(name)

    -- A body error skips the flag. Plenary catches the error itself, so
    -- this wrapper neither catches nor raises it again.
    original(desc, function()
      body()
      passed = true
    end)

    event.finish(name, passed and "pass" or "fail")
  end

  _G.it = busted.it
end

-- Installs the wrappers once. A test whose `before_each` raises an error
-- reports no end event; the runner counts it as an error.
function M.install()
  local busted = require("plenary.busted")

  if installed then
    return
  end

  ---@type string[]
  local stack = {}
  wrap_describe(busted, stack)
  wrap_it(busted, stack)
  installed = true
end

return M
