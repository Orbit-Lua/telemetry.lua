-- Host selection under the interpreter that runs this spec: Neovim, Lua
-- with luv, or Lua without luv.
local hosts = require("telemetry.host")
local t = require("tests.support.harness")

local in_nvim = rawget(_G, "vim") ~= nil
local has_luv = not in_nvim and pcall(require, "luv")

---@param values table<string, string>
---@return fun(name: string): string?
local function env(values)
  return function(name)
    return values[name]
  end
end

---@param choice? Telemetry.HostName
---@param values table<string, string>
---@return string? name
---@return string? err
local function pick(choice, values)
  local ok, host = pcall(hosts.select, choice, env(values))

  if ok then
    return host.name
  end

  return nil, tostring(host)
end

t.test("auto picks nvim inside Neovim, else luv, else raises", function()
  local name, err = pick(nil, {})

  if in_nvim then
    t.equal("nvim", name)
  elseif has_luv then
    t.equal("luv", name)
  else
    t.equal(nil, name)
    t.contains(err, "Neovim")
    t.contains(err, "luarocks install luv")
  end

  t.equal(name, (pick("auto", { TELEMETRY_HOST = "auto" })))
end)

t.test("an unavailable choice raises an error that names the host", function()
  local missing = in_nvim and "luv" or "nvim"

  local _, from_spec = pick(missing, {})
  t.contains(from_spec, "the " .. missing .. " host is unavailable")

  local _, from_env = pick(nil, { TELEMETRY_HOST = missing })
  t.contains(from_env, "the " .. missing .. " host is unavailable")
end)

t.test("spec.host overrides TELEMETRY_HOST", function()
  local available = in_nvim and "nvim" or has_luv and "luv" or nil
  local missing = in_nvim and "luv" or "nvim"

  if available then
    t.equal(available, (pick(available, { TELEMETRY_HOST = missing })))
  end

  local _, err = pick(missing, { TELEMETRY_HOST = available or "auto" })
  t.contains(err, "the " .. missing .. " host is unavailable")
end)

t.test("an unknown TELEMETRY_HOST raises an error", function()
  local _, err = pick(nil, { TELEMETRY_HOST = "basic" })
  t.contains(err, "TELEMETRY_HOST must be auto, nvim or luv")
end)

t.finish()
