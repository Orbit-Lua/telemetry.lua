local protocol = require("telemetry.protocol")

---@param chunks string[]
---@return { line: string, newline: boolean }[]
local function split(chunks)
  local lines = {}
  local splitter = protocol.splitter(function(line, newline)
    lines[#lines + 1] = { line = line, newline = newline }
  end)

  for _, chunk in ipairs(chunks) do
    splitter.feed(chunk)
  end

  splitter.flush()
  return lines
end

describe("protocol", function()
  it("decodes an encoded event", function()
    local event = { event = "test_end", name = "a b", status = "fail" }
    local line = protocol.encode(event):gsub("\n$", "")

    assert.same(event, protocol.decode(line))
  end)

  it("keeps ordinary and malformed lines as output", function()
    assert.is_nil(protocol.decode("Success: || a test"))
    assert.is_nil(protocol.decode(protocol.prefix .. "{not json"))
    assert.is_nil(protocol.decode(protocol.prefix .. '{"event":"other"}'))

    local missing = '{"event":"test_end","name":"x"}'
    assert.is_nil(protocol.decode(protocol.prefix .. missing))
  end)

  it("joins a line that spans chunks and strips carriage returns", function()
    local encoded = protocol.encode({ event = "test_start", name = "slow" })
    local middle = math.floor(#encoded / 2)
    local lines = split({
      "first\r\nsec",
      "ond\n" .. encoded:sub(1, middle),
      encoded:sub(middle + 1) .. "tail",
    })

    assert.same({ line = "first", newline = true }, lines[1])
    assert.same({ line = "second", newline = true }, lines[2])
    assert.same(
      { event = "test_start", name = "slow" },
      protocol.decode(lines[3].line)
    )
    assert.same({ line = "tail", newline = false }, lines[4])
    assert.equal(4, #lines)
  end)
end)
