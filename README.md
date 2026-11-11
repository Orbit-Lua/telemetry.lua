# telemetry.lua

Run Lua test suites as child processes and watch them in one fixed terminal view, inside Neovim or with luv.

[![Validate](https://github.com/Orbit-Lua/telemetry.lua/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/Orbit-Lua/telemetry.lua/actions/workflows/validate.yml?query=branch%3Amain) [![Release](https://img.shields.io/github/v/release/Orbit-Lua/telemetry.lua)](https://github.com/Orbit-Lua/telemetry.lua/releases/latest) [![Lua](https://img.shields.io/badge/Lua-5.1%2B-2C2D72?logo=lua&logoColor=white)](https://www.lua.org/)

On an interactive terminal, telemetry draws a progress bar, the running suite and test, and colored counts. Each completed suite leaves its status, name and duration above the progress view. Only the progress view redraws.

When the run ends, telemetry prints labeled failure details before the summary. On abort, it emits pending failure details and restores the cursor.

On a pipe or in CI, telemetry writes one plain line for each suite and the full output of each failed suite. It writes no color and no cursor control. On GitHub Actions, it folds failure output into log groups and adds error annotations.

## Install

telemetry runs on one of two hosts:

| Host | Runner | Requirement |
| --- | --- | --- |
| `nvim` | `nvim -l` | Neovim 0.12+ |
| `luv` | LuaJIT or Lua 5.1 to 5.4 | [luv](https://github.com/luvit/luv), for example `luarocks install luv` |

The Plenary adapter also needs [plenary.nvim](https://github.com/nvim-lua/plenary.nvim).

telemetry is a test tool, not an editor plugin. Clone a release tag next to your other test dependencies:

```sh
git clone --depth 1 --branch 0.1.1 https://github.com/Orbit-Lua/telemetry.lua.git .deps/telemetry.lua
```

## Usage

Write a runner script that lists the suites and passes them to `telemetry.run`:

```lua
-- scripts/test.lua
package.path = ".deps/telemetry.lua/lua/?.lua;.deps/telemetry.lua/lua/?/init.lua;" .. package.path

local telemetry = require("telemetry")

telemetry.exit(telemetry.run({
  title = "test",
  suites = {
    {
      name = "tests/example_spec.lua",
      argv = { "luajit", "tests/example_spec.lua" },
      -- The child finds telemetry.event through LUA_PATH; ";;" keeps the default path.
      env = { LUA_PATH = ".deps/telemetry.lua/lua/?.lua;.deps/telemetry.lua/lua/?/init.lua;;" },
    },
  },
}))
```

Run it on either host:

```sh
nvim --headless --clean -l scripts/test.lua
luajit scripts/test.lua
```

`telemetry.exit` exits with 0 when each suite passes, and 1 otherwise. On Ctrl-C, telemetry stops the running suite with its child processes and restores the cursor. SIGTERM and SIGHUP do the same. The exit code is then 130 under luv. Under Neovim, it is nonzero.

### Report each test

Without events, the view shows suites only. To show each test, report it from the child process. telemetry sets `TELEMETRY_EVENTS=1` in each child. Without that variable, the child reports nothing.

For a spec script without a test framework, wrap each test body. This works under any Lua version:

```lua
local event = require("telemetry.event")

local ok, err = event.test("formats a buffer on save", function()
  -- assertions
end)
```

For Plenary busted specs, install the adapter before the spec runs. Put `.deps/telemetry.lua` on the child's `runtimepath`.

```lua
-- tests/busted.lua
require("telemetry.busted").install()
require("plenary.busted").run(arg[1])
```

## Spec fields

| Field | Type | Description |
| --- | --- | --- |
| `title` | `string` | Name of the suite group, such as `"test"`. |
| `suites` | `Telemetry.Suite[]` | Suites in run order. |
| `mode` | `"auto"\|"live"\|"plain"?` | View selection. The default is `"auto"`. |
| `host` | `"auto"\|"nvim"\|"luv"?` | Host selection. The default is `"auto"`. |
| `terminal` | `Telemetry.Terminal?` | Output target. The default is standard output. |

## Suite fields

| Field | Type | Description |
| --- | --- | --- |
| `name` | `string` | Label in the view and in the result. |
| `argv` | `string[]` | Command line. `argv[1]` is the executable. |
| `cwd` | `string?` | Working directory of the process. |
| `env` | `table<string, string>?` | Variables added to the inherited environment. |
| `timeout` | `integer?` | Milliseconds before telemetry stops the process. The default is 120000. |
| `check` | `fun(result): string?` | Runs after a zero exit. A returned message fails the suite. |

`telemetry.run` returns a `Telemetry.Result` with each suite's status, exit code, duration, output and tests, and the name of the host. `lua/telemetry/types.lua` declares each type. The other modules are private.

## Host selection

telemetry selects the host in this order:

1. The `host` field of the spec.
2. `TELEMETRY_HOST=nvim` or `TELEMETRY_HOST=luv` in the environment.
3. `auto`: `nvim` inside Neovim, else `luv` when `require("luv")` works.

A host that cannot run raises an error, and so does a run with neither Neovim nor luv.

## Output mode

telemetry selects the view in this order:

1. `TELEMETRY_MODE=live` or `TELEMETRY_MODE=plain` in the environment.
2. The `mode` field of the spec.
3. `auto`: the live view on an interactive terminal outside CI, else the plain view.

Set `NO_COLOR` to remove color from the live view.

## Ownership

telemetry runs the processes, separates events from output, applies timeouts and reports the results. On a timeout, Ctrl-C, SIGTERM or SIGHUP, it stops the suite's whole process group: SIGTERM, then SIGKILL after 2 seconds. On Windows, it runs `taskkill /T /F`.

The runner script owns suite discovery, the process sandbox, such as private XDG directories, and the pass criteria in `check`.
