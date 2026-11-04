-- Shared spec helpers: a recording terminal and suite results.
local M = {}

---@class Telemetry.FakeTerminal: Telemetry.Terminal
---@field writes string[] Every write, in order.
---@field text fun(): string All writes joined.

---@param fields? { width?: integer, tty?: boolean, color?: boolean }
---@return Telemetry.FakeTerminal
function M.fake_terminal(fields)
  fields = fields or {}
  local writes = {}

  return {
    writes = writes,
    text = function()
      return table.concat(writes)
    end,
    write = function(text)
      writes[#writes + 1] = text
    end,
    width = function()
      return fields.width or 40
    end,
    tty = fields.tty ~= false,
    color = fields.color ~= false,
  }
end

---@param fields table Fields that replace the passing defaults.
---@return Telemetry.SuiteResult
function M.suite_result(fields)
  return vim.tbl_extend("force", {
    name = "tests/example_spec.lua",
    status = "pass",
    code = 0,
    signal = 0,
    duration = 1.25,
    output = "",
    tests = {},
  }, fields)
end

-- Runs a function with environment variables set, then restores them.
---@param values table<string, string|false> False removes a variable.
---@param body fun()
function M.with_env(values, body)
  local saved = {}

  for name, value in pairs(values) do
    saved[name] = vim.env[name] or false
    vim.env[name] = value or nil
  end

  local ok, err = pcall(body)

  for name, value in pairs(saved) do
    vim.env[name] = value or nil
  end

  assert(ok, err)
end

return M
