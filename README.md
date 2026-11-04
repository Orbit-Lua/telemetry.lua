# telemetry.nvim

Run headless Neovim test suites as subprocesses and watch them in one fixed terminal view.

[![Validate telemetry.nvim](https://github.com/Orbit-Lua/telemetry.nvim/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/Orbit-Lua/telemetry.nvim/actions/workflows/validate.yml) [![Neovim](https://img.shields.io/badge/Neovim-0.12%2B-57A143?logo=neovim&logoColor=white)](https://neovim.io/)

On an interactive terminal, telemetry draws a progress bar, the running suite and test, and colored counts. The view does not scroll. The output of a failed suite prints above the view.

On a pipe or in CI, telemetry writes one plain line for each suite and the full output of each failed suite. It writes no color and no cursor control. On GitHub Actions, it folds failure output into log groups and adds error annotations.

## Install

Use Neovim 0.12+. The Plenary adapter also needs [plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

telemetry is a test tool, not an editor plugin. Clone it next to your other test dependencies:

```sh
git clone --filter=blob:none https://github.com/Orbit-Lua/telemetry.nvim.git .deps/telemetry.nvim
```

## Usage

Write a runner script that lists the suites and passes them to `telemetry.run`:

```lua
-- scripts/test.lua
package.path = ".deps/telemetry.nvim/lua/?.lua;.deps/telemetry.nvim/lua/?/init.lua;" .. package.path

local telemetry = require("telemetry")

telemetry.exit(telemetry.run({
  title = "test",
  suites = {
    {
      name = "tests/example_spec.lua",
      argv = { vim.v.progpath, "--headless", "-u", "tests/minimal_init.lua", "-l", "tests/busted.lua", "tests/example_spec.lua" },
    },
  },
}))
```

Run it:

```sh
nvim --headless --clean -l scripts/test.lua
```

`telemetry.exit` exits with 0 when each suite passes, and 1 otherwise. On Ctrl-C, telemetry stops the running suite and restores the cursor. The exit code is then nonzero.

### Report each test

Without events, the view shows suites only. To show each test, report it from the child process. telemetry sets `TELEMETRY_EVENTS=1` in each child. Without that variable, the child reports nothing.

For Plenary busted specs, install the adapter before the spec runs. Put `.deps/telemetry.nvim` on the child's `runtimepath`.

```lua
-- tests/busted.lua
require("telemetry.busted").install()
require("plenary.busted").run(arg[1])
```

For a spec script without busted, wrap each test body:

```lua
local event = require("telemetry.event")

local ok, err = event.test("formats a buffer on save", function()
  -- assertions
end)
```

## Suite fields

| Field | Type | Description |
| --- | --- | --- |
| `name` | `string` | Label in the view and in the result. |
| `argv` | `string[]` | Command line. `argv[1]` is the executable. |
| `cwd` | `string?` | Working directory of the process. |
| `env` | `table<string, string>?` | Variables added to the inherited environment. |
| `timeout` | `integer?` | Milliseconds before telemetry stops the process. The default is 120000. |
| `check` | `fun(result): string?` | Runs after a zero exit. A returned message fails the suite. |

`telemetry.run` returns a `Telemetry.Result` with each suite's status, exit code, duration, output and tests. `lua/telemetry/types.lua` declares each type.

## Output mode

telemetry selects the view in this order:

1. `TELEMETRY_MODE=live` or `TELEMETRY_MODE=plain` in the environment.
2. The `mode` field of the spec.
3. `auto`: the live view on an interactive terminal outside CI, else the plain view.

Set `NO_COLOR` to remove color from the live view.

## Ownership

telemetry runs the processes, separates events from output, applies timeouts and reports the results. The runner script owns suite discovery, the process sandbox, such as private XDG directories, and the pass criteria in `check`.
