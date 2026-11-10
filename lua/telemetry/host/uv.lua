-- Process control, clock and terminal on libuv, shared by the nvim and luv
-- hosts. Each host supplies a loop that runs libuv until a condition holds.
--
-- libuv callbacks may run in a fast context, as in Neovim. They only queue
-- output and set flags. The wait loop delivers output in a normal context.
local M = {}

-- Interval of the wait loop in milliseconds. It bounds the redraw rate.
M.poll_interval = 50

-- Milliseconds between SIGTERM and SIGKILL when a process group stops.
M.kill_grace = 2000

-- Milliseconds to wait for the pipes to close after the group was killed.
-- A grandchild that left the group could otherwise hold them open forever.
M.drain_limit = 5000

M.windows = package.config:sub(1, 1) == "\\"

---@class Telemetry.UvLoop
---@field wait fun(ms: integer, done: fun(): boolean) Runs libuv until done() returns true or ms pass.
---@field interrupted fun(): boolean True after Ctrl-C.

---@class Telemetry.UvProcess
---@field pid integer
---@field exited boolean
---@field code integer
---@field signal integer
---@field pipes table<"stdout"|"stderr", uv.uv_pipe_t>
---@field open integer Pipes that have not reached EOF.
---@field queue { [1]: "stdout"|"stderr", [2]: string }[] Output not yet given to the sink.

---@class Telemetry.UvHost
---@field uv table libuv binding: Neovim's uv module or luv.
---@field loop Telemetry.UvLoop
---@field current? Telemetry.UvProcess Running process.
local Host = {}
Host.__index = Host

local unpack = table.unpack or unpack

---@param name string
---@return string
local function env_key(name)
  return M.windows and name:upper() or name
end

