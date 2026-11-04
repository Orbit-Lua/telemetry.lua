---@meta
-- Shared LuaDoc classes. This file declares types only and returns nothing.

---@alias Telemetry.Mode "auto"|"live"|"plain"

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
