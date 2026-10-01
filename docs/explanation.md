# Explanation

Understanding-oriented discussion of how this decision-logic library
works and why it is built the way it is. Read this when you want the
*why*; for the *what*, see the [Reference](reference.md), and for *how
to get a job done*, the [How-to guides](how-to.md).

> **AI agents:** the canonical, verified calling guide is
> [../AGENTS.md](../AGENTS.md). Mirror its facts exactly.

---

## What decision logic is for

Most programs eventually grow a thicket of `if`/`else` that encodes
*business* policy — who counts as a minor, which order ships free, what
tier a customer lands in. Decision logic pulls that policy out of the
control flow and expresses it as **data**: a **condition** (one
field/op/value test), a compound **predicate** (`all-of` / `any-of` /
`not-of`), a **decision table** (a list of `when → then` rules under a
hit policy), or a **decision tree** (branch and leaf nodes you walk).
You then evaluate that data against an input `Map` and read back the
result.

This is the right tool when:

- the rules change more often than the code that runs them, so you want
  them editable as data rather than recompiled;
- you want to *inspect, serialize, or generate* the rules — a table is a
  plain list of Maps, so it round-trips through JSON and can be built by
  another program;
- the policy is naturally tabular ("for these conditions, this outcome")
  or hierarchical (a sequence of questions narrowing to an answer), which
  the table and tree models capture directly.

It is the wrong tool when the logic is genuinely procedural — multi-step
computation, side effects, loops over the input — or when there is only
one trivial branch. Decision logic earns its keep by making a *set* of
rules legible and uniform, not by replacing every `if`.

