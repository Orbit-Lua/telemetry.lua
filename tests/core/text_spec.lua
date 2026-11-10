local t = require("tests.support.harness")
local text = require("telemetry.text")

t.test(
  "width counts wide characters as two columns and marks as zero",
  function()
    t.equal(5, text.width("abc d"))
    t.equal(4, text.width("中文"))
    t.equal(2, text.width("😀"))
    t.equal(1, text.width("e\204\129"), "e with a combining acute accent")
    t.equal(6, text.width("ｆｕｌ"), "fullwidth letters")
    t.equal(4, text.width("\128\146ab"), "stray continuation bytes count as 1")
  end
)

t.test("truncate cuts at a character boundary and adds an ellipsis", function()
  t.equal("abc", text.truncate("abc", 3))
  t.equal("ab…", text.truncate("abcd", 3))
  t.equal("中…", text.truncate("中文字", 4))
  t.equal("…", text.truncate("中文", 2))
  t.equal(".", text.truncate("abc", 1))
end)

t.test("duration formats seconds and minutes with integer parts", function()
  t.equal("1.2s", text.duration(1.25))
  t.equal("1m05s", text.duration(65.9))
  t.equal("10m00s", text.duration(600))
end)

t.test("strip removes CSI, OSC and charset escape sequences", function()
  local link = "\27]8;;https://example.com\27\\link\27]8;;\27\\"
  t.equal(
    "red link title text",
    text.strip(
      "\27[31mred\27[0m " .. link .. " \27]0;t\7title \27(Btext\27[>4;1m\27"
    )
  )
end)

t.test(
  "strip removes UTF-8 encoded C1 sequences and keeps other text",
  function()
    local csi, osc, st = "\194\155", "\194\157", "\194\156"
    t.equal(
      "red title link \194\169 caf\195\169",
      text.strip(
        csi
          .. "31mred"
          .. csi
          .. "0m "
          .. osc
          .. "0;t\7title "
          .. osc
          .. "8;;u"
          .. st
          .. "link"
          .. "\194\133 \194\169 caf\195\169"
      )
    )
  end
)

t.test("lines keeps empty lines", function()
  t.same({ "a", "", "b", "" }, text.lines("a\n\nb\n"))
end)

t.finish()
