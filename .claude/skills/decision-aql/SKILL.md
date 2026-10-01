---
name: decision-aql
description: Use when writing or editing boru code that calls the Decision decision-logic library — Decision.cond / all-of / any-of / not-of / make-rule / make-table / with-policy / make-branch / make-leaf / make-tree / eval-cond / eval-pred / eval-table / eval-tree / decide / apply-op, or any file that does `import "./decision.aql"`. Provides the exact boru calling convention (which is not C/Python/JS) — forward form with the receiver (model/table/input) last — the builders/evaluators/ops/hit-policies, the eq-vs-deq / immutability / has / overflow by-design notes, verified copy-paste idioms (a table and a tree), and fixes for the mistakes agents most often make (foreign call syntax, the silent swapped model/input order, the missing-field `not_comparable` raise).
---

# Calling the Decision decision-logic library (boru)

Declarative **decision logic**: express business rules as data — a
**condition**, a compound **predicate**, a **decision table** (rules + hit
policy), or a **decision tree** (branch/leaf nodes) — then evaluate against an
input `Map`. Public surface = the `Decision` namespace. Everything below is
verified against boru main @ `64c5ab2` (2026-10-01).

## Import

```boru
import "./decision.aql"
```

- A relative path resolves against the **importing file's own directory**
  (for both `boru file` and `boru check file`), not the working directory —
  a script in `test/` writes `import "../decision.aql"`.
- Needs a current boru main (verified at `64c5ab2`; uses surface/exposes,
  generics, `refine Record`, `fnsig`). It imports no `boru:*` dependencies.
- boru main has **one execution path**: `boru file` runs a static pre-flight
  check, then compiles to bytecode and runs on the VM — there is no
  interpreter fallback, and `--compile`/`--force-compile`/`--no-compile` are
  retired (usage errors). A check error or a `[boru/compile_failed]` blocks
  the run.

## The one calling rule

boru has no `f(a, b)` and no `obj.method(a)`. The canonical form is **forward**
— the verb first, then its arguments, with the **receiver last**:

```
Decision.verb …args receiver
```

Every public word takes the thing it operates on — the model/table/input, the
**receiver** — as its **last** argument. Written forward, the receiver falls
naturally at the end:

- `Decision.decide model input` — `input` (the data being evaluated) is last.
- `Decision.eval-table table input` / `Decision.eval-cond cond input` — input last.
- `Decision.with-policy policy table` — `table` (the model being rewritten) is last.

**Use the forward form and keep the receiver last.** Because the receiver is
the last parameter, a stack/piping form *also* binds
(`{age:25} Decision.decide table` works), but with two `Map`s it reads
backwards — prefer forward. What you must **not** do is put the receiver
*first* in an all-forward call:

```boru
import "./decision.aql"
def table (Decision.make-table [(Decision.make-rule {field:"age" op:"gte" value:18} {category:"adult"})])
print (Decision.decide table {age:25})    # ✓ model, then input (receiver) last => {"category": "adult"}
print (Decision.decide {age:25} table)    # ✗ receiver first: binds model:={age:25}
                                          #   => {"ok": false, "error": "unknown-model-kind"}
```

That swap is **silent**. `model` and `input` are both `Map`, so no signature
rejects it, and `boru check` has no diagnostic for it: an all-forward call is
not a mixed-form call, so the `mixed_form_call` advisory (which fires only for
3+-argument mixed-form calls whose deepest stack slot is `Any`) never applies,
and boru has no "did you mean the other order?" hint. You just get a
plausible-looking error Map (`unknown-model-kind`, or `no-match`) back, so
getting the order right matters. (`eval-table` / `with-policy` are luckier:
a swap there mismatches a type and raises, rather than returning a fake miss.)

- **Wrap a call in parens, or end it,** when a bare value would otherwise
  follow the verb and get swallowed: `(Decision.decide table {age:25})`.

## API

Records are plain `refine Record` values — build them with a builder **or**
write them as Map literals; the evaluators only read fields.

**Builders**

| Call | Returns | Notes |
|------|---------|-------|
| `Decision.cond field op value` | `Cond` | `field` is an Atom (`age/q`); `op` a String. |
| `Decision.all-of children` | `Pred` | every child must hold. |
| `Decision.any-of children` | `Pred` | at least one child must hold. |
| `Decision.not-of child` | `Pred` | negate one condition. |
| `Decision.make-rule when then` | `Rule` | `then` MUST be a Map. |
| `Decision.make-table rules` | `DTable` | list of rules; hit policy defaults to `"first"`. |
| `Decision.with-policy policy table` | `DTable` | copy `table` with a new hit policy. |
| `Decision.make-branch id branches` | `BranchNode` | `id` Atom; `branches` = `[{when:… next:…} …]`. |
| `Decision.make-leaf id result` | `LeafNode` | `id` Atom; `result` any value. |
| `Decision.make-tree root nodes` | `DTree` | `root` = start node id (Atom); `nodes` = node list. |

**Evaluators** (each applied against an input `Map`)

| Call | Returns | Notes |
|------|---------|-------|
| `Decision.apply-op rhs op lhs` | `Boolean` | primitive compare: `lhs op rhs`. |
| `Decision.eval-cond cond input` | `Boolean` | reads `input.(cond.field)`, applies `cond.op` vs `cond.value`. |
| `Decision.eval-pred pred input` | `Boolean` | evaluates an all/any/not group (or a bare cond). |
| `Decision.eval-table table input` | result, or `{ok:false error:…}` | runs the table under its hit policy. |
| `Decision.eval-tree tree input` | leaf result, or `{ok:false error:…}` | walks branches to a leaf. |
| `Decision.decide model input` | as above | dispatches on `model.kind` (`"table"` / `"tree"`). |

