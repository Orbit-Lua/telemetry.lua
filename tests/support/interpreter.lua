-- Find the command that runs a Lua file with the current interpreter.
local M = {}

-- Returns the argv prefix: Neovim's own binary with `-l`, or the
-- interpreter at the lowest negative index of `arg`. Higher negative
-- indexes hold interpreter options, which a child must not repeat.
---@return string[]
function M.command()
  local editor = rawget(_G, "vim")

  if type(editor) == "table" and editor.v then
    return { editor.v.progpath, "--headless", "--clean", "-i", "NONE", "-l" }
  end

  local index = 0
  while arg[index - 1] do
    index = index - 1
  end

  return { (assert(arg[index], "cannot find the interpreter in arg")) }
end

-- Returns the uv module of the interpreter: Neovim's own or luv.
---@return table
function M.uv()
  local editor = rawget(_G, "vim")

  if type(editor) == "table" and editor.uv then
    return editor.uv
  end

  return require("luv")
end

return M
