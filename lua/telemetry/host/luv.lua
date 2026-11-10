-- Host for LuaJIT and Lua 5.1 to 5.4 with the luv library. A repeating
-- timer makes each uv.run("once") return within the poll interval, so polls,
-- timeouts and redraws continue while a child is silent.
local uv = require("luv")
local uv_host = require("telemetry.host.uv")

local interrupted = false
local timer = assert(uv.new_timer())

local function noop() end

---@type Telemetry.UvLoop
local loop = {
  wait = function(ms, done)
    uv.update_time()
    local deadline = uv.now() + ms
    timer:start(uv_host.poll_interval, uv_host.poll_interval, noop)

    while not done() and uv.now() < deadline do
      uv.run("once")
    end

    timer:stop()
  end,
  interrupted = function()
    return interrupted
  end,
}

local host = uv_host.new(uv, loop)

-- Signals that end the run: Ctrl-C, `kill`, and a closed terminal. The
-- suite runs in its own process group, so it receives none of them itself.
local stop_signals = { "sigint", "sigterm", "sighup" }

-- A stop signal sets a flag. The running suite then stops its process
-- group, and the run ends with result.interrupted, which exits with 130.
-- The handler cannot stop the group itself: libuv cannot re-enter uv.run
-- from a callback.
---@param _ fun() Unused: the run loop restores the terminal itself.
---@return fun() remove
local function guard(_)
  interrupted = false
  local handles = {}

  for _, name in ipairs(stop_signals) do
    local signal = assert(uv.new_signal())

    -- Windows has no SIGTERM. luv returns nil for a signal that libuv
    -- cannot watch; older versions raise an error instead.
    local ok, started = pcall(signal.start, signal, name, function()
      interrupted = true
    end)

    if ok and started then
      handles[#handles + 1] = signal
    else
      signal:close()
    end
  end

  return function()
    for _, signal in ipairs(handles) do
      signal:stop()
      signal:close()
    end

    uv.run("nowait")
  end
end

---@type Telemetry.Host
return {
  name = "luv",
  getenv = os.getenv,
  clock = function()
    return host:clock()
  end,
  terminal = function()
    return host:terminal()
  end,
  execute = function(request, sink)
    return host:execute(request, sink)
  end,
  guard = guard,
  -- Run pending callbacks first: a signal that arrived during blocking
  -- work, such as a suite check, reaches its handler only in uv.run.
  interrupted = function()
    uv.run("nowait")
    return interrupted
  end,
}
