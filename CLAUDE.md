# CLAUDE.md

This repository is the `Decision` decision-logic library, written in boru.

## Using the library

See @AGENTS.md for how to call the `Decision` API correctly from boru — the
calling convention, the full API, copy-paste idioms, and the common
mistakes to avoid. Every example there was executed against boru main @
`64c5ab2` (2026-10-01).

## Working on this repository

- A SessionStart hook (`.claude/settings.json` →
  `.claude/hooks/session-start.sh`) builds `boru` from the current `main`
  HEAD in remote sessions, so a fresh session can run the suites. Locally,
  build it once from source (there is no tagged release and
  `go install …/cmd/go/boru@latest` is blocked by replace directives) — see
  [docs/how-to.md](docs/how-to.md#install-and-run-boru).
- **One execution path.** On boru main, `boru file` runs a static pre-flight
  check, then compiles to bytecode and runs on the VM; there is no
  interpreter fallback, and `--compile`/`--force-compile`/`--no-compile` are
  retired (usage errors). "The suite runs" therefore means "the suite fully
  compiles". A `[boru/compile_failed] … compiler defect` is a boru bug: reduce
  it, look it up in boru's `NUR.md`, and work around it only with a natural,
  semantics-preserving rewrite carrying a comment that names the defect.
- Relative imports resolve against the **importing file's directory**: the
  suites in `test/` import `"../decision.aql"`.
- Tests live in `test/`, named `decision_<unit|prop>_<test|spec>.aql` plus a
  `decision_smoke_test.aql`: `_test` = imperative (`Test.test`/`Test.check-prop`),
  `_spec` = declarative spec; `unit` = example-based, `prop` = property-based.
  Each assertion-bearing suite ends with `Assert.equal 0 (Test.fail-count)`
  and prints `all green`; the smoke suite carries no assertion (pass = no
  error). Keep the summary in the forward `print (value)` form — the
  stack-form `"x" print … print` chain reorders and strands values.
- `test/diverge.sh` is the test gate and **tracks the latest `boru` from
  `main`** (boru is on an iterative-improvement track — no fixed "best" pin).
  Hard invariants: every suite exits 0 under `boru <suite>` (compiled) and
  prints `all green` where it asserts, and `boru check` reports 0 errors on
  every suite and on `decision.aql`. It builds `main` HEAD by default
  (override with `BORU=/path/to/boru` or `BORU_REF=<sha>`). See
  [docs/how-to.md](docs/how-to.md#run-the-test-gate).
- Known boru gotchas, the migration to boru main @ `64c5ab2`, and the open
  upstream defects (with minimal repros) are in `dx-report.md`. There is no
  pinned boru commit: CI (`.github/workflows/test.yml`) and the hook both
  resolve `main` HEAD.
