-- Text helpers for the views: display width, cuts, styles and durations.
-- They work on UTF-8 text under every supported Lua version.
local M = {}

---@alias Telemetry.Style "bold"|"dim"|"red"|"green"|"yellow"|"cyan"

---@type table<Telemetry.Style, string>
local styles = {
  bold = "1",
  dim = "2",
  red = "31",
  green = "32",
  yellow = "33",
  cyan = "36",
}

-- Code point ranges with a display width other than 1, sorted by start:
-- combining marks and format characters (0), East Asian Wide and Fullwidth
-- characters and emoji presentation (2).
---@type { [1]: integer, [2]: integer, [3]: integer }[]
local ranges = {
  { 0x0300, 0x036F, 0 },
  { 0x0483, 0x0489, 0 },
  { 0x0591, 0x05BD, 0 },
  { 0x05BF, 0x05BF, 0 },
  { 0x05C1, 0x05C2, 0 },
  { 0x05C4, 0x05C5, 0 },
  { 0x05C7, 0x05C7, 0 },
  { 0x0610, 0x061A, 0 },
  { 0x064B, 0x065F, 0 },
  { 0x0670, 0x0670, 0 },
  { 0x06D6, 0x06DC, 0 },
  { 0x06DF, 0x06E4, 0 },
  { 0x06E7, 0x06E8, 0 },
  { 0x06EA, 0x06ED, 0 },
  { 0x0E31, 0x0E31, 0 },
  { 0x0E34, 0x0E3A, 0 },
  { 0x0E47, 0x0E4E, 0 },
  { 0x1100, 0x115F, 2 },
  { 0x1AB0, 0x1AFF, 0 },
  { 0x1DC0, 0x1DFF, 0 },
  { 0x200B, 0x200F, 0 },
  { 0x202A, 0x202E, 0 },
  { 0x2060, 0x2064, 0 },
  { 0x20D0, 0x20FF, 0 },
  { 0x231A, 0x231B, 2 },
  { 0x2329, 0x232A, 2 },
  { 0x23E9, 0x23EC, 2 },
  { 0x23F0, 0x23F0, 2 },
  { 0x23F3, 0x23F3, 2 },
  { 0x25FD, 0x25FE, 2 },
  { 0x2614, 0x2615, 2 },
  { 0x2648, 0x2653, 2 },
  { 0x267F, 0x267F, 2 },
  { 0x2693, 0x2693, 2 },
  { 0x26A1, 0x26A1, 2 },
  { 0x26AA, 0x26AB, 2 },
  { 0x26BD, 0x26BE, 2 },
  { 0x26C4, 0x26C5, 2 },
  { 0x26CE, 0x26CE, 2 },
  { 0x26D4, 0x26D4, 2 },
  { 0x26EA, 0x26EA, 2 },
  { 0x26F2, 0x26F3, 2 },
  { 0x26F5, 0x26F5, 2 },
  { 0x26FA, 0x26FA, 2 },
  { 0x26FD, 0x26FD, 2 },
  { 0x2705, 0x2705, 2 },
  { 0x270A, 0x270B, 2 },
  { 0x2728, 0x2728, 2 },
  { 0x274C, 0x274C, 2 },
  { 0x274E, 0x274E, 2 },
  { 0x2753, 0x2755, 2 },
  { 0x2757, 0x2757, 2 },
  { 0x2795, 0x2797, 2 },
  { 0x27B0, 0x27B0, 2 },
  { 0x27BF, 0x27BF, 2 },
  { 0x2B1B, 0x2B1C, 2 },
  { 0x2B50, 0x2B50, 2 },
  { 0x2B55, 0x2B55, 2 },
  { 0x2E80, 0x3029, 2 },
  { 0x302A, 0x302D, 0 },
  { 0x302E, 0x303E, 2 },
  { 0x3041, 0x3098, 2 },
  { 0x3099, 0x309A, 0 },
  { 0x309B, 0x33FF, 2 },
  { 0x3400, 0x4DBF, 2 },
  { 0x4E00, 0x9FFF, 2 },
  { 0xA000, 0xA4CF, 2 },
  { 0xA960, 0xA97F, 2 },
  { 0xAC00, 0xD7A3, 2 },
  { 0xF900, 0xFAFF, 2 },
  { 0xFE00, 0xFE0F, 0 },
  { 0xFE10, 0xFE19, 2 },
  { 0xFE20, 0xFE2F, 0 },
  { 0xFE30, 0xFE6F, 2 },
  { 0xFEFF, 0xFEFF, 0 },
  { 0xFF00, 0xFF60, 2 },
  { 0xFFE0, 0xFFE6, 2 },
  { 0x1F004, 0x1F004, 2 },
  { 0x1F0CF, 0x1F0CF, 2 },
  { 0x1F18E, 0x1F18E, 2 },
  { 0x1F191, 0x1F19A, 2 },
  { 0x1F200, 0x1F202, 2 },
  { 0x1F210, 0x1F23B, 2 },
  { 0x1F240, 0x1F248, 2 },
  { 0x1F250, 0x1F251, 2 },
  { 0x1F260, 0x1F265, 2 },
  { 0x1F300, 0x1F64F, 2 },
  { 0x1F680, 0x1F6FF, 2 },
  { 0x1F7E0, 0x1F7EB, 2 },
  { 0x1F90C, 0x1F9FF, 2 },
  { 0x1FA70, 0x1FAFF, 2 },
  { 0x20000, 0x2FFFD, 2 },
  { 0x30000, 0x3FFFD, 2 },
  { 0xE0001, 0xE007F, 0 },
  { 0xE0100, 0xE01EF, 0 },
}

