# Prompt: make the client test suites fully `--force-compile` on boru `main`

> **Historical record (superseded 2026-10-01).** This document predates
> boru main's single execution path (2026-09-19): `--compile`,
> `--force-compile` and `--no-compile` are now retired (usage errors), every
> program is compiled to bytecode and run on the VM, and `/r` is spelled
> `/v`. As of boru main @ `64c5ab2` all five suites compile and pass — see
> [dx-report.md](dx-report.md#migration-to-boru-main--64c5ab2-2026-10-01)
> and `test/diverge.sh`. Kept unedited below as the record of what was
> observed at the time.

You are working in **`boru-lang/boru`**. The goal below is concrete and verifiable.
Everything here is grounded in the current `main` design docs and in a live
verification of the `voxgig-boru/decision` library against `main @ 407fedad`.

---

## Goal

**Every test suite of the three client libraries (`decision`, `trie`,
`bloom-filter`) must run under strict `boru --force-compile` and produce output
byte-identical to the interpreter.** "Full compilation": no suite falls back, no
suite refuses.

Today these suites already **interpret** and **`boru check`** clean (0 errors),
and `--compile` (silent fallback) matches the interpreter everywhere. The only
gap is the **strict** bytecode path (`--force-compile`), which still *refuses* a
small, enumerated set of constructs. Closing that gap is the whole task.

Definition of done:

1. For each client suite, `boru --force-compile test/<suite>.aql` exits 0 and its
   stdout equals `boru test/<suite>.aql` (the differential invariant).
2. The langspec compilation corpus (`test/go/langspec`) is green with its
   ratchets at or below their new floors, **deliberately re-baselined** where
   a refusal legitimately becomes a compile (see Workstream B).
3. `make fmt && make vet && make lint && make test` all pass.
4. No miscompilation is introduced: a refusal must only ever become a *correct*
   compile, never a wrong answer. "Refusal is always sound" stays true
   (`design/COMPILABLE-SUBSET.md`).

---

## Current state — the exact refusals (measured on `main @ 407fedad`)

`decision` (run from the decision repo root so `import "./decision.aql"` resolves):

| Suite | `--force-compile` result |
|---|---|
| `decision_prop_test` | ✅ compiles (output == interpreter) — the proof the path works end-to-end |
| `decision_unit_test` | ❌ `code-body word test-test (Stage 2)` |
| `decision_unit_spec` | ❌ `code-body word each (Stage 2)` |
| `decision_prop_spec` | ❌ `code-body word each (Stage 2)` |
| `decision_smoke_test` | ❌ `check diagnostics` (the dynamic-help artifact, NOT a real check error) |

Across all 21 client suites (`design/CLIENT-VERIFICATION-MAIN-2026-06-24.md`) the
full refusal set is exactly five classes:

| Refusal | Suites | Root |
|---|---|---|
| `code-body word each (Stage 2)` | every `*_spec`, several units | `each`/`fold`/`filter` whose body is a `var`/lambda block — `var` splices onto the tape; lowering the value-body closure is the tracked Stage-2 work |
| `code-body word test-test (Stage 2)` | `*_unit_test` | the test framework's `test-test` driver word (META tier) |
| `code-body word test-check-prop (Stage 2)` | `*_prop_test` (trie) | the property-test `test-check-prop` word (META tier) |
| `unannotated or opaque word do` | bloom/tst/burst suites | a `do {key:[expr]}` computed-value **map body** |
| `check diagnostics` | `decision_smoke`, `radix_unit`, `trie_smoke` | the **dynamic-help example generator**, not a real check error |

`decision`'s share is two of these: the **Stage-2 code-body cluster**
(`each`, `test-test`) and the **dynamic-help `check diagnostics` artifact**.
There are therefore two workstreams.

---

## Workstream A — Stage-2 code-body lowering (`each` / `test-test` / `do`)

These are the named Stage-2 emitter cluster (`design/aql-bytecode-completion.0.md`,
`design/COMPILABLE-SUBSET.md`). The mechanism to extend already exists: a
higher-order word's code body lowers to a **capture-resolved closure unit**
(`opClosure` / `PUSH_CLOSURE`) that the driving word invokes through the VM seam
(`eng/go/bytecode.go`: `IsCompiledClosure`, `InvokeBody`). Map iteration for
`each`/`fold`/`filter` over `{…}` was already moved from islanded to native this
way — use that as the template, per-handler, not as a forced uniform closure
(the doc records that a uniform-closure attempt was reverted; each higher-order
word routes its compiled closure through its own handler shape).

Tasks, in leverage ÷ risk order (each must land gate-clean and lower
`refusalCeiling` / `computeRefusalCeiling` monotonically — `test/go/langspec/
compiled_coverage_test.go`):

1. **`each`/`fold`/`filter` with a `var`/lambda code body.** This is the dominant
   class (~22 rows + islands) and unblocks every `*_spec` suite and several
   units. The blocker is the `var`-splice body: the body splices onto the tape,
   so its closure unit must capture-resolve and invoke per element through the
   driving handler. Extend the existing value-body closure path to the `var`
   body shape.
2. **Test-framework code-body words** (`test-test`, `test-check-prop`,
   `test-skip`, `test-prop` — the META tier, ~16 rows). Today these are handled
   by **meta-fallback** (`TestOnlyMetaFallsBack`,
   `test/go/langspec/compiled_metafallback_test.go`) — they fall back to the
   interpreter rather than truly lowering, which is exactly why
   `--force-compile` (no fallback) refuses them. Lower them for real: the test
   words take a quoted assertion/case body (`NoEvalArgs`) and drive it; that body
   is a code-body closure, same seam as (1). When real lowering lands, move these
   rows off the meta-fallback ratchet.
3. **`do {key:[expr]}` computed map bodies** (`unannotated or opaque word do`).
   A `do` map body with computed values is a code body whose result is a map;
   lower it as a closure that produces the map, resolving the same
   "unknown-provenance → refuse" gate `COMPILABLE-SUBSET.md` documents.

Per-item discipline (the §6 discipline in `aql-bytecode-completion.0.md`): land
each separately, gate-clean, with its before/after ratchet delta; keep the
differential (`--compile`/compiled == interpreter) green; a refusal may only ever
become a correct compile.

---

## Workstream B — the dynamic-help `check diagnostics` artifact

This one is **not** a missing emitter feature; it is an entanglement, and it is
the harder of the two. Fully diagnosed in
`design/module-fn-checkstate-ownership.5.md` and `.6.md` — read both first.

What it is: the **dynamic-help example generator**
(`lang/go/native_help.go`: `EnableDynamicHelp` → `makeDynamicEval` →
`GenerateDynamicExamples`) fires from `OnRegisterHook` for every fn registered
after `MarkReady`, and runs each fn body **in check mode** against synthetic
example args (`{a:1,b:2}`). The body's dispatch failures against that stand-in
become error-severity diagnostics. `CompileCheck` refuses any program carrying an
error diagnostic — so these synthetic failures gate the emit even though the
suite's *real* `boru check` is 0 errors. (`decision_smoke_test` checks clean; only
the compile path's internal check trips.)

Why it can't be hot-fixed (measured in `.6`, do not repeat these):

- The eval is **load-bearing twice**: it is also the *only* construction-time
  check of a defined-but-never-called fn body (pinned by
  `TestCheckUncalledFnBodyTypoStillFlagged` and `TestForwardStrandAdvisory` in
  `lang/go/test`).
- The 2830-row langspec compilation corpus is calibrated to the **exact**
  diagnostic set the eval emits. Any *partial* suppression reclassifies rows and
  even changed observable behavior (a spec row's `Assert.throws` stopped
  throwing) — that behavioral change is the red line.

The sound fix is the three-part decouple-and-rebaseline project from `.6` §4 — do
it as one reviewed change, not a filter:

1. **Make the documentation eval hermetic** — run it in a fully isolated check
   state (snapshot+restore diagnostics, not just `Suspend()` on Emit) so it never
   contributes to program diagnostics, compile gating, or coverage.
2. **Add a first-class construction-time body-check pass** — post-binding (so
   recursion resolves) and against **carrier** args (an abstract `Map`/`List`
   param reads `dynamic(Any)`, not the literal `{a:1,b:2}`). This replaces the
   eval's accidental side-channel and must keep the `zzyzx` uncalled-typo and
   forward-strand tests passing.
3. **Re-baseline the langspec compilation corpus in lockstep** — with the
   synthetic errors gone, some rows compile further and some refuse for real
   reasons; re-set the ceilings and per-row tiers, **and investigate the masked
   "did not throw" row** (`.6` §3 flags it as a likely genuine compile-soundness
   gap the synthetic error was hiding — that one must be root-caused, not
   re-baselined away).

Do **not** ship any partial diagnostic filter on the help eval (`.6` approaches
(a)/(c)): they silently reclassify compilation and altered runtime behavior.

---

## Hard constraints

- **Soundness first.** A refusal must only become a *correct* compile. The
  differential test (compiled output == interpreter output) is the gate; if you
  can't prove faithful lowering, keep refusing.
- **Ratchets move monotonically down and stay green.** `refusalCeiling` /
  `computeRefusalCeiling` (`test/go/langspec`) only decrease; no row regresses
  tier without a deliberate, reviewed re-baseline (Workstream B step 3).
- **No client-library source changes.** The fix is entirely in boru; the client
  suites are the acceptance fixtures, unchanged.
- Land per-item, commit per-item with the ratchet delta, full suite green
  (`make fmt && make vet && make lint && make test`).

---

## Verification

```bash
# Build
( cd cmd/go && GOFLAGS=-mod=mod go build -o /tmp/aql-bin ./boru )

# A. Per client suite, from each client repo ROOT — the acceptance fixtures:
for f in test/*.aql; do
  /tmp/aql-bin "$f" >/tmp/i 2>&1                       # interpret  (baseline)
  /tmp/aql-bin --force-compile "$f" >/tmp/c 2>&1       # MUST exit 0…
  diff /tmp/i /tmp/c && echo "compile==interp  $f"     # …and match the interpreter
done

# decision's own multi-mode gate already encodes the differential invariant and
# tracks main HEAD — use it as a ready-made check:
#   voxgig-boru/decision: bash test/diverge.sh
#   (as each refusal clears, that suite flips from "compile n/a (refused)" to
#    "compile ok (== interp)" automatically — its compilable subset is auto-detected)

# B. boru's own gates (must stay green throughout):
make fmt && make vet && make lint && make test
go test ./test/go/langspec/...        # the compilation corpus + ratchets
go test ./lang/go/test/...            # incl. TestCheckUncalledFnBodyTypoStillFlagged,
                                      #      TestForwardStrandAdvisory
```

Done when every client suite's `--force-compile` matches its interpreter run, the
corpus is green at its re-baselined floors, and the full `make` gate passes.

---

## Reference docs (in `design/`)

- `COMPILABLE-SUBSET.md` — the subset rule, the closure seam, "refusal is always sound".
- `aql-bytecode-completion.0.md` — the refusal census, the three ratchet tiers, the per-handler closure approach, the §6 land-gate-clean discipline.
- `aql-bytecode-final-two-refusals.0.md`, `aql-bytecode-finish-line.0.md` — how prior refusals were driven to the ceiling (compile-to-trap vs. lower), `recordCallRefusal`, the gate test.
- `module-fn-checkstate-ownership.5.md` / `.6.md` — the dynamic-help entanglement, the three failed partial fixes, and the sound decouple-and-rebaseline shape.
- `CLIENT-VERIFICATION-MAIN-2026-06-24.md` — the 21-suite client matrix and the canonical refusal table.
