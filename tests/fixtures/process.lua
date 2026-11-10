-- Child process for the host specs. The first argument selects a behavior.
-- Usage: <lua> tests/fixtures/process.lua <mode> [arguments]
local event = require("telemetry.event")
local interpreter = require("tests.support.interpreter")

local unpack = table.unpack or unpack
local uv = interpreter.uv()

---@param path string
---@param text string
local function write_file(path, text)
  local file = assert(io.open(path, "w"))
  file:write(text)
  file:close()
end

-- Starts a grandchild that shares this process's stdout and stderr, so it
-- holds the runner's pipes open. Writes "<pid> <grandchild pid>" to a file.
---@param command string
---@param args string[]
---@param pidfile string
local function spawn_holder(command, args, pidfile)
  local handle, pid = uv.spawn(
    command,
    { args = args, stdio = { nil, 1, 2 } },
    function() end
  )
  assert(handle, pid)
  write_file(
    pidfile,
    string.format("%d %d", math.floor(uv.os_getpid()), math.floor(pid))
  )
end

---@type table<string, fun(...: string)>
local modes = {
  exit = function(code)
    io.stdout:write("out\n")
    io.stdout:flush()
    os.exit(tonumber(code))
  end,

  order = function()
    for _, item in ipairs({
      { io.stdout, "a" },
      { io.stderr, "b" },
      { io.stdout, "c" },
    }) do
      item[1]:write(item[2], "\n")
      item[1]:flush()
      uv.sleep(100)
    end
  end,

  -- A partial stderr line around a stdout event line.
  split = function()
    io.stderr:write("err-")
    io.stderr:flush()
    uv.sleep(100)
    event.test("first", function() end)
    uv.sleep(100)
    io.stderr:write("part\n")
  end,

  env = function(...)
    for _, name in ipairs({ ... }) do
      io.stdout:write(name, "=", tostring(os.getenv(name)), "\n")
    end
  end,

  cwd = function()
    io.stdout:write(uv.fs_realpath(uv.cwd()), "\n")
  end,

  events = function()
    event.test("passes", function() end)
    event.test("fails", function()
      error("expected failure")
    end)
  end,

  touch = function(path)
    write_file(path, "started")
  end,

  nap = function(ms)
    uv.sleep(tonumber(ms))
  end,

  -- POSIX only: a grandchild whose SIGTERM trap writes <marker> after one
  -- second. This process exits at once, so only the grandchild holds the
  -- pipes when the runner stops the group.
  trap = function(pidfile, marker)
    local script =
      'trap "sleep 1; touch \\"$0\\"; exit" TERM; while :; do sleep 0.1; done'
    spawn_holder("sh", { "-c", script, marker }, pidfile)
  end,

  sleep = function()
    uv.sleep(30000)
  end,

  hold = function(pidfile)
    local command = interpreter.command()
    local args = { unpack(command, 2) }
    args[#args + 1] = arg[0]
    args[#args + 1] = "sleep"
    spawn_holder(command[1], args, pidfile)
    uv.sleep(30000)
  end,

  -- POSIX only: the grandchild ignores SIGTERM, so only SIGKILL stops it.
  stubborn = function(pidfile)
    spawn_holder("sh", { "-c", "trap '' TERM; sleep 30" }, pidfile)
    uv.sleep(30000)
  end,
}

local mode = assert(modes[arg[1]], "unknown mode: " .. tostring(arg[1]))
mode(select(2, unpack(arg)))
