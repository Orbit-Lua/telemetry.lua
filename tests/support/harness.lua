-- A small test runner for plain Lua specs, built on telemetry.event. It runs
-- under Neovim, LuaJIT and Lua 5.1 to 5.5 without other libraries.
--
--   local t = require("tests.support.harness")
--   t.test("adds", function() t.equal(2, 1 + 1) end)
--   t.finish()
local event = require("telemetry.event")

local M = {}

local count = 0
local failed = 0

-- Runs one test and prints its failure on standard error.
---@param name string
---@param body fun()
function M.test(name, body)
  count = count + 1
  local ok, err = event.test(name, body)

  if not ok then
    failed = failed + 1
    io.stderr:write("FAIL ", name, "\n", tostring(err), "\n")
  end
end

---@param value any
---@return string
local function show(value)
  if type(value) == "string" then
    return string.format("%q", value)
  end

  return tostring(value)
end

---@param message? string
---@param text string
local function raise(message, text)
  error((message and (message .. ": ") or "") .. text, 3)
end

---@param expected any
---@param actual any
---@param message? string
function M.equal(expected, actual, message)
  if expected ~= actual then
    raise(message, "expected " .. show(expected) .. ", got " .. show(actual))
  end
end

---@param expected any
---@param actual any
---@param path string
---@return string? difference
local function differ(expected, actual, path)
  if type(expected) ~= "table" or type(actual) ~= "table" then
    if expected ~= actual then
      return string.format(
        "%s: expected %s, got %s",
        path,
        show(expected),
        show(actual)
      )
    end

    return nil
  end

  for key, value in pairs(expected) do
    local difference = differ(value, actual[key], path .. "." .. tostring(key))
    if difference then
      return difference
    end
  end

  for key in pairs(actual) do
    if expected[key] == nil then
      return path .. "." .. tostring(key) .. ": unexpected field"
    end
  end
end

-- Compares tables by value.
---@param expected any
---@param actual any
---@param message? string
function M.same(expected, actual, message)
  local difference = differ(expected, actual, "value")

  if difference then
    raise(message, difference)
  end
end

---@param value any
---@param message? string
function M.truthy(value, message)
  if not value then
    raise(message, "expected a true value, got " .. show(value))
  end
end

-- Checks that text contains a plain substring.
---@param text string
---@param part string
---@param message? string
function M.contains(text, part, message)
  if type(text) ~= "string" or not text:find(part, 1, true) then
    raise(message, show(part) .. " not found in " .. show(text))
  end
end

-- Calls a function that must raise an error and returns the message.
---@param body fun()
---@return string
function M.raises(body)
  local ok, err = pcall(body)

  if ok then
    raise(nil, "expected an error")
  end

  return tostring(err)
end

-- Exits with 1 when a test failed or when no test ran.
function M.finish()
  if count == 0 then
    io.stderr:write("no tests ran\n")
    os.exit(1)
  end

  os.exit(failed == 0 and 0 or 1)
end

return M
