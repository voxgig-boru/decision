# AGENTS.md — using the `Decision` library

Guidance for an AI coding agent calling this decision-logic library from a
boru project. Every code block below was executed against `boru-lang/boru`
main @ `64c5ab2` (2026-10-01). If you read nothing else, read
[The one calling rule](#the-one-calling-rule) and
[Common mistakes](#common-mistakes).

## What it is

Declarative **decision logic**: express business rules as data — a
**condition**, a compound **predicate**, a **decision table** (rules with a
hit policy), or a **decision tree** (branch/leaf nodes) — then evaluate them
against an input `Map`. The public surface is the `Decision` namespace.

This library needs a current **boru main** (verified at `64c5ab2`) — it uses
`surface`/`exposes`, generics, `refine Record`, and `fnsig`. It imports no
`boru:*` dependencies.

boru main has **one execution path**: `boru file` runs a static pre-flight
check, then compiles the program to bytecode and runs it on the VM. There is
no interpreter fallback, and `--compile` / `--force-compile` /
`--no-compile` are retired (passing them is a usage error). A check error,
or a `[boru/compile_failed] … this is a compiler defect`, blocks the run.

> **Calling convention.** Forward args, receiver (the model/input) last:
> `Decision.decide model input`. Piping the input in also works
> (`input Decision.decide model`); putting the receiver **first** silently
> misbinds — both are `Map`s, so nothing type-checks it and you get a
> plausible-looking wrong result, not an error.

## Import

```boru
import "./decision.aql"
```

- A relative path resolves against the **importing file's own directory**
  (for both `boru file` and `boru check file`), not the working directory.
  A script next to `decision.aql` writes `import "./decision.aql"`; one in
  `test/` writes `import "../decision.aql"`.

## The one calling rule

boru is not C/Python/JS. There is no `f(a, b)` and no `obj.method(a)`. The
canonical form is **forward** — the verb first, then its arguments, with the
**receiver last**:

```
Decision.verb …args receiver
```

Every public word takes the thing it operates on — the model/table/input, the
**receiver** — as its **last** argument. Written forward, the receiver falls
naturally at the end:

- `Decision.decide model input` — `input` (the data being evaluated) is last.
- `Decision.eval-table table input` / `Decision.eval-cond cond input` — input last.
- `Decision.with-policy policy table` — `table` (the model being rewritten) is last.

Because the receiver is the last parameter, a stack/piping form *also* binds
(`{age:25} Decision.decide table` works), but with two `Map`s it reads
backwards — prefer forward. What you must **not** do is put the receiver
*first* in an all-forward call:

```boru
import "./decision.aql"
def table (Decision.make-table [(Decision.make-rule {field:"age" op:"gte" value:18} {category:"adult"})])
print (Decision.decide table {age:25})    # ✓ model, then input (receiver) last => {category: adult}
print (Decision.decide {age:25} table)    # ✗ receiver first: binds model:={age:25}
                                          #   => {ok:false error:"unknown-model-kind"}
```

That swap is **silent**. `model` and `input` are both `Map`, so nothing
type-checks it, and — unlike a plain word — `boru check`'s `mixed_form_call`
nudge does **not** fire on the namespaced `Decision.*` dispatch path. You just
get a plausible-looking error Map (`unknown-model-kind`, or `no-match`) back,
so getting the order right matters.

- **Wrap a call in parens, or end it,** when a bare value would otherwise
  follow the verb and get swallowed: `(Decision.decide table {age:25})`.

## API reference (exact call shapes)

Records are plain `refine Record` values — build them with a builder **or**
write them as Map literals; the evaluators only read fields.

**Builders**

| Call | Returns | Notes |
|------|---------|-------|
| `Decision.cond field op value` | `Cond` | `field` is an Atom (`age/q`); `op` a String; see ops below. |
| `Decision.all-of children` | `Pred` | every child condition/predicate must hold. |
| `Decision.any-of children` | `Pred` | at least one child must hold. |
| `Decision.not-of child` | `Pred` | negate one condition. |
| `Decision.make-rule when then` | `Rule` | pair a `when` (cond/pred Map) with a `then` result. |
| `Decision.make-table rules` | `DTable` | a list of rules; hit policy defaults to `"first"`. |
| `Decision.with-policy policy table` | `DTable` | copy `table` with a new hit policy. |
| `Decision.make-branch id branches` | `BranchNode` | `id` Atom; `branches` = `[{when:… next:…} …]`. |
| `Decision.make-leaf id result` | `LeafNode` | `id` Atom; `result` any value. |
| `Decision.make-tree root nodes` | `DTree` | `root` = the start node id (Atom); `nodes` = node list. |

**Evaluators** (each applied against an input `Map`)

| Call | Returns | Notes |
|------|---------|-------|
| `Decision.apply-op rhs op lhs` | `Boolean` | the primitive compare: `lhs op rhs`. Ordering ops need Comparable operands. |
| `Decision.eval-cond cond input` | `Boolean` | reads `input.(cond.field)` and applies `cond.op` against `cond.value`. |
| `Decision.eval-pred pred input` | `Boolean` | evaluates an all/any/not group (or a bare condition). |
| `Decision.eval-table table input` | result `Map` / value, or `{ok:false error:…}` | runs the table under its hit policy. |
| `Decision.eval-tree tree input` | leaf result, or `{ok:false error:…}` | walks branches to a leaf. |
| `Decision.decide model input` | as above | dispatches on `model.kind` (`"table"` or `"tree"`). |

**Operators** (the `op` String)

- Binary, Comparable: `eq`, `neq`, `lt`, `lte`, `gt`, `gte` — used in conditions
  (`{field op value}`) and via `Decision.apply-op rhs op lhs`.
- Unary: `is_true`, `is_false`, `is_null`, `is_not_null` — reachable **only**
  through the direct two-arg call `Decision.apply-op rhs op`. They are **not**
  usable inside a condition/table/tree, because `eval-cond` always supplies a
  `value`, so a unary op there falls through to the binary form and raises.

**Hit policies** (for tables)

- `"first"` *(default)* — the first matching rule's `then`.
- `"unique"` — the single match; `{ok:false error:"multiple-matches"}` if more
  than one rule matches, `"no-match"` if none.
- `"collect"` — a **List** of every matching rule's `then`.
- `"priority"` — the matching rule with the highest `priority` field (default
  `0`).

**Error results** — evaluators never throw on a miss; they return a Map:
`{ok:false error:"no-match"}`, `"multiple-matches"`, `"unknown-model-kind"`,
`"no-branch-match"`, `"node-not-found"`, `"unknown-node-kind"`,
`"max-depth-exceeded"`.

## Copy-paste idioms (all verified)

A decision **table** (first-match routing):

```boru
import "./decision.aql"
def rules [
  (Decision.make-rule {field:"age" op:"lt"  value:18} {category:"minor"})
  (Decision.make-rule {field:"age" op:"gte" value:65} {category:"senior"})
]
def table (Decision.make-table rules)
print (Decision.decide table {age:12})   # => {category: minor}
print (Decision.decide table {age:70})   # => {category: senior}
print (Decision.decide table {age:30})   # => {ok:false error:no-match}
```

A compound condition inside a rule (`all-of` / `any-of` / `not-of`):

```boru
def rule (Decision.make-rule
  {kind:"group" op:"all" children:[
    {field:"age"   op:"gte" value:18}
    {field:"score" op:"gte" value:90}
  ]}
  {tier:"premium"})
def tbl (Decision.make-table [rule])
print (Decision.decide tbl {age:25 score:95})   # => {tier: premium}
print (Decision.decide tbl {age:25 score:50})   # => {ok:false error:no-match}
```

Collect every matching rule instead of just the first:

```boru
def tags (Decision.with-policy "collect" (Decision.make-table [
  (Decision.make-rule {field:"age"   op:"gte" value:18} {tag:"adult"})
  (Decision.make-rule {field:"score" op:"gte" value:50} {tag:"passing"})
]))
print (Decision.decide tags {age:25 score:80})   # => [{tag: adult}, {tag: passing}]
```

A decision **tree** (branch → leaf), written as a Map literal and run with
its own evaluator, `eval-tree`:

```boru
def tree {kind:"tree" root:"root" nodes:[
  {id:"root" kind:"branch" branches:[
    {when:{field:"age" op:"lt"  value:18} next:"minor"}
    {when:{field:"age" op:"gte" value:18} next:"adult"}
  ]}
  {id:"minor" kind:"leaf" result:"too-young"}
  {id:"adult" kind:"leaf" result:"welcome"}
]}
print (Decision.eval-tree tree {age:40})   # => welcome
```

The same tree built with the builders also runs through `decide`:

```boru
def tree (Decision.make-tree root/q [
  (Decision.make-branch root/q [
    {when:{field:"age" op:"lt"  value:18} next:"minor"}
    {when:{field:"age" op:"gte" value:18} next:"adult"}
  ])
  (Decision.make-leaf minor/q "too-young")
  (Decision.make-leaf adult/q "welcome")
])
print (Decision.decide tree {age:40})   # => welcome
```

> **`decide` + a Map-literal model trips a boru-check false positive (boru
> main @ `64c5ab2`).** The pre-flight check analyses `decide`'s *other* arm
> with the literal's concrete fields — a literal tree has no `rules`, a
> literal table no `nodes` — and reports `no_signature` (e.g. `cannot call
> eval-table-first … got (Map, None)`), which blocks the run although the
> code is correct. With a literal model call its own evaluator
> (`Decision.eval-table` / `Decision.eval-tree`), or build the model with the
> builders (`make-table` / `make-tree`) and `decide` works.

Test one condition or one operator directly:

```boru
print (Decision.eval-cond {field:"age" op:"gte" value:18} {age:25})   # => true
print (Decision.apply-op 18 "gte" 25)                                  # => true  (lhs 25 gte rhs 18)
```

## Common mistakes

| ✗ Don't write | ✓ Write | Why |
|---------------|---------|-----|
| `Decision.decide {age:25} table` | `Decision.decide table {age:25}` | Forward form is `verb …args receiver`: the **model first, the input (receiver) last**. Both are `Map`, so a swap isn't type-checked and no `mixed_form_call` nudge fires — it **silently** returns a plausible error Map. |
| `decide table input` (unqualified) | `Decision.decide table input` | Words live under the `Decision` namespace after import. |
| `Decision.eval-table rules input` | `Decision.eval-table table input` | Pass the **table** (`make-table rules`), not the raw rules list. |
| `op: ">="` / `op: "ge"` | `op: "gte"` | Ops are `eq/neq/lt/lte/gt/gte` + the unary `is_*` set. |
| compare a Map/List with `lt` | compare scalars (or `eq`/`neq` only) | Ordering ops need **Comparable** operands; otherwise `apply-op` raises `not_comparable`. |
| treat a miss as an exception | inspect `result.error` (a hit has none) | A *non-match* returns `{ok:false error:"…"}` (no throw); a hit is your bare `then`/leaf value, with no `ok`/`error` fields. |
| an ordering op (`lt`/`gte`/…) on a maybe-missing field | guarantee the field is present, or compare it only with `eq`/`neq` | A missing field is `None`, not Comparable, so an ordering op **raises** `not_comparable`. (`eq`/`neq` return false for a missing field; the unary `is_*` ops can't gate this — they aren't usable in conditions.) |
| `make-branch "root" …` | `make-branch root/q …` | The builder's `id` is an **Atom**; quote bare names with `/q`. |
| `Decision.decide {kind:"tree" …literal…} input` | `Decision.eval-tree tree input` (or build with `make-tree` and `decide`) | boru main's pre-flight check analyses `decide`'s other arm with the literal's missing field and reports a false `no_signature` that blocks the run. |

A note on `print` while debugging: `print` collects a forward argument, so a
chain like `(a) print (b) print` can reorder (each `print` collects the next
statement's value). Write `print (value)` — verb first, one value per
statement — and output appears in source order.

## Where to look next

- `docs/reference.md` — full signatures, the record shapes, and complexity.
- `api.json` — the same API as a machine-readable manifest (call shapes, arg
  order, return types).
- `docs/how-to.md` — task recipes (tables, trees, hit policies, testing).
- `test/decision_smoke_test.aql` — a complete, runnable worked example.
- `dx-report.md` — boru-runtime notes observed building this library, including
  the migration to boru main @ `64c5ab2` and its open upstream defects.