---@param code integer
---@return integer
local function code_width(code)
  if code < 0x20 or (code >= 0x7F and code < 0xA0) then
    return 0
  elseif code < 0x300 then
    return 1
  end

  local low, high = 1, #ranges
  while low <= high do
    local middle = math.floor((low + high) / 2)
    local range = ranges[middle]

    if code < range[1] then
      high = middle - 1
    elseif code > range[2] then
      low = middle + 1
    else
      return range[3]
    end
  end

  return 1
end

-- Value bits of a lead byte, by sequence length.
local lead_bits = { 0x80, 0x20, 0x10, 0x08 }

-- Iterates over the characters of UTF-8 text. Each step gives the byte
-- position after the character and its code point. An invalid byte counts
-- as one character of width 1.
---@param text string
---@return fun(): integer?, integer?
local function characters(text)
  local at = 1

  return function()
    if at > #text then
      return nil
    end

    local byte = text:byte(at)
    local length = byte >= 0xF0 and 4
      or byte >= 0xE0 and 3
      or byte >= 0xC0 and 2
      or 1
    local code = byte % lead_bits[length]

    -- A stray continuation byte or an overlong lead is not a character.
    if (length == 1 and byte >= 0x80) or byte >= 0xF8 then
      at = at + 1
      return at, 0xFFFD
    end

    for index = at + 1, at + length - 1 do
      local next_byte = text:byte(index)

      if not next_byte or next_byte < 0x80 or next_byte >= 0xC0 then
        length, code = 1, 0xFFFD
        break
      end

      code = code * 0x40 + next_byte % 0x40
    end

    at = at + length
    return at, code
  end
end

-- Returns the number of terminal columns that the text takes.
---@param text string Text without escape sequences.
---@return integer
function M.width(text)
  local columns = 0

  for _, code in characters(text) do
    columns = columns + code_width(code)
  end

  return columns
end

-- Cuts text to a display width and marks the cut with an ellipsis.
---@param text string Text without escape sequences.
---@param width integer
---@return string
function M.truncate(text, width)
  if M.width(text) <= width then
    return text
  end

  if width <= 1 then
    return string.rep(".", math.max(width, 0))
  end

  local stop, columns = 0, 0
  for after, code in characters(text) do
    columns = columns + code_width(code)

    if columns > width - 1 then
      break
    end

    stop = after - 1
  end

  return text:sub(1, stop) .. "…"
end

-- Wraps text in an SGR sequence when the terminal accepts color.
---@param terminal Telemetry.Terminal
---@param style Telemetry.Style
---@param text string
---@return string
function M.paint(terminal, style, text)
  if not terminal.color or text == "" then
    return text
  end

  return "\27[" .. styles[style] .. "m" .. text .. "\27[0m"
end

-- Removes escape sequences, such as Plenary's colors and terminal links.
---@param text string
---@return string
function M.strip(text)
  local plain = text
    :gsub("\27%][^\7\27]*\7", "") -- OSC ended by BEL, such as a title
    :gsub("\27%][^\7\27]*\27\\", "") -- OSC ended by ST, such as a link
    :gsub("\27%[[\48-\63]*[\32-\47]*[\64-\126]", "") -- CSI
    :gsub("\27[\32-\47]*[\48-\126]", "") -- other escapes, such as ESC ( B
    :gsub("\27", "") -- a bare ESC, such as one cut off at a line end
  return plain
end

---@class Telemetry.Segment
---@field [1] string Text without escape sequences.
---@field [2]? Telemetry.Style

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
    local columns = M.width(text)
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

-- Splits text at each newline and keeps empty lines.
---@param text string
---@return string[]
function M.lines(text)
  local lines = {}

  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end

  return lines
end

-- Formats seconds as "12.3s" or "4m05s".
---@param seconds number
---@return string
function M.duration(seconds)
  if seconds < 60 then
    return string.format("%.1fs", seconds)
  end

  local whole = math.floor(seconds)
  return string.format("%dm%02ds", math.floor(whole / 60), whole % 60)
end

return M
