# decision

A small, dependency-light **decision-logic** library implemented in
[boru](https://github.com/boru-lang/boru) — express business rules as
*data* (a condition, a compound predicate, a **decision table** with a
hit policy, or a **decision tree** of branch/leaf nodes), then evaluate
them against an input `Map`. No `boru:*` dependencies. The public surface
is the single `Decision` namespace.

```boru
import "./decision.aql"

def table (Decision.make-table [
  (Decision.make-rule {field:"age" op:"lt"  value:18} {category:"minor"})
  (Decision.make-rule {field:"age" op:"gte" value:65} {category:"senior"})
])

print (Decision.decide table {age:12})   # => {"category": "minor"}
print (Decision.decide table {age:70})   # => {"category": "senior"}
print (Decision.decide table {age:30})   # => {"ok": false, "error": "no-match"}
```

> **Calling convention.** boru is forward: the verb first, arguments
> after, with the **receiver (the model/input) last** —
> `Decision.decide model input`. Piping the input in also binds
> (`input Decision.decide model`), but putting the receiver **first**
> silently misbinds: both are `Map`s, so nothing type-checks it and you
> get a plausible-looking wrong result rather than an error. A
> *non-match* returns `{ok:false error:"…"}` rather than throwing.

> **Calling this library from an AI coding agent?** Read
> **[AGENTS.md](AGENTS.md)** first — the exact boru calling convention,
> verified idioms, and common mistakes. (Claude Code auto-loads it via
> `CLAUDE.md`; a portable skill lives in
> [`.claude/skills/decision-aql`](.claude/skills/decision-aql/SKILL.md).)

## Documentation

The docs follow the [Diátaxis](https://diataxis.fr) framework — four
modes, each serving a different need. Start wherever your need is:

| | Mode | Read this when you want to… |
|--|------|----------------------------|
| 🎓 | **[Tutorial](docs/tutorial.md)** | learn by building your first decision table step by step |
| 🔧 | **[How-to guides](docs/how-to.md)** | accomplish a specific task (tables, trees, hit policies, testing…) |
| 📖 | **[Reference](docs/reference.md)** | look up exact words, call shapes, and return types |
| 💡 | **[Explanation](docs/explanation.md)** | understand how it works and why it's built this way |

New here? Read the [Tutorial](docs/tutorial.md). Already know decision
tables and just want the API? Jump to the [Reference](docs/reference.md).

## API at a glance

Build a model with the builders (or write the records as plain `Map`
literals — the evaluators only read fields), then run it with an
evaluator against an input `Map`.

| Word | Purpose |
|------|---------|
| `Decision.cond field op value`       | a single condition (`field` is an Atom, e.g. `age/q`) |
| `Decision.all-of children`           | predicate: every child must hold |
| `Decision.any-of children`           | predicate: at least one child must hold |
| `Decision.not-of child`              | predicate: negate one condition |
| `Decision.make-rule when then`       | pair a `when` (cond/pred) with a `then` result Map |
| `Decision.make-table rules`          | a list of rules; hit policy defaults to `"first"` |
| `Decision.with-policy policy table`  | copy a table with a new hit policy |
| `Decision.make-branch id branches`   | a branch node (`id` Atom; `branches` = `[{when:… next:…} …]`) |
| `Decision.make-leaf id result`       | a leaf node (`id` Atom; any `result` value) |
| `Decision.make-tree root nodes`      | a tree (`root` start-node id; `nodes` list) |
| `Decision.apply-op rhs op lhs`       | the primitive compare → Boolean (`lhs op rhs`) |
| `Decision.eval-cond cond input`      | evaluate one condition against `input` → Boolean |
| `Decision.eval-pred pred input`      | evaluate an all/any/not group → Boolean |
| `Decision.eval-table table input`    | run a table under its hit policy → result, or `{ok:false error:…}` |
| `Decision.eval-tree tree input`      | walk a tree to a leaf → result, or `{ok:false error:…}` |
| `Decision.decide model input`        | dispatch on `model.kind` (`"table"` / `"tree"`) |

Operators are `eq`, `neq`, `lt`, `lte`, `gt`, `gte` (binary, Comparable)
plus the unary `is_true`, `is_false`, `is_null`, `is_not_null`. Hit
policies are `"first"` (default), `"unique"`, `"collect"` (returns a
List), and `"priority"`. Full signatures, record shapes, and the error
results (`"no-match"`, `"multiple-matches"`, `"unknown-model-kind"`,
`"no-branch-match"`, `"node-not-found"`, `"unknown-node-kind"`,
`"max-depth-exceeded"`) are in the [Reference](docs/reference.md).

## For AI coding agents

If an agent will call this library, point it at **[AGENTS.md](AGENTS.md)**
— the exact boru calling convention, verified idioms, and the common
mistakes to avoid — alongside [`api.json`](api.json), the same API as a
machine-readable manifest (call shapes, arg order, return types).

To make that guidance available in *another* project that uses this
library, install the bundled skill either way:

- **Copy the skill** — drop
  [`.claude/skills/decision-aql/`](.claude/skills/decision-aql/SKILL.md)
  into that project's `.claude/skills/` (or your `~/.claude/skills/`). It
  loads on demand whenever `Decision` calls appear.
- **Install the plugin** — this repo is also a plugin marketplace:

  ```
  /plugin marketplace add voxgig-boru/decision
  /plugin install decision-aql@voxgig-boru
  ```

Working inside *this* repo, Claude Code picks the guidance up
automatically via `CLAUDE.md` (which imports `AGENTS.md`) and the bundled
skill.

## Project layout

```
decision.aql                   the library (the Decision namespace)
AGENTS.md                      agent guide: how to call this library correctly
api.json                       machine-readable API manifest (call shapes, arg order, returns)
test/decision_unit_test.aql    example-based unit tests — direct (Test.test)
test/decision_unit_spec.aql    example-based unit tests — declarative spec format
test/decision_prop_test.aql    property-based tests — direct (Test.check-prop)
test/decision_prop_spec.aql    property-based tests — declarative spec format
test/decision_smoke_test.aql   end-to-end smoke run over every public word
test/diverge.sh                test gate (tracks latest boru main; every suite compiles+runs, 0 check errors)
bench/                         performance baseline (bench.sh, decision_bench.aql, BASELINE.md)
docs/                          Diátaxis documentation (above)
dx-report.md                   developer-experience notes; migration to boru main @ 64c5ab2 and open upstream defects
```

Test files follow a consistent naming convention: `_test.aql` for direct
tests (unit or property), `_spec.aql` for declarative specs (unit or
property).

## Running it

Build `boru` from source at `main` (this library tracks `main`; last
verified at `64c5ab2`, 2026-10-01), then run any script or test — see
[How-to → Install and run](docs/how-to.md#install-and-run-boru):

```bash
boru test/decision_unit_test.aql   # unit tests — direct
boru test/decision_unit_spec.aql   # unit tests — declarative spec format
boru test/decision_prop_test.aql   # property tests — direct
boru test/decision_prop_spec.aql   # property tests — declarative spec format
boru test/decision_smoke_test.aql  # end-to-end smoke run
```

Each assertion-bearing suite ends by asserting `Test.fail-count` is `0`
and printing `all green`; the smoke run passes if it completes without an
error. A GitHub Actions workflow
([`.github/workflows/test.yml`](.github/workflows/test.yml)) builds boru
at the current `main` HEAD and runs every suite on each push and pull
request.

boru main has **one execution path**: `boru file` runs the static checker
as a pre-flight, then compiles the program to bytecode and runs it on the
VM — there is no interpreter fallback, so a suite that runs is a suite
that fully compiles. `bash test/diverge.sh` tracks the **latest `boru`
from `main`**; its hard guarantees are that every suite compiles, runs and
passes, and that `boru check` reports zero errors on every suite and on
`decision.aql`. All five suites are fully compiled on `64c5ab2`. See
[How-to → Run the test gate](docs/how-to.md#run-the-test-gate).

## License

See [LICENSE](LICENSE).