-- Raw uv.spawn replaces the whole environment, so merge the inherited one.
---@param inherited table<string, string>
---@param added table<string, string>
---@return string[]
local function environment(inherited, added)
  local merged = {}

  for _, source in ipairs({ inherited, added }) do
    for name, value in pairs(source) do
      merged[env_key(name)] = name .. "=" .. value
    end
  end

  local list = {}
  for _, entry in pairs(merged) do
    list[#list + 1] = entry
  end

  return list
end

---@param process Telemetry.UvProcess
---@return boolean
local function finished(process)
  return process.exited and process.open == 0
end

---@param process Telemetry.UvProcess
local function close_pipes(process)
  for _, pipe in pairs(process.pipes) do
    if not pipe:is_closing() then
      pipe:close()
    end
  end

  process.open = 0
end

---@param process Telemetry.UvProcess
---@param sink Telemetry.ProcessSink
local function deliver(process, sink)
  local queue = process.queue
  process.queue = {}

  for _, item in ipairs(queue) do
    sink.output(item[1], item[2])
  end
end

---@param process Telemetry.UvProcess
---@param stream "stdout"|"stderr"
local function read(process, stream)
  local pipe = process.pipes[stream]

  pipe:read_start(function(_, data)
    if data then
      process.queue[#process.queue + 1] = { stream, data }
      return
    end

    pipe:read_stop()
    pipe:close()
    process.open = process.open - 1
  end)
end

-- Returns the value of a variable in the added environment, else in the
-- inherited one. Names compare case-insensitively on Windows.
---@param added table<string, string>
---@param name string
---@return string?
local function lookup(added, name)
  for key, value in pairs(added) do
    if env_key(key) == env_key(name) then
      return value
    end
  end

  return os.getenv(name)
end

-- libuv searches PATH only for .exe and .com files on Windows. Resolve
-- PATHEXT files, such as .cmd, to a full path first, as Neovim's exepath
-- does: a name without an extension never matches an extensionless file,
-- such as the shell shim that npm installs next to each .cmd file.
---@param command string
---@param env table<string, string> Added variables of the request.
---@return string
function Host:resolve(command, env)
  if not M.windows or command:find("[/\\]") then
    return command
  end

  local pathext = lookup(env, "PATHEXT") or ".COM;.EXE;.BAT;.CMD"
  local extensions = {}
  for extension in pathext:gmatch("[^;]+") do
    extensions[#extensions + 1] = extension
  end

  if command:find(".", 1, true) then
    table.insert(extensions, 1, "")
  end

  for directory in (lookup(env, "PATH") or ""):gmatch("[^;]+") do
    for _, extension in ipairs(extensions) do
      local path = directory .. "\\" .. command .. extension
      local stat = self.uv.fs_stat(path)

      if stat and stat.type == "file" then
        return path
      end
    end
  end

  return command
end

---@param request Telemetry.ProcessRequest
---@return Telemetry.UvProcess? process
---@return string? err
function Host:spawn(request)
  local uv = self.uv
  local pipes = { stdout = uv.new_pipe(false), stderr = uv.new_pipe(false) }
  ---@type Telemetry.UvProcess
  local process = {
    pid = 0,
    exited = false,
    code = -1,
    signal = 0,
    pipes = pipes,
    open = 2,
    queue = {},
  }
  local handle

  local ok, spawned, pid = pcall(
    uv.spawn,
    self:resolve(request.argv[1], request.env),
    {
      args = { unpack(request.argv, 2) },
      cwd = request.cwd,
      env = environment(uv.os_environ(), request.env),
      stdio = { nil, pipes.stdout, pipes.stderr },
      -- A detached POSIX child leads its own process group, so one kill
      -- reaches its grandchildren too.
      detached = not M.windows,
      hide = true,
    },
    function(code, signal)
      process.exited, process.code, process.signal = true, code, signal
      handle:close()
    end
  )

  if not ok or not spawned then
    pipes.stdout:close()
    pipes.stderr:close()
    return nil, tostring(ok and pid or spawned)
  end

  handle, process.pid = spawned, pid
  read(process, "stdout")
  read(process, "stderr")
  return process
end

---@param pid integer
function Host:taskkill(pid)
  local done = false
  local ok, handle = pcall(self.uv.spawn, "taskkill", {
    args = { "/T", "/F", "/PID", string.format("%d", math.floor(pid)) },
    hide = true,
  }, function()
    done = true
  end)

  if ok and handle then
    self.loop.wait(M.drain_limit, function()
      return done
    end)
    handle:close()
  end
end

-- Stops the process group: SIGTERM, then SIGKILL after the grace period.
-- SIGKILL also reaches group members that outlive the leader.
---@param process Telemetry.UvProcess
function Host:stop(process)
  if M.windows then
    self:taskkill(process.pid)
    return
  end

  local uv = self.uv
  pcall(uv.kill, -process.pid, "sigterm")

  -- Give the whole group the grace period, so that a grandchild's SIGTERM
  -- trap can finish after the leader exits. kill(-pid, 0) fails once no
  -- member is left.
  self.loop.wait(M.kill_grace, function()
    local ok, result = pcall(uv.kill, -process.pid, 0)
    return process.exited and not (ok and (result == 0 or result == true))
  end)
  pcall(uv.kill, -process.pid, "sigkill")
end

---@param process Telemetry.UvProcess
---@param request Telemetry.ProcessRequest
---@param sink Telemetry.ProcessSink
---@return Telemetry.ProcessExit
function Host:supervise(process, request, sink)
  local exit = { code = -1, signal = 0, timed_out = false, interrupted = false }
  -- The loop time goes stale while the loop is idle, such as during a
  -- previous suite's check. Refresh it so the timeout starts now.
  self.uv.update_time()
  local deadline = self.uv.now() + request.timeout

  while not finished(process) do
    self.loop.wait(M.poll_interval, function()
      return finished(process)
    end)
    deliver(process, sink)

    if sink.poll() or self.loop.interrupted() then
      exit.interrupted = true
    elseif self.uv.now() >= deadline then
      exit.timed_out = true
    end

    -- After a stop, return even when the process did not report its exit,
    -- as when taskkill fails. The exit code is then -1.
    if exit.interrupted or exit.timed_out then
      self:stop(process)
      self.loop.wait(M.drain_limit, function()
        return finished(process)
      end)
      close_pipes(process)
      break
    end
  end

  deliver(process, sink)
  exit.code = process.exited and process.code or -1
  exit.signal = process.signal
  return exit
end

---@param request Telemetry.ProcessRequest
---@param sink Telemetry.ProcessSink
---@return Telemetry.ProcessExit
function Host:execute(request, sink)
  local process, err = self:spawn(request)

  if not process then
    local message = string.format("cannot start %s: %s", request.argv[1], err)
    return {
      code = -1,
      signal = 0,
      timed_out = false,
      interrupted = false,
      error = message,
    }
  end

  self.current = process
  local ok, exit = pcall(self.supervise, self, process, request, sink)
  self.current = nil

  if not ok then
    self:stop(process)
    close_pipes(process)
    error(exit, 0)
  end

  return exit
end

-- Stops the running group, as on host exit. It waits through the grace
-- period, but not for the pipes: a grandchild outside the group could
-- hold them and block the exit.
function Host:abort()
  if self.current then
    self:stop(self.current)
  end
end

---@return number seconds
function Host:clock()
  return self.uv.hrtime() / 1e9
end

---@return Telemetry.Terminal
function Host:terminal()
  return require("telemetry.host.terminal").new(self.uv, self.loop)
end

---@param uv table libuv binding: Neovim's uv module or luv.
---@param loop Telemetry.UvLoop
---@return Telemetry.UvHost
function M.new(uv, loop)
  return setmetatable({ uv = uv, loop = loop }, Host)
end

return M
