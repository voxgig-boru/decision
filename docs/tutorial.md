# Tutorial: your first decision table

This is a hands-on lesson. By the end you will have built a small boru
script that classifies people by age with a **decision table**, grown it
into a compound rule, collected every match, and finally walked a
**decision tree**. You need no prior knowledge of decision logic — just a
working `boru` binary (see
[How-to → Install and run](how-to.md#install-and-run-boru)) and this
repository checked out.

> **AI agents:** for the calling convention and a verified cheat-sheet,
> see [AGENTS.md](../AGENTS.md).

Follow along by typing the script into a file as we grow it. We will
build it up in pieces and run it after each step. The one rule to keep in
mind: boru is forward — the verb comes first, then its arguments, with the
**receiver (the model/input) last**: `Decision.decide table input`. Get
that order wrong (`Decision.decide input table`) and it misbinds
*silently* — both are Maps, so you get a plausible-looking wrong result,
not an error. Wrap each call in parens (or end it) so the next token
isn't swallowed.

---

## Step 1 — import the module and build a rule

Create a file `classify.aql` next to `decision.aql` with this content:

```boru
import "./decision.aql"

def minor-rule (Decision.make-rule {field:"age" op:"lt" value:18} {category:"minor"})
print (minor-rule) end
```

A **rule** pairs a `when` (a condition to test) with a `then` (the result
to return when it matches). `Decision.make-rule` takes the `when` first
and the `then` second — here, "if `age` is less than 18, the category is
`minor`". The condition is a plain Map: a `field` to read, an `op` to
apply, and a `value` to compare against. Run it:

```console
$ boru classify.aql
{"when": {"field": "age", "op": "lt", "value": 18}, "then": {"category": "minor"}}
```

That printed Map *is* the rule — a piece of data you can store, pass
around, and combine. The operator `lt` is one of six binary comparisons:
`eq`, `neq`, `lt`, `lte`, `gt`, `gte`.

---

## Step 2 — collect rules into a table and decide

One rule is a condition; a *list* of rules with a hit policy is a
**decision table**. Replace the body of `classify.aql` with three rules
wrapped in a table, then ask it to `decide`:

```boru
import "./decision.aql"

def rules [
  (Decision.make-rule {field:"age" op:"lt"  value:18} {category:"minor"})
  (Decision.make-rule {field:"age" op:"gte" value:65} {category:"senior"})
  (Decision.make-rule {field:"age" op:"gte" value:18} {category:"adult"})
]
def table (Decision.make-table rules)

print (Decision.decide table {age:12}) end
print (Decision.decide table {age:70}) end
print (Decision.decide table {age:30}) end
```

`Decision.make-table` defaults to the `"first"` hit policy: rules are
tried top to bottom and the **first** match wins. So order matters — the
`gte 18` adult rule sits last, after the `gte 65` senior rule, otherwise a
70-year-old would match "adult" first. `Decision.decide` dispatches on the
model's `kind` (here, a table) and runs it against the input Map. Run it:

```console
$ boru classify.aql
{"category": "minor"}
{"category": "senior"}
{"category": "adult"}
```

Age 12 hits the first rule, 70 the second, 30 falls through to the adult
catch-all. The result is the matching rule's `then`, returned as-is.

---

## Step 3 — handle a miss

What if nothing matches? Evaluators never throw on a miss — they return an
error Map. Trim the table to a single rule and feed it an input that
slips past:

```boru
import "./decision.aql"

def strict (Decision.make-table [
  (Decision.make-rule {field:"age" op:"lt" value:18} {category:"minor"})
])
print (Decision.decide strict {age:40}) end
```

```console
$ boru classify.aql
{"ok": false, "error": "no-match"}
```

No rule matched age 40, so you get `{ok:false error:"no-match"}` rather
than an exception. Always branch on `result.ok` (or check `result.error`)
before using a result, since a miss is a value, not a crash. The other
error strings you might see are `"multiple-matches"`,
`"unknown-model-kind"`, `"no-branch-match"`, `"node-not-found"`,
`"unknown-node-kind"`, and `"max-depth-exceeded"`.

---

## Step 4 — a compound condition

A single `field`/`op`/`value` test is often too coarse. `Decision.all-of`
groups several conditions so that **every** child must hold (there are
`Decision.any-of` and `Decision.not-of` too). Build a rule that only fires
for an adult with a high score:

```boru
import "./decision.aql"

def premium (Decision.make-rule
  (Decision.all-of [
    {field:"age"   op:"gte" value:18}
    {field:"score" op:"gte" value:90}
  ])
  {tier:"premium"})
def vip-table (Decision.make-table [premium])

print (Decision.decide vip-table {age:25 score:95}) end
print (Decision.decide vip-table {age:25 score:50}) end
```

```console
$ boru classify.aql
{"tier": "premium"}
{"ok": false, "error": "no-match"}
```

The first input clears both bars and earns `premium`; the second has a low
score, so the `all-of` fails and the rule misses. One caution: an ordering
op (`lt`/`lte`/`gt`/`gte`) on a **missing** field raises `not_comparable`,
because a missing field is `None` and `None` is not comparable. Keep the
fields your rules read present in the input — both inputs above carry
`age` and `score`.

---

## Step 5 — collect every match instead of the first

The `"first"` policy stops at the first hit. Swap in the `"collect"`
policy with `Decision.with-policy` and the table returns a **List** of
every matching rule's `then` — handy for tagging, where several labels can
apply at once:

```boru
import "./decision.aql"

def tags (Decision.with-policy "collect" (Decision.make-table [
  (Decision.make-rule {field:"age"   op:"gte" value:18} {tag:"adult"})
  (Decision.make-rule {field:"score" op:"gte" value:50} {tag:"passing"})
]))

print (Decision.decide tags {age:25 score:80}) end
```

```console
$ boru classify.aql
[{"tag": "adult"}, {"tag": "passing"}]
```

Both rules matched, so both tags come back in a List. The other policies
are `"unique"` (exactly one match, else a `"multiple-matches"` or
`"no-match"` error) and `"priority"` (the matching rule with the highest
`priority` field wins).

---

## Step 6 — branch with a decision tree

A table is flat. When a decision depends on an earlier answer, reach for a
**decision tree**: branch nodes route the input to the next node by
testing a condition, and leaf nodes carry the final result. The node ids
are Atoms — quote a bare name with `/q`. Build a tree that first splits on
age, then asks adults whether they're a member:

```boru
import "./decision.aql"

def tree-nodes [
  (Decision.make-branch root/q [
    {when:{field:"age" op:"lt"  value:18} next:"minor"}
    {when:{field:"age" op:"gte" value:18} next:"adult-check"}
  ])
  (Decision.make-leaf minor/q "too-young")
  (Decision.make-branch adult-check/q [
    {when:{field:"member" op:"eq" value:true}  next:"vip"}
    {when:{field:"member" op:"eq" value:false} next:"guest"}
  ])
  (Decision.make-leaf vip/q   "welcome-vip")
  (Decision.make-leaf guest/q "welcome-guest")
]
def tree (Decision.make-tree root/q tree-nodes)

print (Decision.decide tree {age:12 member:true}) end
print (Decision.decide tree {age:40 member:true}) end
print (Decision.decide tree {age:40 member:false}) end
```

`Decision.make-tree` takes the `root` node id and the list of nodes;
`Decision.decide` walks from the root, following each branch's `next`
until it reaches a leaf and returns that leaf's `result`. Run it:

```console
$ boru classify.aql
too-young
welcome-vip
welcome-guest
```

The 12-year-old stops at the `minor` leaf and never reaches the
membership check. The two adults both pass the first branch, then split on
`member` at `adult-check`. Same `Decision.decide`, same input Maps — only
the model changed.

---

## Step 7 — peek at the primitives

`decide` is built from two smaller pieces you can call directly while
debugging. `Decision.eval-cond` tests one condition against an input;
`Decision.apply-op` is the raw comparison underneath it (`lhs op rhs`,
with the right-hand side first — `apply-op rhs op lhs`):

```boru
import "./decision.aql"

print (Decision.eval-cond {field:"age" op:"gte" value:18} {age:25}) end
print (Decision.eval-cond {field:"age" op:"gte" value:18} {age:15}) end
print (Decision.apply-op 18 "gte" 25) end
print (Decision.apply-op true "is_true") end
```

```console
$ boru classify.aql
true
false
true
true
```

The last line uses a **unary** op. The four unary ops — `is_true`,
`is_false`, `is_null`, `is_not_null` — take no `value` and are reached
only through the two-argument `Decision.apply-op rhs op` form, not through
a condition's `op` field. Reach for these when you want to inspect a
single test in isolation.

---

## What you've learned

- `Decision.make-rule when then` builds a rule; `Decision.make-table`
  collects rules into a table (default hit policy `"first"`).
- `Decision.decide model input` runs a table *or* a tree against an input
  Map — the model comes first.
- A miss is a value, not a throw: `{ok:false error:"no-match"}`. Check
  `result.ok` before trusting a result.
- `Decision.all-of` / `any-of` / `not-of` combine conditions; ordering ops
  on a missing field raise `not_comparable`.
- `Decision.with-policy "collect"` returns every match as a List;
  `"unique"` and `"priority"` are the other policies.
- A decision tree (`make-branch` / `make-leaf` / `make-tree`, ids as
  Atoms) routes through branches to a leaf when one answer depends on
  another.

## Where to go next

- Solve specific problems with the [How-to guides](how-to.md) — hit
  policies, trees, testing your models, running the suites.
- Look up exact signatures and record shapes in the
  [Reference](reference.md).
- Understand the design — the Comparable surface, generic rules, the
  hit-policy semantics — in the [Explanation](explanation.md).
