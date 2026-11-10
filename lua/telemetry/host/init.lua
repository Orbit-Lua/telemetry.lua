-- Select the host that runs the suites: spec.host, then TELEMETRY_HOST,
-- then auto detection. Auto picks nvim inside Neovim, else luv.
local M = {}

local luv_hint = "install luv, for example with `luarocks install luv`"

---@type table<"nvim"|"luv", fun(): string?>
local unavailable = {
  nvim = function()
    local editor = rawget(_G, "vim")

    if type(editor) ~= "table" or editor.uv == nil then
      return "run telemetry inside Neovim, for example with `nvim -l`"
    end
  end,
  luv = function()
    local editor = rawget(_G, "vim")
    if type(editor) == "table" and editor.uv ~= nil then
      return "Neovim runs its own libuv loop; use the nvim host"
    end

    if not pcall(require, "luv") then
      return luv_hint
    end
  end,
}

---@param name "nvim"|"luv"
---@return Telemetry.Host
local function load(name)
  local reason = unavailable[name]()

  if reason then
    error(
      string.format("telemetry: the %s host is unavailable: %s", name, reason),
      0
    )
  end

  return require("telemetry.host." .. name)
end

-- Returns the host for a run. An explicit choice that cannot run raises an
-- error, as does a run with neither Neovim nor luv.
---@param choice? Telemetry.HostName spec.host.
---@param getenv fun(name: string): string? Reads TELEMETRY_HOST.
---@return Telemetry.Host
function M.select(choice, getenv)
  if choice == nil or choice == "auto" then
    choice = getenv("TELEMETRY_HOST")
  end

  if choice == "nvim" or choice == "luv" then
    return load(choice)
  elseif choice ~= nil and choice ~= "" and choice ~= "auto" then
    error(
      "telemetry: TELEMETRY_HOST must be auto, nvim or luv, got " .. choice,
      0
    )
  end

  for _, name in ipairs({ "nvim", "luv" }) do
    if not unavailable[name]() then
      return require("telemetry.host." .. name)
    end
  end

  error(
    "telemetry: no host is available. Run inside Neovim for the nvim host, or "
      .. luv_hint
      .. " for the luv host",
    0
  )
end

return M
