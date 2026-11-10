-- Encode and decode JSON without a host library. The encoder writes flat
-- objects of strings, numbers and booleans with sorted keys. The decoder
-- reads any JSON value and returns nil and a message for invalid text.
local M = {}

---@type table<string, string>
local escapes = {
  ['"'] = '\\"',
  ["\\"] = "\\\\",
  ["\b"] = "\\b",
  ["\f"] = "\\f",
  ["\n"] = "\\n",
  ["\r"] = "\\r",
  ["\t"] = "\\t",
}

---@param text string
---@return string
local function quote(text)
  local escaped = text:gsub('[%c"\\]', function(char)
    return escapes[char] or string.format("\\u%04x", char:byte())
  end)

  return '"' .. escaped .. '"'
end

---@param value string|number|boolean
---@return string
local function scalar(value)
  local kind = type(value)

  if kind == "string" then
    return quote(value)
  elseif kind == "boolean" then
    return tostring(value)
  elseif kind == "number" and value == value and value ~= math.huge and value ~= -math.huge then
    if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
      return string.format("%d", value)
    end

    return string.format("%.17g", value)
  end

  error("json: cannot encode a " .. kind, 2)
end

-- Encodes a table of string keys and scalar values as one JSON object.
---@param object table<string, string|number|boolean>
---@return string
function M.encode(object)
  local keys = {}

  for key in pairs(object) do
    keys[#keys + 1] = key
  end

  table.sort(keys)

  local fields = {}
  for _, key in ipairs(keys) do
    fields[#fields + 1] = quote(key) .. ":" .. scalar(object[key])
  end

  return "{" .. table.concat(fields, ",") .. "}"
end

-- Encodes a code point as UTF-8 without the utf8 library or bit operators.
---@param code integer
---@return string
local function utf8_char(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
  elseif code < 0x10000 then
    return string.char(
      0xE0 + math.floor(code / 0x1000),
      0x80 + math.floor(code / 0x40) % 0x40,
      0x80 + code % 0x40
    )
  end

  return string.char(
    0xF0 + math.floor(code / 0x40000),
    0x80 + math.floor(code / 0x1000) % 0x40,
    0x80 + math.floor(code / 0x40) % 0x40,
    0x80 + code % 0x40
  )
end

---@class Telemetry.JsonReader
---@field text string
---@field at integer Position of the next character.

local simple = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

---@param reader Telemetry.JsonReader
---@return integer
local function hex4(reader)
  local digits = reader.text:sub(reader.at, reader.at + 3)

  if not digits:match("^%x%x%x%x$") then
    error("invalid \\u escape", 0)
  end

  reader.at = reader.at + 4
  return tonumber(digits, 16)
end

-- Reads one \u escape after its backslash and "u", with a surrogate pair.
---@param reader Telemetry.JsonReader
---@return string
local function unicode(reader)
  local code = hex4(reader)

  if code >= 0xD800 and code <= 0xDBFF then
    if reader.text:sub(reader.at, reader.at + 1) ~= "\\u" then
      error("unpaired surrogate", 0)
    end

    reader.at = reader.at + 2
    local low = hex4(reader)

    if low < 0xDC00 or low > 0xDFFF then
      error("invalid surrogate pair", 0)
    end

    code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
  elseif code >= 0xDC00 and code <= 0xDFFF then
    error("unpaired surrogate", 0)
  end

  return utf8_char(code)
end

---@param reader Telemetry.JsonReader
---@return string
local function read_string(reader)
  local parts = {}
  reader.at = reader.at + 1

  while true do
    local start = reader.at
    local stop = reader.text:find('["\\%c]', start)

    if not stop then
      error("unterminated string", 0)
    end

    parts[#parts + 1] = reader.text:sub(start, stop - 1)
    local char = reader.text:sub(stop, stop)
    reader.at = stop + 1

    if char == '"' then
      return table.concat(parts)
    elseif char ~= "\\" then
      error("control character in string", 0)
    end

    local kind = reader.text:sub(reader.at, reader.at)
    reader.at = reader.at + 1

    if kind == "u" then
      parts[#parts + 1] = unicode(reader)
    elseif simple[kind] then
      parts[#parts + 1] = simple[kind]
    else
      error("invalid escape", 0)
    end
  end
end

---@param reader Telemetry.JsonReader
local function skip_space(reader)
  reader.at = reader.text:find("[^ \t\r\n]", reader.at) or #reader.text + 1
end

local read_value

---@param reader Telemetry.JsonReader
---@param close string
---@param read_item fun()
local function read_sequence(reader, close, read_item)
  reader.at = reader.at + 1
  skip_space(reader)

  if reader.text:sub(reader.at, reader.at) == close then
    reader.at = reader.at + 1
    return
  end

  while true do
    read_item()
    skip_space(reader)
    local char = reader.text:sub(reader.at, reader.at)
    reader.at = reader.at + 1

    if char == close then
      return
    elseif char ~= "," then
      error("expected ',' or '" .. close .. "'", 0)
    end

    skip_space(reader)
  end
end

---@param reader Telemetry.JsonReader
---@return table
local function read_object(reader)
  local object = {}

  read_sequence(reader, "}", function()
    if reader.text:sub(reader.at, reader.at) ~= '"' then
      error("expected a key", 0)
    end

    local key = read_string(reader)
    skip_space(reader)

    if reader.text:sub(reader.at, reader.at) ~= ":" then
      error("expected ':'", 0)
    end

    reader.at = reader.at + 1
    skip_space(reader)
    object[key] = read_value(reader)
  end)

  return object
end

---@param reader Telemetry.JsonReader
---@return any[]
local function read_array(reader)
  local array = {}

  read_sequence(reader, "]", function()
    array[#array + 1] = read_value(reader)
  end)

  return array
end

local literals = { ["true"] = true, ["false"] = false }

---@param reader Telemetry.JsonReader
---@return any
function read_value(reader)
  local char = reader.text:sub(reader.at, reader.at)

  if char == "{" then
    return read_object(reader)
  elseif char == "[" then
    return read_array(reader)
  elseif char == '"' then
    return read_string(reader)
  end

  local word = reader.text:match("^%a+", reader.at)
  if word == "null" or literals[word] ~= nil then
    reader.at = reader.at + #word
    return literals[word]
  end

  local number = reader.text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", reader.at)
  if number and tonumber(number) then
    reader.at = reader.at + #number
    return tonumber(number)
  end

  error("unexpected character at " .. reader.at, 0)
end

-- Decodes one JSON value. JSON null becomes nil.
---@param text string
---@return any value
---@return string? err Set when the text is not valid JSON.
function M.decode(text)
  local reader = { text = text, at = 1 }
  local ok, value = pcall(function()
    skip_space(reader)
    local result = read_value(reader)
    skip_space(reader)

    if reader.at <= #text then
      error("trailing text at " .. reader.at, 0)
    end

    return result
  end)

  if not ok then
    return nil, "json: " .. tostring(value)
  end

  return value
end

return M
