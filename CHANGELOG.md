# Changelog

All notable changes to telemetry.lua are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-11-10

### Fixed

- Child output and test names lose UTF-8 encoded C1 controls, such as CSI (U+009B) and OSC (U+009D) sequences.
- A Ctrl-C under Neovim while the summary prints restores the cursor that the live view hid.

## [0.1.0] - 2026-11-10

### Added

- The `luv` host runs telemetry under LuaJIT and Lua 5.1 to 5.4 with luv. Ctrl-C there exits with 130.
- `spec.host` and `TELEMETRY_HOST` select the host. `Telemetry.Result.host` names the host that ran the suites.
- `telemetry.event` and the core load under LuaJIT and Lua 5.1 to 5.5.

### Changed

- The repository is renamed from telemetry.nvim to telemetry.lua. The Lua module name stays `telemetry`.
- `telemetry.terminal`, `telemetry.state`, `telemetry.runner`, `telemetry.protocol` and `telemetry.view.*` are private. `telemetry.terminal` is removed.
- A timeout, Ctrl-C, SIGTERM or SIGHUP stops the suite's whole process group: SIGTERM, then SIGKILL after 2 seconds. On Windows, telemetry runs `taskkill /T /F`.
- A stop signal between suites ends the run before the next suite starts.
- `timeout` must be a positive integer.
- Test names from a child lose escape sequences and control characters, in the views and in `Telemetry.Result`.
- A suite that a signal ended fails, even when libuv reports exit code 0.
- A suite's timeout starts when the suite starts, not at the last libuv loop update.
- On Windows, a command name resolves through `PATHEXT` before an extensionless file, as in Neovim's `exepath`.

[0.1.1]: https://github.com/Orbit-Lua/telemetry.lua/releases/tag/0.1.1
[0.1.0]: https://github.com/Orbit-Lua/telemetry.lua/releases/tag/0.1.0
