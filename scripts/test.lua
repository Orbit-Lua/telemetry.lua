-- Run the specs through telemetry. Each spec runs in its own Neovim process.
-- Usage: nvim --headless --clean -i NONE -l scripts/test.lua [pattern]
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
package.path = root
  .. "/lua/?.lua;"
  .. root
  .. "/lua/?/init.lua;"
  .. package.path

local telemetry = require("telemetry")
local pattern = arg[1] ~= "" and arg[1] or nil

---@type string[]
local specs = {}
for name, kind in vim.fs.dir(root .. "/tests") do
  if kind == "file" and name:match("_spec%.lua$") then
    local path = "tests/" .. name

    if not pattern or path:find(pattern, 1, true) then
      specs[#specs + 1] = path
    end
  end
end
table.sort(specs)
assert(#specs > 0, "no specs match " .. tostring(pattern))

-- A spec that reports no test ran nothing, for example after a load error.
---@param result Telemetry.SuiteResult
---@return string?
local function check(result)
  if #result.tests == 0 then
    return "the spec reported no tests"
  end
end

---@type Telemetry.Suite[]
local suites = vim.tbl_map(function(path)
  return {
    name = path,
    cwd = root,
    check = check,
    argv = {
      vim.v.progpath,
      "--headless",
      "--noplugin",
      "-i",
      "NONE",
      "-u",
      "tests/minimal_init.lua",
      "-l",
      "tests/busted.lua",
      path,
    },
  }
end, specs)

telemetry.exit(telemetry.run({ title = "test", suites = suites }))
