-- Output targets and text helpers for the views.
local M = {}

M.default_width = 80

---@type table<string, string>
local styles = {
  bold = "1",
  dim = "2",
  red = "31",
  green = "32",
  yellow = "33",
  cyan = "36",
}

---@return boolean
local function color_allowed()
  return vim.env.NO_COLOR == nil or vim.env.NO_COLOR == ""
end

-- Writes through a libuv TTY handle. libuv translates VT sequences on a
-- Windows console without VT mode, so both platforms share one path.
---@return Telemetry.Terminal
local function tty_terminal()
  local tty = assert(vim.uv.new_tty(1, false))
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
    vim.wait(1000, function()
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
---@return Telemetry.Terminal
function M.stdout()
  if vim.uv.guess_handle(1) == "tty" then
    return tty_terminal()
  end

  return stream_terminal()
end

-- Wraps text in an SGR sequence when the terminal accepts color.
---@param terminal Telemetry.Terminal
---@param style "bold"|"dim"|"red"|"green"|"yellow"|"cyan"
---@param text string
---@return string
function M.paint(terminal, style, text)
  if not terminal.color or text == "" then
    return text
  end

  return "\27[" .. styles[style] .. "m" .. text .. "\27[0m"
end

-- Removes SGR and other CSI sequences, such as Plenary's colors.
---@param text string
---@return string
function M.strip(text)
  return (text:gsub("\27%[[%d;?]*[%a]", ""))
end

-- Cuts text to a display width. Wide characters count as two columns.
---@param text string Text without escape sequences.
---@param width integer
---@return string
function M.truncate(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end

  if width <= 1 then
    return string.rep(".", math.max(width, 0))
  end

  local length = math.min(vim.fn.strchars(text), width)
  local cut = vim.fn.strcharpart(text, 0, length)

  while length > 0 and vim.fn.strdisplaywidth(cut) > width - 1 do
    length = length - 1
    cut = vim.fn.strcharpart(text, 0, length)
  end

  return cut .. "…"
end

---@class Telemetry.Segment
---@field [1] string Text without escape sequences.
---@field [2]? "bold"|"dim"|"red"|"green"|"yellow"|"cyan" Style.

-- Joins styled segments into one line of at most `width` columns. The cut
-- happens on plain text, so escape sequences never count as columns.
---@param terminal Telemetry.Terminal
---@param segments Telemetry.Segment[]
---@param width integer
---@return string
function M.fit(terminal, segments, width)
  local parts = {}
  local remaining = width

  for _, segment in ipairs(segments) do
    local text, style = segment[1], segment[2]
    local columns = vim.fn.strdisplaywidth(text)
    local cut = columns > remaining

    if cut then
      text = M.truncate(text, remaining)
    end

    parts[#parts + 1] = style and M.paint(terminal, style, text) or text
    remaining = remaining - columns

    if cut or remaining <= 0 then
      break
    end
  end

  return table.concat(parts)
end

-- Formats seconds as "12.3s" or "4m05s".
---@param seconds number
---@return string
function M.duration(seconds)
  if seconds < 60 then
    return string.format("%.1fs", seconds)
  end

  return string.format("%dm%02ds", math.floor(seconds / 60), seconds % 60)
end

return M
