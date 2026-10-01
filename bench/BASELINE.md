# Decision library — performance baseline

## Current baseline — boru main @ `64c5ab2` (2026-10-01), single execution path

boru main no longer has an interpreter mode: since 2026-09-19 every program
compiles to bytecode and runs on the VM (or fails with
`[boru/compile_failed]`), and `-no-compile` / `--force-compile` are retired.
`bench/bench.sh` therefore measures the one path and checks the checksum
against an independently computed value instead of diffing two modes.

```bash
BORU=/path/to/boru bash bench/bench.sh          # default: iters=3000 runs=3
BORU=/path/to/boru ITERS=5000 RUNS=5 bash bench/bench.sh
```

Measured in this environment, `iters=3000`, best-of-3:

| metric | compiled (the only path) |
|---|---|
| total wall (s) | 1.98 |
| fixed overhead — pre-flight check + compile (s) | 0.84 |
| per-iteration execution (µs) | 378 |
| checksum | `1184` (expected `1184`) |

Against the `203ea2f` compiled column below, per-iteration execution is in
the same range (323 → 378 µs) while the fixed parse + check + compile
overhead grew (0.28 → 0.84 s); absolute seconds are environment-specific, so
compare like with like. The workload needed one
compile-defect workaround (`bench/decision_bench.aql`, "dynamic-scope def
`acc` of unpromoted computed value"). The sections below are the historical
two-mode baseline, kept as the record.

---

The `Decision` library now runs **fully bytecode-compiled** — every one of the
five test suites (`decision_{unit,prop}_{test,spec}` + `decision_smoke_test`)
compiles under strict `boru --force-compile` with output byte-identical to the
interpreter (see `test/diverge.sh`, "5/5 suites compile"). This document records
the compiled-vs-interpreted performance baseline for that fully-compiled state so
future `boru` changes can be measured against it.

## How to reproduce

```bash
BENCH_AQL=/path/to/aql bash bench/bench.sh          # default: iters=3000 runs=3
BENCH_AQL=/path/to/aql ITERS=5000 RUNS=5 bash bench/bench.sh
```

The harness (`bench/bench.sh`) runs `bench/decision_bench.aql` — a hot loop that
builds a priority-policy **decision table**, a multi-level **decision tree**, and
a compound **predicate** once, then evaluates them across many synthetic inputs
(`decide` over the table, `decide` over the tree, `eval-pred`) — under two modes:

- **interpreter** — `boru -no-compile`, the tree-walking engine;
- **compiled** — `boru --force-compile`, the kernel bytecode VM (aborts rather
  than silently falling back if any part of the program refuses to lower).

Both modes must print the same checksum; the harness fails loudly on divergence.
It reports best-of-N wall time and, by also timing a 1-iteration run, separates
the fixed parse/check/compile overhead from the per-iteration execution cost.

## Baseline numbers

Measured on this environment, `boru` @ `main` `203ea2f` + the compile fixes in
this work, `iters=3000`, best-of-3:

| metric | interpreter | compiled | ratio |
|---|---|---|---|
| total wall (s) | 34.30 | 1.25 | **27.6×** |
| fixed overhead (s) | 0.07 | 0.28 | — |
| per-iteration execution (µs) | 11 409 | 323 | **35.3×** |

Reading the numbers:

- **The compiled VM executes the Decision evaluators ~35× faster per call.**
  The interpreter spends ~11.4 ms per loop iteration (each iteration runs a
  table `decide`, a tree `decide`, and an `eval-pred`); the VM spends ~0.32 ms.
- **Compilation adds ~0.19 s of one-time cost** (parse+check+compile is 0.28 s
  vs the interpreter's 0.07 s parse+check). Break-even is ~17 iterations — past
  that the compiled path wins, and by 3 000 iterations the interpreter is ~28×
  slower wall-clock overall.
- The checksum (`1184`) is identical in both modes: the ~35× speedup is a pure
  execution win with **no behavioural difference** — the same invariant the
  suites' differential gate enforces.

The absolute seconds are environment-specific; the **ratios** are the durable
baseline. Re-run `bench/bench.sh` after an `boru` bump and compare the ratio and
per-iteration µs, not the wall-clock.
