-- Host for Neovim, such as `nvim -l`. It runs libuv through vim.wait.
--
-- Neovim may end the process itself on Ctrl-C ("Caught deadly signal"),
-- before vim.wait reports the press. It still runs VimLeavePre, so the guard
-- stops the child's process group there and restores the terminal. The exit
-- code is then Neovim's own, which is nonzero.
local uv_host = require("telemetry.host.uv")

local interrupted = false

---@type Telemetry.UvLoop
local loop = {
  wait = function(ms, done)
    local _, status = vim.wait(ms, done, 10)

    if status == -2 then
      interrupted = true
    end
  end,
  interrupted = function()
    return interrupted
  end,
}

local host = uv_host.new(vim.uv, loop)

---@param on_abort fun()
---@return fun() remove
local function guard(on_abort)
  interrupted = false
  local signal = vim.uv.new_signal()

  if signal then
    signal:start("sigint", function()
      interrupted = true
    end)
  end

  local group = vim.api.nvim_create_augroup("telemetry.run", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      -- A uv timer cannot fire after this, so the grace wait blocks here.
      host:abort()
      on_abort()
    end,
  })

  return function()
    if signal then
      signal:stop()
      signal:close()
    end

    vim.api.nvim_del_augroup_by_id(group)
  end
end

---@type Telemetry.Host
return {
  name = "nvim",
  getenv = os.getenv,
  clock = function()
    return host:clock()
  end,
  terminal = function()
    return host:terminal()
  end,
  execute = function(request, sink)
    return host:execute(request, sink)
  end,
  guard = guard,
  -- Run pending callbacks first: a signal that arrived during blocking
  -- work, such as a suite check, reaches its handler only in the loop.
  interrupted = function()
    loop.wait(0, function()
      return false
    end)
    return interrupted
  end,
}
