-- Clone the pinned test dependencies into .deps/ at their commits.
-- Usage: nvim --headless --clean -u NONE -l scripts/deps.lua

---@class Telemetry.Dependency
---@field name string Directory name below .deps/.
---@field url string Git remote.
---@field commit string Pinned commit that exists on the remote.

---@type Telemetry.Dependency[]
local dependencies = {
  {
    name = "plenary.nvim",
    url = "https://github.com/nvim-lua/plenary.nvim.git",
    commit = "74b06c6c75e4eeb3108ec01852001636d85a932b",
  },
}

---@param command string[]
local function run(command)
  local result = vim.system(command, { text = true }):wait(300000)

  if result.code ~= 0 then
    local message = table.concat(command, " ") .. " failed:\n"
    error(message .. (result.stderr or ""), 0)
  end
end

local root = vim.fn.getcwd() .. "/.deps"
vim.fn.mkdir(root, "p")

for _, dependency in ipairs(dependencies) do
  local path = root .. "/" .. dependency.name

  if vim.fn.isdirectory(path .. "/.git") == 0 then
    run({ "git", "clone", "--filter=blob:none", dependency.url, path })
  end

  run({ "git", "-C", path, "fetch", "--quiet", "origin", dependency.commit })
  run({
    "git",
    "-C",
    path,
    "checkout",
    "--quiet",
    "--detach",
    dependency.commit,
  })
end