A note on what the evaluators return: a successful evaluation yields the
matching rule's `then` (or a leaf's `result`); a *non-match* is not an
exception but a value — `{ok:false error:"no-match"}`. That choice is
discussed under [Design choices](#design-choices-specific-to-this-library).

---

## How tables and trees are evaluated

A **decision table** is a list of rules and a **hit policy**. Each rule
is a `{when then}` pairing: `when` is a condition or predicate, `then`
is the result to return. `eval-table` walks the rules, evaluating each
`when` against the input, and the hit policy decides what to do with the
matches:

- **`first`** *(the default from `make-table`)* — return the `then` of
  the first rule whose `when` holds, in list order. Later matches are
  never examined once one is found. This is the routing policy: order
  your rules from most specific to most general and the first hit wins.
- **`unique`** — there must be *exactly one* match. Zero matches return
  `{ok:false error:"no-match"}`; two or more return
  `{ok:false error:"multiple-matches"}`. Use this to assert your rules
  are mutually exclusive and to catch the bug where they are not.
- **`collect`** — return a **List** of the `then` of *every* matching
  rule, in list order. This is the only policy that returns a list, and
  it returns the empty list `[]` when nothing matches (not an error
  Map), because "no matches" is a perfectly good collected result.
- **`priority`** — among all matching rules, return the `then` of the
  one with the highest `priority` field. A rule with no `priority` field
  is treated as priority `0`. Ties resolve to the first such rule
  encountered, since a strictly-greater test replaces the running best.

You set a policy by building the table with `make-table` (which defaults
to `first`) and then copying it with `with-policy` — for example
`Decision.with-policy "collect" table`.

A **decision tree** is a set of nodes and the id of a `root` node.
`eval-tree` starts at the root and walks:

- a **leaf** node carries a `result`; reaching one ends the walk and
  returns that result;
- a **branch** node carries an ordered list of `{when next}` branches.
  The walk evaluates every `when` against the input and follows the
  `next` id of the matching branch to the next node. Branches are meant
  to be mutually exclusive — as in the canonical `lt 18` / `gte 18`
  split — so that exactly one holds; if more than one matches, the last
  matching branch in list order wins.

The walk is bounded. `eval-tree` iterates at most **100 steps**; a tree
that has not reached a leaf by then returns
`{ok:false error:"max-depth-exceeded"}`. This cap is a deliberate
guard against a malformed tree whose `next` ids cycle — without it a
loop in the data would hang the evaluator. Three other shapes of
malformed tree surface as their own error values: a branch where no
`when` matches returns `{ok:false error:"no-branch-match"}`, a `next`
that names a node not in the set returns
`{ok:false error:"node-not-found"}`, and a node whose `kind` is neither
`"branch"` nor `"leaf"` returns `{ok:false error:"unknown-node-kind"}`.

`decide` is the front door over both: it reads `model.kind` and
dispatches to `eval-table` for `"table"` or `eval-tree` for `"tree"`,
returning `{ok:false error:"unknown-model-kind"}` for anything else.
Because tables and trees are just Maps with a `kind` field, the same
`decide model input` call drives either one.

---

## Conditions, predicates, and the Comparable surface

The atom of all of this is the **condition**: `{field op value}`.
`eval-cond` looks up `input.(field)`, then applies `op` to that
left-hand value and the condition's `value`. The operators split into
two families:

- **binary** — `eq`, `neq`, `lt`, `lte`, `gt`, `gte`. These take two
  operands and drive conditions through `eval-cond`. The ordering four
  (`lt`/`lte`/`gt`/`gte`) require Comparable operands; `eq`/`neq` do not.
- **unary** (they ignore `value`) — `is_true`, `is_false`, `is_null`,
  `is_not_null`. These are the one-operand form of `apply-op`, called
  directly as `Decision.apply-op rhs op`.

Predicates compose conditions. `all-of` holds when every child holds,
`any-of` when at least one does, `not-of` negates a single condition;
they nest freely, so an `all-of` can contain an `any-of`, and so on.
`eval-pred` folds the children with the matching list quantifier, which
short-circuits — `all-of` stops at the first child that fails, `any-of`
at the first that holds.

The interesting design point is **Comparable**. The ordering operators
(`lt`/`lte`/`gt`/`gte`) are not defined for every value — it makes no
sense to ask whether one Map is "less than" another. In this library
Comparable is a **surface**: the `cmp` contract that a type must expose
to be ordered. The scalar builtins (Integer, Float, String, Boolean,
Atom) expose it; Maps and Lists do not. `apply-op`'s relational form is
generic over that surface, so when an ordering op meets a non-Comparable
operand the bounded signature rejects it and the fallback **raises**
`not_comparable`. Equality (`eq`/`neq`) is defined for everything, so it
never raises.

This has a consequence worth internalising, because it is the most
common surprise:

> An ordering op on a **missing** field raises. A field that is absent
> from the input reads as `None`, and `None` is not Comparable, so
> `lt`/`gte`/… on it raise `not_comparable` rather than quietly
> returning `false`.

That is **by design**: the library prefers to be *loud* over
*silently-false*. A rule that meant to compare an age, run against an
input that has no `age`, almost certainly indicates a mistake — a typo'd
field name, a malformed input, a rule applied to the wrong record. A
silent `false` would let that mistake flow on as a plausible-looking
"didn't match"; a raised `not_comparable` stops it at the point of the
error. The flip side is a discipline for the caller: when a field might
be absent, guarantee it is present before you order on it, so the
ordering op only ever runs on a value that exists. The equality ops
(`eq`/`neq`) need no such care — they are defined for everything,
return cleanly on a missing field, and are the safe way to test a value
that may not be there.

---

## Design choices specific to this library

### Records as data — models are plain Maps

`Cond`, `Pred`, `Rule`, `DTable`, `DTree`, `BranchNode`, and `LeafNode`
are `refine Record` types, but they are *only* shapes. The builders
(`cond`, `make-rule`, `make-table`, `make-branch`, …) are conveniences;
nothing in the evaluators depends on a value having been built by one.
`eval-table table input` reads `table.rules` and `table.hit-policy`,
each rule's `when` and `then`, and so on — it reads fields, never type
tags. So a model written as a bare Map literal evaluates identically to
one assembled by the builders, which is why the table in
`{kind:"table" hit-policy:"first" rules:[…]}` form works in `decide`
just as a `make-table` result does.

Keeping models as plain data is what makes the rest possible: a table
serializes to JSON and back unchanged, a rule set can be generated by
another program or loaded from a file, and you can `print` a model and
read exactly what it will do. The types document the expected shape and
let the type checker catch a malformed builder call; they do not lock
the data into an opaque object.

### Errors as values, not exceptions

The evaluators distinguish two kinds of failure. A **structural** error
in *how you called the operator* — an ordering comparison on something
that cannot be ordered — raises, because it is a programming mistake
that should not be papered over (see
[Comparable](#conditions-predicates-and-the-comparable-surface)
above). But an ordinary **miss** — no rule matched, a unique policy saw
two matches, a tree ran off its nodes — is returned as a value:
`{ok:false error:"…"}`. The full set is `"no-match"`,
`"multiple-matches"`, `"unknown-model-kind"`, `"no-branch-match"`,
`"node-not-found"`, `"unknown-node-kind"`, and `"max-depth-exceeded"`.

This split keeps the common path branch-free for the caller: you check
`result.ok` (or the presence of `result.error`) and handle the miss
inline, rather than wrapping every `decide` in error-handling
machinery. A miss is an expected outcome of evaluating rules against
arbitrary input — it deserves to be a value you can route on, not an
exception you must catch. The `collect` policy carries the same spirit:
"nothing matched" is the empty list, a first-class result, not an error.

### Pure boru, no Go

This library is a port of the interpreter's internal `boru:decision`
module written **entirely in boru** — no Go, no native extensions. It
imports no `boru:*` dependencies; it builds only on core language
features (`surface`/`exposes`, generics, `refine Record`, and `fnsig`;
first available at boru `61856202`, now verified on boru main @
`64c5ab2`, where every program — this library included — is compiled to
bytecode and run on the VM). The practical upshot is that the whole
module is readable, hackable, and portable boru you can vendor into a
project with a single `import "./decision.aql"` — the behaviour is
defined by the source you can see, not by a runtime you cannot. It is
also a worked demonstration that a non-trivial, type-checked DSL — a
Comparable surface, generic rule/result types, four hit policies, a
bounded tree walk — fits comfortably inside the boru language itself.

---

## Further reading

- [Tutorial](tutorial.md) — build your first decision table step by step.
- [How-to guides](how-to.md) — task-focused recipes.
- [Reference](reference.md) — the exact API.
