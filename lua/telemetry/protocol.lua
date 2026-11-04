-- Exchange test events between a child process and the runner.
--
-- A child writes each event as one line on standard output: the record
-- separator byte, the word "telemetry", a space and a JSON object. The runner
-- removes these lines from the captured output. Every function here is safe
-- in a fast event context.
local M = {}

M.prefix = "\30telemetry "

---@type table<string, true>
local events = { test_start = true, test_end = true }

---@type table<string, true>
local statuses = { pass = true, fail = true, error = true }

---@param event Telemetry.Event
---@return string line Encoded line with its newline.
function M.encode(event)
  return M.prefix .. vim.json.encode(event) .. "\n"
end

---@param value any
---@return boolean
local function is_event(value)
  if type(value) ~= "table" or not events[value.event] then
    return false
  end

  if type(value.name) ~= "string" then
    return false
  end

  if value.event == "test_end" then
    return statuses[value.status] == true
  end

  return value.status == nil
end

-- Returns nil for a line that is not an event, including a malformed one,
-- so that the caller keeps it as ordinary output.
---@param line string Line without its newline.
---@return Telemetry.Event?
function M.decode(line)
  if line:sub(1, #M.prefix) ~= M.prefix then
    return nil
  end

  local ok, value = pcall(vim.json.decode, line:sub(#M.prefix + 1))

  if ok and is_event(value) then
    return value
  end

  return nil
end

---@class Telemetry.LineSplitter
---@field feed fun(chunk: string) Adds a chunk of output.
---@field flush fun() Emits a final line without a newline.

-- Splits a stream of chunks into lines. A line can span several chunks.
---@param on_line fun(line: string, newline: boolean) Receives each line without its "\r\n" or "\n".
---@return Telemetry.LineSplitter
function M.splitter(on_line)
  local pending = ""

  local function feed(chunk)
    pending = pending .. chunk

    while true do
      local stop = pending:find("\n", 1, true)

      if not stop then
        return
      end

      local line = pending:sub(1, stop - 1):gsub("\r$", "")
      pending = pending:sub(stop + 1)
      on_line(line, true)
    end
  end

  local function flush()
    if pending ~= "" then
      local line = pending
      pending = ""
      on_line(line, false)
    end
  end

  return { feed = feed, flush = flush }
end

return M
