---@meta
-- Shared LuaDoc classes. This file declares types only and returns nothing.

---@alias Telemetry.Mode "auto"|"live"|"plain"

---@alias Telemetry.HostName "auto"|"nvim"|"luv"

---@alias Telemetry.SuiteStatus "pass"|"fail"|"timeout"

---@alias Telemetry.TestStatus "pass"|"fail"|"error"

---@class Telemetry.Suite
---@field name string Label in the view and in the result.
---@field argv string[] Command line; `argv[1]` is the executable.
---@field cwd? string Working directory of the process.
---@field env? table<string, string> Variables added to the inherited environment.
---@field timeout? integer Milliseconds before the process is stopped. Default 120000.
---@field check? fun(result: Telemetry.SuiteResult): string? Runs after a zero exit; a returned message fails the suite.

---@class Telemetry.Spec
---@field title string Name of the suite group, such as "test".
---@field suites Telemetry.Suite[] Suites in run order.
---@field mode? Telemetry.Mode View selection. Default "auto".
---@field terminal? Telemetry.Terminal Output target. Default: standard output.
---@field host? Telemetry.HostName Host selection. Overrides TELEMETRY_HOST. Default "auto".

---@class Telemetry.TestResult
---@field name string Full test description.
---@field status Telemetry.TestStatus

---@class Telemetry.SuiteResult
---@field name string
---@field status Telemetry.SuiteStatus
---@field code integer Process exit code.
---@field signal integer Signal that stopped the process, or 0.
---@field duration number Seconds.
---@field output string Standard output and error in arrival order, without event lines.
---@field tests Telemetry.TestResult[] Tests reported by the child, in end order.
---@field message? string Reason for a failure that the exit code does not give.

---@class Telemetry.Result
---@field title string
---@field suites Telemetry.SuiteResult[]
---@field passed integer Suites with status "pass".
---@field failed integer Suites with status "fail" or "timeout".
---@field duration number Seconds.
---@field interrupted boolean True when Ctrl-C stopped the run.
---@field host "nvim"|"luv" Host that ran the suites.

---@class Telemetry.Event
---@field event "test_start"|"test_end"
---@field name string Full test description.
---@field status? Telemetry.TestStatus Set on "test_end".

---@class Telemetry.Terminal
---@field write fun(text: string) Writes raw text.
---@field width fun(): integer Columns of the output.
---@field tty boolean True when the output is an interactive terminal.
---@field color boolean True when the output accepts color.
---@field close? fun() Releases the output handle.

---@class Telemetry.View
---@field update fun(state: Telemetry.State) Shows the current progress.
---@field suite_finished fun(state: Telemetry.State, result: Telemetry.SuiteResult)
---@field finish fun(state: Telemetry.State, result: Telemetry.Result)
---@field abort fun() Restores the terminal after an error.

-- Host interface. The core reaches processes, time, the terminal and
-- interrupts only through a host. These types are private.

-- guard: on host exit, the host stops the running process group with the
-- routine of `execute` and then calls on_abort.
---@class Telemetry.Host
---@field name "nvim"|"luv"
---@field getenv fun(name: string): string?
---@field clock fun(): number Seconds from an arbitrary start.
---@field terminal fun(): Telemetry.Terminal Standard output; close() drains pending writes.
---@field execute fun(request: Telemetry.ProcessRequest, sink: Telemetry.ProcessSink): Telemetry.ProcessExit
---@field guard fun(on_abort: fun()): fun() Watches Ctrl-C and host exit; returns the remover.
---@field interrupted fun(): boolean True after a stop signal since the guard started.

---@class Telemetry.ProcessRequest
---@field argv string[]
---@field cwd? string
---@field env table<string, string> Added variables. The host merges them over the inherited environment.
---@field timeout integer Milliseconds.

---@class Telemetry.ProcessSink
---@field output fun(stream: "stdout"|"stderr", chunk: string) Always called from a normal context.
---@field poll fun(): boolean Runs at least every poll interval; returns true to cancel.

---@class Telemetry.ProcessExit
---@field code integer -1 when the process did not start or did not report a code.
---@field signal integer
---@field timed_out boolean
---@field interrupted boolean
---@field error? string Spawn failure.
