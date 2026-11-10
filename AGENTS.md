# AGENTS Instructions

Linux and Windows are equal targets.

## Git

- Write commits in [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) format.
- Start the type, the scope and the description in lowercase. Keep the case of code identifiers and proper nouns.
- For a non-trivial change, write a commit body that explains why.
- Mark a breaking change with `!` and a `BREAKING CHANGE:` footer.
- Author commits as the user alone. Add no agent trailers or links, such as `Co-Authored-By` or a session URL.
- Commit as the plan progresses.
- Before you push, squash related commits into one commit to keep the history clean.
- Push only after the user approves that push.

## Releases

- Version releases with [Semantic Versioning 2.0.0](https://semver.org/).
- Name each release tag with the bare version, such as `1.2.3`. If the repo already uses a tag prefix, such as `v`, keep it.
- When you create a changelog, use [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/) format. Keep the format of an existing changelog.
- Release in this order:
  1. Update the version files and the changelog in one commit, such as `chore(release): prepare 1.2.3`.
  2. Push the commit to the default branch.
  3. Wait until the branch pipeline of that commit passes.
  4. Tag that commit with an annotated tag: `git tag -a 1.2.3 -m "Release 1.2.3" <commit>`. Tag a release candidate as `1.2.3-rc.1`.
  5. Push the tag alone: `git push origin 1.2.3`. The tag pipeline publishes the package and creates the release.
- Push the commit and the tag in separate pushes. Do not use `git push --follow-tags`. One push starts two overlapping pipelines, and a single runner queues the tag pipeline.

## Interface

- Consumers pin the commit of a release tag. A push to `main` reaches no consumer until it updates its pin.
- Keep `telemetry.run`, `telemetry.exit`, the spec and suite fields, the event lines, `telemetry.event` and the busted adapter backward compatible.
- Treat every other module as private. Consumers must not require it.
- Before a breaking interface change, update each consumer in the same plan.

## Hosts

- Keep the core free of `vim`. Only `lua/telemetry/host/nvim.lua` and the Neovim test glue may use it.
- Reach processes, time, the terminal and Ctrl-C only through the host interface in `lua/telemetry/types.lua`.
- Only queue data in libuv callbacks. They can run in a fast context, where most Neovim calls fail.
- Deliver output to the sink from the host's wait loop.
- Stop a suite's whole process group on a timeout, a cancel and a host exit. Use the routine of `execute` for each case.
- Under Neovim, block in `VimLeavePre` through the kill grace period. A uv timer cannot fire after Neovim exits.
- Do not wait for pipe EOF in the exit guard. A grandchild outside the group can hold the pipes.

## Code

- Load the core under LuaJIT and Lua 5.1 to 5.5:
  - Use no `goto`, `utf8` library, `//` or bit operators.
  - Use `table.unpack or unpack`.
  - Wrap each `xpcall` body in a closure. Pass no extra arguments to `xpcall`.
  - Do not assign to a for-loop variable.
  - Format a number with `%d` only after `math.floor`. luv returns floats under Lua 5.3+.
- Wrap `assert` in parentheses inside a table constructor. Otherwise the message becomes a second item.
- Keep the plain view free of escape sequences. Remove them from child output too.
- Fit each live frame line in the terminal width minus one column. A wrapped line breaks the cursor movement.
- Keep each function body at 60 lines or fewer, nesting at 4 levels or fewer and each file at 400 lines or fewer.
- Declare a LuaDoc type for each public function, option and callback. Do not use a bare `table` for a known shape.

## Platforms

- Build paths with `/`, which Neovim and libuv accept on Windows.
- Keep just recipes valid under Unix `sh` and native Windows `cmd.exe`.

## Tests

- Add a test to the repo only when it guards behavior that no existing test covers.
- The test must fail when that behavior breaks. Weigh this before you add each test.
- Run throwaway tests freely to check your work.
- Keep throwaway tests out of the repo unless they meet the bar above.
- Pin each test dependency in `scripts/deps.lua` to a commit that exists on its remote.
- Run `just deps` once, then `just all` before you finish.
- Run `just test-core <interpreter>` for each installed interpreter: `luajit`, `lua5.1`, `lua5.4` and `lua5.5`.
- Run `just test-hosts luajit` with luv before you change a host.
- Put specs that run on the fake host in `tests/core/`. They must run under every interpreter.
- Put specs that need real processes in `tests/host/`, and Plenary specs in `tests/nvim/`.
- Test the views on the fake terminal in `tests/support/fake.lua`, not on the real output.
- Change `tests/support/frames.lua` only for an intended change of the view output.

## CI

- Keep a CI check only when it catches a concrete failure that no existing check covers.
- Identify that failure before you add or keep the check.
- Apply the test rules to CI checks too.
- Run the repo's entry points against real inputs or isolated fixtures.
- Reject duplicate checks, source-text assertions, copied inventories and checks that only prove that a command or file exists.
- Name each workflow, job and step by its target and its action.
- Propagate command failures.
- Count a missing prerequisite or skipped required coverage as a failure.
- Run the checks in branch pipelines only. A tag pipeline builds, smoke-tests and publishes the package, and then creates the release.
- Start each release job with a check that the tagged commit is on the default branch.
- Match release jobs to the tag format of the version, such as `/^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$/`.
- Protect the release tags. Only protected refs can read the release credentials.
- A tag pipeline uses the CI config of the tagged commit. Merge a CI change to the default branch before you tag.
- Run the checks in a workflow on `pull_request` and on `push` to branches.
- Run the release in a separate workflow on `push` of tags that match `[0-9]+.[0-9]+.[0-9]+`. GitHub tag filters are globs, such as `[0-9]+.[0-9]+.[0-9]+` and `[0-9]+.[0-9]+.[0-9]+-*`.
- Check out release jobs with `fetch-depth: 0`, so that the ancestry check sees the default branch.
- Keep release secrets in an environment that allows only the release tags. Protect the tags with a tag ruleset.
- After you change these rules, audit the repo against them.
- Validate changes locally. Then verify the required CI on the pushed commit.
- Report each uncovered contract and each unavailable check.

## Docs

- Keep each doc concise and plain. Each sentence must carry information.
- Write only standing rules in `AGENTS.md`. A standing rule changes how an agent does later, unrelated tasks.
- Record a fact about one place or one failure at its source: a code comment, a test, a commit body, an ADR or an issue.
- Write English docs in US English, to the [ASD-STE100](https://www.asd-ste100.org/) writing rules:
  - Give one instruction in each sentence.
  - Write instructions in the imperative and in the active voice.
  - Use one word for one meaning, and one meaning for one word.
  - An instruction has 20 words or fewer. A description has 25 words or fewer.
- Review each sentence over these limits. Split it if it holds more than one instruction or fact.
- Use a numbered list for three or more instructions in a fixed order, also across sentences.
- Write a set of full-sentence items, or of more than five items, as a bullet list. Otherwise, the set can stay in one sentence, even when the sentence is over the limits.
- Write a non-English doc in two passes:
  1. Write an English draft to these rules.
  2. Translate the draft:
     1. Keep its sentence boundaries and one term for each concept.
     2. Keep commands, paths and code unchanged.
     3. Use the natural word order of the target language.
- Document each public type in `lua/telemetry/types.lua`. Update the README tables when a public field changes.
- Record each user-visible change in `CHANGELOG.md`.
