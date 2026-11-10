local json = require("telemetry.json")
local protocol = require("telemetry.protocol")
local t = require("tests.support.harness")

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

t.test("json round-trips a flat object with escapes", function()
  local object = {
    name = 'quote " slash \\ tab \t nl \n bell \7 中文',
    count = 3,
    ok = true,
  }
  t.same(object, json.decode(json.encode(object)))
  t.equal('{"a":1,"b":"x"}', json.encode({ b = "x", a = 1 }), "sorted keys")
end)

t.test("json decodes unicode escapes and surrogate pairs", function()
  t.equal("é中😀", json.decode('"\\u00e9\\u4e2d\\ud83d\\ude00"'))
  t.same(
    { list = { 1, -2.5, false }, nested = { k = "v" } },
    json.decode('{"list":[1,-2.5e0,false],"nested":{"k":"v"},"none":null}')
  )
end)

t.test("json rejects invalid text without raising", function()
  for _, text in ipairs({
    "{not json",
    '"\\ud83d"',
    '{"a":1} tail',
    '"\\x"',
    "",
  }) do
    local value, err = json.decode(text)
    t.equal(nil, value, text)
    t.contains(err, "json: ", text)
  end
end)

t.test("protocol decodes an encoded event", function()
  local event = { event = "test_end", name = "a b 中", status = "fail" }
  local line = protocol.encode(event):gsub("\n$", "")
  t.same(event, protocol.decode(line))
end)

t.test("protocol keeps ordinary and malformed lines as output", function()
  t.equal(nil, protocol.decode("Success: || a test"))
  t.equal(nil, protocol.decode(protocol.prefix .. "{not json"))
  t.equal(nil, protocol.decode(protocol.prefix .. '{"event":"other"}'))
  t.equal(
    nil,
    protocol.decode(protocol.prefix .. '{"event":"test_end","name":"x"}')
  )
end)

t.test(
  "protocol joins a line across chunks and strips carriage returns",
  function()
    local encoded = protocol.encode({ event = "test_start", name = "slow" })
    local middle = math.floor(#encoded / 2)
    local lines = split({
      "first\r\nsec",
      "ond\n" .. encoded:sub(1, middle),
      encoded:sub(middle + 1) .. "tail",
    })

    t.same({ line = "first", newline = true }, lines[1])
    t.same({ line = "second", newline = true }, lines[2])
    t.same(
      { event = "test_start", name = "slow" },
      protocol.decode(lines[3].line)
    )
    t.same({ line = "tail", newline = false }, lines[4])
    t.equal(4, #lines)
  end
)

t.finish()
