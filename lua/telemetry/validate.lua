-- Check a run spec before it starts. Each error names the field path, such
-- as "spec.suites[2].argv", so that a caller finds the wrong field.
local M = {}

---@type table<Telemetry.Mode, true>
M.modes = { auto = true, live = true, plain = true }

---@type table<Telemetry.HostName, true>
M.hosts = { auto = true, nvim = true, luv = true }

---@param path string
---@param expected string
---@param value any
local function fail(path, expected, value)
  error(string.format("%s: expected %s, got %s", path, expected, type(value)), 0)
end

---@param path string
---@param value any
---@param kind type
---@param optional? boolean
local function check(path, value, kind, optional)
  if (value == nil and optional) or type(value) == kind then
    return
  end

  fail(path, kind, value)
end

---@param path string
---@param value any
---@param allowed table<string, true>
---@param expected string
local function check_choice(path, value, allowed, expected)
  if value ~= nil and not allowed[value] then
    error(string.format("%s: expected %s, got %s", path, expected, tostring(value)), 0)
  end
end

-- Neovim's process API accepted numbers in argv and env, so they stay valid.
---@param path string
---@param value any
local function check_text(path, value)
  if type(value) ~= "string" and type(value) ~= "number" then
    fail(path, "string", value)
  end
end

---@param path string
---@param argv any
local function check_argv(path, argv)
  if type(argv) ~= "table" or #argv == 0 then
    fail(path, "a non-empty list of strings", argv)
  end

  for index, item in ipairs(argv) do
    check_text(string.format("%s[%d]", path, index), item)
  end
end

---@param path string
---@param env any
local function check_env(path, env)
  check(path, env, "table", true)

  for name, value in pairs(env or {}) do
    check_text(path .. "." .. tostring(name), value)
  end
end

---@param path string
---@param suite any
local function check_suite(path, suite)
  check(path, suite, "table")
  check(path .. ".name", suite.name, "string")
  check_argv(path .. ".argv", suite.argv)
  check(path .. ".cwd", suite.cwd, "string", true)
  check_env(path .. ".env", suite.env)
  local timeout = suite.timeout
  if
    timeout ~= nil
    and (
      type(timeout) ~= "number"
      or timeout < 1
      or timeout ~= math.floor(timeout)
    )
  then
    fail(path .. ".timeout", "a positive integer", timeout)
  end
  check(path .. ".check", suite.check, "function", true)
end

-- Raises an error for the first invalid field of the spec.
---@param spec Telemetry.Spec
function M.spec(spec)
  check("spec", spec, "table")
  check("spec.title", spec.title, "string")

  if type(spec.suites) ~= "table" or #spec.suites == 0 then
    fail("spec.suites", "a non-empty list", spec.suites)
  end

  check_choice("spec.mode", spec.mode, M.modes, "auto, live or plain")
  check_choice("spec.host", spec.host, M.hosts, "auto, nvim or luv")
  check("spec.terminal", spec.terminal, "table", true)

  for index, suite in ipairs(spec.suites) do
    check_suite(string.format("spec.suites[%d]", index), suite)
  end
end

return M
