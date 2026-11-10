-- Run the specs through telemetry. Each spec runs in its own process.
--
-- Usage: <lua> scripts/test.lua <group> [pattern] [child]
--
-- <lua> is `nvim -l`, or LuaJIT or Lua 5.1 to 5.4 with luv. The groups:
--   core  plain Lua specs on a fake host; [child] picks their interpreter
--   host  host specs on real processes, under the runner's interpreter
--   nvim  Plenary specs for the busted adapter, under Neovim only
--   all   every group under Neovim
local source = debug.getinfo(1, "S").source:sub(2):gsub("\\", "/")
local relative = source:match("^(.*)/scripts/[^/]*$") or "."
package.path = relative
  .. "/?.lua;"
  .. relative
  .. "/lua/?.lua;"
  .. relative
  .. "/lua/?/init.lua;"
  .. package.path

local unpack = table.unpack or unpack

local fs = require("tests.support.fs")
local interpreter = require("tests.support.interpreter")
local telemetry = require("telemetry")

local root = relative
if not (root:match("^/") or root:match("^%a:")) then
  root = interpreter.uv().cwd():gsub("\\", "/") .. "/" .. root:gsub("^%./?", "")
end
root = root:gsub("/$", "")

local group, pattern, child = arg[1] or "all", arg[2], arg[3]
pattern = pattern ~= "" and pattern or nil
child = child ~= "" and child or nil

-- Child processes find the repo modules through LUA_PATH. The trailing ";;"
-- keeps each interpreter's default path.
---@return table<string, string>
local function child_env()
  local path = root
    .. "/?.lua;"
    .. root
    .. "/lua/?.lua;"
    .. root
    .. "/lua/?/init.lua;"
  local env = { TELEMETRY_REPOSITORY = root }

  for _, name in ipairs({ "LUA_PATH", "LUA_PATH_5_4", "LUA_PATH_5_5" }) do
    env[name] = path .. (os.getenv(name) or ";")
  end

  return env
end

-- A spec that reports no test ran nothing, for example after a load error.
---@param result Telemetry.SuiteResult
---@return string?
local function check(result)
  if #result.tests == 0 then
    return "the spec reported no tests"
  end
end

---@param name string Group directory below tests/.
---@return string[] argv prefix
local function command(name)
  if name == "nvim" then
    local nvim = interpreter.command()[1]
    return {
      nvim,
      "--headless",
      "--noplugin",
      "-i",
      "NONE",
      "-u",
      "tests/nvim/minimal_init.lua",
      "-l",
      "tests/nvim/busted.lua",
    }
  elseif name == "core" and child then
    return { child }
  end

  return interpreter.command()
end

---@param name string
---@param suites Telemetry.Suite[]
local function add_group(name, suites)
  local prefix = command(name)

  for _, file in ipairs(fs.files(root .. "/tests/" .. name)) do
    local path = "tests/" .. name .. "/" .. file

    if
      file:match("_spec%.lua$") and (not pattern or path:find(pattern, 1, true))
    then
      local argv = { unpack(prefix) }
      argv[#argv + 1] = path
      suites[#suites + 1] = {
        name = path,
        cwd = root,
        env = child_env(),
        check = check,
        argv = argv,
      }
    end
  end
end

local groups = group == "all" and { "core", "host", "nvim" } or { group }
---@type Telemetry.Suite[]
local suites = {}
for _, name in ipairs(groups) do
  add_group(name, suites)
end
assert(#suites > 0, "no specs match " .. group .. " " .. tostring(pattern))

telemetry.exit(
  telemetry.run({ title = group == "all" and "test" or group, suites = suites })
)
