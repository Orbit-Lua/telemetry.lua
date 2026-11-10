-- Helpers for the host specs: fixture commands, pid files and liveness.
local interpreter = require("tests.support.interpreter")

local M = {}

M.root = assert(
  os.getenv("TELEMETRY_REPOSITORY"),
  "run the specs through scripts/test.lua"
)
M.windows = package.config:sub(1, 1) == "\\"
M.uv = interpreter.uv()

-- Returns argv that runs a fixture file with the current interpreter.
---@param fixture string File name below tests/fixtures/.
---@param ... string Fixture arguments.
---@return string[]
function M.fixture(fixture, ...)
  local argv = interpreter.command()
  argv[#argv + 1] = M.root .. "/tests/fixtures/" .. fixture

  for _, value in ipairs({ ... }) do
    argv[#argv + 1] = value
  end

  return argv
end

---@return string
function M.tempname()
  return M.uv.os_tmpdir():gsub("\\", "/")
    .. "/telemetry-"
    .. M.uv.os_getpid()
    .. "-"
    .. M.uv.hrtime()
end

-- Reads the pids that a fixture wrote, separated by spaces.
---@param path string
---@return integer[]
function M.read_pids(path)
  local file = io.open(path, "r")
  local pids = {}

  if file then
    for pid in file:read("*a"):gmatch("%d+") do
      pids[#pids + 1] = tonumber(pid)
    end
    file:close()
  end

  return pids
end

---@param pid integer
---@return boolean
local function exists(pid)
  local result = M.uv.kill(pid, 0)
  return result == 0 or result == true
end

-- Returns true when the process still exists after two seconds. A killed
-- orphan stays a zombie until its new parent reaps it, and a zombie exists.
---@param pid integer
---@return boolean
function M.alive(pid)
  for _ = 1, 100 do
    if not exists(pid) then
      return false
    end

    M.uv.sleep(20)
  end

  return true
end

return M
