-- The standard output terminal on libuv.
local M = {}

M.default_width = 80

---@return boolean
local function color_allowed()
  local value = os.getenv("NO_COLOR")
  return value == nil or value == ""
end

-- Writes through a libuv TTY handle. libuv translates VT sequences on a
-- Windows console without VT mode, so both platforms share one path.
---@param uv table
---@param loop Telemetry.UvLoop
---@return Telemetry.Terminal
local function tty_terminal(uv, loop)
  local tty = assert(uv.new_tty(1, false))
  local pending = 0

  local function write(text)
    pending = pending + 1
    tty:write(text, function()
      pending = pending - 1
    end)
  end

  local function width()
    local columns = tty:get_winsize()
    return (columns and columns > 0) and columns or M.default_width
  end

  -- Writes are asynchronous; wait for them so that an exit loses no text.
  local function close()
    loop.wait(1000, function()
      return pending == 0
    end)
    tty:close()
  end

  return {
    write = write,
    width = width,
    tty = true,
    color = color_allowed(),
    close = close,
  }
end

---@return Telemetry.Terminal
local function stream_terminal()
  return {
    write = function(text)
      io.stdout:write(text)
      io.stdout:flush()
    end,
    width = function()
      return M.default_width
    end,
    tty = false,
    color = false,
  }
end

-- Returns the terminal of standard output.
---@param uv table libuv binding.
---@param loop Telemetry.UvLoop
---@return Telemetry.Terminal
function M.new(uv, loop)
  if uv.guess_handle(1) == "tty" then
    return tty_terminal(uv, loop)
  end

  return stream_terminal()
end

return M