**Operators** (the `op` String) — binary, Comparable: `eq` `neq` `lt` `lte`
`gt` `gte` (used in conditions and `apply-op`); unary: `is_true` `is_false`
`is_null` `is_not_null` — reachable **only** via the direct two-arg
`Decision.apply-op rhs op`, **not** inside a condition/table/tree (eval-cond
always supplies a `value`, so a unary op there raises).

**Hit policies** (tables) — `"first"` *(default)* first match's `then`;
`"unique"` the single match (`{ok:false error:"multiple-matches"}` if >1);
`"collect"` a **List** of every match's `then`; `"priority"` the match with the
highest `priority` field (default `0`).

**Error results** — evaluators never throw on a miss; they return a Map
`{ok:false error:…}`: `"no-match"`, `"multiple-matches"`,
`"unknown-model-kind"`, `"no-branch-match"`, `"node-not-found"`,
`"unknown-node-kind"`, `"max-depth-exceeded"`.

## Idioms (verified)

A decision **table** (first-match routing):

```boru
import "./decision.aql"
def rules [
  (Decision.make-rule {field:"age" op:"lt"  value:18} {category:"minor"})
  (Decision.make-rule {field:"age" op:"gte" value:65} {category:"senior"})
]
def table (Decision.make-table rules)
print (Decision.decide table {age:12})   # => {"category": "minor"}
print (Decision.decide table {age:70})   # => {"category": "senior"}
print (Decision.decide table {age:30})   # => {"ok": false, "error": "no-match"}
```

Collect every matching rule instead of just the first:

```boru
def tags (Decision.with-policy "collect" (Decision.make-table [
  (Decision.make-rule {field:"age"   op:"gte" value:18} {tag:"adult"})
  (Decision.make-rule {field:"score" op:"gte" value:50} {tag:"passing"})
]))
print (Decision.decide tags {age:25 score:80})   # => [{"tag": "adult"}, {"tag": "passing"}]
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

## By-design notes (boru)

- **`eq` is identity; `deq` is structural.** `{a:1} {a:1} eq` → `false`; use
  `deq` for structural equality of `Map`/`List` values
  (`{a:1} {a:1} deq` → `true`). The condition ops `eq`/`neq` compare scalars,
  so this rarely bites inside a table — but it does when you assert on a
  `then`/leaf **result Map**.
- **`has` tests key presence** — `{a:1} "a" has` → `true`,
  `{a:1} "b" has` → `false`. Prefer it over a manual `field None neq` check
  before an ordering compare on a maybe-missing field.
- **Maps/Lists are immutable.** Builders return fresh values; there is no
  in-place edit. If you genuinely need a mutable Map, wrap it with `flex`
  (`def m (flex {a:1})` then `(m set "b" 2)` → `{a:1 b:2}`).
- **Integer overflow is fail-loud, by design.** Integers are signed 64-bit;
  an overflowing `add`/`mul` **raises** `integer_overflow` rather than
  wrapping.

## Common mistakes

| ✗ Don't write | ✓ Write | Why |
|---------------|---------|-----|
| `Decision.decide {age:25} table` | `Decision.decide table {age:25}` | Forward form is `verb …args receiver`: the **model first, the input (receiver) last**. Both are `Map`, so a swap isn't type-checked and no `mixed_form_call` nudge fires — it **silently** returns a plausible error Map. |
| `decide table input` (unqualified) | `Decision.decide table input` | Words live under the `Decision` namespace after import. |
| `Decision.eval-table rules input` | `Decision.eval-table table input` | Pass the **table** (`make-table rules`), not the raw rules list. |
| `op: ">="` / `op: "ge"` | `op: "gte"` | Condition ops are `eq/neq/lt/lte/gt/gte`; the unary `is_*` set works only via direct `apply-op`. |
| compare a Map/List with `lt` | compare scalars (or `eq`/`neq` only) | Ordering ops need **Comparable** operands; else `apply-op` raises `not_comparable`. |
| treat a miss as an exception | inspect `result.error` (a hit has none) | A *non-match* returns `{ok:false error:"…"}` (no throw); a hit is your bare `then`/leaf value. |
| an ordering op (`lt`/`gte`/…) on a maybe-missing field | gate presence first (`{…} field has`), or compare with `eq`/`neq` only | A missing field is `None`, not Comparable, so an ordering op **raises** `not_comparable`. (`is_*` can't gate this — not usable in conditions.) |
| `make-branch "root" …` | `make-branch root/q …` | The builder's `id` is an **Atom**; quote bare names with `/q`. |
| `Decision.decide {kind:"tree" …literal…} input` | `Decision.eval-tree tree input` (or build with `make-tree` and `decide`) | boru main's pre-flight check analyses `decide`'s other arm with the literal's missing field and reports a false `no_signature` that blocks the run. |

A note on `print` while debugging: `print` collects a forward argument, so a
chain like `(a) print (b) print` can reorder (each `print` collects the next
statement's value). Write `print (value)` — verb first, one value per
statement — and output appears in source order.

If the full repo is available, `AGENTS.md`, `api.json` (machine-readable
signatures), and `docs/reference.md` have the complete guide;
`test/decision_smoke_test.aql` is a runnable example.
