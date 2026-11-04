---@meta _

stds = { "luajit" }
cache = true
codes = true
globals = { "vim" }
exclude_files = { ".deps/**", ".plans/**" }
files["tests/**"] = {
  read_globals = {
    "assert",
    "describe",
    "it",
    "before_each",
    "after_each",
  },
}
