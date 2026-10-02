# Developer-experience report: porting `boru:decision` — notes for improving boru

> **Latest: [Migration to boru main @ 64c5ab2 (2026-10-01)](#migration-to-boru-main--64c5ab2-2026-10-01)**
> — all five suites fully compile and pass on the single execution path;
> three compile-defect workarounds, one library-side workaround for a
> `boru check` false positive, six open upstream defects with repros.

**Date:** 2026-06-11
**Builds under test:** `boru-lang/boru` @ `958c379b` (the `main` this library
originally targeted) and `db828ec` (the older ref the sibling bloom-filter/trie
libraries pin). Every finding below was reproduced against the actual binaries;
the commands and output are quoted verbatim.

> **Re-reviewed 2026-06-11 against `main` @ `7193a7d3`, re-confirmed
> 2026-06-18 against `main` @ `5aed3834`.** Upstream responded the same day
> the report was filed (`1981f601`, *"fix: decision DX report"*): findings
> **3, 4, 6, 8 are fixed**, **5 and 7** got their documentation halves (the
> `check` lints remain open), **2 is partially fixed** (the hint never fires
> for namespace-exposed words — this library's case), and **1 is unchanged**.
> Every status held on the re-confirm (`5aed3834` is ~200 commits later —
> bytecode-compiler, checker-accuracy, and vault work — none of it touches
> this library). All five test suites pass unchanged and every idiom block is
> byte-identical on both refs, so bumping the pin is verified safe — but the
> bump itself needs a maintainer, because the workflow file holding the
> canonical `BORU_REF` requires `workflow` scope to edit (see
> [the bump checklist](#re-review-status-on-latest-main-7193a7d3)). Verified
> evidence per finding:
> [Re-review: status on latest main](#re-review-status-on-latest-main-7193a7d3).

## Migration to boru main @ 64c5ab2 (2026-10-01)

**Build under test:** `boru-lang/boru` main @ `64c5ab2` (2026-09-30), 1,587
commits past the `6185620` this library was last verified on. **Result: all
five suites fully compile, run and print `all green` (smoke: clean exit), and
`boru check` reports 0 errors / 0 warnings on every suite and on
`decision.aql`.** Three compile defects needed a natural, semantics-preserving
rewrite (each carries a comment naming the defect). A fourth rewrite works
around a `boru check` false positive that blocked callers who pass Map-literal
models (workaround 4, defect F). Every assertion and expected value is
unchanged. Every code example in `AGENTS.md`, the skill,
`README.md` and `docs/` was executed against this build and fixed where it no
longer behaved as documented.

Separately, a **library fix** (2026-10-02) makes a rule's `then` and a leaf's
`result` data on every path: decision now returns a function stored there and
never calls it. It is a change to the library's semantics, kept whatever
happens upstream; the compiler defects it brought to light are recorded
upstream (rows G–J below).

### Breaking changes hit

| Change | Upstream | What it took here |
|---|---|---|
| **One execution path.** Every program compiles to bytecode and runs on the VM, or fails `[boru/compile_failed] … this is a compiler defect`; no interpreter fallback; `--compile` / `--force-compile` / `--no-compile` (and the `BORU_*COMPILE` env vars) retired — a usage error. `boru file` also runs the static check as a pre-flight; a check error blocks the run. | 2026-09-19 | `test/diverge.sh` rewritten: gate = every suite exits 0 under `boru <suite>` (and prints `all green` where it asserts) **and** `boru check` reports 0 errors on every suite and module. The interpreter/bytecode columns and the divergence diff are gone (there is nothing left to diverge from). `bench/bench.sh` rewritten to one mode with an independently computed checksum. |
| **`/r` → `/v`** (the word `ref` → `valof`). | ADR-011, 2026-08-19 | The 16 `export` entries in `decision.aql` (`cond/v`, …). |
| **Relative imports resolve against the importing file's directory** (run *and* check). | — | Suites and the bench `import "../decision.aql"`; the bench materialises its work copies next to the source. Every doc that said "relative to the working directory" corrected. |
| `aql:` module prefix gone (`boru:`), CLI binary is `boru`. | — | Nothing in code (no `boru:*` deps; the suites already used `boru:test`); doc/hook wording. |
| `print` still forward-collects (finding 5, by design). | — | The suites' stack-form summary `"---" print "fail count: " print Test.fail-count end print 0 Test.fail-count end Assert.equal end` let each `print` take the *next* statement's value; `"---"` was stranded and the final `Assert.equal` compared `Test.fail-count` against it — it passed only through the `Assert.equal` coercion defect below (and correctly failed when the count was non-zero). Rewritten as one forward `print (value)` per statement plus `Assert.equal 0 (Test.fail-count)`. Doc examples in the stack form `(x) print` printed out of order (e.g. `docs/reference.md` showed `false true` for `true false`) — all converted to `print (x)`. |
| Map printing keeps insertion order. | — | Tutorial console output `{"error": …, "ok": false}` → `{"ok": false, "error": …}`. |
| Integer is signed 64-bit (overflow still raises `integer_overflow`). | REFERENCE.md | Skill note said 63-bit; corrected. |

### Workarounds applied (remove when fixed upstream)

**1. `def x (do {map})` after a fn-local def — `decision.aql` (eval-tree and
all the miss results).** The miss results were written `(do {ok: false,
error: "…"})`. When a fn-local def precedes `def x (do {map})`, later
loop-body reads of that local break when compiled: `eval-tree` declined to
compile with *"fn eval-tree: a gradual read in a nested body has no seated
guard: the interpreter dispatches it as a word when it holds a fn (NUR361)"*
(it blocked `decision_unit_test` and `decision_smoke_test`), and the same
shape without the rebinding is a **wrong runtime answer** —
`undefined word`. A literal of literal values needs no `do`, so the misses
are now plain Map literals.

```boru
# compile decline (NUR361)
def fnode fn [[xs:List] [Any] [xs 0 get]]
def tw fn [[xs:List] [Any] [def cur 0 def r (do {}) for 2 [def cur (xs fnode) print cur] end r]]
print (tw [3])
# expected: 3 3 {}   actual: [boru/compile_failed] … fn tw: a gradual read in a nested body has no seated guard … (NUR361)

# runtime answer bug (same trigger, unrecorded)
def tw fn [[n:Integer] [Any] [def cur (n add 2) def r (do {}) for 2 [print cur] end r]]
print (tw 1)
# expected: 3 3 {}   actual: [boru/undefined_word]: undefined word: cur   (boru check: 0 errors)
# both: `def r {}` (no `do`) compiles and prints 3 3 {}
```

**2. `do {…}` with effectful list values in a property generator —
`test/decision_prop_test.aql` (P2).**

```boru
import "boru:test"
Test.check-prop "p" [do {a: [r.int 0 5], b: [r.int 0 5]}] [var [[pair] true]] 5 1 0
# [boru/compile_failed] … fn storedfn$body: a call matched at run time takes a list or map
# literal whose evaluation may have an effect … (NUR356)
```

Rewritten as `[{a: (r.int 0 5), b: (r.int 0 5)}]` — a map literal evaluates
its paren values directly, giving the same generated map.

**3. A loop-body def of a computed `if` over the same name —
`bench/decision_bench.aql`.**

```boru
def acc 0
for 3 [def acc (if (i 1 gt) [acc 1 add] [acc])] end
print (acc)
# expected: 1   actual: [boru/compile_failed] dynamic-scope def `acc` of unpromoted computed value
```

Rewritten as `if ok [def acc (acc 1 add)] []` (the "dynamic-scope def
family" in boru's `design/COMPILABLE-SUBSET.md`).

**4. Map-literal models passed to the kind-dispatching words —
`decision.aql` (`eval-pred`, `decide`).** Defect F below: the pre-flight check
analyses an imported fn's untaken arm with the caller's Map literal and
reports `no_signature` on the absent field, blocking the run. It hit
`Decision.decide` with a literal tree or table, and also
`Decision.eval-pred` with a bare condition literal (analysed through the
group arm, `children` None) or a group literal (analysed through the
condition arm, `field` None). The API reference documents all of these call
shapes. Both words now pass the record to each arm through a `[Map]`-declared
identity, `def as-map fn [[m:Map] [Map] [m]]`, so the checker sees a plain
`Map`, not the literal's shape. Runtime behaviour is identical: the same
results on every probe, and a malformed model, such as a table without
`rules`, still raises `signature_error`. The false positive depends on the
*first* call: boru check analyses an imported word with the argument shapes of
its first call, so a program whose first `eval-pred` call takes a
builder-made predicate never sees it. `test/decision_smoke_test.aql` therefore
opens with literal-model calls, so the gate fails if the workaround is
dropped (verified: against the pre-workaround `decision.aql` its pre-flight
check fails with 5 errors). Each call below was blocked by the check before
the change and now runs:

```boru
import "./decision.aql"
print (Decision.eval-pred {field:"age" op:"gte" value:18} {age:25})                                    # => true
print (Decision.eval-pred {kind:"group" op:"all" children:[{field:"age" op:"gte" value:18}]} {age:25}) # => true
print (Decision.decide {kind:"tree" root:"r" nodes:[{id:"r" kind:"leaf" result:"welcome"}]} {age:40})  # => welcome
print (Decision.decide {kind:"table" rules:[{when:{field:"age" op:"gte" value:18} then:"adult"}]} {age:25}) # => adult
```

### Library fix: a stored `then` / leaf `result` is data (2026-10-02)

Not a workaround: this is the library's own contract, and it stays when the
upstream defects below are fixed. A rule's `then` and a leaf's `result` are
the decision's **result value**. The evaluators now return them exactly as
stored on every path. A function stored there comes back as a Function value
(read it with `/v`), and decision never calls it.

Before, the answer depended on the path. Each evaluator ended by reading the
value through a bare name (`… end result`), and in boru a bare name holding a
function calls it (ADR-011). What happened to a fn stored in `then` /
`result` on `64c5ab2`:

| Path | Before | Why | Now |
|---|---|---|---|
| `first` and `priority` hit policies; trees | **called** (the result was the fn's return value) | bare tail read; the stamp declined (row G), so the fn ran on the interpreter, which dispatches the read | the Function |
| `unique` | returned uncalled | bare read in an `if` arm after the `for`; that unit compiled, and the compiled read does not dispatch (row I, a miscompile) | the Function |
| `collect` | returned uncalled | the values are pushed into a list, never read by name | the Function |
| `make-leaf` with a fn `result` | **the program did not compile** (`` fn make-leaf: bare read of `result` is consumed where the interpreter dispatches it (a container member …) — NUR123 ``) | the bare read sat inside the record literal | a `LeafNode` holding the fn |

The fix reads each value with `/v` at seven sites: the tails of
`eval-table-first`, `eval-table-priority`, `eval-tree`, `find-node` and
`find-branch-next`, the `unique` arm, and `make-leaf`'s record literal.
(`make-rule` is unchanged: its `then` parameter is declared `Map`, so a fn
`then` can only come from a literal rule.) Data results are unaffected:
every suite's expected values are unchanged, and the bench checksum stays
`1184`. As a side effect, the five functions whose stamp declined (row G)
now stamp, so every `Decision` word runs compiled (`boru -compile-report`
lists no library declines). `test/decision_unit_test.aql`'s
`stored-fn-results-are-data` case checks all six paths: four hit policies,
a literal tree and a builder tree. Against the previous `decision.aql` it
fails. The builder row stops the suite compiling, and without that row the
case fails (fail count 1). `AGENTS.md`, the skill, `docs/reference.md` and
`api.json` (`conventions.results_are_data`) document the contract.

```boru
import "./decision.aql"
def f42 ([] => [42])
def w {field:"age" op:"gte" value:18}
def out (Decision.decide {kind:"table" hit-policy:"first" rules:[{when:w then:f42/v}]} {age:25})
print (out/v typeof)
# now: Function    before: Integer (first/priority/trees called it; unique/collect did not)
```

**Calling a returned function.** It is the caller's to call, and on
`64c5ab2` only some spellings agree with the interpreter (row J). These do,
and are what the docs name: `41 out/v apply` (arguments first, then the
value with `/v`), or passing `out/v` to a fn whose parameter is declared
`Function` (`(g n)` inside it; `(g)` for a 0-arg one). `print (41 out) 7`
compiles and answers wrongly without an error (it prints `41` and leaves
`8`; the interpreter prints `42` and leaves `7`). `(out 41)` and a 0-arg
`out/v apply` fail to compile.

### Open upstream defects found

| # | Kind | Defect | Record | Effect here |
|---|---|---|---|---|
| A | compile defect | `def x (do {map})` after a fn-local def → NUR361 decline in a later nested read | NUR361 (shape not listed) | worked around (1) |
| B | runtime answer bug | same trigger → `undefined word` for the earlier local in a later loop body | unrecorded | worked around (1) |
| C | compile defect | effectful `do {k: [..] …}` literal in a stored fn body | NUR356 | worked around (2) |
| D | compile defect | dynamic-scope def of an unpromoted computed value | COMPILABLE-SUBSET "dynamic-scope def family" | worked around (3) |
| E | runtime answer bug | **`Assert.equal` coerces a mismatched type to the expected type's zero value**: `Assert.equal 0 "A"`, `Assert.equal "" 5`, `Assert.equal false [1]` all *pass*. `assertEqualHandler` calls `core.ValuesEqual`, which assumes both sides share a type and reads the second through the first's accessor (`AsInteger("A")` → 0). Any `Assert.equal` whose computed side is `0`/`""`/`false` passes against a value of another type. | unrecorded | masked the broken suite summaries until they were fixed; the unit suite was re-verified with a structural `deq` check (all 35 assertions hold) |
| F | checker false positive | **`boru check` analyses an imported fn's untaken `if` arm with the caller's concrete Map literal** and reports `no_signature` on the absent (None) field, which blocks the run. `Decision.decide` with a Map-literal model hits it (a literal tree has no `rules`: `cannot call eval-table-first … got (Map, None)`; a literal table has no `nodes`: `cannot call find-node … got (None, None)`), and so does `Decision.eval-pred` with a bare-condition literal (`cannot call eval-pred-all … got (Map, None)`) or a group literal (`cannot call convert … got (None, Word)` in `eval-cond`). The same program in one file checks clean. The excerpt printed is the importing file's while the position is the imported module's. | unrecorded | worked around in the library (4); the suites were never affected (they pass literals only inside `Test.test` bodies or through `Test.run-spec`, which the check does not specialise) |
| G | compile refusal | **A file-imported fn whose body result is a bare read of a gradual non-parameter binding declines its stamp** (`` stored fn: bare read of `result` may hold a fn the interpreter dispatches as a word (NUR279) ``), so every call of it runs on the interpreter, data or fn. | `design/COMPILABLE-SUBSET.md` §5, open refusals recorded 2026-10-02 ([boru-lang/boru#528](https://github.com/boru-lang/boru/pull/528)) | five functions declined (`eval-table-first`, `eval-table-priority`, `eval-tree`, `find-node`, `find-branch-next`); none now, since the library fix above reads `/v` |
| H | runtime answer bug | **such a declined fn that breaks its declared return count raises `internal_error` compiled** (`dynamic frame replay … result count 2 differs from the declared 1`), where the interpreter raises the return contract's `type_error` | NUR366 ([#528](https://github.com/boru-lang/boru/pull/528)) | none: found while narrowing row G; every `Decision` fn leaves exactly its declared values |
| I | runtime answer bug (**silent**) | **a local rebound in a `for` / `while` body and read bare in an `if` arm after the loop, holding a fn, comes back uncalled compiled**; the interpreter calls it. With an `each` / `for-each` body the compiled lane raises instead. One-file repro, `boru check` clean. | NUR367 ([#528](https://github.com/boru-lang/boru/pull/528)) | made the `unique` hit policy return a stored fn uncalled while `first` / `priority` called it; none now (the library fix) |
| J | runtime answer bug (**silent**) + compile refusals | **calling a fn value obtained at run time and held in a local**: `print (41 out) 7` prints `41` and leaves `8` compiled (the interpreter prints `42` and leaves `7`; `boru check` clean); a 0-arg one bound `def r (out)` reads back `undefined_word`; most other spellings (`(out 41)`, a 0-arg `out/v apply`, `[(41 out) 7]`) fail to compile | NUR368 + `design/COMPILABLE-SUBSET.md` §5 ([#528](https://github.com/boru-lang/boru/pull/528)) | a caller applying a returned `then` / `result`; the docs name `41 out/v apply` and a `Function`-typed param, which agree |

Minimal standalone repro for F (two files):

```boru
# lib.boru
def cnt fn [[xs:List] [Integer] [xs size]]
def f fn [[m:Map] [Any] [if ((m get "kind") "list" eq) [(m get "xs") cnt] [0]]]
export "L" {f: f/v}

# main.boru
import "./lib.boru"
print (L.f {kind:"other"})
# expected: 0   actual: check: 2:70: [error] no_signature: cannot call `cnt` … got (None); nearest [List]
```

The same program in **one** file (`def cnt …`, `def f …`, `print (f
{kind:"other"})`) checks clean and prints `0`, so the trigger is the import
boundary plus a concrete literal argument; `boru -no-check main.boru` also
prints `0` (the run itself is correct — only the pre-flight check blocks it).

The library-level repro, against `decision.aql` *before* workaround 4 (a
scratch dir holding a copy of that version):

```boru
import "./decision.aql"
def tree {kind:"tree" root:"root" nodes:[
  {id:"root" kind:"leaf" result:"welcome"}
]}
print (Decision.decide tree {age:40})
# expected: welcome
# actual:   check: 180:157: [error] no_signature: cannot call `eval-table-first` — no signature
#           matches the arguments; got (Map, None); nearest [List Map] … (×5, one per
#           eval-table-* call in decide's untaken "table" arm) → check failed: 5 error(s)
```

`def tbl {kind:"table" policy:"first" rules:[]}` + `Decision.decide tbl
{age:40}` is the mirror image (2 errors: `cannot call find-node … got (None,
None)` from the untaken "tree" arm). `Decision.eval-tree tree {age:40}` and
`Decision.decide (Decision.make-tree root/q [(Decision.make-leaf root/q
"welcome")]) {age:40}` both check clean and print `welcome` — the builders
return a Map whose fields the checker does not specialise. No NUR / check-
accuracy record found for this shape (NUR.md is the answer-divergence
register; `design/CHECK-ACCURACY-RATCHET.10.md` lists none like it).

**Not hit here: the `boru:test` type-ID collision.** On `64c5ab2`
`boru:test` mints its record types from a fresh type-ID counter, so in a
program that imports `boru:test` a library fn *declared to return its own
class* fails its return contract (`expected X, got X`; the sibling bloom and
stats libraries import their module before `boru:test` to dodge it). Every
`Decision` word is declared to return `Map`, `Boolean` or `Any` — the
`refine Record` types are documentation, never a return contract — so the
suites keep their `import "boru:test"` first. Verified: builders, `decide`
on a builder table and on a builder tree all run correctly after
`import "boru:test"`.

### Original findings, re-checked on `64c5ab2`

**1** still open (no tags at all now; `cmd/go/go.mod` still carries local
`replace`s). **2** still partial: the swapped `Decision.with-policy t
"collect"` is now an `uncalled_function` *check error* (it blocks the run —
better), but with no swap hint, and the Map/Map swap `Decision.decide
{age:25} table` still silently returns `unknown-model-kind`. The plain-word
hint the `7193a7d3` re-review saw is gone as well: a plain
`def wp fn [[policy:String table:Map] [Map] [table]]` called `wp {a:1} "x"`
reports `no_signature … got (Map, ProperString); nearest [String Map]` with
no reorder suggestion. (`mixed_form_call` cannot help: it fires only for 3+-
argument *mixed-form* calls whose deepest stack slot is `Any`.) **3, 4, 6, 8**
remain fixed. **5** and **7**: behaviour unchanged by design; the proposed
`check` lints are still absent (`"a" print "b" print` prints `b a`, and
`{a:1} {a:1} eq` draws no warning).

---

This report comes out of porting the interpreter's internal `boru:decision`
module into a standalone pure-boru library. The port itself went well — the
module's boru source ran as a file module essentially unchanged (see
[What worked well](#what-worked-well)) — so this is **not** a complaint list;
it is the set of language/tooling friction points that cost real time, written
up so they can be fixed at the source.

## How to read this

Each finding is tagged:

- **language-bug** — incorrect or surprising semantics.
- **rough-by-design** — the behaviour is intended and consistent, but the
  ergonomics or diagnostics around it are poor.
- **tooling** — build / version / release / CLI, not the language proper.
- **docs-gap** — works, but the safe path is undiscoverable.

…and a severity for a library author (`high`/`medium`/`low`).

## Priority summary

| # | Finding | Tag | Sev | One-line fix | Status @ `7193a7d3` |
|---|---------|-----|-----|--------------|---------------------|
| 1 | No installable `boru` release — everyone builds from source | tooling | **high** | Tagged releases + prebuilt binaries; unblock `go install` | **open** |
| 2 | A swapped argument order has no "did you mean reordered?" hint — and can silently return a *wrong answer* | rough-by-design | **high** | On signature failure, try arg permutations and say so | **partial** — fires for plain words, not namespaced ones |
| 3 | No first-class key-presence predicate (`has`), and no catch/recover word | language-bug | medium | Add a total `has`/`haskey` Boolean (the missing `get`/`getr` sibling) | **fixed** — `has` shipped |
| 4 | Errors raised across an import boundary lose their filename + source excerpt and leak a `CallAQL:` prefix | language-bug | medium | Render imported-file errors like entry-file errors | **fixed** |
| 5 | `print` forward-collects, so sequential prints emit out of order — silently | rough-by-design | medium | Ship `puts`/`println` (= `print/s`); have `check` flag stranded operands | docs fixed; lint open |
| 6 | `do/error` leaks the caught error on the stack (and `raise`'s own doc example is broken) | rough-by-design | medium | Bind the error as a normal arg; make the construct stack-neutral | **fixed** |
| 7 | `eq` on maps/lists is identity-based — equal literals compare `false`, silently | rough-by-design | medium | `check`-time warning when both `eq` operands are Map/List (esp. a literal) | docs fixed; lint open |
| 8 | `boru -version` reports `0.1.0-dev`, ignoring the embedded VCS revision; skew errors misdirect | tooling | medium | Read `debug.ReadBuildInfo` vcs.revision; better "needs newer boru" hint | **fixed** |

---

## Re-review: status on latest main (7193a7d3)

Re-tested 2026-06-11 against `main` @ `7193a7d3` (39 commits past
`958c379b`), which includes upstream's same-day response commit `1981f601`
(*"fix: decision DX report — do/error stack-neutral, has word,
import-boundary errors, swapped-arg hint, version stamp, doc fixes"*). All
five of this library's test suites pass unchanged on `7193a7d3`, every
AGENTS.md/skill code block re-verified, and `boru check --soft` behaves as
before — so adopting it is safe. Per-finding status, each re-verified
against the freshly built binary:

> **Re-confirmed 2026-06-18 against `main` @ `5aed3834`** (the newest main,
> ~200 commits past `7193a7d3` — mostly the bytecode-compiler effort, checker
> accuracy, and vault TUI). Every per-finding status below is unchanged, all
> five suites still pass, all idiom blocks emit identical output, and the
> advisory `boru check --soft` noise even dropped (51→39 errors, from the
> checker-accuracy work). The findings still open — **1** and the
> namespaced-word half of **2** — are still open verbatim. If the pin is
> bumped, `5aed3834` is the newest verified-safe target; the checklist below
> uses it.

**1 — open.** Still exactly one tag (`eng/go/v0.0.1`, the kernel sub-module,
not the CLI), and all four `replace` directives remain in `cmd/go/go.mod`,
so `go install …@latest` stays blocked and every consumer still bootstraps
from a pinned clone — this review hand-built yet another one.

**2 — partially fixed.** The proposed permutation probe exists and fires for
plain words, in both the forward and the stack form:

```
$ boru -e 'def wp fn [[p:String t:Map] [Map] [t]] wp {a:1} "collect"'
error: [aql/signature_error]: no matching signature for wp
  = no signature matches (Map, ProperString); one exists for (String, Map)
    — did you swap the arguments? expected: wp p:String t:Map
```

But it never fires for **namespace-exposed words** — and this library
exports everything through `surface`/`exposes`. The report's original repro,
`Decision.with-policy table "collect"`, still fails down the
`uncalled_function` path with a swap-blind hint (*"check the call's argument
types and arity — or use with-policy/r …"* — better than the old grouping
hint, but it doesn't see the reorder). And the dangerous same-typed swap,
`Decision.decide {age:30} table`, still returns the byte-identical
`{ok:false error:"unknown-model-kind"}`, as predicted — no checker can catch
Map/Map. Remaining ask: run the same permutation probe on the
namespaced-dispatch failure path, where real library calls live.

**3 — fixed.** `has` shipped with exactly the proposed semantics: a total
Boolean presence test that distinguishes present-but-`None` from absent,
mirrors `get`'s container table, never raises, and composes in conditions:

```
$ boru -e '{a:None} "a" has'                  # present, value None
true
$ boru -e '{a:1} "b" has'                     # absent
false
$ boru -e 'none "a" has'                      # None parent — total
false
$ boru -e '[{a:1} {b:2}] filter ["a" has]'    # composes
[{a:1}]
```

(Relatedly, `getr`'s absence raise now carries the documented `not_found`
code — `93ebcd40`.) This unblocks the library-side follow-up: the
presence/optional-input conditions this module had to cut are now
expressible.

**4 — fixed.** The same missing-field repro now renders with the imported
file's name, source excerpt, and caret — identical fidelity to entry-file
errors — and the `CallAQL:` prefix is gone:

```
error: [aql/not_comparable]: gte
  --> ./decision.aql:130:396
  130 | def apply-op gen [(T extends Comparable)] fn [[rhs:T op:String lhs:T] …
                                                            ^^^^^ gte
```

**5 — docs fixed; the `check` lint remains open.** Behaviour is unchanged by
design (`"a" print "b" print` still emits `b` then `a`), but
`describe print` now documents the ordering pitfall prominently and
recommends `print/s` or statement terminators for sequences. The proposed
`check` advisory for stranded-then-flushed values is still future work.

**6 — fixed.** `do [ raise "boom" ] error [ "recovered" ]` now leaves
exactly `recovered` — nothing leaks to stdout, and the
`def result do […] error […]` form binds the handler's result, not the
caught error. The broken `dup.got` example in `describe raise` was replaced
with the working `var [[e] …]` form.

**7 — docs fixed; the `check` lint remains open.** Identity semantics are
intentionally kept, but `describe eq`'s notes now lead with
`` `{a:1} eq {a:1}` is `false` `` and close with "in tests, assert maps/lists
with `deq`, not `eq`". The proposed `check`-time warning for Map/List `eq`
operands is still future work.

**8 — fixed.** Dev builds now read the embedded VCS stamp:

```
$ boru -version
boru 0.1.0-dev (git 7193a7d3c698, dirty)
```

**Net:** four findings fully fixed (3, 4, 6, 8), two shipped their
documentation halves with the `check` lints still open (5, 7), one is
partially fixed with a concrete remaining gap (2 — the probe skips
namespace-exposed words), and the release-engineering finding is untouched
(1). The two `high`-severity items are, fittingly, the two still open:
installable releases, and swap diagnostics on the dispatch path real
libraries actually use.

**To adopt the pin** (verified safe; needs a maintainer because
`.github/workflows/test.yml` requires `workflow` scope — finding 1 in
miniature): set the new ref in every lockstep location, then re-run the
suites —

1. `.github/workflows/test.yml` → `BORU_REF: 5aed3834d9cc1bd4fd1ea5ad5b5ef37f9c973574`
   (the single source of truth the consistency job checks the rest against),
2. `.claude/hooks/session-start.sh` → the same 40-char `BORU_REF`,
3. `api.json` → `"aql_ref": "5aed3834"`,
4. the short-ref mentions in `README.md` ("pinned commit"), `CLAUDE.md`
   (`BORU_REF =`), and `docs/how-to.md` (the `git checkout` line).

---

## 1. No installable `boru` release — every consumer builds from source · *tooling · high*

> **Re-review @ `7193a7d3`: still open.** See [the re-review](#re-review-status-on-latest-main-7193a7d3); the section below is the original finding, kept as the record.

A downstream pure-boru library needs a *specific* `boru` binary to run and test
its module (this one requires `958c379b`). There is no tagged release, no
`brew`/binary download, and `go install` is blocked:

```
$ go install github.com/boru-lang/boru/cmd/go/aql@latest
go: ...cmd/go@v0.0.0-20260611024449-958c379b1229: The go.mod file for the module
providing named packages contains one or more replace directives. It must not
contain directives that would cause it to be interpreted differently than if it
were the main module.

$ git -C boru tag
eng/go/v0.0.1          # the ONLY tag — and it's the kernel sub-module, not the CLI
```

So the only bootstrap is `git clone` + `cd cmd/go && make build`, at a commit
that must then be single-sourced across every consumer touchpoint (CI workflow,
SessionStart hook, `api.json`) and re-pinned by hand each time the language
moves. This library already pins a *different* commit than its sibling repos,
multiplying the bookkeeping.

**Suggestion.** (1) Publish prebuilt binaries via tagged GitHub Releases +
goreleaser so non-Go consumers (CI hooks) can `curl` a versioned asset.
(2) Unblock `go install ...@vX.Y.Z`: the two local-path replaces in
`cmd/go/go.mod` (`=> ../../eng/go`, `=> ../../lang/go`) are monorepo-dev only —
move them to a `go.work` file (which `go install` ignores) and require `eng/go`
/ `lang/go` at real tags; the two remaining replaces are dependency *renames*
(`voxgig/struct => voxgig/struct/go`, `voxgiguniversalsdk => voxgig/udk/go`) —
import the real published paths in code so no rename is needed. (3) Cut semver
tags for the CLI module so `@latest` resolves.

---

## 2. A swapped argument order has no diagnostic — and can silently return a wrong answer · *rough-by-design · high*

> **Re-review @ `7193a7d3`: partially fixed — the hint fires for plain words but not namespace-exposed ones.** See [the re-review](#re-review-status-on-latest-main-7193a7d3); the section below is the original finding, kept as the record.

The receiver/model-first convention reads naturally but is easy to invert, and
inverting it produces one of three unhelpful symptoms depending on the arg
types. We mis-ordered `decide`, `eval-cond`, and `with-policy` several times.
The dangerous one is same-typed params:

```
# Decision.decide takes (model, input), both Map. Swap them:
Decision.decide {age:30} table     # => {"error": "unknown-model-kind", "ok": false}
```

That output is **byte-identical to a legitimate** `unknown-model-kind` result —
exit code 0, and `boru check` is clean — so a swapped call looks like a real
domain error and you debug the wrong thing. With distinct types it's instead a
silent no-dispatch:

```
$ boru check -e '... Decision.with-policy table "collect"'   # args swapped (Map, String)
check: [error] uncalled_function: call to 'with-policy' matched no signature
       and was left on the stack as data (arguments: Map, ProperString)
```

The checker prints the *actual* arg types and `describe` knows the declared sig
`[String Map]` — yet the only structural hint offered is "forward args may have
run into the next word; group with parens", which points at parsing and is the
wrong fix.

**Suggestion.** When a call matches no signature, run a cheap permutation check
of the actual arg-type tuple against each declared sig; on a reorder match, emit
a dedicated hint — *"no signature matches (Map, String); one exists for (String,
Map) — did you swap arguments? expected: `with-policy policy:String table:Map`"*
— and suppress the misleading grouping hint. For genuinely same-typed params
(Map/Map) the checker can't tell, so also document encouraging
positionally-distinct nominal types (e.g. `refine Record` `Model` vs `Input`) so
dispatch can distinguish them.

---

## 3. No first-class key-presence predicate, and no catch/recover word · *language-bug · medium*

> **Re-review @ `7193a7d3`: fixed — `has` shipped.** See [the re-review](#re-review-status-on-latest-main-7193a7d3); the section below is the original finding, kept as the record.

A decision condition wants to ask "is this field present?" (DMN-style optional
inputs). It can't be expressed, because there is no way to distinguish *absent*
from *present-but-`None`*, and no Boolean presence test:

```
$ boru -e '{a:1}    "b" get'    # absent
None
$ boru -e '{a:None} "a" get'    # present, value is None
None
$ boru -e '{a:1} "a" has'       # and there is no presence word
error: [aql/undefined_word]: undefined word: has      # same for haskey, has-key, in, member
```

`getr` *can* tell them apart, but it **raises** rather than returning a Boolean —
and there is no `try`/`catch`/`recover`/`rescue` word anywhere in `boru describe`
to turn that raise into a predicate. So the whole class of presence/optional
conditions had to be cut from the decision tables/trees (the module's own
`api.json` documents the surrender).

**Suggestion.** Add a total Boolean `has` (alias `haskey`): `{a:None} "a" has`
→ `true`, `{a:1} "b" has` → `false` — "the key is bound, regardless of value".
Mirror `get`'s signature table (String/Atom key over Map/Object/Store; Integer
index over List/Array) and return `false` (never raise) on a `None` parent, so
it composes inside `if`/`filter`/conditions. It is the missing third member of
the `get` (None on miss) / `getr` (raise on miss) family — and its
implementation is the lookup `getr` already does, returning ok/err as a Boolean.
(Lower priority: a `try`/recover primitive would also let userland downgrade any
raise to a value.)

---

## 4. Errors across an import boundary lose their location · *language-bug · medium*

> **Re-review @ `7193a7d3`: fixed.** See [the re-review](#re-review-status-on-latest-main-7193a7d3); the section below is the original finding, kept as the record.

An error raised inside an *imported* file renders far worse than the same error
in the entry file. Evaluating a condition against an input missing the queried
field (very common) aborts with:

```
error: CallAQL: [aql/not_comparable]: gte
  --> 130:396
```

`130:396` points into a long one-line definition of an imported file that is
**not named**, with **no source excerpt** — you can't tell which of 14 exported
functions failed or on which field. The same raise in the *entry* file gets the
normal treatment (excerpt + caret). Worse, the language's *own* comparison error
is genuinely good — and it too collapses across an import:

```
# direct, entry file — actionable:
error: [aql/incomparable]: gte: cannot order None and Integer
  = different types with no shared ordering; use tcmp for a cross-type total order

# the identical error, raised from inside an imported file — location lost, prefix leaked:
error: CallAQL: [aql/incomparable]: gte: cannot order None and Integer
  --> 1:40
```

**Suggestion.** Render imported-file runtime errors with the same fidelity as
entry-file errors: `--> decision.aql:130:396` plus the source-line excerpt and
caret, and drop the internal-sounding `CallAQL:` prefix (or replace it with a
real call-site frame). This helps *every* error that crosses an import boundary.
(Separately, the bare `gte` body here is partly the library's doing — its
`raise not_comparable op` passes only the op string instead of the
field/operands — but the location-rendering gap is the language's.)

---

## 5. `print` forward-collects, so sequential prints emit out of order — silently · *rough-by-design · medium*

> **Re-review @ `7193a7d3`: docs fixed; `check` lint still open.** See [the re-review](#re-review-status-on-latest-main-7193a7d3); the section below is the original finding, kept as the record.

`print` looks ahead for its argument, so each `print` grabs the *next*
statement's value and the leftovers flush at program end:

```
$ boru /tmp/p.aql        # source:  "a" print  "b" print
b
a
$ boru /tmp/p3.aql       # three statements, one print each (no `end`)
b
c
a                       # not even a clean reverse
```

It never errors and `boru check` says nothing, so it silently scrambles any
test/smoke/doc snippet that prints a sequence of values — and a 3-way scramble
makes "is my expected output right?" unreliable. The clean fix already exists
but is undiscoverable:

```
$ boru /tmp/ps.aql       # "a" print/s  "b" print/s  "c" print/s   (stack-only modifier)
a
b
c
$ boru describe print    # …never mentions /s or the ordering pitfall
print — Print a value to stdout followed by a newline.  Precedence: forward …
```

**Suggestion.** Ship a non-collecting `puts`/`println` defined as `print/s` (or
have `describe print` recommend `print/s` / `print … end` for sequences). And
extend `check`: the existing `forward_strands_operand` advisory ignores 1-arg
forward-only words like `print`; make it fire when a forward word strands *any*
value at a statement boundary that is later flushed unconsumed.

---

## 6. `do/error` leaks the caught error on the stack · *rough-by-design · medium*

> **Re-review @ `7193a7d3`: fixed.** See [the re-review](#re-review-status-on-latest-main-7193a7d3); the section below is the original finding, kept as the record.

The natural recovering wrapper `do [ …risky… ] error [ fallback ]` silently
leaves the caught error on the stack *beneath* the handler's result — so the
next `def`/sig-match binds the wrong value, or the error auto-prints:

```
$ boru -e 'do [ raise "boom" ] error [ "recovered" ]'
error(boom) recovered                         # the error leaked onto stdout

$ boru /tmp/r12.aql       # def result do [ raise "boom" ] error [ "recovered" ]   result print
recovered
error(boom)              # `def result` bound the top; error(boom) leaked beneath and auto-printed
```

The happy path `do [ 42 ] error [ … ]` is stack-neutral (leaves just `42`), so
the error branch's extra value is an asymmetry you only discover via a stray
`error(...)` or a downstream mismatch — no diagnostic. The correct form,
`error [ var [[e] … ] ]`, has to be known in advance.

**Bonus bug:** `raise`'s own documented example is broken —
`do [raise {…got:42}] error [dup.got print]` raises `signature_error: no
matching signature for dup` (because `dup.got` parses as `dup get got`). The
working forms are `error [ get got print ]` or `error [ var [[e] e.got print ] ]`.

**Suggestion.** Make the handler receive the caught error as a normal bound
argument (the `var [[e] …]` binding becomes the default) and make `do/error`
leave exactly one value — the handler's result — mirroring the happy path. Fix
or remove the broken `dup.got` doc example.

---

## 7. `eq` on maps/lists is identity-based — equal literals compare `false` · *rough-by-design · medium*

> **Re-review @ `7193a7d3`: docs fixed; `check` lint still open.** See [the re-review](#re-review-status-on-latest-main-7193a7d3); the section below is the original finding, kept as the record.

Comparing two structurally-equal maps with `eq` is `false` — at top level,
inside an fn body, and inside an `each`/`var` body alike (we initially suspected
a scope-dependent flip; there is none — it's consistently `false`):

```
$ boru /tmp/eq.aql
top  : false        # ({a:1} eq {a:1})
fn   : false        # same, inside an fn body
each : [false]      # same, inside each/var
deq  : true         # deq is the structural compare
```

This is documented (`describe eq`: "Compound values compare by IDENTITY … use
`deq`") and intentional — but a property test naturally writes
`result eq {hit:"first"}`, which reads as obviously true and silently yields
`false`. Every map assertion in the test suite had to be rewritten to extract a
scalar field first.

**Suggestion.** Keep the semantics, but add a `check`-time warning when both
`eq`/`neq` operands are statically Map- or List-typed (the `x eq {literal}` case
is almost always a mistake and is cheaply detectable): *"`eq` on Map compares by
identity; did you mean `deq`?"* Surface the `{a:1} eq {a:1} => false` / `deq =>
true` pair in `describe eq`'s examples, and consider a `Test`/`Assert`
deep-equal helper so test authors stop re-inventing the per-field workaround.

---

## 8. `boru -version` hides the build commit; skew errors misdirect · *tooling · medium*

> **Re-review @ `7193a7d3`: fixed.** See [the re-review](#re-review-status-on-latest-main-7193a7d3); the section below is the original finding, kept as the record.

A stale `boru` on PATH silently lacked newer words, and `-version` couldn't
disambiguate the build — everything not `make publish`'d reads `0.1.0-dev`, even
though the Go toolchain already embeds the revision:

```
$ boru -version
boru 0.1.0-dev
$ go version -m $(which boru) | grep vcs
	build	vcs.revision=958c379b12295652c739a88f2f198726d48897fb
	build	vcs.modified=true            # boru just never reads this
```

And when you *do* run an older build, the version-skew error misdirects — it
reads as a quoting mistake in your code, never "this word is newer than your
binary":

```
$ aql-db828ec -e 'def C surface {…}'
error: [aql/undefined_word]: undefined word: surface
  = did you mean `def … (surface)` to bind its value, or `def … surface/q` …?
```

**Suggestion.** In the `-version` path, when `Version == "0.1.0-dev"`, fall back
to `debug.ReadBuildInfo()` and append the VCS stamp (e.g. `boru 0.1.0-dev (git
958c379b, dirty)`); stop hardcoding `VERSION := 0.1.0-dev` for dev builds. Make
the `undefined_word` "did you mean (x)/x/q" hint fire only when a same-named
binding plausibly exists; otherwise emit a neutral *"'surface' is not defined in
this build — it may be a newer language word; check `boru describe` or upgrade
aql."* (Higher-effort: let `aql.jsonic` declare a minimum engine revision so
`import`/`check` can fail with *"requires boru ≥ <rev>"*.)

---

## Library-side notes (not language issues)

These tripped the port too, but they are decision-module *design* choices, not
boru problems — recorded so they aren't mistaken for language bugs:

- **Evaluators take the model first, the input second** (`decide model input`).
  A convention, not a language rule. (It's the *diagnostic* when you get it
  wrong that's the language issue — see finding 2.)
- **Unary ops (`is_null`/`is_not_null`) are unreachable through `eval-cond`** —
  `eval-cond` always supplies a `value`, so a unary op there raises. This is
  downstream of the missing `has` predicate (finding 3); the module simply can't
  express a presence condition. *(Update: `has` shipped in `7193a7d3`, so this
  is now a library to-do rather than a language blocker.)*
- **`make-rule` requires a `Map` `then`** while `make-leaf` accepts any result —
  a builder being stricter than its generic type, a module choice.
- **A "miss" is a value** (`{ok:false error:"…"}`), not a throw — a good pattern,
  noted because a hit has *no* `ok`/`error` fields (inspect `result.error`).

## What worked well

- **The native module's boru *is* the library.** `boru:decision` is implemented
  as an embedded boru source string with a thin Go loader; that source ran as a
  standalone file module with **zero changes** (only a header added). That the
  same boru works as a built-in module and a vendored file is a real strength of
  the design.
- **`refine Record` + generics + `surface`/`exposes`** expressed the typed
  decision records (Cond/Pred/Rule/DTable/DTree, the `Comparable` surface)
  cleanly and read well.
- **Loud-over-silent comparison** (raising on `None` ordering instead of
  returning a silent `false`) is the right call — the issue (finding 4) is the
  error's *location rendering*, not the policy.
- The safe primitives all **exist** — `print/s`, `deq`, `getr` — the gaps are
  discoverability (`describe`) and diagnostics (`check`), which are cheap to
  close.

## Bottom line

The language is clearly capable — a non-trivial DSL module ported to a
standalone library with no algorithm changes. The friction was almost entirely
in **diagnostics and tooling**: a swapped argument, a missing key, or a
cross-import raise all fail in ways that point at the wrong cause, and the
toolchain can't be installed or version-identified without ceremony. The two
highest-leverage fixes — installable releases (1) and reorder-aware signature
diagnostics (2) — would remove most of the time this port lost, and the
`check`-time lints proposed in 5/7 would convert today's silent footguns into
actionable warnings.
