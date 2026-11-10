-- List the files of a directory under any interpreter: through Neovim's uv
-- module, through luv, or through the shell.
local M = {}

M.windows = package.config:sub(1, 1) == "\\"

---@return table?
local function libuv()
  local editor = rawget(_G, "vim")

  if type(editor) == "table" and editor.uv then
    return editor.uv
  end

  local ok, luv = pcall(require, "luv")
  return ok and luv or nil
end

---@param uv table
---@param directory string
---@return string[]
local function scan(uv, directory)
  local names = {}
  local handle = assert(uv.fs_scandir(directory))

  while true do
    local name, kind = uv.fs_scandir_next(handle)

    if not name then
      return names
    end

    if kind == "file" then
      names[#names + 1] = name
    end
  end
end

---@param directory string
---@return string[]
local function shell(directory)
  local command = M.windows
      and ('dir /b /a-d "' .. directory:gsub("/", "\\") .. '"')
    or ("ls -1 '" .. directory .. "'")
  local pipe = assert(io.popen(command))
  local names = {}

  for name in pipe:lines() do
    names[#names + 1] = name
  end

  pipe:close()
  return names
end

-- Returns the sorted file names of a directory.
---@param directory string
---@return string[]
function M.files(directory)
  local uv = libuv()
  local names = uv and scan(uv, directory) or shell(directory)
  table.sort(names)
  return names
end

return M
