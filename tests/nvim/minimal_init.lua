-- Isolate each spec process: no user config, private XDG directories, and
-- only this repo and the pinned Plenary on the runtime path.
local repository = vim.fn.getcwd()
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")

for _, name in ipairs({ "CONFIG", "DATA", "STATE", "CACHE" }) do
  vim.env["XDG_" .. name .. "_HOME"] = root .. "/" .. name:lower()
end

vim.o.shadafile = "NONE"
vim.o.swapfile = false
vim.opt.runtimepath = { repository, vim.env.VIMRUNTIME }
vim.opt.packpath = {}

local plenary = repository .. "/.deps/plenary.nvim"
assert(vim.fn.isdirectory(plenary) == 1, "run `just deps` first: " .. plenary)
vim.opt.runtimepath:append(plenary)
vim.cmd("runtime plugin/plenary.vim")

package.path = repository
  .. "/?.lua;"
  .. repository
  .. "/lua/?.lua;"
  .. repository
  .. "/lua/?/init.lua;"
  .. package.path

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    vim.fn.delete(root, "rf")
  end,
})
